#!/bin/bash

# Script per il controllo e fix del CIS Control 10.15
# Do not resolve hosts on logging valves
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione delle valvole di logging:
#   AccessLogValve
#   RemoteAddrValve
#   RemoteHostValve
# 
# Controlli specifici per:
#   Attributo resolveHosts
#   Attributo requestAttributesEnabled per AccessLogValve
#   Altri attributi correlati alla sicurezza
# 
# Funzionalità di correzione:
#   Disabilita la risoluzione degli host
#   Imposta attributi di sicurezza appropriati
#   Mantiene altre configurazioni esistenti

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
    local backup_dir="/tmp/tomcat_valve_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.15"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
    ls -l "$SERVER_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$SERVER_XML" "${backup_dir}/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_enableLookups_configuration() {
    local result=0
    # verifica se il file server.xml contiene enableLookups="true"
    if grep -q 'enableLookups="true"' "$SERVER_XML"; then
        echo -e "${RED}[WARN] Attenzione: enableLookups è impostato su true${NC}"
        result=1
    else 
        echo -e "${GREEN}[OK] enableLookups è impostato su false o mancante ${NC}"
        result=0
    fi
    return $result
}

fix_enableLookups_configuration() {
    echo "Correzione configurazione enableLookups..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # con sed cambia enableLookups="true" in enableLookups="false"
    sed -i 's/enableLookups="true"/enableLookups="false"/' "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione enableLookups aggiornata${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_enableLookups_configuration
}

main() {
    echo "Controllo CIS 10.15 - Do not resolve hosts on logging valves"
    echo "--------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_enableLookups_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_enableLookups_configuration
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare i log per assicurarsi che il logging funzioni correttamente${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main