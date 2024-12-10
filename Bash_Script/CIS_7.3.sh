#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
WEBAPPS_DIR="$TOMCAT_HOME/conf/Catalina"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Valid classNames
declare -a VALID_CLASSNAMES=(
    "org.apache.catalina.valves.AccessLogValve"
    "org.apache.catalina.valves.RemoteAddrValve"
    "org.apache.catalina.valves.RemoteHostValve"
    "org.apache.catalina.authenticator.BasicAuthenticator"
    "org.apache.catalina.authenticator.DigestAuthenticator"
)

check_file_exists() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] context.xml not found: $CONTEXT_XML${NC}"
        exit 1
    fi
}

check_classnames() {
    local result=0
    
    echo -e "\nChecking className attributes in context.xml files:"
    
    # Check main context.xml
    echo -e "\nChecking main context.xml:"
    check_single_file "$CONTEXT_XML"
    result=$((result + $?))
    
    # Check application-specific context.xml files
    if [ -d "$WEBAPPS_DIR" ]; then
        for app_dir in "$WEBAPPS_DIR"/*; do
            if [ -d "$app_dir" ]; then
                local app_context="$app_dir/context.xml.default"
                if [ -f "$app_context" ]; then
                    echo -e "\nChecking $(basename "$app_dir") context.xml:"
                    check_single_file "$app_context"
                    result=$((result + $?))
                fi
            fi
        done
    fi
    
    return $result
}

check_single_file() {
    local file=$1
    local result=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ className=\"([^\"]*)\" ]]; then
            local classname="${BASH_REMATCH[1]}"
            local valid=0
            
            for valid_class in "${VALID_CLASSNAMES[@]}"; do
                if [ "$classname" == "$valid_class" ]; then
                    valid=1
                    break
                fi
            done
            
            if [ $valid -eq 0 ]; then
                echo -e "${YELLOW}[WARN] Invalid className found: $classname in $file${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Valid className: $classname${NC}"
            fi
        fi
    done < "$file"
    
    return $result
}

create_backup() {
    local file=$1
    local backup_file="${file}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$file" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_classnames() {
    # Fix main context.xml
    fix_single_file "$CONTEXT_XML"
    
    # Fix application-specific context.xml files
    if [ -d "$WEBAPPS_DIR" ]; then
        for app_dir in "$WEBAPPS_DIR"/*; do
            if [ -d "$app_dir" ]; then
                local app_context="$app_dir/context.xml.default"
                if [ -f "$app_context" ]; then
                    fix_single_file "$app_context"
                fi
            fi
        done
    fi
}

fix_single_file() {
    local file=$1
    local temp_file=$(mktemp)
    
    create_backup "$file"
    
    while IFS= read -r line; do
        if [[ "$line" =~ className=\"([^\"]*)\" ]]; then
            local classname="${BASH_REMATCH[1]}"
            local valid=0
            
            for valid_class in "${VALID_CLASSNAMES[@]}"; do
                if [ "$classname" == "$valid_class" ]; then
                    valid=1
                    break
                fi
            done
            
            if [ $valid -eq 0 ]; then
                # Replace invalid className with a default valid one
                line="${line/className=\"$classname\"/className=\"org.apache.catalina.valves.AccessLogValve\"}"
                echo -e "${YELLOW}[INFO] Replaced invalid className: $classname${NC}"
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$file"
    
    mv "$temp_file" "$file"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    chmod 640 "$file"
    
    echo -e "${GREEN}[OK] Updated className attributes in $file${NC}"
}

print_current_status() {
    echo -e "\nCurrent className Configuration:"
    echo -e "\nMain context.xml:"
    grep -i "className" "$CONTEXT_XML" | sed 's/^/  /'
    
    if [ -d "$WEBAPPS_DIR" ]; then
        for app_dir in "$WEBAPPS_DIR"/*; do
            if [ -d "$app_dir" ]; then
                local app_context="$app_dir/context.xml.default"
                if [ -f "$app_context" ]; then
                    echo -e "\n$(basename "$app_dir") context.xml:"
                    grep -i "className" "$app_context" | sed 's/^/  /'
                fi
            fi
        done
    fi
}

main() {
    echo "CIS 7.3 Check - className Configuration"
    echo "------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_classnames
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_classnames
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review replaced className attributes"
            echo -e "2. Verify application functionality"
            echo -e "3. Restart Tomcat to apply changes"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main