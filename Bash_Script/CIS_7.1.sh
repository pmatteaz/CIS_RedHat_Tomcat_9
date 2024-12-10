#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
LOGGING_PROPERTIES="$TOMCAT_HOME/conf/logging.properties"
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
    
    if [ ! -f "$LOGGING_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] logging.properties not found: $LOGGING_PROPERTIES${NC}"
        result=1
    fi
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] webapps directory not found: $WEBAPPS_DIR${NC}"
        result=1
    fi
    
    return $result
}

check_app_logging() {
    local result=0
    
    echo -e "\nChecking application logging configuration:"
    
    # Check global logging settings
    if ! grep -q "handlers = " "$LOGGING_PROPERTIES"; then
        echo -e "${YELLOW}[WARN] No global handlers defined in logging.properties${NC}"
        result=1
    fi
    
    # Check for application-specific loggers
    local webapps=()
    for app in "$WEBAPPS_DIR"/*; do
        if [ -d "$app" ]; then
            app_name=$(basename "$app")
            webapps+=("$app_name")
            
            echo -e "\nChecking logging for application: $app_name"
            
            # Check for application-specific logger in logging.properties
            if ! grep -q "^${app_name}.org.apache.juli.AsyncFileHandler" "$LOGGING_PROPERTIES"; then
                echo -e "${YELLOW}[WARN] No specific logger configured for $app_name${NC}"
                result=1
            fi
            
            # Check for WEB-INF/classes/logging.properties
            if [ -f "$app/WEB-INF/classes/logging.properties" ]; then
                echo -e "${GREEN}[OK] Application has its own logging.properties${NC}"
                
                # Verify logging configuration
                if ! grep -q "handlers = " "$app/WEB-INF/classes/logging.properties"; then
                    echo -e "${YELLOW}[WARN] Invalid logging configuration in $app_name/WEB-INF/classes/logging.properties${NC}"
                    result=1
                fi
            else
                echo -e "${YELLOW}[WARN] No application-specific logging.properties found${NC}"
                result=1
            fi
        fi
    done
    
    return $result
}

create_backup() {
    local backup_file="${LOGGING_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$LOGGING_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_app_logging() {
    create_backup
    
    # Add/Update handlers in global logging.properties
    local handlers_line=$(grep "handlers = " "$LOGGING_PROPERTIES" || echo "handlers = ")
    local new_handlers="$handlers_line"
    
    for app in "$WEBAPPS_DIR"/*; do
        if [ -d "$app" ]; then
            app_name=$(basename "$app")
            
            # Add application-specific handler if not present
            if ! echo "$new_handlers" | grep -q "${app_name}.org.apache.juli.AsyncFileHandler"; then
                new_handlers="${new_handlers}${app_name}.org.apache.juli.AsyncFileHandler, "
            fi
            
            # Configure application-specific logging
            if ! grep -q "^${app_name}.org.apache.juli.AsyncFileHandler" "$LOGGING_PROPERTIES"; then
                echo "
# Handler specific properties for $app_name
${app_name}.org.apache.juli.AsyncFileHandler.level = FINE
${app_name}.org.apache.juli.AsyncFileHandler.directory = \${catalina.base}/logs
${app_name}.org.apache.juli.AsyncFileHandler.prefix = ${app_name}.
${app_name}.org.apache.juli.AsyncFileHandler.encoding = UTF-8
${app_name}.org.apache.juli.AsyncFileHandler.maxDays = 90" >> "$LOGGING_PROPERTIES"
            fi
            
            # Create/Update application-specific logging.properties
            mkdir -p "$app/WEB-INF/classes"
            cat > "$app/WEB-INF/classes/logging.properties" << EOF
handlers = ${app_name}.org.apache.juli.AsyncFileHandler

# Set root logger level
.level = INFO

# Handler specific properties
${app_name}.org.apache.juli.AsyncFileHandler.level = FINE
${app_name}.org.apache.juli.AsyncFileHandler.directory = \${catalina.base}/logs
${app_name}.org.apache.juli.AsyncFileHandler.prefix = ${app_name}.
${app_name}.org.apache.juli.AsyncFileHandler.encoding = UTF-8
${app_name}.org.apache.juli.AsyncFileHandler.maxDays = 90

# Application specific logger
${app_name}.level = FINE
EOF
            
            # Set proper permissions
            chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$app/WEB-INF/classes/logging.properties"
            chmod 640 "$app/WEB-INF/classes/logging.properties"
        fi
    done
    
    # Update global handlers
    sed -i "s|^handlers = .*|$new_handlers|" "$LOGGING_PROPERTIES"
    
    echo -e "${GREEN}[OK] Application logging configuration updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Logging Configuration:"
    echo -e "\nGlobal handlers:"
    grep "handlers = " "$LOGGING_PROPERTIES" | sed 's/^/  /'
    
    echo -e "\nApplication specific handlers:"
    for app in "$WEBAPPS_DIR"/*; do
        if [ -d "$app" ]; then
            app_name=$(basename "$app")
            echo -e "\n  $app_name:"
            grep -A 5 "^${app_name}.org.apache.juli.AsyncFileHandler" "$LOGGING_PROPERTIES" 2>/dev/null | sed 's/^/    /'
        fi
    done
}

main() {
    echo "CIS 7.1 Check - Application Specific Logging"
    echo "------------------------------------------"
    
    if ! check_files_exist; then
        exit 1
    fi
    
    local needs_fix=0
    check_app_logging
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_app_logging
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review logging configuration for each application"
            echo -e "2. Adjust log levels as needed"
            echo -e "3. Restart Tomcat to apply changes"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main