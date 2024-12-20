#!/bin/bash

# Script per il controllo e fix del CIS Control 10.9
# Configure connectionTimeout
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione del connectionTimeout:
#   Controlla tutti i connettori in server.xml
#   Verifica i valori configurati (60 secondi raccomandati)
#   Identifica connettori senza timeout configurato
#   Controlla parametri correlati come keepAliveTimeout
# 
# Funzionalità di correzione:
#   Imposta il valore raccomandato di 60 secondi
#   Aggiunge il parametro dove mancante
#   Verifica la sintassi XML dopo le modifiche
# 
# Sistema di backup:
#   Backup completo di server.xml
#   Salvataggio delle ACL
#   Verifica dell'integrità tramite hash

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Valore raccomandato per connectionTimeout (60 secondi)
RECOMMENDED_TIMEOUT="60000"
MIN_TIMEOUT="20000"
MAX_TIMEOUT="120000"

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
    local backup_dir="/tmp/tomcat_timeout_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.9"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $SERVER_XML" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    ls -l "$SERVER_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml.acl"
    fi
    
    # Copia fisica del file
    cp -p "$SERVER_XML" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_timeout_configuration() {
    local result=0
    
    echo "Controllo configurazione connectionTimeout..."
    
    # Controlla tutti i connettori
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            echo -e "\nAnalisi connettore:"
            echo "$line"
            
            if [[ $line =~ connectionTimeout=\"([0-9]+)\" ]]; then
                local timeout="${BASH_REMATCH[1]}"
                if [ "$timeout" -lt "$MIN_TIMEOUT" ]; then
                    echo -e "${YELLOW}[WARN] connectionTimeout ($timeout ms) è troppo basso${NC}"
                    result=1
                elif [ "$timeout" -gt "$MAX_TIMEOUT" ]; then
                    echo -e "${YELLOW}[WARN] connectionTimeout ($timeout ms) è troppo alto${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] connectionTimeout configurato correttamente${NC}"
                fi
            else
                echo -e "${YELLOW}[WARN] connectionTimeout non configurato per questo connettore${NC}"
                result=1
            fi
            
            # Verifica altri parametri correlati
            if [[ $line =~ protocol=\"([^\"]+)\" ]]; then
                local protocol="${BASH_REMATCH[1]}"
                echo -e "Protocollo configurato: $protocol"
            fi
            
            # Verifica keepAliveTimeout se presente
            if [[ $line =~ keepAliveTimeout=\"([0-9]+)\" ]]; then
                local keep_alive="${BASH_REMATCH[1]}"
                if [ "$keep_alive" -gt "$RECOMMENDED_TIMEOUT" ]; then
                    echo -e "${YELLOW}[WARN] keepAliveTimeout ($keep_alive ms) potrebbe essere troppo alto${NC}"
                    result=1
                fi
            fi
        fi
    done < "$SERVER_XML"
    
    return $result
}

fix_timeout_configuration() {
    echo "Applicazione configurazione connectionTimeout..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Modifica ogni connettore
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            if [[ $line =~ connectionTimeout=\"([0-9]+)\" ]]; then
                # Sostituisci il valore esistente
                line=$(echo "$line" | sed "s/connectionTimeout=\"[0-9]*\"/connectionTimeout=\"$RECOMMENDED_TIMEOUT\"/")
            else
                # Aggiungi il parametro se non presente
                line=$(echo "$line" | sed "s/>/ connectionTimeout=\"$RECOMMENDED_TIMEOUT\">/")
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    # Sostituisci il file originale
    mv "$temp_file" "$SERVER_XML"
    
    # Imposta permessi corretti
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione connectionTimeout aggiornata${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_timeout_configuration
}

verify_xml_syntax() {
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$SERVER_XML" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore nella sintassi XML di server.xml${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, impossibile verificare la sintassi XML${NC}"
    fi
    return 0
}

main() {
    echo "Controllo CIS 10.9 - Configure connectionTimeout"
    echo "-------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_timeout_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_timeout_configuration
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato con successo.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Monitorare i log per eventuali timeout indesiderati${NC}"
                echo -e "${YELLOW}NOTA: Considerare l'aggiustamento dei valori in base al carico del server${NC}"
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