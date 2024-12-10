#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
WEB_XML="$TOMCAT_HOME/conf/web.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$WEB_XML" ]; then
        echo -e "${RED}[ERROR] web.xml not found: $WEB_XML${NC}"
        exit 1
    fi
}

check_ownership() {
    local result=0
    local owner=$(stat -c '%U' "$WEB_XML")
    local group=$(stat -c '%G' "$WEB_XML")
    
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
    local perms=$(stat -c '%a' "$WEB_XML")
    
    if [ "$perms" != "640" ]; then
        echo -e "${YELLOW}[WARN] Invalid permissions: $perms (should be 640)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] File permissions${NC}"
    fi
    
    return $result
}

check_web_config() {
    local result=0
    
    # Check for security configurations
    local security_checks=(
        "<security-constraint>"
        "<transport-guarantee>CONFIDENTIAL</transport-guarantee>"
        "<session-config>"
    )
    
    for check in "${security_checks[@]}"; do
        if ! grep -q "$check" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Recommended security configuration missing: $check${NC}"
            result=1
        fi
    done
    
    # Check for dangerous servlet configurations
    local dangerous_patterns=(
        "debug=\"true\""
        "listings=\"true\""
        "allowTrace=\"true\""
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        if grep -q "$pattern" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Potentially dangerous configuration found: $pattern${NC}"
            result=1
        fi
    done
    
    return $result
}

create_backup() {
    local backup_file="${WEB_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$WEB_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_ownership() {
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$WEB_XML"
    echo -e "${GREEN}[OK] Fixed ownership${NC}"
}

fix_permissions() {
    chmod 640 "$WEB_XML"
    echo -e "${GREEN}[OK] Fixed permissions${NC}"
}

print_current_status() {
    echo -e "\n${YELLOW}Current Status:${NC}"
    echo -e "File: $WEB_XML"
    echo -e "Owner: $(stat -c '%U' "$WEB_XML")"
    echo -e "Group: $(stat -c '%G' "$WEB_XML")"
    echo -e "Permissions: $(stat -c '%a' "$WEB_XML")"
    
    # Additional security checks
    echo -e "\nSecurity Configuration Status:"
    if ! grep -q "<security-constraint>" "$WEB_XML"; then
        echo -e "${YELLOW}- No security constraints defined${NC}"
    fi
    
    if ! grep -q "<session-timeout>" "$WEB_XML"; then
        echo -e "${YELLOW}- Session timeout not configured${NC}"
    fi
    
    if grep -q "debug=\"true\"" "$WEB_XML"; then
        echo -e "${YELLOW}- Debug mode enabled${NC}"
    fi
}

main() {
    echo "CIS 4.14 Check - web.xml Access"
    echo "------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_ownership
    needs_fix=$((needs_fix + $?))
    
    check_permissions
    needs_fix=$((needs_fix + $?))
    
    check_web_config
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
            echo -e "${YELLOW}[WARNING] Please review web.xml manually for security configurations:${NC}"
            echo -e "  - Security constraints"
            echo -e "  - Session configuration"
            echo -e "  - Debug settings"
            echo -e "  - Directory listings"
            echo -e "${YELLOW}[INFO] Backup created at ${WEB_XML}.*.bak${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main