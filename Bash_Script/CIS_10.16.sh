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

# Memory Leak Listener class
LISTENER_CLASS="org.apache.catalina.core.JreMemoryLeakPreventionListener"

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        exit 1
    fi
}

check_memory_leak_listener() {
    local result=0
    
    echo -e "\nChecking Memory Leak Listener configuration:"
    
    # Check if listener is present
    if ! grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Memory Leak Listener not configured${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Memory Leak Listener found${NC}"
        
        # Check listener attributes
        if grep -q "$LISTENER_CLASS.*gcDaemonProtection=\"false\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] GC Daemon Protection is disabled${NC}"
            result=1
        fi
        
        if grep -q "$LISTENER_CLASS.*driverManagerProtection=\"false\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Driver Manager Protection is disabled${NC}"
            result=1
        fi
        
        if grep -q "$LISTENER_CLASS.*urlCacheProtection=\"false\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] URL Cache Protection is disabled${NC}"
            result=1
        fi
    fi
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_memory_leak_listener() {
    create_backup
    
    local temp_file=$(mktemp)
    
    if ! grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        # Add Memory Leak Listener if not present
        sed '/<Server/a \    <Listener className="'"$LISTENER_CLASS"'" \
        gcDaemonProtection="true" \
        driverManagerProtection="true" \
        urlCacheProtection="true" \
        />' "$SERVER_XML" > "$temp_file"
    else
        # Update existing Memory Leak Listener
        sed '/'"$LISTENER_CLASS"'/ {
            s/gcDaemonProtection="false"/gcDaemonProtection="true"/g
            s/driverManagerProtection="false"/driverManagerProtection="true"/g
            s/urlCacheProtection="false"/urlCacheProtection="true"/g
        }' "$SERVER_XML" > "$temp_file"
    fi
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Memory Leak Listener configuration updated${NC}"
}

verify_configuration() {
    echo -e "\nVerifying configuration:"
    
    if grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Memory Leak Listener is configured${NC}"
        grep -A 1 "$LISTENER_CLASS" "$SERVER_XML" | sed 's/^/  /'
    else
        echo -e "${RED}[ERROR] Memory Leak Listener not found after fix${NC}"
    fi
}

print_current_status() {
    echo -e "\nCurrent Memory Leak Listener Configuration:"
    if grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        grep -A 1 "$LISTENER_CLASS" "$SERVER_XML" | sed 's/^/  /'
    else
        echo -e "${YELLOW}  Memory Leak Listener not configured${NC}"
    fi
}

main() {
    echo "CIS 10.16 Check - Memory Leak Listener"
    echo "------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_memory_leak_listener
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_memory_leak_listener
            verify_configuration
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review memory leak protection settings"
            echo -e "2. Monitor memory usage"
            echo -e "3. Check application stability"
            echo -e "4. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[INFO] Memory leak protection enabled with default settings${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main