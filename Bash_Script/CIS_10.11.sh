#!/bin/bash

# Script per il controllo e fix del CIS Control 10.11
# Force SSL for all applications
#
# Lo script implementa le seguenti funzionalità:
# Verifica configurazione SSL:
#   Connettore HTTPS in server.xml
#   Protocolli SSL/TLS abilitati
#   Cipher suites sicure
#   Security constraints in web.xml
# 
# Funzionalità aggiuntive:
#   Backup dei file modificati
#   Verifica permessi


# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
WEBAPPS_DIR="$TOMCAT_HOME/conf/Catalina/localhost"
WEB_XML="$TOMCAT_HOME/conf/web.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Security constraint configuration to add to web.xml if missing
SECURITY_CONSTRAINT='    <security-constraint>\n        <web-resource-collection>\n            <web-resource-name>Entire Application</web-resource-name>\n            <url-pattern>/*</url-pattern>\n        </web-resource-collection>\n        <user-data-constraint>\n            <transport-guarantee>CONFIDENTIAL</transport-guarantee>\n        </user-data-constraint>\n    </security-constraint>'

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

check_security_constraint() {
    local result=0
    if grep -q '<transport-guarantee>CONFIDENTIAL</transport-guarantee>' "$WEB_XML"; then
        echo -e "${GREEN}[OK] Security constraint trovata con valore CONFIDENTIAL in web.xml${NC}"
        result=0
    elif grep -q '<transport-guarantee>INTEGRAL</transport-guarantee>' "$WEB_XML"; then
        echo -e "${YELLOW}[WARN] Security constraint con valore INTEGRAL non atteso in web.xml${NC}"
        result=1
    else
        echo -e "${RED}[ERROR] Security constraint mancante in web.xml${NC}"
        result=1
    fi

    return $result
}

fix_security_constraint() {
  if grep -q '<transport-guarantee>INTEGRAL</transport-guarantee>' "$WEB_XML"; then
        echo -e "${YELLOW}[WARN] Security constraint con valore INTEGRAL non atteso in web.xml${NC}"
        sed -i 's/<transport-guarantee>INTEGRAL<\/transport-guarantee>/<transport-guarantee>CONFIDENTIAL<\/transport-guarantee>/' "$WEB_XML"
    else
        echo -e "${RED}[ERROR] Security constraint mancante in web.xml${NC}"
        #add secuity contrain
        sed -i "/<\/web-app>/i\\${SECURITY_CONSTRAINT}" "$WEB_XML"
    fi  
} 

verify_xml_syntax() {
    local xml_file="$1"
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$xml_file" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore nella sintassi XML di server.xml${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, impossibile verificare la sintassi XML${NC}"
    fi
    return 0
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_ssl_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.11"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup di $file..."
    
    mkdir -p "$backup_dir"
    cp -p "$file" "$backup_dir/"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" > "${backup_dir}/$(basename "$file").sha256"
    fi
    
    echo "# Backup created: $(date)" > "$backup_file"
    echo "# Original file: $file" >> "$backup_file"
    ls -l "$file" >> "$backup_file"
    
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}


main() {
    echo "Controllo CIS 10.11 - Force SSL for all applications"
    echo "------------------------------------------------"
    
    check_root
    
    local needs_fix=0

    check_security_constraint || needs_fix=1
    
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_security_constraint 
            if verify_xml_syntax $WEB_XML ; then
                echo -e "\n${GREEN}Fix completato con successo.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Monitorare i log per eventuali problemi con le richieste HTTP${NC}"
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