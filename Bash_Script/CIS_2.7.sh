#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_server_xml() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        exit 1
    }
}

check_server_header() {
    local result=0
    
    # Check all Connector elements for server attribute
    if grep -q '<Connector[^>]*server="[^"]*"' "$SERVER_XML"; then
        # Verify if any connector still shows default server value
        if grep -q '<Connector[^>]*server="Apache[^"]*"' "$SERVER_XML" || \
           grep -q '<Connector[^>]*server="Apache Tomcat"' "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Found default server header values${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] All connectors have custom server headers${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN] Server header not configured for connectors${NC}"
        result=1
    fi
    
    return $result
}

fix_server_header() {
    # Backup original file
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    
    # Replace or add server attribute for HTTP and AJP connectors
    sed -i -E '/<Connector.*protocol="HTTP\/1.1"/ s/>/& server="SecureServer"/' "$SERVER_XML"
    sed -i -E '/<Connector.*protocol="AJP\/1.3"/ s/>/& server="SecureServer"/' "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Updated server headers to generic value${NC}"
}

main() {
    echo "CIS 2.7 Check - Server Header Information Disclosure"
    echo "-------------------------------------------------"
    
    check_server_xml
    
    local needs_fix=0
    check_server_header
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_server_header
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main