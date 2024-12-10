#!/bin/bash
# 
# Script per il controllo e fix del CIS Control 2.7
# Ensure Server Header is Modified To Prevent Information Disclosure
#
# Lo script implementa le seguenti funzionalità:
#
# Verifica la configurazione dell'header Server in:
#
# server.xml (per tutti i connettori)
# catalina.properties (server.info property)
#
# Controlla i permessi dei file di configurazione
# Se necessario, offre l'opzione di fix automatico che:
# Modifica l'attributo server per tutti i connettori in server.xml
# Aggiorna/aggiunge la proprietà server.info in catalina.properties
# Corregge i permessi dei file (600)
# Crea backup dei file prima delle modifiche

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
CATALINA_PROPERTIES="$TOMCAT_HOME/conf/catalina.properties"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Valore personalizzato per l'header Server
CUSTOM_SERVER_VALUE="MyServer"

check_tomcat_home() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] Directory Tomcat non trovata: $TOMCAT_HOME${NC}"
        exit 1
    fi
}

check_server_header_config() {
    local result=0
    
    # Controlla server.xml per configurazioni dei connettori
    echo "Controllo configurazioni connettori in server.xml..."
    
    # Verifica se ci sono connettori senza server attribute personalizzato
    if grep -E "<Connector[^>]*>" "$SERVER_XML" | grep -qv "server=\""; then
        echo -e "${YELLOW}[WARN] Trovati connettori senza attributo server personalizzato${NC}"
        result=1
    else
        if grep -q "server=\"$CUSTOM_SERVER_VALUE\"" "$SERVER_XML"; then
            echo -e "${GREEN}[OK] Attributo server correttamente configurato nei connettori${NC}"
        else
            echo -e "${YELLOW}[WARN] Attributo server non configurato con il valore atteso${NC}"
            result=1
        fi
    fi
    
    # Controlla catalina.properties per server.info property
    echo "Controllo server.info in catalina.properties..."
    if grep -q "^server.info=" "$CATALINA_PROPERTIES"; then
        if grep -q "^server.info=$CUSTOM_SERVER_VALUE" "$CATALINA_PROPERTIES"; then
            echo -e "${GREEN}[OK] server.info correttamente configurato${NC}"
        else
            echo -e "${YELLOW}[WARN] server.info presente ma non configurato con il valore atteso${NC}"
            result=1
        fi
    else
        echo -e "${YELLOW}[WARN] server.info non configurato${NC}"
        result=1
    fi
    
    return $result
}

fix_server_header() {
    echo "Applicazione delle correzioni..."
    
    # Backup dei file
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    cp "$CATALINA_PROPERTIES" "${CATALINA_PROPERTIES}.bak"
    
    # Modifica server.xml
    # Aggiunge o aggiorna l'attributo server per tutti i connettori
    local temp_file=$(mktemp)
    
    # Usa awk per una sostituzione più precisa
    awk -v custom="$CUSTOM_SERVER_VALUE" '
        /<Connector/ {
            if (!/server="/) {
                sub(/>/, " server=\"" custom "\">");
            } else {
                sub(/server="[^"]*"/, "server=\"" custom "\"");
            }
        }
        { print }
    ' "$SERVER_XML" > "$temp_file"
    
    mv "$temp_file" "$SERVER_XML"
    
    # Modifica catalina.properties
    if grep -q "^server.info=" "$CATALINA_PROPERTIES"; then
        sed -i "s/^server.info=.*/server.info=$CUSTOM_SERVER_VALUE/" "$CATALINA_PROPERTIES"
    else
        echo "server.info=$CUSTOM_SERVER_VALUE" >> "$CATALINA_PROPERTIES"
    fi
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    if grep -q "server=\"$CUSTOM_SERVER_VALUE\"" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Attributo server aggiornato in server.xml${NC}"
    else
        echo -e "${RED}[ERROR] Problemi nell'aggiornamento di server.xml${NC}"
    fi
    
    if grep -q "^server.info=$CUSTOM_SERVER_VALUE" "$CATALINA_PROPERTIES"; then
        echo -e "${GREEN}[OK] server.info aggiornato in catalina.properties${NC}"
    else
        echo -e "${RED}[ERROR] Problemi nell'aggiornamento di catalina.properties${NC}"
    fi
}

check_file_permissions() {
    local result=0
    
    # Verifica i permessi dei file modificati
    echo "Controllo permessi dei file..."
    
    for file in "$SERVER_XML" "$CATALINA_PROPERTIES"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}[ERROR] File non trovato: $file${NC}"
            result=1
            continue
        fi
        
        local perms=$(stat -c "%a" "$file")
        if [ "$perms" != "600" ]; then
            echo -e "${YELLOW}[WARN] Permessi non corretti per $file: $perms (dovrebbe essere 600)${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Permessi corretti per $file${NC}"
        fi
    done
    
    return $result
}

fix_file_permissions() {
    echo "Correzione permessi dei file..."
    
    for file in "$SERVER_XML" "$CATALINA_PROPERTIES"; do
        if [ -f "$file" ]; then
            chmod 600 "$file"
            echo -e "${GREEN}[OK] Permessi aggiornati per $file${NC}"
        fi
    done
}

main() {
    echo "Controllo CIS 2.7 - Server Header Information Disclosure"
    echo "-----------------------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    
    check_server_header_config
    needs_fix=$((needs_fix + $?))
    
    check_file_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_server_header
            fix_file_permissions
            echo -e "\n${GREEN}Fix completato. Riavviare Tomcat per applicare le modifiche.${NC}"
            echo -e "${YELLOW}NOTA: Il valore dell'header Server è stato impostato a '$CUSTOM_SERVER_VALUE'.${NC}"
            echo -e "${YELLOW}      Modificare la variabile CUSTOM_SERVER_VALUE nello script per personalizzarlo.${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main