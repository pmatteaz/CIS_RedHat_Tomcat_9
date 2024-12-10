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

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$SERVER_XML")
    local group=$(stat -c '%G' "$SERVER_XML")
    
    if [ "$owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Invalid owner: $owner (should be $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File owner${NC}"
    fi
    
    if [ "$group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid group: $group (should be $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File group${NC}"
    fi
    
    return $result
}

check_permissions() {
    local result=0
    local perms=$(stat -c '%a' "$SERVER_XML")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_server_config() {
    local result=0
    
    # Check for critical security configurations
    local security_checks=(
        "<Connector.*secure=\"true\""
        "<Connector.*SSLEnabled=\"true\""
        "<Connector.*scheme=\"https\""
        "shutdown=\"NONDETERMINISTICVALUE\""  # Should not be "SHUTDOWN"
    )
    
    for check in "${security_checks[@]}"; do
        if ! grep -q "$check" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Recommended security configuration missing: $check${NC}"
            result=1
        fi
    done
    
    # Check for insecure configurations
    local insecure_patterns=(
        "allowTrace=\"true\""
        "enableLookups=\"true\""
        "server=\"Apache Tomcat\""  # Default server value
        "shutdown=\"SHUTDOWN\""     # Default shutdown value
    )
    
    for pattern in "${insecure_patterns[@]}"; do
        if grep -q "$pattern" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Potentially insecure configuration found: $pattern${NC}"
            result=1
        fi
    done
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$SERVER_XML"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

print_current_status() {
    echo -e "\n${YELLOW}Current Status:${NC}"
    echo -e "File: $SERVER_XML"
    echo -e "Owner: $(stat -c '%U' "$SERVER_XML")"
    echo -e "Group: $(stat -c '%G' "$SERVER_XML")"
    echo -e "Permissions: $(stat -c '%a' "$SERVER_XML")"
    
    # Additional security checks
    echo -e "\nSecurity Configuration Status:"
    if grep -q "shutdown=\"SHUTDOWN\"" "$SERVER_XML"; then
        echo -e "${YELLOW}- Default shutdown command detected${NC}"
    fi
    
    if ! grep -q "<Connector.*SSLEnabled=\"true\"" "$SERVER_XML"; then
        echo -e "${YELLOW}- SSL might not be properly configured${NC}"
    fi
}

main() {
    echo "CIS 4.12 Check - server.xml Access"
    echo "---------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_server_config
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
            echo -e "${YELLOW}[WARNING] Please review server.xml contents manually for security configuration${NC}"
            echo -e "${YELLOW}[INFO] Backup created at ${SERVER_XML}.*.bak${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main