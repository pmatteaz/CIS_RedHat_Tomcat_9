#!/bin/bash

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
WEB_XML="$TOMCAT_HOME/conf/web.xml"
ERROR_PAGE_DIR="$TOMCAT_HOME/webapps/ROOT/WEB-INF/error"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_tomcat_home() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] Tomcat directory not found: $TOMCAT_HOME${NC}"
        exit 1
    fi
}

check_error_pages() {
    local result=0
    
    if [ ! -d "$ERROR_PAGE_DIR" ]; then
        echo -e "${YELLOW}[WARN] Custom error pages directory not found${NC}"
        result=1
    fi

    if ! grep -q "<error-page>" "$WEB_XML"; then
        echo -e "${YELLOW}[WARN] Error pages not configured in web.xml${NC}"
        result=1
    fi
    
    return $result
}

create_error_pages() {
    mkdir -p "$ERROR_PAGE_DIR"
    
    # Create generic error page
    cat > "$ERROR_PAGE_DIR/error.jsp" << 'EOF'
<%@ page isErrorPage="true" %>
<!DOCTYPE html>
<html>
<head>
    <title>Error</title>
</head>
<body>
    <h2>An error has occurred</h2>
    <p>Please contact system administrator</p>
</body>
</html>
EOF
    
    echo -e "${GREEN}[OK] Created custom error pages${NC}"
}

configure_error_handling() {
    cp "$WEB_XML" "${WEB_XML}.bak"
    
    # Add error page configuration if not present
    if ! grep -q "<error-page>" "$WEB_XML"; then
        sed -i '/<\/web-app>/i \
    <!-- Generic error page -->\
    <error-page>\
        <exception-type>java.lang.Throwable</exception-type>\
        <location>/WEB-INF/error/error.jsp</location>\
    </error-page>\
    <!-- 404 error page -->\
    <error-page>\
        <error-code>404</error-code>\
        <location>/WEB-INF/error/error.jsp</location>\
    </error-page>\
    <!-- 500 error page -->\
    <error-page>\
        <error-code>500</error-code>\
        <location>/WEB-INF/error/error.jsp</location>\
    </error-page>' "$WEB_XML"
    fi
    
    echo -e "${GREEN}[OK] Configured error handling in web.xml${NC}"
}

main() {
    echo "CIS 2.5 Check - Disable client facing Stack Traces"
    echo "------------------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    check_error_pages
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_error_pages
            configure_error_handling
            echo -e "\n${GREEN}Fix completed. Restart Tomcat to apply changes.${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main