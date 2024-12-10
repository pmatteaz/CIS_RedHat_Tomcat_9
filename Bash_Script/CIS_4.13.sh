#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USERS_XML="$TOMCAT_HOME/conf/tomcat-users.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$TOMCAT_USERS_XML" ]; then
        echo -e "${RED}[ERROR] tomcat-users.xml not found: $TOMCAT_USERS_XML${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$TOMCAT_USERS_XML")
    local group=$(stat -c '%G' "$TOMCAT_USERS_XML")
    
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
    local perms=$(stat -c '%a' "$TOMCAT_USERS_XML")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_users_config() {
    local result=0
    
    # Check for plaintext passwords
    if grep -q "<user.*password=\"[^\"]*\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}[WARN] Plaintext passwords found in configuration${NC}"
        result=1
    fi
    
    # Check for default roles
    local default_roles=("admin" "manager" "admin-gui" "manager-gui")
    for role in "${default_roles[@]}"; do
        if grep -qi "role=\".*${role}.*\"" "$TOMCAT_USERS_XML"; then
            echo -e "${YELLOW}[WARN] Default role '$role' found${NC}"
            result=1
        fi
    done
    
    return $result
}

create_backup() {
    local backup_file="${TOMCAT_USERS_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$TOMCAT_USERS_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$TOMCAT_USERS_XML"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$TOMCAT_USERS_XML"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

print_current_status() {
    echo -e "\n${YELLOW}Current Status:${NC}"
    echo -e "File: $TOMCAT_USERS_XML"
    echo -e "Owner: $(stat -c '%U' "$TOMCAT_USERS_XML")"
    echo -e "Group: $(stat -c '%G' "$TOMCAT_USERS_XML")"
    echo -e "Permissions: $(stat -c '%a' "$TOMCAT_USERS_XML")"
    
    # Additional security checks
    echo -e "\nSecurity Analysis:"
    local user_count=$(grep -c "<user " "$TOMCAT_USERS_XML")
    echo -e "- Number of defined users: $user_count"
    
    if grep -q "password=\"\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}- Empty passwords detected${NC}"
    fi
    
    if grep -q "<user.*roles=\".*manager-gui.*\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}- Manager GUI access configured${NC}"
    fi
}

main() {
    echo "CIS 4.13 Check - tomcat-users.xml Access"
    echo "---------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_users_config
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
            echo -e "${YELLOW}[WARNING] Please review tomcat-users.xml manually for:${NC}"
            echo -e "  - Plaintext passwords"
            echo -e "  - Default/unnecessary roles"
            echo -e "  - Unnecessary user accounts"
            echo -e "${YELLOW}[INFO] Backup created at ${TOMCAT_USERS_XML}.*.bak${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main