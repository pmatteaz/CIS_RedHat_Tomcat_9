#!/bin/bash

CATALINA_BASE=${CATALINA_BASE:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_directory() {
    if [ ! -d "$CATALINA_BASE" ]; then
        echo -e "${RED}[ERROR] $CATALINA_BASE not found${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local current_owner=$(stat -c '%U' "$CATALINA_BASE")
    local current_group=$(stat -c '%G' "$CATALINA_BASE")
    
    if [ "$current_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Invalid owner: $current_owner${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Owner correct${NC}"
    fi
    
    if [ "$current_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid group: $current_group${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Group correct${NC}"
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    # Check base directory
    local dir_perms=$(stat -c '%a' "$CATALINA_BASE")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Base directory permissions: $dir_perms${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Base directory permissions${NC}"
    fi
    
    # Check critical subdirectories
    local critical_dirs=("conf" "lib" "logs" "temp" "webapps" "work")
    for dir in "${critical_dirs[@]}"; do
        if [ -d "$CATALINA_BASE/$dir" ]; then
            perms=$(stat -c '%a' "$CATALINA_BASE/$dir")
            if [ "$perms" != "750" ]; then
                echo -e "${YELLOW}[WARN] $dir permissions: $perms${NC}"
                result=1
            fi
        fi
    done
    
    # Check configuration files
    find "$CATALINA_BASE/conf" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Config file $file: $perms${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_BASE"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    # Set directory permissions
    find "$CATALINA_BASE" -type d -exec chmod 750 {} \;
    
    # Set file permissions
    find "$CATALINA_BASE" -type f -exec chmod 640 {} \;
    
    # Special permissions for executable files
    find "$CATALINA_BASE/bin" -type f -name "*.sh" -exec chmod 750 {} \;
    
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.2 Check - CATALINA_BASE Access Restrictions"
    
    check_directory
    
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