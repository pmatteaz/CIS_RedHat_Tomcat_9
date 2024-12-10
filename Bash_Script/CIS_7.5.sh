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

# Recommended pattern for access logging
RECOMMENDED_PATTERN='%h %l %t %u "%r" %s %b "%{Referer}i" "%{User-Agent}i"'

check_file_exists() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] context.xml not found: $CONTEXT_XML${NC}"
        exit 1
    fi
}

check_patterns() {
    local result=0
    
    echo -e "\nChecking pattern attributes in context.xml files:"
    
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
    
    # Check if AccessLogValve is present
    if ! grep -q "org.apache.catalina.valves.AccessLogValve" "$file"; then
        echo -e "${YELLOW}[WARN] AccessLogValve not found in $file${NC}"
        result=1
    else
        # Check pattern attribute
        if ! grep -q "pattern=\".*\"" "$file"; then
            echo -e "${YELLOW}[WARN] No pattern attribute found in AccessLogValve in $file${NC}"
            result=1
        else
            local current_pattern=$(grep -o 'pattern="[^"]*"' "$file" | sed 's/pattern="\(.*\)"/\1/')
            if [ "$current_pattern" != "$RECOMMENDED_PATTERN" ]; then
                echo -e "${YELLOW}[WARN] Pattern does not match recommended format in $file${NC}"
                echo -e "Current:     $current_pattern"
                echo -e "Recommended: $RECOMMENDED_PATTERN"
                result=1
            else
                echo -e "${GREEN}[OK] Pattern matches recommended format${NC}"
            fi
        fi
    fi
    
    return $result
}

create_backup() {
    local file=$1
    local backup_file="${file}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$file" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_patterns() {
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
    
    if ! grep -q "org.apache.catalina.valves.AccessLogValve" "$file"; then
        # Add AccessLogValve if not present
        sed '/<\/Context>/i\    <Valve className="org.apache.catalina.valves.AccessLogValve" \
        pattern="'"$RECOMMENDED_PATTERN"'" \
        directory="${catalina.base}/logs" \
        prefix="access_log" suffix=".txt" \
        rotatable="true" renameOnRotate="true" \
        fileDateFormat="yyyy-MM-dd" />' "$file" > "$temp_file"
    else
        # Update existing pattern
        sed 's/pattern="[^"]*"/pattern="'"$RECOMMENDED_PATTERN"'"/' "$file" > "$temp_file"
    fi
    
    mv "$temp_file" "$file"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    chmod 640 "$file"
    
    echo -e "${GREEN}[OK] Updated pattern in $file${NC}"
}

print_current_status() {
    echo -e "\nCurrent AccessLogValve Configuration:"
    echo -e "\nMain context.xml:"
    grep -A 3 "AccessLogValve" "$CONTEXT_XML" | sed 's/^/  /'
    
    if [ -d "$WEBAPPS_DIR" ]; then
        for app_dir in "$WEBAPPS_DIR"/*; do
            if [ -d "$app_dir" ]; then
                local app_context="$app_dir/context.xml.default"
                if [ -f "$app_context" ]; then
                    echo -e "\n$(basename "$app_dir") context.xml:"
                    grep -A 3 "AccessLogValve" "$app_context" | sed 's/^/  /'
                fi
            fi
        done
    fi
}

main() {
    echo "CIS 7.5 Check - Access Log Pattern Configuration"
    echo "---------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_patterns
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_patterns
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review access log patterns"
            echo -e "2. Verify log rotation settings"
            echo -e "3. Restart Tomcat to apply changes"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main