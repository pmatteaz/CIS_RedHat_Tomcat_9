#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
LOGS_DIR="$TOMCAT_HOME/logs"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_logs_dir() {
    if [ ! -d "$LOGS_DIR" ]; then
        echo -e "${RED}[ERROR] Logs directory not found: $LOGS_DIR${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local dir_owner=$(stat -c '%U' "$LOGS_DIR")
    local dir_group=$(stat -c '%G' "$LOGS_DIR")
    
    if [ "$dir_owner" != "$TOMCAT_USER" ] || [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid ownership: $dir_owner:$dir_group${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Directory ownership${NC}"
    fi
    
    find "$LOGS_DIR" -type f -print0 | while IFS= read -r -d '' file; do
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
    local dir_perms=$(stat -c '%a' "$LOGS_DIR")
    
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Invalid directory permissions: $dir_perms${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Directory permissions${NC}"
    fi
    
    find "$LOGS_DIR" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for $file: $perms${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$LOGS_DIR"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 750 "$LOGS_DIR"
    find "$LOGS_DIR" -type f -exec chmod 640 {} \;
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.4 Check - Logs Directory Access"
    
    check_logs_dir
    
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