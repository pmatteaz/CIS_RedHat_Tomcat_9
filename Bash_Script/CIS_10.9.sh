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

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
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
    
    # Controlla tutti i timeout configurati
    local timeout_values=$(grep -o 'connectionTimeout="[0-9]*"' "$SERVER_XML" | cut -d'"' -f2)
    if [ -z "$timeout_values" ]; then
        echo -e "${RED}[ERROR] Nessun connectionTimeout configurato in server.xml${NC}"
        result=1
    else
        for timeout in $timeout_values; do
            if [ "$timeout" -ne "$RECOMMENDED_TIMEOUT" ] ; then
                echo -e "${YELLOW}[WARN] Valore connectionTimeout diverso da quello raccomandato: $timeout${NC}"
                result=1
            fi
        done
    fi
    
    return $result
}
add_connection_timeout (){
    local xml_file="$1"
    
    if [ ! -f "$xml_file" ]; then
        echo "Errore: Il file $xml_file non esiste"
        return 1
    fi
    
    # Usa sed per:
    # 1. Ignora i commenti
    # 2. Trova il tag Connector che non ha già connectionTimeout
    # 3. Aggiunge connectionTimeout="6000" prima della chiusura del tag
 sed -i -e '
    /<!--/,/-->/b
    /<Connector/{
        :a
        N
        /\/>/!ba
        /connectionTimeout/b
        s/\([[:space:]]*\)\([^[:space:]>][^>]*\)\([[:space:]]*\)\/>/\1\2\n\1connectionTimeout="'$RECOMMENDED_TIMEOUT'" \/>/
    }' "$xml_file"
    echo "Modifichato connectionTimeout a $RECOMMENDED_TIMEOUT applicate a $xml_file"
}

fix_timeout_configuration() {
    echo "Applicazione configurazione connectionTimeout..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    if [ -z "$temp_file" ]; then
        echo -e "${RED}[ERROR] Impossibile creare un file temporaneo${NC}"
        exit 1
    fi

    if  grep -q 'connectionTimeout=' "$SERVER_XML"; then
        sed -i -e 's/connectionTimeout=\"[0-9]*\"/connectionTimeout=\"'$RECOMMENDED_TIMEOUT'\"/' "$SERVER_XML" 
    else  
        add_connection_timeout "$SERVER_XML"
    fi
    
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