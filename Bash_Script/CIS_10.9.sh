#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Recommended timeout in milliseconds (60 seconds)
RECOMMENDED_TIMEOUT=60000

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

check_connection_timeout() {
    local result=0
    
    echo -e "\nChecking connection timeout settings:"
    
    # Check all Connector elements
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local protocol=$(echo "$connector" | grep -oP 'protocol="\K[^"]+' || echo "HTTP/1.1")
        local timeout=$(echo "$connector" | grep -oP 'connectionTimeout="\K[^"]+' || echo "0")
        
        echo -e "\nChecking Connector (Port: $port, Protocol: $protocol):"
        
        if [ -z "$timeout" ] || [ "$timeout" == "0" ]; then
            echo -e "${YELLOW}[WARN] connectionTimeout not set for port $port${NC}"
            result=1
        elif [ "$timeout" -gt "$RECOMMENDED_TIMEOUT" ]; then
            echo -e "${YELLOW}[WARN] connectionTimeout too high ($timeout ms) for port $port${NC}"
            result=1
        elif [ "$timeout" -lt "$RECOMMENDED_TIMEOUT" ]; then
            echo -e "${YELLOW}[WARN] connectionTimeout too low ($timeout ms) for port $port${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] connectionTimeout properly configured ($timeout ms)${NC}"
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_connection_timeout() {
    create_backup
    
    local temp_file=$(mktemp)
    
    # Process each Connector element
    while IFS= read -r line; do
        if [[ "$line" =~ \<Connector[^>]+ ]]; then
            if echo "$line" | grep -q "connectionTimeout=\""; then
                # Update existing connectionTimeout
                line=$(echo "$line" | sed "s/connectionTimeout=\"[^\"]*\"/connectionTimeout=\"$RECOMMENDED_TIMEOUT\"/")
            else
                # Add connectionTimeout attribute
                line=$(echo "$line" | sed "s/>/ connectionTimeout=\"$RECOMMENDED_TIMEOUT\">/")
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Connection timeout settings updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Connector Configuration:"
    grep -E "<Connector[^>]+" "$SERVER_XML" | sed 's/^/  /'
}

verify_changes() {
    echo -e "\nVerifying changes:"
    local issues=0
    
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local timeout=$(echo "$connector" | grep -oP 'connectionTimeout="\K[^"]+' || echo "0")
        
        if [ "$timeout" != "$RECOMMENDED_TIMEOUT" ]; then
            echo -e "${YELLOW}[WARN] Port $port still has incorrect timeout: $timeout${NC}"
            issues=1
        else
            echo -e "${GREEN}[OK] Port $port timeout configured correctly${NC}"
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    return $issues
}

main() {
    echo "CIS 10.9 Check - Connection Timeout Configuration"
    echo "----------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_connection_timeout
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_connection_timeout
            verify_changes
            
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review connection timeout settings"
            echo -e "2. Test application under normal load"
            echo -e "3. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Connection timeout set to $RECOMMENDED_TIMEOUT ms${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main