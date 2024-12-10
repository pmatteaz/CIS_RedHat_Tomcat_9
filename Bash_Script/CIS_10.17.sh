#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Security Lifecycle Listener class
LISTENER_CLASS="org.apache.catalina.security.SecurityListener"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default security values
UMASK="0007"
MIN_UMASK="0007"

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        exit 1
    fi
}

check_security_listener() {
    local result=0
    
    echo -e "\nChecking Security Lifecycle Listener configuration:"
    
    # Check if listener is present
    if ! grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Security Lifecycle Listener not configured${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Security Lifecycle Listener found${NC}"
        
        # Check security attributes
        local listener_line=$(grep "$LISTENER_CLASS" "$SERVER_XML")
        
        # Check checkedOsUsers
        if ! echo "$listener_line" | grep -q "checkedOsUsers="; then
            echo -e "${YELLOW}[WARN] checkedOsUsers not configured${NC}"
            result=1
        fi
        
        # Check minimumUmask
        if ! echo "$listener_line" | grep -q "minimumUmask=\"$MIN_UMASK\""; then
            echo -e "${YELLOW}[WARN] minimumUmask not set to $MIN_UMASK${NC}"
            result=1
        fi
    fi
    
    # Check actual system umask
    local current_umask=$(umask)
    if [[ "$current_umask" != "$UMASK" ]]; then
        echo -e "${YELLOW}[WARN] System umask ($current_umask) does not match required umask ($UMASK)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] System umask is correctly set${NC}"
    fi
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_security_listener() {
    create_backup
    
    local temp_file=$(mktemp)
    
    if ! grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        # Add Security Lifecycle Listener if not present
        sed '/<Server/a \    <Listener className="'"$LISTENER_CLASS"'" \
        checkedOsUsers="tomcat" \
        minimumUmask="'"$MIN_UMASK"'" />' "$SERVER_XML" > "$temp_file"
    else
        # Update existing Security Lifecycle Listener
        sed -E '/'"$LISTENER_CLASS"'/ {
            s/minimumUmask="[^"]*"/minimumUmask="'"$MIN_UMASK"'"/g
            /checkedOsUsers=/! s/\/>/ checkedOsUsers="tomcat"\/>/g
        }' "$SERVER_XML" > "$temp_file"
    fi
    
    # Apply changes
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    # Update system umask if needed
    if [[ "$(umask)" != "$UMASK" ]]; then
        echo -e "${YELLOW}[INFO] Updating system umask...${NC}"
        umask "$UMASK"
        
        # Add umask to Tomcat service file if it exists
        if [ -f "/etc/systemd/system/tomcat.service" ]; then
            sed -i "/\[Service\]/a UMask=$UMASK" "/etc/systemd/system/tomcat.service"
            systemctl daemon-reload
        fi
        
        # Add umask to startup scripts
        for script in "$TOMCAT_HOME/bin/"*.sh; do
            if [ -f "$script" ]; then
                if ! grep -q "umask $UMASK" "$script"; then
                    sed -i "2i umask $UMASK" "$script"
                fi
            fi
        done
    fi
    
    echo -e "${GREEN}[OK] Security Lifecycle Listener configuration updated${NC}"
}

verify_configuration() {
    echo -e "\nVerifying configuration:"
    
    if grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Security Lifecycle Listener is configured${NC}"
        grep -A 1 "$LISTENER_CLASS" "$SERVER_XML" | sed 's/^/  /'
        
        # Verify umask
        if [[ "$(umask)" == "$UMASK" ]]; then
            echo -e "${GREEN}[OK] System umask is correct${NC}"
        else
            echo -e "${YELLOW}[WARN] System umask is not correct. Please restart Tomcat${NC}"
        fi
        
        # Verify service file
        if [ -f "/etc/systemd/system/tomcat.service" ]; then
            if grep -q "UMask=$UMASK" "/etc/systemd/system/tomcat.service"; then
                echo -e "${GREEN}[OK] Service file umask is correct${NC}"
            else
                echo -e "${YELLOW}[WARN] Service file umask not set${NC}"
            fi
        fi
        
        # Verify startup scripts
        local scripts_ok=true
        for script in "$TOMCAT_HOME/bin/"*.sh; do
            if [ -f "$script" ] && ! grep -q "umask $UMASK" "$script"; then
                scripts_ok=false
                break
            fi
        done
        if [ "$scripts_ok" = true ]; then
            echo -e "${GREEN}[OK] Startup scripts umask is correct${NC}"
        else
            echo -e "${YELLOW}[WARN] Some startup scripts missing umask${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Security Lifecycle Listener not found after fix${NC}"
    fi
}

print_current_status() {
    echo -e "\nCurrent Security Configuration:"
    echo -e "Current system umask: $(umask)"
    
    if grep -q "$LISTENER_CLASS" "$SERVER_XML"; then
        echo -e "\nSecurity Lifecycle Listener configuration:"
        grep -A 1 "$LISTENER_CLASS" "$SERVER_XML" | sed 's/^/  /'
    else
        echo -e "${YELLOW}  Security Lifecycle Listener not configured${NC}"
    fi
    
    if [ -f "/etc/systemd/system/tomcat.service" ]; then
        echo -e "\nService file umask setting:"
        grep "UMask" "/etc/systemd/system/tomcat.service" 2>/dev/null | sed 's/^/  /' || echo "  No UMask setting found"
    fi
}

main() {
    echo "CIS 10.17 Check - Security Lifecycle Listener"
    echo "------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_security_listener
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_security_listener
            verify_configuration
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review security listener settings"
            echo -e "2. Verify umask settings"
            echo -e "3. Check service configuration"
            echo -e "4. Review startup scripts"
            echo -e "5. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Update the checkedOsUsers list according to your environment${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main