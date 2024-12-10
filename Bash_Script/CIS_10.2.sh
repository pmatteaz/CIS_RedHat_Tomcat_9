#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
MANAGER_CONTEXT="$TOMCAT_HOME/webapps/manager/META-INF/context.xml"
HOST_MANAGER_CONTEXT="$TOMCAT_HOME/webapps/host-manager/META-INF/context.xml"
TOMCAT_USERS="$TOMCAT_HOME/conf/tomcat-users.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_files_exist() {
    local result=0
    for file in "$MANAGER_CONTEXT" "$HOST_MANAGER_CONTEXT" "$TOMCAT_USERS"; do
        if [ ! -f "$file" ]; then
            echo -e "${YELLOW}[WARN] File not found: $file${NC}"
            result=1
        fi
    done
    return $result
}

check_access_restrictions() {
    local result=0
    
    echo -e "\nChecking web administration access restrictions:"
    
    # Check Manager application
    if [ -f "$MANAGER_CONTEXT" ]; then
        echo -e "\nChecking Manager application:"
        check_context_file "$MANAGER_CONTEXT"
        result=$((result + $?))
    fi
    
    # Check Host Manager application
    if [ -f "$HOST_MANAGER_CONTEXT" ]; then
        echo -e "\nChecking Host Manager application:"
        check_context_file "$HOST_MANAGER_CONTEXT"
        result=$((result + $?))
    fi
    
    # Check tomcat-users.xml
    if [ -f "$TOMCAT_USERS" ]; then
        echo -e "\nChecking tomcat-users.xml:"
        check_users_file
        result=$((result + $?))
    fi
    
    return $result
}

check_context_file() {
    local file=$1
    local result=0
    
    # Check for RemoteAddrValve
    if ! grep -q "org.apache.catalina.valves.RemoteAddrValve" "$file"; then
        echo -e "${YELLOW}[WARN] RemoteAddrValve not configured in $(basename "$file")${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] RemoteAddrValve found${NC}"
        
        # Check allow/deny patterns
        if ! grep -q "allow=\"127\\.\\d+\\.\\d+\\.\\d+|::1|0:0:0:0:0:0:0:1\"" "$file"; then
            echo -e "${YELLOW}[WARN] RemoteAddrValve pattern not properly restricted${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] RemoteAddrValve properly configured${NC}"
        fi
    fi
    
    return $result
}

check_users_file() {
    local result=0
    
    # Check for manager roles
    local restricted_roles=("manager-gui" "manager-script" "manager-jmx" "manager-status" "admin-gui" "admin-script")
    
    for role in "${restricted_roles[@]}"; do
        if grep -q "\"$role\"" "$TOMCAT_USERS"; then
            local users=$(grep -B1 "\"$role\"" "$TOMCAT_USERS" | grep "<user " | wc -l)
            if [ "$users" -gt 1 ]; then
                echo -e "${YELLOW}[WARN] Multiple users found with role: $role${NC}"
                result=1
            fi
        fi
    done
    
    # Check for weak passwords
    if grep -q 'password="[^"]\{0,7\}"' "$TOMCAT_USERS"; then
        echo -e "${YELLOW}[WARN] Weak passwords found (less than 8 characters)${NC}"
        result=1
    fi
    
    return $result
}

create_backup() {
    local file=$1
    local backup_file="${file}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$file" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_context_file() {
    local file=$1
    create_backup "$file"
    
    # Add or update RemoteAddrValve
    if ! grep -q "org.apache.catalina.valves.RemoteAddrValve" "$file"; then
        sed -i '/<Context>/a \    <Valve className="org.apache.catalina.valves.RemoteAddrValve" \
        allow="127\\.\\d+\\.\\d+\\.\\d+|::1|0:0:0:0:0:0:0:1"/>' "$file"
    else
        sed -i 's/allow="[^"]*"/allow="127\\.\\d+\\.\\d+\\.\\d+|::1|0:0:0:0:0:0:0:1"/' "$file"
    fi
    
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    chmod 640 "$file"
}

fix_access_restrictions() {
    echo -e "\nApplying access restrictions:"
    
    # Fix Manager context
    if [ -f "$MANAGER_CONTEXT" ]; then
        echo -e "\nFixing Manager context..."
        fix_context_file "$MANAGER_CONTEXT"
    fi
    
    # Fix Host Manager context
    if [ -f "$HOST_MANAGER_CONTEXT" ]; then
        echo -e "\nFixing Host Manager context..."
        fix_context_file "$HOST_MANAGER_CONTEXT"
    fi
    
    echo -e "\n${GREEN}[OK] Access restrictions updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Access Configuration:"
    
    for file in "$MANAGER_CONTEXT" "$HOST_MANAGER_CONTEXT"; do
        if [ -f "$file" ]; then
            echo -e "\n$(basename "$file"):"
            grep -A 2 "RemoteAddrValve" "$file" 2>/dev/null | sed 's/^/  /'
        fi
    done
}

main() {
    echo "CIS 10.2 Check - Web Administration Access Restrictions"
    echo "---------------------------------------------------"
    
    check_files_exist
    
    local needs_fix=0
    check_access_restrictions
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_access_restrictions
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review access restrictions"
            echo -e "2. Update admin passwords if needed"
            echo -e "3. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Access is now restricted to localhost only${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main