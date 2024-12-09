#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_shutdown_port() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found${NC}"
        exit 1
    }

    local port=$(grep -oP 'port="\K[^"]+' "$SERVER_XML" | head -1)
    if [ "$port" == "-1" ]; then
        echo -e "${GREEN}[OK] Shutdown port is disabled${NC}"
        return 0
    else
        echo -e "${YELLOW}[WARN] Shutdown port is enabled (port: $port)${NC}"
        return 1
    fi
}

disable_shutdown_port() {
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    sed -i '/<Server/s/port="[^"]*"/port="-1"/' "$SERVER_XML"
    echo -e "${GREEN}[OK] Disabled shutdown port${NC}"
}

main() {
    echo "CIS 3.2 Check - Shutdown Port"
    local needs_fix=0
    check_shutdown_port
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            disable_shutdown_port
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
        fi
    fi
}

main