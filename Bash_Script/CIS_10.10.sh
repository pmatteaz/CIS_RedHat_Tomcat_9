#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Recommended max header size in bytes (8KB)
RECOMMENDED_SIZE=8192

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

check_max_header_size() {
    local result=0
    
    echo -e "\nChecking maxHttpHeaderSize settings:"
    
    # Check all HTTP Connector elements
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local protocol=$(echo "$connector" | grep -oP 'protocol="\K[^"]+' || echo "HTTP/1.1")
        local max_size=$(echo "$connector" | grep -oP 'maxHttpHeaderSize="\K[^"]+' || echo "0")
        
        echo -e "\nChecking Connector (Port: $port, Protocol: $protocol):"
        
        if [ -z "$max_size" ] || [ "$max_size" == "0" ]; then
            echo -e "${YELLOW}[WARN] maxHttpHeaderSize not set for port $port${NC}"
            result=1
        elif [ "$max_size" -gt "$RECOMMENDED_SIZE" ]; then
            echo -e "${YELLOW}[WARN] maxHttpHeaderSize too large ($max_size bytes) for port $port${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] maxHttpHeaderSize properly configured ($max_size bytes)${NC}"
        fi
    done < <(grep -E "<Connector[^>]+protocol=\"HTTP/1\.1\"" "$SERVER_XML")
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_max_header_size() {
    create_backup
    
    local temp_file=$(mktemp)
    
    # Process each Connector element
    while IFS= read -r line; do
        if [[ "$line" =~ \<Connector[^>]+protocol=\"HTTP/1\.1\" ]]; then
            if echo "$line" | grep -q "maxHttpHeaderSize=\""; then
                # Update existing maxHttpHeaderSize
                line=$(echo "$line" | sed "s/maxHttpHeaderSize=\"[^\"]*\"/maxHttpHeaderSize=\"$RECOMMENDED_SIZE\"/")
            else
                # Add maxHttpHeaderSize attribute
                line=$(echo "$line" | sed "s/>/ maxHttpHeaderSize=\"$RECOMMENDED_SIZE\">/")
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] MaxHttpHeaderSize settings updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent HTTP Connector Configuration:"
    grep -E "<Connector[^>]+protocol=\"HTTP/1\.1\"" "$SERVER_XML" | sed 's/^/  /'
}

verify_changes() {
    echo -e "\nVerifying changes:"
    local issues=0
    
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local max_size=$(echo "$connector" | grep -oP 'maxHttpHeaderSize="\K[^"]+' || echo "0")
        
        if [ "$max_size" != "$RECOMMENDED_SIZE" ]; then
            echo -e "${YELLOW}[WARN] Port $port still has incorrect maxHttpHeaderSize: $max_size${NC}"
            issues=1
        else
            echo -e "${GREEN}[OK] Port $port maxHttpHeaderSize configured correctly${NC}"
        fi
    done < <(grep -E "<Connector[^>]+protocol=\"HTTP/1\.1\"" "$SERVER_XML")
    
    return $issues
}

main() {
    echo "CIS 10.10 Check - MaxHttpHeaderSize Configuration"
    echo "----------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_max_header_size
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_max_header_size
            verify_changes
            
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review maxHttpHeaderSize settings"
            echo -e "2. Test application functionality"
            echo -e "3. Monitor for any header size related issues"
            echo -e "4. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] MaxHttpHeaderSize set to $RECOMMENDED_SIZE bytes${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main