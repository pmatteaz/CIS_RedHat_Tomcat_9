#!/bin/bash

# Script per il controllo e fix del CIS Control 2.4
# Disable X-Powered-By HTTP Header and Rename the Server Value for all Connectors
# Lo script esegue le seguenti operazioni:
# Verifica la presenza di X-Powered-By header e il suo stato
# Controlla la personalizzazione dell'header Server
# Se necessario, offre l'opzione di fix automatico che:
# Disabilita X-Powered-By tramite HttpHeaderSecurityFilter
# Personalizza il Server header per tutti i connettori
# Crea backup dei file prima delle modifiche


TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
WEB_XML="$TOMCAT_HOME/conf/web.xml"

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

check_xpowered_by() {
    local result=0
    
    # Controlla se x-powered-by è disabilitato in web.xml
    if grep -q "org.apache.catalina.filters.HttpHeaderSecurityFilter" "$WEB_XML"; then
        if grep -q "xpoweredBy=\"false\"" "$WEB_XML"; then
            echo -e "${GREEN}[OK] X-Powered-By header è già disabilitato${NC}"
        else
            echo -e "${YELLOW}[WARN] X-Powered-By header non è disabilitato${NC}"
            result=1
        fi
    else
        echo -e "${YELLOW}[WARN] HttpHeaderSecurityFilter non configurato${NC}"
        result=1
    fi
    
    return $result
}

check_server_header() {
    local result=0
    
    # Controlla se il server header è personalizzato in server.xml
    if grep -q "server=\"Apache\"" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Server header è già personalizzato${NC}"
    else
        echo -e "${YELLOW}[WARN] Server header non è personalizzato${NC}"
        result=1
    fi
    
    return $result
}

fix_xpowered_by() {
    # Backup del file
    cp "$WEB_XML" "${WEB_XML}.bak"
    
    # Aggiunge o aggiorna HttpHeaderSecurityFilter
    if ! grep -q "org.apache.catalina.filters.HttpHeaderSecurityFilter" "$WEB_XML"; then
        sed -i '/<\/web-app>/i \
    <filter>\
        <filter-name>httpHeaderSecurity</filter-name>\
        <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>\
        <init-param>\
            <param-name>xpoweredBy</param-name>\
            <param-value>false</param-value>\
        </init-param>\
    </filter>\
    <filter-mapping>\
        <filter-name>httpHeaderSecurity</filter-name>\
        <url-pattern>/*</url-pattern>\
    </filter-mapping>' "$WEB_XML"
    else
        sed -i 's/xpoweredBy="true"/xpoweredBy="false"/' "$WEB_XML"
    fi
    
    echo -e "${GREEN}[OK] X-Powered-By header disabilitato${NC}"
}

fix_server_header() {
    # Backup del file
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    
    # Aggiunge o aggiorna l'attributo server per tutti i connettori
    sed -i '/<Connector/s/>/ server="Apache">/' "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Server header personalizzato${NC}"
}

main() {
    echo "Controllo CIS 2.4 - HTTP Headers Security"
    echo "----------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    
    check_xpowered_by
    needs_fix=$((needs_fix + $?))
    
    check_server_header
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_xpowered_by
            fix_server_header
            echo -e "\n${GREEN}Fix completato. Riavviare Tomcat per applicare le modifiche.${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main
