#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CATALINA_POLICY="$TOMCAT_HOME/conf/catalina.policy"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$CATALINA_POLICY" ]; then
        echo -e "${RED}[ERROR] catalina.policy not found: $CATALINA_POLICY${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$CATALINA_POLICY")
    local group=$(stat -c '%G' "$CATALINA_POLICY")
    
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
    local perms=$(stat -c '%a' "$CATALINA_POLICY")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_policy_contents() {
    local result=0
    
    # Check for critical security policies
    local required_policies=(
        "grant codeBase \"file:\${catalina.home}/bin/.*\""
        "grant codeBase \"file:\${catalina.home}/lib/.*\""
        "grant codeBase \"file:\${catalina.home}/webapps/.*\""
    )
    
    for policy in "${required_policies[@]}"; do
        if ! grep -q "$policy" "$CATALINA_POLICY"; then
            echo -e "${YELLOW}[WARN] Missing policy: $policy${NC}"
            result=1
        fi
    done
    
    # Check for potentially dangerous permissions
    local dangerous_permissions=(
        "permission java.security.AllPermission"
        "permission java.io.FilePermission \"<<ALL FILES>>\""
    )
    
    for perm in "${dangerous_permissions[@]}"; do
        if grep -q "$perm" "$CATALINA_POLICY"; then
            echo -e "${YELLOW}[WARN] Found potentially dangerous permission: $perm${NC}"
            result=1
        fi
    done
    
    return $result
}

create_backup() {
    local backup_file="${CATALINA_POLICY}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$CATALINA_POLICY" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_POLICY"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$CATALINA_POLICY"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.9 Check - catalina.policy Access"
    echo "-------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_policy_contents
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Current Status:${NC}"
        echo -e "Owner: $(stat -c '%U' "$CATALINA_POLICY")"
        echo -e "Group: $(stat -c '%G' "$CATALINA_POLICY")"
        echo -e "Permissions: $(stat -c '%a' "$CATALINA_POLICY")"
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
            echo -e "${YELLOW}[WARNING] Please review policy contents manually for security issues${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main