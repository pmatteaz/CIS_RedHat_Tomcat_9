#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
LOGGING_PROPERTIES="$TOMCAT_HOME/conf/logging.properties"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Required handlers
declare -A REQUIRED_HANDLERS=(
    ["catalina"]="org.apache.juli.AsyncFileHandler"
    ["localhost"]="org.apache.juli.AsyncFileHandler"
    ["manager"]="org.apache.juli.AsyncFileHandler"
    ["host-manager"]="org.apache.juli.AsyncFileHandler"
    ["admin"]="org.apache.juli.AsyncFileHandler"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$LOGGING_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] logging.properties not found: $LOGGING_PROPERTIES${NC}"
        exit 1
    fi
}

check_handlers() {
    local result=0
    
    echo -e "\nChecking file handlers configuration:"
    
    # Check for handlers definition
    if ! grep -q "^handlers = " "$LOGGING_PROPERTIES"; then
        echo -e "${YELLOW}[WARN] No handlers defined in logging.properties${NC}"
        result=1
    fi
    
    # Check each required handler
    for handler in "${!REQUIRED_HANDLERS[@]}"; do
        echo -e "\nChecking $handler handler:"
        
        local handler_class="${REQUIRED_HANDLERS[$handler]}"
        local handler_pattern="^${handler}.${handler_class}"
        
        if ! grep -q "$handler_pattern" "$LOGGING_PROPERTIES"; then
            echo -e "${YELLOW}[WARN] Missing handler: $handler${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Handler found: $handler${NC}"
            
            # Check handler properties
            local properties=(
                "level"
                "prefix"
                "suffix"
                "directory"
                "encoding"
            )
            
            for prop in "${properties[@]}"; do
                if ! grep -q "^${handler}.${handler_class}.${prop}" "$LOGGING_PROPERTIES"; then
                    echo -e "${YELLOW}[WARN] Missing property $prop for handler $handler${NC}"
                    result=1
                fi
            done
        fi
    done
    
    # Check for console handler
    if ! grep -q "^1catalina.org.apache.juli.AsyncFileHandler.level" "$LOGGING_PROPERTIES"; then
        echo -e "${YELLOW}[WARN] Console handler not properly configured${NC}"
        result=1
    fi
    
    return $result
}

create_backup() {
    local backup_file="${LOGGING_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$LOGGING_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_handlers() {
    create_backup
    
    # Initialize handlers line
    local handlers_line="handlers = "
    
    # Add standard handlers configuration
    for handler in "${!REQUIRED_HANDLERS[@]}"; do
        handlers_line+="${handler}.${REQUIRED_HANDLERS[$handler]}, "
        
        # Add handler configuration if missing
        if ! grep -q "^${handler}.${REQUIRED_HANDLERS[$handler]}" "$LOGGING_PROPERTIES"; then
            echo "
# Handler configuration for $handler
${handler}.${REQUIRED_HANDLERS[$handler]}.level = FINE
${handler}.${REQUIRED_HANDLERS[$handler]}.directory = \${catalina.base}/logs
${handler}.${REQUIRED_HANDLERS[$handler]}.prefix = ${handler}.
${handler}.${REQUIRED_HANDLERS[$handler]}.suffix = .log
${handler}.${REQUIRED_HANDLERS[$handler]}.encoding = UTF-8
${handler}.${REQUIRED_HANDLERS[$handler]}.maxDays = 90" >> "$LOGGING_PROPERTIES"
        fi
    done
    
    # Update handlers line
    if grep -q "^handlers = " "$LOGGING_PROPERTIES"; then
        sed -i "s/^handlers = .*/$handlers_line/" "$LOGGING_PROPERTIES"
    else
        # Add handlers line at the beginning of the file
        sed -i "1i$handlers_line" "$LOGGING_PROPERTIES"
    fi
    
    # Add console handler if missing
    if ! grep -q "^1catalina.org.apache.juli.AsyncFileHandler.level" "$LOGGING_PROPERTIES"; then
        echo "
# Console handler configuration
1catalina.org.apache.juli.AsyncFileHandler.level = FINE
1catalina.org.apache.juli.AsyncFileHandler.directory = \${catalina.base}/logs
1catalina.org.apache.juli.AsyncFileHandler.prefix = catalina.
1catalina.org.apache.juli.AsyncFileHandler.encoding = UTF-8
1catalina.org.apache.juli.AsyncFileHandler.maxDays = 90" >> "$LOGGING_PROPERTIES"
    fi
    
    # Set proper permissions
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$LOGGING_PROPERTIES"
    chmod 640 "$LOGGING_PROPERTIES"
    
    echo -e "${GREEN}[OK] File handlers configuration updated${NC}"
}

print_current_status() {
    echo -e "\nCurrent Logging Configuration:"
    echo -e "\nGlobal handlers:"
    grep "^handlers = " "$LOGGING_PROPERTIES" | sed 's/^/  /'
    
    echo -e "\nHandler configurations:"
    for handler in "${!REQUIRED_HANDLERS[@]}"; do
        echo -e "\n  $handler handler:"
        grep -A 6 "^${handler}.${REQUIRED_HANDLERS[$handler]}" "$LOGGING_PROPERTIES" | sed 's/^/    /'
    done
}

main() {
    echo "CIS 7.2 Check - File Handlers Configuration"
    echo "-----------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_handlers
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_handlers
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review log levels for each handler"
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