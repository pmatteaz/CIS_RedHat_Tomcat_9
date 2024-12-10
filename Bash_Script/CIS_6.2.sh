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

check_ssl_connectors() {
    local result=0
    
    # Get all HTTP connectors
    echo -e "\nChecking HTTP/AJP Connectors:"
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        local protocol=$(echo "$connector" | grep -oP 'protocol="\K[^"]+' || echo "HTTP/1.1")
        local ssl_enabled=$(echo "$connector" | grep -oP 'SSLEnabled="\K[^"]+' || echo "false")
        local scheme=$(echo "$connector" | grep -oP 'scheme="\K[^"]+' || echo "http")
        
        # Check if this is a sensitive connector (8443, admin ports, etc)
        if [[ "$port" == "8443" || "$connector" =~ "admin" || "$scheme" == "https" ]]; then
            echo -e "\nChecking sensitive connector on port $port:"
            
            if [ "$ssl_enabled" != "true" ]; then
                echo -e "${YELLOW}[WARN] SSL not enabled on sensitive port $port${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] SSL enabled on port $port${NC}"
            fi
            
            # Check SSL configuration if enabled
            if [ "$ssl_enabled" == "true" ]; then
                # Check for required SSL attributes
                local missing_attrs=0
                for attr in "keystoreFile" "keystorePass" "clientAuth" "sslProtocol"; do
                    if ! echo "$connector" | grep -q "$attr=\""; then
                        echo -e "${YELLOW}[WARN] Missing $attr attribute${NC}"
                        missing_attrs=1
                    fi
                done
                
                # Check SSL protocol version
                if echo "$connector" | grep -q "sslProtocol=\"TLS\""; then
                    echo -e "${GREEN}[OK] Using TLS protocol${NC}"
                else
                    echo -e "${YELLOW}[WARN] Not using TLS protocol${NC}"
                    result=1
                fi
                
                [ $missing_attrs -eq 1 ] && result=1
            fi
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ssl_connectors() {
    local temp_file=$(mktemp)
    cp "$SERVER_XML" "$temp_file"
    
    # Fix each connector
    while IFS= read -r connector; do
        local port=$(echo "$connector" | grep -oP 'port="\K[^"]+')
        
        # Check if this is a sensitive connector
        if [[ "$port" == "8443" || "$connector" =~ "admin" || "$connector" =~ "scheme=\"https\"" ]]; then
            # Prepare new connector configuration
            local new_connector=$(echo "$connector" | \
                sed 's/SSLEnabled="false"/SSLEnabled="true"/' | \
                sed 's/scheme="http"/scheme="https"/' | \
                sed 's/secure="false"/secure="true"/')
            
            # Add SSL configuration if missing
            if ! echo "$new_connector" | grep -q "keystoreFile"; then
                new_connector=$(echo "$new_connector" | sed 's/>/ keystoreFile="${user.home}\/\.keystore" keystorePass="changeit" clientAuth="false" sslProtocol="TLS">/')
            fi
            
            # Replace old connector with new one
            sed -i "s|$connector|$new_connector|" "$temp_file"
        fi
    done < <(grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML")
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] SSL configuration updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent SSL Connector Status:"
    grep -E "<Connector[^>]+(HTTP\/1.1|AJP\/1.3)" "$SERVER_XML" | sed 's/^/  /'
}

main() {
    echo "CIS 6.2 Check - SSL Configuration"
    echo "--------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ssl_connectors
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_ssl_connectors
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Configure proper keystore location and password"
            echo -e "2. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Default keystore settings were applied. Please update them!${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main