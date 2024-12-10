#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_files_exist() {
    local result=0
    
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] server.xml not found: $SERVER_XML${NC}"
        result=1
    fi
    
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] context.xml not found: $CONTEXT_XML${NC}"
        result=1
    fi
    
    return $result
}

check_resolve_hosts() {
    local result=0
    
    echo -e "\nChecking host name resolution settings in logging valves:"
    
    # Check server.xml for AccessLogValve
    echo -e "\nChecking server.xml:"
    while IFS= read -r line; do
        if [[ "$line" =~ "org.apache.catalina.valves.AccessLogValve" ]]; then
            if echo "$line" | grep -q 'resolveHosts="true"'; then
                echo -e "${YELLOW}[WARN] Host resolution enabled in server.xml AccessLogValve${NC}"
                result=1
            elif ! echo "$line" | grep -q 'resolveHosts='; then
                echo -e "${YELLOW}[WARN] resolveHosts not explicitly disabled in server.xml AccessLogValve${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Host resolution properly configured in server.xml${NC}"
            fi
        fi
    done < "$SERVER_XML"
    
    # Check context.xml for AccessLogValve
    echo -e "\nChecking context.xml:"
    while IFS= read -r line; do
        if [[ "$line" =~ "org.apache.catalina.valves.AccessLogValve" ]]; then
            if echo "$line" | grep -q 'resolveHosts="true"'; then
                echo -e "${YELLOW}[WARN] Host resolution enabled in context.xml AccessLogValve${NC}"
                result=1
            elif ! echo "$line" | grep -q 'resolveHosts='; then
                echo -e "${YELLOW}[WARN] resolveHosts not explicitly disabled in context.xml AccessLogValve${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Host resolution properly configured in context.xml${NC}"
            fi
        fi
    done < "$CONTEXT_XML"
    
    # Check application-specific configurations
    echo -e "\nChecking application contexts:"
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local meta_inf="$app_dir/META-INF"
            local context_file="$meta_inf/context.xml"
            
            if [ -f "$context_file" ]; then
                local app_name=$(basename "$app_dir")
                while IFS= read -r line; do
                    if [[ "$line" =~ "org.apache.catalina.valves.AccessLogValve" ]]; then
                        if echo "$line" | grep -q 'resolveHosts="true"'; then
                            echo -e "${YELLOW}[WARN] Host resolution enabled in $app_name AccessLogValve${NC}"
                            result=1
                        elif ! echo "$line" | grep -q 'resolveHosts='; then
                            echo -e "${YELLOW}[WARN] resolveHosts not explicitly disabled in $app_name AccessLogValve${NC}"
                            result=1
                        else
                            echo -e "${GREEN}[OK] Host resolution properly configured in $app_name${NC}"
                        fi
                    fi
                done < "$context_file"
            fi
        fi
    done
    
    return $result
}

create_backup() {
    local file=$1
    local backup_file="${file}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$file" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_resolve_hosts() {
    # Fix server.xml
    create_backup "$SERVER_XML"
    sed -i '/<Valve className="org.apache.catalina.valves.AccessLogValve"/ {
        /resolveHosts=/! s/>/ resolveHosts="false">/
        s/resolveHosts="true"/resolveHosts="false"/
    }' "$SERVER_XML"
    
    # Fix context.xml
    create_backup "$CONTEXT_XML"
    sed -i '/<Valve className="org.apache.catalina.valves.AccessLogValve"/ {
        /resolveHosts=/! s/>/ resolveHosts="false">/
        s/resolveHosts="true"/resolveHosts="false"/
    }' "$CONTEXT_XML"
    
    # Fix application contexts
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local context_file="$app_dir/META-INF/context.xml"
            if [ -f "$context_file" ]; then
                create_backup "$context_file"
                sed -i '/<Valve className="org.apache.catalina.valves.AccessLogValve"/ {
                    /resolveHosts=/! s/>/ resolveHosts="false">/
                    s/resolveHosts="true"/resolveHosts="false"/
                }' "$context_file"
                
                # Set proper permissions
                chown "$TOMCAT_USER:$TOMCAT_GROUP" "$context_file"
                chmod 640 "$context_file"
            fi
        fi
    done
    
    # Set proper permissions for global files
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML" "$CONTEXT_XML"
    chmod 640 "$SERVER_XML" "$CONTEXT_XML"
    
    echo -e "${GREEN}[OK] Host resolution settings updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Host Resolution Configuration:"
    
    echo -e "\nServer.xml AccessLogValve:"
    grep -A 1 "org.apache.catalina.valves.AccessLogValve" "$SERVER_XML" | sed 's/^/  /'
    
    echo -e "\nContext.xml AccessLogValve:"
    grep -A 1 "org.apache.catalina.valves.AccessLogValve" "$CONTEXT_XML" | sed 's/^/  /'
    
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local context_file="$app_dir/META-INF/context.xml"
            if [ -f "$context_file" ] && grep -q "org.apache.catalina.valves.AccessLogValve" "$context_file"; then
                echo -e "\n$(basename "$app_dir") AccessLogValve:"
                grep -A 1 "org.apache.catalina.valves.AccessLogValve" "$context_file" | sed 's/^/  /'
            fi
        fi
    done
}

main() {
    echo "CIS 10.15 Check - Host Name Resolution in Logging"
    echo "---------------------------------------------"
    
    if ! check_files_exist; then
        exit 1
    fi
    
    local needs_fix=0
    check_resolve_hosts
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_resolve_hosts
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review changes"
            echo -e "2. Check logging performance"
            echo -e "3. Verify log format"
            echo -e "4. Restart Tomcat to apply changes"
            echo -e "\n${GREEN}[INFO] Host resolution disabled - IP addresses will be logged instead of hostnames${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main