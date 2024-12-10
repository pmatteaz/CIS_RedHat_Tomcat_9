#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_directories() {
    local result=0
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] Webapps directory not found: $WEBAPPS_DIR${NC}"
        result=1
    fi
    
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] Context configuration not found: $CONTEXT_XML${NC}"
        result=1
    fi
    
    return $result
}

check_configuration() {
    local result=0
    
    echo -e "\nChecking application configurations:"
    
    # Check global context.xml for logEffectiveWebXml
    echo -e "\nChecking global context.xml:"
    if ! grep -q 'logEffectiveWebXml="true"' "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] logEffectiveWebXml not enabled in global context${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] logEffectiveWebXml enabled in global context${NC}"
    fi
    
    # Check each web application
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local web_xml="$app_dir/WEB-INF/web.xml"
            local context_xml="$app_dir/META-INF/context.xml"
            
            echo -e "\nChecking application: $app_name"
            
            # Check web.xml for metadata-complete
            if [ -f "$web_xml" ]; then
                if ! grep -q 'metadata-complete="true"' "$web_xml"; then
                    echo -e "${YELLOW}[WARN] metadata-complete not set in $app_name/web.xml${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] metadata-complete set in $app_name/web.xml${NC}"
                fi
            else
                echo -e "${YELLOW}[WARN] web.xml not found in $app_name${NC}"
                result=1
            fi
            
            # Check application context.xml for logEffectiveWebXml
            if [ -f "$context_xml" ]; then
                if ! grep -q 'logEffectiveWebXml="true"' "$context_xml"; then
                    echo -e "${YELLOW}[WARN] logEffectiveWebXml not enabled in $app_name context${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] logEffectiveWebXml enabled in $app_name context${NC}"
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

fix_configuration() {
    # Fix global context.xml
    create_backup "$CONTEXT_XML"
    if ! grep -q 'logEffectiveWebXml="true"' "$CONTEXT_XML"; then
        sed -i '/<Context/s/>/& logEffectiveWebXml="true">/' "$CONTEXT_XML"
    fi
    
    # Fix each web application
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local web_xml="$app_dir/WEB-INF/web.xml"
            local context_xml="$app_dir/META-INF/context.xml"
            local meta_inf="$app_dir/META-INF"
            
            # Create necessary directories
            if [ ! -d "$meta_inf" ]; then
                mkdir -p "$meta_inf"
            fi
            
            # Fix web.xml
            if [ -f "$web_xml" ]; then
                create_backup "$web_xml"
                if ! grep -q 'metadata-complete="true"' "$web_xml"; then
                    sed -i '/<web-app/s/>/& metadata-complete="true">/' "$web_xml"
                fi
            else
                # Create minimal web.xml if it doesn't exist
                mkdir -p "$(dirname "$web_xml")"
                cat > "$web_xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://xmlns.jcp.org/xml/ns/javaee"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee
                             http://xmlns.jcp.org/xml/ns/javaee/web-app_4_0.xsd"
         version="4.0"
         metadata-complete="true">
    <display-name>$app_name</display-name>
</web-app>
EOF
            fi
            
            # Fix context.xml
            if [ -f "$context_xml" ]; then
                create_backup "$context_xml"
                if ! grep -q 'logEffectiveWebXml="true"' "$context_xml"; then
                    if grep -q '<Context' "$context_xml"; then
                        sed -i '/<Context/s/>/& logEffectiveWebXml="true">/' "$context_xml"
                    else
                        echo '<Context logEffectiveWebXml="true">' > "$context_xml.tmp"
                        cat "$context_xml" >> "$context_xml.tmp"
                        echo '</Context>' >> "$context_xml.tmp"
                        mv "$context_xml.tmp" "$context_xml"
                    fi
                fi
            else
                # Create context.xml if it doesn't exist
                cat > "$context_xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<Context logEffectiveWebXml="true">
</Context>
EOF
            fi
            
            # Set proper permissions
            chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$app_dir"
            find "$app_dir" -type f -exec chmod 640 {} \;
            find "$app_dir" -type d -exec chmod 750 {} \;
        fi
    done
    
    echo -e "${GREEN}[OK] Configuration updated${NC}"
}

verify_changes() {
    echo -e "\nVerifying changes:"
    
    # Verify global context.xml
    if grep -q 'logEffectiveWebXml="true"' "$CONTEXT_XML"; then
        echo -e "${GREEN}[OK] Global logEffectiveWebXml setting verified${NC}"
    else
        echo -e "${RED}[ERROR] Global logEffectiveWebXml setting not applied${NC}"
    fi
    
    # Verify applications
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            local web_xml="$app_dir/WEB-INF/web.xml"
            local context_xml="$app_dir/META-INF/context.xml"
            
            echo -e "\nVerifying $app_name:"
            
            if [ -f "$web_xml" ]; then
                if grep -q 'metadata-complete="true"' "$web_xml"; then
                    echo -e "${GREEN}[OK] metadata-complete setting verified${NC}"
                else
                    echo -e "${RED}[ERROR] metadata-complete setting not applied${NC}"
                fi
            fi
            
            if [ -f "$context_xml" ]; then
                if grep -q 'logEffectiveWebXml="true"' "$context_xml"; then
                    echo -e "${GREEN}[OK] Application logEffectiveWebXml setting verified${NC}"
                else
                    echo -e "${RED}[ERROR] Application logEffectiveWebXml setting not applied${NC}"
                fi
            fi
        fi
    done
}

print_current_status() {
    echo -e "\nCurrent Configuration:"
    
    echo -e "\nGlobal context.xml:"
    grep -A 1 "<Context" "$CONTEXT_XML" | sed 's/^/  /'
    
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local app_name=$(basename "$app_dir")
            echo -e "\n$app_name configuration:"
            
            local web_xml="$app_dir/WEB-INF/web.xml"
            if [ -f "$web_xml" ]; then
                echo -e "\n  web.xml:"
                grep -A 1 "<web-app" "$web_xml" | sed 's/^/    /'
            fi
            
            local context_xml="$app_dir/META-INF/context.xml"
            if [ -f "$context_xml" ]; then
                echo -e "\n  context.xml:"
                grep -A 1 "<Context" "$context_xml" | sed 's/^/    /'
            fi
        fi
    done
}

main() {
    echo "CIS 10.18 Check - Web Application Deployment Settings"
    echo "-------------------------------------------------"
    
    if ! check_directories; then
        exit 1
    fi
    
    local needs_fix=0
    check_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_configuration
            verify_changes
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review web.xml configurations"
            echo -e "2. Verify context.xml settings"
            echo -e "3. Check application functionality"
            echo -e "4. Review logging output"
            echo -e "5. Restart Tomcat to apply changes"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main