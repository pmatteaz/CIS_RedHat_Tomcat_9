#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
LOGGING_PROPERTIES="$TOMCAT_HOME/conf/logging.properties"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

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

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$LOGGING_PROPERTIES")
    local group=$(stat -c '%G' "$LOGGING_PROPERTIES")
    
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
    local perms=$(stat -c '%a' "$LOGGING_PROPERTIES")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_logging_config() {
    local result=0
    
    # Check for essential logging handlers
    local required_handlers=(
        "handlers = "
        "1catalina.org.apache.juli.AsyncFileHandler"
        "2localhost.org.apache.juli.AsyncFileHandler"
        "3manager.org.apache.juli.AsyncFileHandler"
        "4host-manager.org.apache.juli.AsyncFileHandler"
        "java.util.logging.ConsoleHandler"
    )
    
    for handler in "${required_handlers[@]}"; do
        if ! grep -q "$handler" "$LOGGING_PROPERTIES"; then
            echo -e "${YELLOW}[WARN] Missing logging handler: $handler${NC}"
            result=1
        fi
    done
    
    # Check log levels
    if ! grep -q "\.level = INFO" "$LOGGING_PROPERTIES"; then
        echo -e "${YELLOW}[WARN] Default log level should be set to INFO${NC}"
        result=1
    fi
    
    return $result
}

create_backup() {
    local backup_file="${LOGGING_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$LOGGING_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$LOGGING_PROPERTIES"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$LOGGING_PROPERTIES"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

print_current_status() {
    echo -e "\n${YELLOW}Current Status:${NC}"
    echo -e "File: $LOGGING_PROPERTIES"
    echo -e "Owner: $(stat -c '%U' "$LOGGING_PROPERTIES")"
    echo -e "Group: $(stat -c '%G' "$LOGGING_PROPERTIES")"
    echo -e "Permissions: $(stat -c '%a' "$LOGGING_PROPERTIES")"
}

validate_logging_directory() {
    local log_dir=$(grep "^[0-9]*catalina.org.apache.juli.AsyncFileHandler.directory" "$LOGGING_PROPERTIES" | cut -d= -f2 | tr -d ' ')
    
    if [ -n "$log_dir" ] && [ -d "$log_dir" ]; then
        local dir_perms=$(stat -c '%a' "$log_dir")
        if [ "$dir_perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Log directory $log_dir has incorrect permissions: $dir_perms (should be 750)${NC}"
            return 1
        fi
    fi
    return 0
}

main() {
    echo "CIS 4.11 Check - logging.properties Access"
    echo "----------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_logging_config
    needs_fix=$((needs_fix + $?))
    
    validate_logging_directory
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
            echo -e "${YELLOW}[WARNING] Please review logging.properties contents manually${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main