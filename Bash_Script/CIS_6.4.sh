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

check_secure_attribute() {
    local result=0
    
    echo -e "\nChecking Connector secure attributes:"
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local ssl_enabled=$(echo "$connector" | grep -oP 'SSLEnabled="\K[^"]+' || echo "false")
        local secure=$(echo "$connector" | grep -oP 'secure="\K[^"]+' || echo "false")
        local protocol=$(echo "$connector" | grep -oP 'protocol="\K[^"]+' || echo "HTTP/1.1")
        
        echo -e "\nAnalyzing connector on port $port (Protocol: $protocol):"
        
        if [ "$ssl_enabled" == "true" ] && [ "$secure" != "true" ]; then
            echo -e "${YELLOW}[WARN] SSL enabled but secure attribute is false on port $port${NC}"
            result=1
        elif [ "$ssl_enabled" != "true" ] && [ "$secure" == "true" ]; then
            echo -e "${YELLOW}[WARN] SSL disabled but secure attribute is true on port $port${NC}"
            result=1
        elif [ "$ssl_enabled" == "true" ] && [ "$secure" == "true" ]; then
            echo -e "${GREEN}[OK] SSL enabled and secure attribute is true on port $port${NC}"
        else
            echo -e "${GREEN}[OK] SSL disabled and secure attribute is false on port $port${NC}"
        fi
        
        # Additional check for missing secure attribute
        if ! echo "$connector" | grep -q 'secure="'; then
            echo -e "${YELLOW}[WARN] secure attribute not explicitly set on port $port${NC}"
            result=1
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_secure_attribute() {
    local temp_file=$(mktemp)
    cp "$SERVER_XML" "$temp_file"
    
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local ssl_enabled=$(echo "$connector" | grep -oP 'SSLEnabled="\K[^"]+' || echo "false")
        local new_connector="$connector"
        
        if [ "$ssl_enabled" == "true" ]; then
            # Set secure="true" for SSL-enabled connectors
            if echo "$connector" | grep -q 'secure="'; then
                new_connector=$(echo "$connector" | sed 's/secure="[^"]*"/secure="true"/')
            else
                new_connector=$(echo "$connector" | sed 's/>/ secure="true">/')
            fi
        else
            # Set secure="false" for non-SSL connectors
            if echo "$connector" | grep -q 'secure="'; then
                new_connector=$(echo "$connector" | sed 's/secure="[^"]*"/secure="false"/')
            else
                new_connector=$(echo "$connector" | sed 's/>/ secure="false">/')
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
    
    echo -e "${GREEN}[OK] Secure attributes updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Connector Configuration:"
    grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML" | sed 's/^/  /'
}

main() {
    echo "CIS 6.4 Check - Secure Attribute Configuration"
    echo "--------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_secure_attribute
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_secure_attribute
            echo -e "\n${GREEN}Fix completed. Please restart Tomcat to apply changes.${NC}"
            echo -e "${YELLOW}[WARNING] Verify SSL configuration for secure connectors${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main