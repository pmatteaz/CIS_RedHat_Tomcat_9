#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
BIN_DIR="$TOMCAT_HOME/bin"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_bin_dir() {
    if [ ! -d "$BIN_DIR" ]; then
        echo -e "${RED}[ERROR] Binaries directory not found: $BIN_DIR${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    
    # Check bin directory ownership
    local dir_owner=$(stat -c '%U' "$BIN_DIR")
    local dir_group=$(stat -c '%G' "$BIN_DIR")
    
    if [ "$dir_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Invalid bin directory owner: $dir_owner (should be $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Bin directory owner${NC}"
    fi
    
    if [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Invalid bin directory group: $dir_group (should be $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Bin directory group${NC}"
    fi
    
    # Check ownership of binaries and scripts
    find "$BIN_DIR" -type f -print0 | while IFS= read -r -d '' file; do
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
    
    # Check bin directory permissions
    local dir_perms=$(stat -c '%a' "$BIN_DIR")
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Invalid bin directory permissions: $dir_perms (should be 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Bin directory permissions${NC}"
    fi
    
    # Check executable files permissions
    find "$BIN_DIR" -type f -name "*.sh" -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for script $file: $perms (should be 750)${NC}"
            result=1
        fi
    done
    
    # Check other files permissions
    find "$BIN_DIR" -type f ! -name "*.sh" -print0 | while IFS= read -r -d '' file; do
        perms=$(stat -c '%a' "$file")
        if [ "$perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Invalid permissions for file $file: $perms (should be 640)${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_ownership() {
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$BIN_DIR"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    # Set bin directory permissions
    chmod 750 "$BIN_DIR"
    
    # Set executable files permissions
    find "$BIN_DIR" -type f -name "*.sh" -exec chmod 750 {} \;
    
    # Set other files permissions
    find "$BIN_DIR" -type f ! -name "*.sh" -exec chmod 640 {} \;
    
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

main() {
    echo "CIS 4.6 Check - Binaries Directory Access"
    echo "----------------------------------------"
    
    check_bin_dir
    
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
            echo -e "\n${GREEN}Fix completed. You may need to restart Tomcat for changes to take effect.${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main