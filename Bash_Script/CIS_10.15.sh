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

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
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
    local backup_dir="/tmp/tomcat_valve_backup_$(date +%Y%m%d_%H%M%S)"
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

check_valve_configuration() {
    local result=0
    
    echo "Controllo configurazione Logging Valves..."
    
    # Array dei pattern da cercare
    local valve_patterns=(
        "org.apache.catalina.valves.AccessLogValve"
        "org.apache.catalina.valves.RemoteAddrValve"
        "org.apache.catalina.valves.RemoteHostValve"
    )
    
    # Controlla ogni tipo di valve
    for pattern in "${valve_patterns[@]}"; do
        echo -e "\nControllo $pattern..."
        
        if grep -q "$pattern" "$SERVER_XML"; then
            # Controlla resolveHosts attribute
            if grep -q "$pattern.*resolveHosts=\"true\"" "$SERVER_XML"; then
                echo -e "${YELLOW}[WARN] Trovato $pattern con resolveHosts abilitato${NC}"
                result=1
            elif ! grep -q "$pattern.*resolveHosts=\"false\"" "$SERVER_XML"; then
                echo -e "${YELLOW}[WARN] $pattern senza attributo resolveHosts esplicito${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] $pattern configurato correttamente${NC}"
            fi
            
            # Controlla altri attributi correlati alla sicurezza
            if [[ "$pattern" == *"AccessLogValve"* ]]; then
                if ! grep -q "$pattern.*requestAttributesEnabled=\"false\"" "$SERVER_XML"; then
                    echo -e "${YELLOW}[WARN] AccessLogValve potrebbe esporre informazioni sensibili${NC}"
                    result=1
                fi
            fi
        else
            echo -e "${GREEN}[OK] $pattern non trovato (non necessita fix)${NC}"
        fi
    done
    
    return $result
}

fix_valve_configuration() {
    echo "Correzione configurazione Logging Valves..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Legge il file riga per riga
    while IFS= read -r line; do
        # Controlla se la riga contiene una valve di logging
        if [[ $line =~ "org.apache.catalina.valves" ]]; then
            # Rimuove resolveHosts se presente
            line=$(echo "$line" | sed 's/resolveHosts="[^"]*"//g')
            
            # Aggiunge resolveHosts="false"
            if [[ $line =~ "AccessLogValve" ]]; then
                # Per AccessLogValve, aggiungi anche requestAttributesEnabled="false"
                if [[ $line =~ "/>" ]]; then
                    line=$(echo "$line" | sed 's/\/>/resolveHosts="false" requestAttributesEnabled="false" \/>/')
                else
                    line=$(echo "$line" | sed 's/>/resolveHosts="false" requestAttributesEnabled="false" >/')
                fi
            else
                # Per altri tipi di valve
                if [[ $line =~ "/>" ]]; then
                    line=$(echo "$line" | sed 's/\/>/resolveHosts="false" \/>/')
                else
                    line=$(echo "$line" | sed 's/>/resolveHosts="false" >/')
                fi
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    # Sostituisce il file originale
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione valve aggiornata${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_valve_configuration
}

main() {
    echo "Controllo CIS 10.15 - Do not resolve hosts on logging valves"
    echo "--------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_valve_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_valve_configuration
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