#!/bin/bash

# Script per il controllo e fix del CIS Control 3.2
# Disable the Shutdown port

# Lo script implementa le seguenti funzionalità:
#
# Verifica la configurazione della porta di shutdown:
#
# Controlla se è presente l'attributo port nel tag Server
# Verifica se la porta è impostata a -1 (disabilitata)
# Controlla i permessi del file server.xml
# Se necessario, offre l'opzione di fix automatico che:
# Disabilita la porta di shutdown impostandola a -1
# Corregge i permessi dei file (600)
# Verifica le modifiche apportate
#
# Crea backup dei file prima delle modifiche

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_tomcat_home() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] Directory Tomcat non trovata: $TOMCAT_HOME${NC}"
        exit 1
    fi
}

check_shutdown_port() {
    local result=0
    
    echo "Controllo configurazione porta shutdown..."
    
    # Verifica la presenza dell'attributo port nel Server
    if grep -q '<Server port="[0-9]*"' "$SERVER_XML"; then
        local port=$(grep -oP '(?<=<Server port=")[^"]*' "$SERVER_XML")
        
        # Verifica se la porta è -1 (disabilitata)
        if [ "$port" != "-1" ]; then
            echo -e "${YELLOW}[WARN] Porta shutdown è abilitata (porta: $port)${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Porta shutdown è correttamente disabilitata${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN] Configurazione porta shutdown non trovata${NC}"
        result=1
    fi
    
    return $result
}

check_file_permissions() {
    local result=0
    
    echo "Controllo permessi del file server.xml..."
    
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] File server.xml non trovato${NC}"
        return 1
    fi
    
    local perms=$(stat -c "%a" "$SERVER_XML")
    if [ "$perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi non corretti per server.xml: $perms (dovrebbe essere 600)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi corretti per server.xml${NC}"
    fi
    
    return $result
}

fix_shutdown_port() {
    echo "Disabilitazione porta shutdown..."
    
    # Backup del file
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    
    # Modifica la porta a -1
    if grep -q '<Server port="[0-9]*"' "$SERVER_XML"; then
        sed -i 's/<Server port="[0-9]*"/<Server port="-1"/' "$SERVER_XML"
        echo -e "${GREEN}[OK] Porta shutdown disabilitata (impostata a -1)${NC}"
    else
        echo -e "${RED}[ERROR] Pattern Server port non trovato in server.xml${NC}"
        echo -e "${YELLOW}[WARN] Potrebbe essere necessaria una verifica manuale${NC}"
        return 1
    fi
    
    return 0
}

fix_file_permissions() {
    echo "Correzione permessi dei file..."
    
    chmod 600 "$SERVER_XML"
    echo -e "${GREEN}[OK] Permessi aggiornati per server.xml${NC}"
}

verify_changes() {
    echo "Verifica delle modifiche..."
    
    if grep -q '<Server port="-1"' "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Configurazione porta shutdown verificata${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Configurazione porta shutdown non corretta${NC}"
        return 1
    fi
}

main() {
    echo "Controllo CIS 3.2 - Shutdown Port Configuration"
    echo "---------------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    
    check_shutdown_port
    needs_fix=$((needs_fix + $?))
    
    check_file_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            if fix_shutdown_port; then
                fix_file_permissions
                if verify_changes; then
                    echo -e "\n${GREEN}Fix completato con successo.${NC}"
                    echo -e "${YELLOW}IMPORTANTE: Riavviare Tomcat per applicare le modifiche.${NC}"
                else
                    echo -e "\n${RED}[ERROR] Verifica delle modifiche fallita.${NC}"
                    echo -e "${YELLOW}Si consiglia di ripristinare il backup: ${SERVER_XML}.bak${NC}"
                fi
            else
                echo -e "\n${RED}[ERROR] Fix non completato.${NC}"
            fi
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main