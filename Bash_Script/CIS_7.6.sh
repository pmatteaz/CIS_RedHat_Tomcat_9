#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
LOGGING_PROPERTIES="$TOMCAT_HOME/conf/logging.properties"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
DEFAULT_LOG_DIR="${TOMCAT_HOME}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$LOGGING_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] logging.properties not found: $LOGGING_PROPERTIES${NC}"
        exit 1
    fi
}

get_log_directories() {
    # Extract all directory properties from logging.properties
    grep -i "directory" "$LOGGING_PROPERTIES" | cut -d'=' -f2 | tr -d ' ' | sort -u
}

check_directory_security() {
    local result=0
    
    echo -e "\nChecking logging directories security:"
    
    # Get all unique log directories
    local directories=$(get_log_directories)
    
    if [ -z "$directories" ]; then
        echo -e "${YELLOW}[WARN] No log directories found in configuration${NC}"
        result=1
    else
        while IFS= read -r dir; do
            # Resolve variables in directory path
            dir=$(eval echo "$dir")
            echo -e "\nChecking directory: $dir"
            
            # Check if directory exists
            if [ ! -d "$dir" ]; then
                echo -e "${YELLOW}[WARN] Directory does not exist: $dir${NC}"
                result=1
                continue
            }
            
            # Check ownership
            local owner=$(stat -c '%U' "$dir")
            local group=$(stat -c '%G' "$dir")
            
            if [ "$owner" != "$TOMCAT_USER" ]; then
                echo -e "${YELLOW}[WARN] Invalid owner: $owner (should be $TOMCAT_USER)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Directory owner${NC}"
            fi
            
            if [ "$group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] Invalid group: $group (should be $TOMCAT_GROUP)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Directory group${NC}"
            fi
            
            # Check permissions
            local perms=$(stat -c '%a' "$dir")
            if [ "$perms" != "750" ]; then
                echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 750)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Directory permissions${NC}"
            fi
            
            # Check parent directory security
            local parent_dir=$(dirname "$dir")
            local parent_perms=$(stat -c '%a' "$parent_dir")
            if [[ "$parent_perms" =~ ^[0-7]{3}[7]$ ]]; then
                echo -e "${YELLOW}[WARN] Parent directory has world-writable permissions: $parent_dir${NC}"
                result=1
            fi
            
            # Check for symbolic links
            if [ -L "$dir" ]; then
                echo -e "${YELLOW}[WARN] Directory is a symbolic link: $dir${NC}"
                result=1
            fi
            
        done <<< "$directories"
    fi
    
    return $result
}

create_backup() {
    local backup_file="${LOGGING_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$LOGGING_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_directory_security() {
    create_backup
    
    local directories=$(get_log_directories)
    
    while IFS= read -r dir; do
        # Resolve variables in directory path
        dir=$(eval echo "$dir")
        echo -e "\nSecuring directory: $dir"
        
        # Create directory if it doesn't exist
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo -e "${GREEN}[OK] Created directory: $dir${NC}"
        fi
        
        # Fix ownership and permissions
        chown "$TOMCAT_USER:$TOMCAT_GROUP" "$dir"
        chmod 750 "$dir"
        
        # Fix parent directory if world-writable
        local parent_dir=$(dirname "$dir")
        local parent_perms=$(stat -c '%a' "$parent_dir")
        if [[ "$parent_perms" =~ ^[0-7]{3}[7]$ ]]; then
            chmod o-w "$parent_dir"
            echo -e "${GREEN}[OK] Removed world-writable permission from parent directory: $parent_dir${NC}"
        fi
        
        # Handle symbolic links
        if [ -L "$dir" ]; then
            local real_path=$(readlink -f "$dir")
            rm "$dir"
            mkdir -p "$real_path"
            chown "$TOMCAT_USER:$TOMCAT_GROUP" "$real_path"
            chmod 750 "$real_path"
            echo -e "${GREEN}[OK] Replaced symbolic link with real directory: $real_path${NC}"
        fi
        
    done <<< "$directories"
}

print_current_status() {
    echo -e "\nCurrent Log Directory Configuration:"
    
    local directories=$(get_log_directories)
    while IFS= read -r dir; do
        dir=$(eval echo "$dir")
        echo -e "\nDirectory: $dir"
        if [ -d "$dir" ]; then
            echo -e "Owner: $(stat -c '%U' "$dir")"
            echo -e "Group: $(stat -c '%G' "$dir")"
            echo -e "Permissions: $(stat -c '%a' "$dir")"
            if [ -L "$dir" ]; then
                echo -e "Type: Symbolic Link -> $(readlink -f "$dir")"
            else
                echo -e "Type: Directory"
            fi
        else
            echo -e "Status: Does not exist"
        fi
    done <<< "$directories"
}

main() {
    echo "CIS 7.6 Check - Logging Directory Security"
    echo "----------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_directory_security
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_directory_security
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Verify log directory locations"
            echo -e "2. Check logging functionality"
            echo -e "3. Review symbolic link replacements"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main