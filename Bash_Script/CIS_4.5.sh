#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TEMP_DIR="$TOMCAT_HOME/temp"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_temp_dir() {
    if [ ! -d "$TEMP_DIR" ]; then
        echo -e "${RED}[ERROR] Temp directory not found: $TEMP_DIR${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    
    # Check temp directory ownership
    local dir_owner=$(stat -c '%U' "$TEMP_DIR")
    local dir_group=$(stat -c '%G' "$TEMP_DIR")
    
    if [ "$dir_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Invalid temp directory owner: $dir_owner (should be $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Temp directory owner${NC}"
    fi
    
    if [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid temp directory group: $dir_group (should be $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Temp directory group${NC}"
    fi
    
    # Check ownership of contents
    find "$TEMP_DIR" -print0 | while IFS= read -r -d '' item; do
        if [ "$item" != "$TEMP_DIR" ]; then
            owner=$(stat -c '%U' "$item")
            group=$(stat -c '%G' "$item")
            if [ "$owner" != "$TOMCAT_USER" ] || [ "$group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] Invalid ownership for $item: $owner:$group${NC}"
                result=1
            fi
        fi
    done
    
    return $result
}

check_permissions() {
    local result=0
    
    # Check temp directory permissions
    local dir_perms=$(stat -c '%a' "$TEMP_DIR")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Invalid temp directory permissions: $dir_perms (should be 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Temp directory permissions${NC}"
    fi
    
    # Check permissions of contents
    find "$TEMP_DIR" -type d -print0 | while IFS= read -r -d '' dir; do
        if [ "$dir" != "$TEMP_DIR" ]; then
            perms=$(stat -c '%a' "$dir")
            if [ "$perms" != "750" ]; then
                echo -e "${YELLOW}[WARN] Invalid permissions for directory $dir: $perms${NC}"
                result=1
            fi
        fi
    done
    
    find "$TEMP_DIR" -type f -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for file $file: $perms${NC}"
            result=1
        fi
    done
    
    return $result
}

cleanup_temp() {
    echo -e "${YELLOW}[INFO] Cleaning up temp directory contents...${NC}"
    rm -rf "$TEMP_DIR"/*
    echo -e "${GREEN}[OK] Temp directory cleaned${NC}"
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$TEMP_DIR"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    # Set temp directory permissions
    chmod 750 "$TEMP_DIR"
    
    # Set permissions for subdirectories
    find "$TEMP_DIR" -type d -exec chmod 750 {} \;
    
    # Set permissions for files
    find "$TEMP_DIR" -type f -exec chmod 640 {} \;
    
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.5 Check - Temp Directory Access"
    echo "------------------------------------"
    
    check_temp_dir
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cleanup_temp
            fix_ownership
            fix_permissions
            echo -e "\n${GREEN}Fix completed. You may need to restart Tomcat for changes to take effect.${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main