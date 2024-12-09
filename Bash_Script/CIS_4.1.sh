#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_directory() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] $TOMCAT_HOME not found${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local current_owner=$(stat -c '%U' "$TOMCAT_HOME")
    local current_group=$(stat -c '%G' "$TOMCAT_HOME")
    
    if [ "$current_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] $TOMCAT_HOME owner is $current_owner (should be $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Owner is correct${NC}"
    fi
    
    if [ "$current_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] $TOMCAT_HOME group is $current_group (should be $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Group is correct${NC}"
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    # Check CATALINA_HOME permissions
    local dir_perms=$(stat -c '%a' "$TOMCAT_HOME")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] $TOMCAT_HOME permissions are $dir_perms (should be 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Directory permissions are correct${NC}"
    fi
    
    # Check subdirectories and files
    find "$TOMCAT_HOME" -type d -print0 | while IFS= read -r -d '' dir; do
        perms=$(stat -c '%a' "$dir")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Directory $dir has permissions $perms${NC}"
            result=1
        fi
    done
    
    find "$TOMCAT_HOME" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] File $file has permissions $perms${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$TOMCAT_HOME"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    # Set directory permissions
    find "$TOMCAT_HOME" -type d -exec chmod 750 {} \;
    
    # Set file permissions
    find "$TOMCAT_HOME" -type f -exec chmod 640 {} \;
    
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.1 Check - $CATALINA_HOME Access Restrictions"
    echo "------------------------------------------------"
    
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
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main