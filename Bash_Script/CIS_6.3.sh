#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        exit 1
    fi
}

check_connector_schemes() {
    local result=0
    
    echo -e "\nChecking Connector Schemes:"
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local ssl_enabled=$(echo "$connector" | grep -oP 'SSLEnabled="\K[^"]+' || echo "false")
        local scheme=$(echo "$connector" | grep -oP 'scheme="\K[^"]+' || echo "http")
        local secure=$(echo "$connector" | grep -oP 'secure="\K[^"]+' || echo "false")
        
        echo -e "\nAnalyzing connector on port $port:"
        
        # Check scheme consistency with SSL configuration
        if [ "$ssl_enabled" == "true" ] && [ "$scheme" != "https" ]; then
            echo -e "${YELLOW}[WARN] SSL is enabled but scheme is not 'https' on port $port${NC}"
            result=1
        elif [ "$ssl_enabled" == "false" ] && [ "$scheme" == "https" ]; then
            echo -e "${YELLOW}[WARN] SSL is disabled but scheme is 'https' on port $port${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Scheme configuration matches SSL status on port $port${NC}"
        fi
        
        # Check secure attribute consistency
        if [ "$ssl_enabled" == "true" ] && [ "$secure" != "true" ]; then
            echo -e "${YELLOW}[WARN] SSL is enabled but secure attribute is not 'true' on port $port${NC}"
            result=1
        elif [ "$ssl_enabled" == "false" ] && [ "$secure" == "true" ]; then
            echo -e "${YELLOW}[WARN] SSL is disabled but secure attribute is 'true' on port $port${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Secure attribute matches SSL status on port $port${NC}"
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_connector_schemes() {
    local temp_file=$(mktemp)
    cp "$SERVER_XML" "$temp_file"
    
    # Fix each connector
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local ssl_enabled=$(echo "$connector" | grep -oP 'SSLEnabled="\K[^"]+' || echo "false")
        local new_connector="$connector"
        
        if [ "$ssl_enabled" == "true" ]; then
            # Update scheme and secure attributes for SSL-enabled connectors
            new_connector=$(echo "$connector" | \
                sed 's/scheme="[^"]*"/scheme="https"/' | \
                sed 's/secure="[^"]*"/secure="true"/')
            if ! echo "$connector" | grep -q 'scheme="'; then
                new_connector=$(echo "$new_connector" | sed 's/>/ scheme="https">/')
            fi
            if ! echo "$connector" | grep -q 'secure="'; then
                new_connector=$(echo "$new_connector" | sed 's/>/ secure="true">/')
            fi
        else
            # Update scheme and secure attributes for non-SSL connectors
            new_connector=$(echo "$connector" | \
                sed 's/scheme="[^"]*"/scheme="http"/' | \
                sed 's/secure="[^"]*"/secure="false"/')
            if ! echo "$connector" | grep -q 'scheme="'; then
                new_connector=$(echo "$new_connector" | sed 's/>/ scheme="http">/')
            fi
            if ! echo "$connector" | grep -q 'secure="'; then
                new_connector=$(echo "$new_connector" | sed 's/>/ secure="false">/')
            fi
        fi
        
        # Replace old connector with new one
        escaped_connector=$(echo "$connector" | sed 's/[\/&]/\\&/g')
        escaped_new_connector=$(echo "$new_connector" | sed 's/[\/&]/\\&/g')
        sed -i "s|$escaped_connector|$escaped_new_connector|" "$temp_file"
        
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Connector schemes updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Connector Configuration:"
    grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML" | sed 's/^/  /'
}

main() {
    echo "CIS 6.3 Check - Connector Schemes"
    echo "--------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_connector_schemes
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_connector_schemes
            echo -e "\n${GREEN}Fix completed. Please restart Tomcat to apply changes.${NC}"
            echo -e "\n${YELLOW}[WARNING] Verify SSL certificates are properly configured for HTTPS connectors${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main