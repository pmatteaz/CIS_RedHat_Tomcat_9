#!/bin/bash

# Script per il controllo e fix del CIS Control 6.3
# Ensure scheme is set accurately
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei connettori:
#   Controllo scheme per connettori SSL e non-SSL
#   Verifica coerenza tra SSL e scheme
#
# Controlli specifici:
#   SSL abilitato richiede scheme="https"
#   Non-SSL richiede scheme="http"
#
# Sistema di correzione:
#   Backup delle configurazioni
#   Correzione automatica degli scheme
#   Verifica sintassi XML

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    local backup_dir="/tmp/tomcat_scheme_backup_$(date +%Y%m%d_%H%M%S)_CIS_6.3"
    local backup_file="${backup_dir}/backup_info.txt"

    echo "Creazione backup della configurazione..."

    mkdir -p "$backup_dir"

    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $SERVER_XML" >> "$backup_file"
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
 
    echo "Controllo configurazione SSL dei connettori..."

    # Estrai tutti i connettori e analizzali

    return $result
}


check_scheme_configuration() {
    local result=0
    # Array per memorizzare le sezioni
    declare -a sections

    # Leggi il file riga per riga
    while IFS= read -r line || [[ -n "$line" ]]; do
        # escludi le parti commentate 

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

    echo "Controllo configurazione scheme dei connettori..."

    # Estrai e analizza ogni connettore
        if [[ ${#sections[@]} -ne 0 ]];then
            # Stampa tutte le sezioni trovate
            for i in "${!sections[@]}"; do
               echo "Sezione $((i+1)):"
               echo "${sections[$i]}"
               echo "-------------------"

                local has_ssl=0
                local has_scheme=0
                local scheme_value=""

                # Controlla se il connettore ha SSL abilitato
                if $(echo ${sections[$i]} | grep -Eq "SSLEnabled\s*=\"true\"" ); then
                has_ssl=1
                fi

                # Controlla se l'attributo scheme è presente e il suo valore
                if $(echo ${sections[$i]} |grep -Eq "scheme=\"([^\"]+)\"" ); then
                has_scheme=1
                scheme_value="$(echo ${sections[$i]} | sed -n 's/.*scheme="\([^"]*\)".*/\1/p')"
                #echo "scheme_value=${scheme_value}"
                fi

                # Verifica la corretta configurazione
                if [ $has_ssl -eq 1 ]; then
                    if [ $has_scheme -eq 0 ]; then
                        echo -e "${YELLOW}[WARN] Connettore SSL senza attributo scheme${NC}"
                        result=1
                    elif [ "$scheme_value" != "https" ]; then
                        echo -e "${YELLOW}[WARN] Connettore SSL con scheme=\"$scheme_value\" (dovrebbe essere https)${NC}"
                        result=1
                    else
                        echo -e "${GREEN}[OK] Connettore SSL con scheme corretto${NC}"
                    fi
                else
                    if [ $has_scheme -eq 1 ] && [ "$scheme_value" = "https" ]; then
                        echo -e "${YELLOW}[WARN] Connettore non-SSL con scheme=\"https\"${NC}"
                        result=1
                    elif [ $has_scheme -eq 0 ] || [ "$scheme_value" != "http" ]; then
                        echo -e "${YELLOW}[WARN] Connettore non-SSL dovrebbe avere scheme=\"http\"${NC}"
                        result=1
                    else
                        echo -e "${GREEN}[OK] Connettore non-SSL con scheme corretto${NC}"
                    fi
                fi
            done    
        fi
    return $result
}

fix_scheme_configuration() {
    echo "Correzione configurazione scheme..."

    local temp_file=$(mktemp)
    local in_connector=1
    local has_ssl=1
    local scheme_ex=1

    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
        in_connector=0
        echo "trovato connector: $line"
        fi
        if [[ $line =~ SSLEnabled=\"true\" ]]; then
        has_ssl=0
        echo "Trovato ssl: $line"
        fi
        if [[ in_connector -eq 0 ]]; then
            if [[ has_ssl -eq 0 ]]; then 
                # Connettore SSL: imposta scheme="https"
                if [[ $line =~ scheme= ]]; then
                    line=$(echo "$line" | sed 's/scheme="[^"]*"/scheme="https"/')
                    echo "Linea match con scheme Modificata in: $line"
                    scheme_ex=0
                else
                    if [[ scheme_ex -eq 1 ]]; then
                        line=$(echo "$line" | sed 's/[[:space:]]*\/\?>[[:space:]]*$/\ scheme="https"\n \/>/')
                        echo "Linea match con fine connector Modificata in: $line"
                        if [[ $line =~ [/]?\> ]]; then
                            in_connector=1
                            has_ssl=1
                        fi
                    fi
                fi
            else
                # Connettore non-SSL: imposta scheme="http"
                if [[ $line =~ scheme= ]]; then
                    line=$(echo "$line" | sed 's/scheme="[^"]*"/scheme="http"/')
                    echo "Linea Modificata in: $line"
                    scheme_ex=0
                    has_ssl=1
                else
                    if [[ scheme_ex -eq 1 ]]; then
                        line=$(echo "$line" | sed 's/[[:space:]]*\/\?>[[:space:]]*$/\ scheme="http"\n \/>/')
                        echo "Linea Modificata in: $line"
                        if [[ $line =~ [/]?\> ]]; then
                            in_connector=1
                            has_ssl=1
                        fi
                    fi
                fi
            fi
        fi 

        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"

    #mv "$temp_file" "$SERVER_XML"
    cp "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"

    echo -e "${GREEN}[OK] Configurazione scheme corretta${NC}"
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
    echo "Controllo CIS 6.3 - Ensure scheme is set accurately"
    echo "-----------------------------------------------"

    check_root
    check_file_exists

    local needs_fix=0

    check_scheme_configuration
    needs_fix=$?

    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_scheme_configuration
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle connessioni HTTP/HTTPS${NC}"
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