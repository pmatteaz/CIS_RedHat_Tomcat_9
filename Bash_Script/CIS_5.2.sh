#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Default LockOut Realm parameters
FAILURECOUNT=3
LOCKOUTTIME=300
CACHETIMESECONDS=300
FAILURECOUNTINTERVAL=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        exit 1
    fi
}

check_lockout_realm() {
    local result=0
    
    # Check if LockOutRealm is configured
    if ! grep -q "<Realm.*className=\"org.apache.catalina.realm.LockOutRealm\"" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] LockOutRealm not configured${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] LockOutRealm is configured${NC}"
        
        # Check LockOutRealm parameters
        local current_failureCount=$(grep -oP 'failureCount="\K[^"]+' "$SERVER_XML" || echo "")
        local current_lockOutTime=$(grep -oP 'lockOutTime="\K[^"]+' "$SERVER_XML" || echo "")
        local current_cacheTime=$(grep -oP 'cacheTime="\K[^"]+' "$SERVER_XML" || echo "")
        local current_failureInterval=$(grep -oP 'failureInterval="\K[^"]+' "$SERVER_XML" || echo "")
        
        if [ -n "$current_failureCount" ] && [ "$current_failureCount" -gt "$FAILURECOUNT" ]; then
            echo -e "${YELLOW}[WARN] failureCount is too high: $current_failureCount${NC}"
            result=1
        fi
        
        if [ -n "$current_lockOutTime" ] && [ "$current_lockOutTime" -lt "$LOCKOUTTIME" ]; then
            echo -e "${YELLOW}[WARN] lockOutTime is too low: $current_lockOutTime${NC}"
            result=1
        fi
    fi
    
    return $result
}

create_backup() {
    local backup_file="${SERVER_XML}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$SERVER_XML" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_lockout_realm() {
    local temp_file=$(mktemp)
    
    # Check if LockOutRealm exists
    if ! grep -q "<Realm.*className=\"org.apache.catalina.realm.LockOutRealm\"" "$SERVER_XML"; then
        # Add LockOutRealm configuration
        awk '/<Engine name="Catalina"/{print;print "      <Realm className=\"org.apache.catalina.realm.LockOutRealm\" \
                failureCount=\"'$FAILURECOUNT'\" \
                lockOutTime=\"'$LOCKOUTTIME'\" \
                cacheTime=\"'$CACHETIMESECONDS'\" \
                failureInterval=\"'$FAILURECOUNTINTERVAL'\">";next}1' "$SERVER_XML" > "$temp_file"
    else
        # Update existing LockOutRealm configuration
        sed -E 's/(<Realm[^>]*className="org.apache.catalina.realm.LockOutRealm")[^>]*>/\1 failureCount="'$FAILURECOUNT'" lockOutTime="'$LOCKOUTTIME'" cacheTime="'$CACHETIMESECONDS'" failureInterval="'$FAILURECOUNTINTERVAL'">/' "$SERVER_XML" > "$temp_file"
    fi
    
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 640 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] LockOutRealm configuration updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent LockOutRealm Configuration:"
    if grep -q "<Realm.*className=\"org.apache.catalina.realm.LockOutRealm\"" "$SERVER_XML"; then
        grep -A 1 "<Realm.*className=\"org.apache.catalina.realm.LockOutRealm\"" "$SERVER_XML" | sed 's/^/  /'
    else
        echo -e "${YELLOW}  No LockOutRealm configuration found${NC}"
    fi
}

main() {
    echo "CIS 5.2 Check - LockOut Realm Configuration"
    echo "------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_lockout_realm
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_lockout_realm
            echo -e "\n${GREEN}Fix completed. Please restart Tomcat to apply changes.${NC}"
            echo -e "${YELLOW}[INFO] Configured parameters:${NC}"
            echo -e "  - failureCount: $FAILURECOUNT"
            echo -e "  - lockOutTime: $LOCKOUTTIME seconds"
            echo -e "  - cacheTime: $CACHETIMESECONDS seconds"
            echo -e "  - failureInterval: $FAILURECOUNTINTERVAL seconds"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main