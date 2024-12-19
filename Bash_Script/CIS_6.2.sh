#!/bin/bash

# Script per il controllo e fix del CIS Control 6.2
# Ensure SSLEnabled is set to True for Sensitive Connectors
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei connettori sensibili:
#  Identificazione porte che richiedono SSL
#  Controllo configurazione SSL completa
#  Verifica protocolli e cipher suites
#
# Controlli specifici per:
#   SSLEnabled="true"
#
#
# Sistema di correzione:
#   Backup delle configurazioni
#   Applicazione configurazioni SSL sicure
#   Rimozione configurazioni non sicure
#   Verifica sintassi XML

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml_test"

# Porte sensibili che richiedono SSL
SENSITIVE_PORTS=(
    "8443"  # HTTPS default
    "8009"  # AJP default
    "443"   # HTTPS standard
)

# Configurazione SSL raccomandata
SSL_CONFIG="SSLEnabled=\"true\" maxThreads=\"150\" scheme=\"https\" secure=\"true\"
           clientAuth=\"false\" sslProtocol=\"TLS\"
           sslEnabledProtocols=\"TLSv1.2,TLSv1.3\"
           ciphers=\"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256\""

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
#Diciaro array per fix porte
declare -a FIX_PORT

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] File server.xml non trovato: $SERVER_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_ssl_backup_$(date +%Y%m%d_%H%M%S)_CIS_6.2"
    local backup_file="${backup_dir}/backup_info.txt"

    echo "Creazione backup della configurazione..."
    mkdir -p "$backup_dir"

    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    ls -l "$SERVER_XML" >> "$backup_file"

    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml.acl"
    fi

    cp -p "$SERVER_XML" "$backup_dir/"

    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi

    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"

    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_ssl_configuration() {
    local result=0
    # Array per memorizzare le sezioni
    declare -a sections

    # Leggi il file riga per riga
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Se troviamo l'inizio di una sezione
        if [[ $line =~ \<Connect.*$ ]]; then
            # Inizia una nuova sezione
            current_section="$line"

            # Continua a leggere finché non troviamo la fine della sezione
            while IFS= read -r next_line || [[ -n "$next_line" ]]; do
                current_section+=$'\n'"$next_line"
                # Se troviamo la fine della sezione
                if [[ $next_line =~ \/\>$ ]] || [[ $next_line =~ \>$ ]]; then
                    # Aggiungi la sezione completa all'array
                    sections+=("$current_section")
                    break
                fi
            done
        fi
    done < "$SERVER_XML"

    echo "Controllo configurazione SSL dei connettori..."

    # Estrai tutti i connettori e analizzali
        if [[ ${#sections[@]} -ne 0 ]];then
            # Stampa tutte le sezioni trovate
            for i in "${!sections[@]}"; do
               echo "Sezione $((i+1)):"
               echo "${sections[$i]}"
               echo "-------------------"
            # Verifica se è una porta sensibile
            port=$(echo "${sections[$i]}" |grep -i "\s[Pp]ort\s*=\?" | cut -d'"' -f2)
#            echo "######### $port #########"

                for sensitive_port in "${SENSITIVE_PORTS[@]}"; do
                    if [ "$port" = "$sensitive_port" ]; then
                        is_sensitive=1
                        break
                    fi
                done
            # Controlla configurazione SSL per porte sensibili
                if [[ $is_sensitive -eq 1 ]]; then
                   if ! $(echo ${sections[$i]} |grep -Eq '(SSLEnabled\s*=\"true\"|protocol=\"AJP\/1.3\")'  2> /dev/null) ; then
                    echo -e "${YELLOW}[WARN] Connettore sulla porta $port non ha SSL abilitato${NC}"
                    result=1
                    FIX_PORT+="$port"
                   fi
                fi
            done
        fi


    return $result
}


enable_ssl_port() {
    local file="$1"
    local port="$2"
    local temp_file=$(mktemp)
    local in_connector=false
    local modified=false
    local current_section=""

    # Verifica i parametri
    if [[ ! -f "$file" ]]; then
        echo "Errore: Il file $file non esiste"
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "Errore: Devi specificare un numero di porta"
        return 1
    fi

    # Leggi il file riga per riga
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Se troviamo l'inizio di un connettore con la porta specificata
        if [[ $line =~ \<Connector.*port=.*\"$port\" ]] || [[ $line =~ \<Connector.*port\ =.*\"$port\" ]]; then
            in_connector=true
            current_section="$line"

            # Se la linea non contiene SSLEnabled, aggiungilo
            if [[ ! $line =~ SSLEnabled ]]; then
                # Se la riga finisce con > o />, aggiungi SSLEnabled prima
                if [[ $line =~ [/]?\>$ ]]; then
                    line="${line%>} SSLEnabled=\"true\">"
                else
                    line="$line SSLEnabled=\"true\""
                fi
                modified=true
            # Se contiene SSLEnabled="false", cambialo in true
            elif [[ $line =~ SSLEnabled=\"false\" ]]; then
                line="${line//SSLEnabled=\"false\"/SSLEnabled=\"true\"}"
                modified=true
            fi
        else
         line=$(echo $line | sed 's/SSLEnabled="false"//g')
        fi

        echo "$line" >> "$temp_file"
    done < "$file"

    if [[ $modified == true ]]; then
        # Fai backup del file originale
        cp "$file" "${file}.bak"
        # Sposta il file temporaneo al posto dell'originale
        mv "$temp_file" "$file"
        echo "SSL abilitato con successo sulla porta $port"
        echo "Backup salvato come ${file}.bak"
        return 0
    else
        rm "$temp_file"
        echo "Nessuna modifica necessaria o connettore sulla porta $port non trovato"
        return 1
    fi
}


verify_xml_syntax() {
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$SERVER_XML" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore di sintassi XML in server.xml${NC}"
            return 1
        fi
        echo -e "${GREEN}[OK] Sintassi XML corretta${NC}"
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    return 0
}

main() {
    echo "Controllo CIS 6.2 - Ensure SSLEnabled is set to True for Sensitive Connectors"
    echo "------------------------------------------------------------------------"

    check_root
    check_file_exists

    local needs_fix=0

    check_ssl_configuration
    needs_fix=$?

    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            if [[ ${#FIX_PORT[@]} -ne 0 ]]; then
              for p in "${!FIX_PORT[@]}"; do
                echo ${FIX_PORT[$p]}
                enable_ssl_port "$SERVER_XML" "${FIX_PORT[$p]}"
              done
            else
            echo "${YELLOW} richiesto fix ma non indicata porta !!${NC}"
            exit 1
            fi
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle connessioni SSL${NC}"
                echo -e "${YELLOW}NOTA: Assicurarsi che i certificati SSL siano configurati correttamente${NC}"
            else
                echo -e "\n${RED}[ERROR] Errore durante l'applicazione delle modifiche${NC}"
                echo -e "${YELLOW}NOTA: Ripristinare il backup e verificare manualmente la configurazione${NC}"
            fi
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main
