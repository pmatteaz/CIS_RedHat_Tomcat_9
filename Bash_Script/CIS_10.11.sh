#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
WEB_XML_GLOBAL="$TOMCAT_HOME/conf/web.xml"
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
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] webapps directory not found: $WEBAPPS_DIR${NC}"
        result=1
    fi
    
    if [ ! -f "$WEB_XML_GLOBAL" ]; then
        echo -e "${RED}[ERROR] global web.xml not found: $WEB_XML_GLOBAL${NC}"
        result=1
    fi
    
    return $result
}

check_ssl_configuration() {
    local result=0
    
    echo -e "\nChecking SSL Configuration:"
    
    # Check SSL connector in server.xml
    echo -e "\nChecking SSL Connector:"
    if ! grep -q '<Connector[^>]*protocol="org.apache.coyote.http11.Http11NioProtocol"[^>]*SSLEnabled="true"' "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] No SSL-enabled connector found${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] SSL connector found${NC}"
        
        # Check SSL attributes
        local connector=$(grep -A 5 '<Connector[^>]*SSLEnabled="true"' "$SERVER_XML")
        if ! echo "$connector" | grep -q 'sslProtocol="TLS"'; then
            echo -e "${YELLOW}[WARN] SSL protocol not set to TLS${NC}"
            result=1
        fi
        if ! echo "$connector" | grep -q 'scheme="https"'; then
            echo -e "${YELLOW}[WARN] HTTPS scheme not configured${NC}"
            result=1
        fi
    fi
    
    # Check security constraints in global web.xml
    echo -e "\nChecking Global Security Constraints:"
    if ! grep -q '<security-constraint>' "$WEB_XML_GLOBAL"; then
        echo -e "${YELLOW}[WARN] No security constraints found in global web.xml${NC}"
        result=1
    else
        if ! grep -q '<transport-guarantee>CONFIDENTIAL</transport-guarantee>' "$WEB_XML_GLOBAL"; then
            echo -e "${YELLOW}[WARN] CONFIDENTIAL transport not enforced in global web.xml${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] SSL enforced in global web.xml${NC}"
        fi
    fi
    
    # Check individual web applications
    echo -e "\nChecking Individual Web Applications:"
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local web_xml="$app_dir/WEB-INF/web.xml"
            if [ -f "$web_xml" ]; then
                local app_name=$(basename "$app_dir")
                echo -e "\nChecking $app_name:"
                
                if ! grep -q '<transport-guarantee>CONFIDENTIAL</transport-guarantee>' "$web_xml"; then
                    echo -e "${YELLOW}[WARN] SSL not enforced in $app_name${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] SSL enforced in $app_name${NC}"
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

fix_ssl_configuration() {
    # Fix server.xml
    create_backup "$SERVER_XML"
    if ! grep -q '<Connector[^>]*SSLEnabled="true"' "$SERVER_XML"; then
        # Add SSL connector
        sed -i '/<Service name="Catalina">/a \    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"\n        SSLEnabled="true" scheme="https" secure="true"\n        sslProtocol="TLS" keystoreFile="conf/localhost-rsa.jks"\n        keystorePass="changeit" />' "$SERVER_XML"
    else
        # Update existing SSL connector
        sed -i '/<Connector[^>]*SSLEnabled="true"/,/>/ {
            s/sslProtocol="[^"]*"/sslProtocol="TLS"/g
            s/scheme="[^"]*"/scheme="https"/g
            s/secure="[^"]*"/secure="true"/g
        }' "$SERVER_XML"
    fi
    
    # Fix global web.xml
    create_backup "$WEB_XML_GLOBAL"
    if ! grep -q '<security-constraint>' "$WEB_XML_GLOBAL"; then
        # Add security constraint
        sed -i '/<\/web-app>/i \    <security-constraint>\n        <web-resource-collection>\n            <web-resource-name>Entire Application</web-resource-name>\n            <url-pattern>/*</url-pattern>\n        </web-resource-collection>\n        <user-data-constraint>\n            <transport-guarantee>CONFIDENTIAL</transport-guarantee>\n        </user-data-constraint>\n    </security-constraint>' "$WEB_XML_GLOBAL"
    fi
    
    # Fix individual web applications
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            local web_xml="$app_dir/WEB-INF/web.xml"
            if [ -f "$web_xml" ]; then
                create_backup "$web_xml"
                if ! grep -q '<security-constraint>' "$web_xml"; then
                    sed -i '/<\/web-app>/i \    <security-constraint>\n        <web-resource-collection>\n            <web-resource-name>Entire Application</web-resource-name>\n            <url-pattern>/*</url-pattern>\n        </web-resource-collection>\n        <user-data-constraint>\n            <transport-guarantee>CONFIDENTIAL</transport-guarantee>\n        </user-data-constraint>\n    </security-constraint>' "$web_xml"
                elif ! grep -q '<transport-guarantee>CONFIDENTIAL</transport-guarantee>' "$web_xml"; then
                    sed -i 's/<transport-guarantee>[^<]*<\/transport-guarantee>/<transport-guarantee>CONFIDENTIAL<\/transport-guarantee>/' "$web_xml"
                fi
            fi
        fi
    done
    
    # Set proper permissions
    find "$TOMCAT_HOME" -name "web.xml" -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$TOMCAT_HOME" -name "web.xml" -exec chmod 640 {} \;
}

print_current_status() {
    echo -e "\nCurrent SSL Configuration:"
    
    echo -e "\nSSL Connector:"
    grep -A 5 '<Connector[^>]*SSLEnabled="true"' "$SERVER_XML" 2>/dev/null | sed 's/^/  /'
    
    echo -e "\nGlobal Security Constraint:"
    grep -A 7 '<security-constraint>' "$WEB_XML_GLOBAL" 2>/dev/null | sed 's/^/  /'
}

main() {
    echo "CIS 10.11 Check - SSL Configuration"
    echo "---------------------------------"
    
    if ! check_files_exist; then
        exit 1
    fi
    
    local needs_fix=0
    check_ssl_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_ssl_configuration
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Configure proper SSL certificate"
            echo -e "2. Update keystore passwords"
            echo -e "3. Review SSL settings"
            echo -e "4. Test HTTPS access"
            echo -e "5. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Default keystore settings were applied. Update them!${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main