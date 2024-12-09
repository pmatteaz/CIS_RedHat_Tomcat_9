#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CONF_DIR="$TOMCAT_HOME/conf"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_conf_dir() {
    if [ ! -d "$CONF_DIR" ]; then
        echo -e "${RED}[ERROR] Configuration directory not found: $CONF_DIR${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    
    # Check conf directory ownership
    local dir_owner=$(stat -c '%U' "$CONF_DIR")
    local dir_group=$(stat -c '%G' "$CONF_DIR")
    
    if [ "$dir_owner" != "$TOMCAT_USER" ] || [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid ownership: $dir_owner:$dir_group${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Directory ownership${NC}"
    fi
    
    # Check conf files ownership
    find "$CONF_DIR" -type f -print0 | while IFS= read -r -d '' file; do
        owner=$(stat -c '%U' "$file")
        group=$(stat -c '%G' "$file")
        if [ "$owner" != "$TOMCAT_USER" ] || [ "$group" != "$TOMCAT_GROUP" ]; then
            echo -e "${YELLOW}[WARN] Invalid ownership for $file: $owner:$group${NC}"
            result=1
        fi
    done
    
    return $result
}

check_permissions() {
    local result=0
    
    # Check conf directory permissions
    local dir_perms=$(stat -c '%a' "$CONF_DIR")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Invalid directory permissions: $dir_perms${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Directory permissions${NC}"
    fi
    
    # Check conf files permissions
    find "$CONF_DIR" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for $file: $perms${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$CONF_DIR"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 750 "$CONF_DIR"
    find "$CONF_DIR" -type f -exec chmod 640 {} \;
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.3 Check - Configuration Directory Access"
    
    check_conf_dir
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed${NC}"
        fi
    fi
}

main