#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] context.xml not found: $CONTEXT_XML${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$CONTEXT_XML")
    local group=$(stat -c '%G' "$CONTEXT_XML")
    
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
    local perms=$(stat -c '%a' "$CONTEXT_XML")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_context_contents() {
    local result=0
    
    # Check for basic Context configuration
    if ! grep -q "<Context>" "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] Missing basic Context configuration${NC}"
        result=1
    fi
    
    # Check for security-related attributes
    local security_checks=(
        "allowLinking=\"false\""
        "privileged=\"false\""
        "crossContext=\"false\""
    )
    
    for check in "${security_checks[@]}"; do
        if ! grep -q "$check" "$CONTEXT_XML"; then
            echo -e "${YELLOW}[WARN] Recommended security setting missing: $check${NC}"
            result=1
        fi
    done
    
    # Check for dangerous configurations
    if grep -q "allowLinking=\"true\"" "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] Dangerous setting found: allowLinking=\"true\"${NC}"
        result=1
    fi
    
    return $result
}

create_backup() {
    local backup_file="${CONTEXT_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$CONTEXT_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CONTEXT_XML"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$CONTEXT_XML"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

print_current_status() {
    echo -e "\n${YELLOW}Current Status:${NC}"
    echo -e "File: $CONTEXT_XML"
    echo -e "Owner: $(stat -c '%U' "$CONTEXT_XML")"
    echo -e "Group: $(stat -c '%G' "$CONTEXT_XML")"
    echo -e "Permissions: $(stat -c '%a' "$CONTEXT_XML")"
}

main() {
    echo "CIS 4.10 Check - context.xml Access"
    echo "----------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_context_contents
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
            echo -e "${YELLOW}[WARNING] Please review context.xml contents manually for security configuration${NC}"
            echo -e "${YELLOW}[INFO] Backup created at ${CONTEXT_XML}.*.bak${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main