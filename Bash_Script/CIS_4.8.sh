#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CATALINA_PROPERTIES="$TOMCAT_HOME/conf/catalina.properties"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$CATALINA_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] catalina.properties not found: $CATALINA_PROPERTIES${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$CATALINA_PROPERTIES")
    local group=$(stat -c '%G' "$CATALINA_PROPERTIES")
    
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
    local perms=$(stat -c '%a' "$CATALINA_PROPERTIES")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

create_backup() {
    local backup_file="${CATALINA_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$CATALINA_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_PROPERTIES"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$CATALINA_PROPERTIES"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

check_file_contents() {
    local result=0
    
    # Check for sensitive properties
    local sensitive_props=(
        "package.access"
        "package.definition"
        "common.loader"
        "shared.loader"
    )
    
    for prop in "${sensitive_props[@]}"; do
        if ! grep -q "^${prop}=" "$CATALINA_PROPERTIES"; then
            echo -e "${YELLOW}[WARN] Missing property: $prop${NC}"
            result=1
        fi
    done
    
    return $result
}

main() {
    echo "CIS 4.8 Check - catalina.properties Access"
    echo "----------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_file_contents
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main