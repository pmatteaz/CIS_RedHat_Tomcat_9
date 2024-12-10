#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_webapps_dir() {
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] Webapps directory not found: $WEBAPPS_DIR${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    
    # Check webapps directory ownership
    local dir_owner=$(stat -c '%U' "$WEBAPPS_DIR")
    local dir_group=$(stat -c '%G' "$WEBAPPS_DIR")
    
    if [ "$dir_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Invalid webapps directory owner: $dir_owner (should be $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Webapps directory owner${NC}"
    fi
    
    if [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid webapps directory group: $dir_group (should be $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Webapps directory group${NC}"
    fi
    
    # Check ownership of all files and directories recursively
    find "$WEBAPPS_DIR" -print0 | while IFS= read -r -d '' item; do
        owner=$(stat -c '%U' "$item")
        group=$(stat -c '%G' "$item")
        if [ "$owner" != "$TOMCAT_USER" ] || [ "$group" != "$TOMCAT_GROUP" ]; then
            echo -e "${YELLOW}[WARN] Invalid ownership for $item: $owner:$group${NC}"
            result=1
        fi
    done
    
    return $result
}

check_permissions() {
    local result=0
    
    # Check webapps directory permissions
    local dir_perms=$(stat -c '%a' "$WEBAPPS_DIR")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Invalid webapps directory permissions: $dir_perms (should be 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Webapps directory permissions${NC}"
    fi
    
    # Check directory permissions recursively
    find "$WEBAPPS_DIR" -type d -print0 | while IFS= read -r -d '' dir; do
        perms=$(stat -c '%a' "$dir")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for directory $dir: $perms (should be 750)${NC}"
            result=1
        fi
    done
    
    # Check file permissions recursively
    find "$WEBAPPS_DIR" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for file $file: $perms (should be 640)${NC}"
            result=1
        fi
    done
    
    # Special check for WEB-INF and META-INF directories
    find "$WEBAPPS_DIR" -type d \( -name "WEB-INF" -o -name "META-INF" \) -print0 | while IFS= read -r -d '' dir; do
        perms=$(stat -c '%a' "$dir")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for sensitive directory $dir: $perms (should be 750)${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    echo -e "${YELLOW}[INFO] Fixing ownership...${NC}"
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$WEBAPPS_DIR"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    echo -e "${YELLOW}[INFO] Fixing permissions...${NC}"
    
    # Fix directory permissions
    find "$WEBAPPS_DIR" -type d -exec chmod 750 {} \;
    
    # Fix file permissions
    find "$WEBAPPS_DIR" -type f -exec chmod 640 {} \;
    
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

backup_webapps() {
    local backup_dir="/tmp/tomcat_webapps_backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}[INFO] Creating backup in $backup_dir${NC}"
    cp -rp "$WEBAPPS_DIR" "$backup_dir"
    echo -e "${GREEN}[OK] Backup created${NC}"
}

main() {
    echo "CIS 4.7 Check - Web Application Directory Access"
    echo "----------------------------------------------"
    
    check_webapps_dir
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            backup_webapps
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
            echo -e "${YELLOW}[INFO] Backup created in /tmp/tomcat_webapps_backup_*${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main