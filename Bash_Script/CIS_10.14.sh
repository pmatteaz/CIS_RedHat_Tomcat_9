#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
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
    
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] context.xml not found: $CONTEXT_XML${NC}"
        result=1
    fi
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] webapps directory not found: $WEBAPPS_DIR${NC}"
        result=1
    fi
    
    return $result
}

check_cross_context() {
    local result=0
    
    echo -e "\nChecking cross context configuration:"
    
    # Check global context.xml
    echo -e "\nChecking global context.xml:"
    if grep -q 'crossContext="true"' "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] Cross context requests enabled in global context.xml${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Cross context disabled in global context.xml${NC}"
    fi
    
    # Check individual web applications
    echo -e "\nChecking individual web applications:"
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local meta_inf="$app_dir/META-INF"
            local context_file="$meta_inf/context.xml"
            
            if [ -f "$context_file" ]; then
                echo -e "\nChecking $app_name:"
                if grep -q 'crossContext="true"' "$context_file"; then
                    echo -e "${YELLOW}[WARN] Cross context requests enabled in $app_name${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Cross context disabled in $app_name${NC}"
                fi
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

fix_cross_context() {
    # Fix global context.xml
    create_backup "$CONTEXT_XML"
    
    if grep -q 'crossContext="true"' "$CONTEXT_XML"; then
        sed -i 's/crossContext="true"/crossContext="false"/' "$CONTEXT_XML"
    elif ! grep -q 'crossContext=' "$CONTEXT_XML"; then
        # Add crossContext="false" if not present
        sed -i '/<Context>/s/>/& crossContext="false">/' "$CONTEXT_XML"
    fi
    
    # Fix individual web applications
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local meta_inf="$app_dir/META-INF"
            local context_file="$meta_inf/context.xml"
            
            if [ -f "$context_file" ]; then
                create_backup "$context_file"
                
                if grep -q 'crossContext="true"' "$context_file"; then
                    sed -i 's/crossContext="true"/crossContext="false"/' "$context_file"
                elif ! grep -q 'crossContext=' "$context_file"; then
                    sed -i '/<Context>/s/>/& crossContext="false">/' "$context_file"
                fi
                
                # Set proper permissions
                chown "$TOMCAT_USER:$TOMCAT_GROUP" "$context_file"
                chmod 640 "$context_file"
            fi
        fi
    done
    
    # Set proper permissions for global context.xml
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CONTEXT_XML"
    chmod 640 "$CONTEXT_XML"
    
    echo -e "${GREEN}[OK] Cross context settings updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Cross Context Configuration:"
    
    echo -e "\nGlobal context.xml:"
    grep -A 1 "<Context" "$CONTEXT_XML" | sed 's/^/  /'
    
    echo -e "\nApplication-specific configurations:"
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local context_file="$app_dir/META-INF/context.xml"
            if [ -f "$context_file" ]; then
                echo -e "\n  $(basename "$app_dir"):"
                grep -A 1 "<Context" "$context_file" | sed 's/^/    /'
            fi
        fi
    done
}

verify_changes() {
    local result=0
    
    echo -e "\nVerifying changes:"
    
    # Check global context.xml
    if grep -q 'crossContext="true"' "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] Cross context still enabled in global context.xml${NC}"
        result=1
    fi
    
    # Check applications
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local context_file="$app_dir/META-INF/context.xml"
            if [ -f "$context_file" ] && grep -q 'crossContext="true"' "$context_file"; then
                echo -e "${YELLOW}[WARN] Cross context still enabled in $(basename "$app_dir")${NC}"
                result=1
            fi
        fi
    done
    
    return $result
}

main() {
    echo "CIS 10.14 Check - Cross Context Requests"
    echo "--------------------------------------"
    
    if ! check_files_exist; then
        exit 1
    fi
    
    local needs_fix=0
    check_cross_context
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_cross_context
            if ! verify_changes; then
                echo -e "\n${YELLOW}[WARN] Some issues remain after fix${NC}"
            fi
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review changes"
            echo -e "2. Test application functionality"
            echo -e "3. Verify application interactions"
            echo -e "4. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Applications relying on cross context requests may not work${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main