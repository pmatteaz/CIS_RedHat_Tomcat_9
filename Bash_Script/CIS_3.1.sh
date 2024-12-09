#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

generate_random_string() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' </dev/urandom | head -c 20
}

check_shutdown_command() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found${NC}"
        exit 1
    }

    local shutdown_command=$(grep -oP 'shutdown="\K[^"]+' "$SERVER_XML")
    if [ "$shutdown_command" == "SHUTDOWN" ]; then
        echo -e "${YELLOW}[WARN] Default shutdown command detected${NC}"
        return 1
    elif [ -z "$shutdown_command" ]; then
        echo -e "${YELLOW}[WARN] No shutdown command found${NC}"
        return 1
    else
        echo -e "${GREEN}[OK] Custom shutdown command present${NC}"
        return 0
    fi
}

fix_shutdown_command() {
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    local new_command=$(generate_random_string)
    sed -i "s/shutdown=\"[^\"]*\"/shutdown=\"$new_command\"/" "$SERVER_XML"
    echo -e "${GREEN}[OK] Updated shutdown command${NC}"
}

main() {
    echo "CIS 3.1 Check - Shutdown Command"
    local needs_fix=0
    check_shutdown_command
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_shutdown_command
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
        fi
    fi
}

main