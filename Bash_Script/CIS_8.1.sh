#!/bin/bash

# Configuration
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
CATALINA_PROPERTIES="$TOMCAT_HOME/conf/catalina.properties"
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Restricted packages list
RESTRICTED_PACKAGES=(
    "sun.*"
    "org.apache.catalina.webresources"
    "org.apache.catalina.security"
    "org.apache.catalina.mbeans"
    "org.apache.catalina.core"
    "org.apache.catalina.startup"
    "org.apache.catalina.loader"
    "org.apache.catalina.security"
    "org.apache.tomcat"
    "org.apache.jasper"
    "java.lang.reflect"
    "javax.security"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_file_exists() {
    if [ ! -f "$CATALINA_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] catalina.properties not found: $CATALINA_PROPERTIES${NC}"
        exit 1
    fi
}

check_package_restrictions() {
    local result=0
    
    echo -e "\nChecking package access restrictions:"
    
    # Check for package.access property
    if ! grep -q "^package.access=" "$CATALINA_PROPERTIES"; then
        echo -e "${YELLOW}[WARN] package.access property not found${NC}"
        result=1
    else
        local current_restrictions=$(grep "^package.access=" "$CATALINA_PROPERTIES" | cut -d'=' -f2)
        
        # Check each required package
        for pkg in "${RESTRICTED_PACKAGES[@]}"; do
            if ! echo "$current_restrictions" | grep -q "$pkg"; then
                echo -e "${YELLOW}[WARN] Missing restriction for package: $pkg${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Found restriction for package: $pkg${NC}"
            fi
        done
    fi
    
    return $result
}

create_backup() {
    local backup_file="${CATALINA_PROPERTIES}.$(date +%Y%m%d_%H%M%S).bak"
    cp "$CATALINA_PROPERTIES" "$backup_file"
    echo -e "${GREEN}[OK] Backup created: $backup_file${NC}"
}

fix_package_restrictions() {
    create_backup
    
    local temp_file=$(mktemp)
    
    # Build package.access string
    local package_access="package.access="
    for pkg in "${RESTRICTED_PACKAGES[@]}"; do
        package_access="${package_access}${pkg},"
    done
    # Remove trailing comma
    package_access=${package_access%,}
    
    # Update or add package.access property
    if grep -q "^package.access=" "$CATALINA_PROPERTIES"; then
        # Update existing property
        sed "s|^package.access=.*|$package_access|" "$CATALINA_PROPERTIES" > "$temp_file"
    else
        # Add new property
        cp "$CATALINA_PROPERTIES" "$temp_file"
        echo -e "\n# Runtime package access restrictions" >> "$temp_file"
        echo "$package_access" >> "$temp_file"
    fi
    
    # Apply changes
    mv "$temp_file" "$CATALINA_PROPERTIES"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_PROPERTIES"
    chmod 640 "$CATALINA_PROPERTIES"
    
    echo -e "${GREEN}[OK] Package access restrictions updated${NC}"
}

verify_restrictions() {
    echo -e "\nVerifying final configuration:"
    if grep -q "^package.access=" "$CATALINA_PROPERTIES"; then
        local current_restrictions=$(grep "^package.access=" "$CATALINA_PROPERTIES")
        echo -e "${GREEN}[OK] Package access configuration:${NC}"
        echo "$current_restrictions" | sed 's/,/,\n\t/g' | sed 's/=/=\n\t/'
    else
        echo -e "${RED}[ERROR] Package access property not found after fix${NC}"
    fi
}

print_current_status() {
    echo -e "\nCurrent Package Access Configuration:"
    if grep -q "^package.access=" "$CATALINA_PROPERTIES"; then
        grep "^package.access=" "$CATALINA_PROPERTIES" | sed 's/,/,\n\t/g' | sed 's/=/=\n\t/'
    else
        echo -e "${YELLOW}No package access restrictions found${NC}"
    fi
}

main() {
    echo "CIS 8.1 Check - Runtime Package Access Restrictions"
    echo "------------------------------------------------"
    
    check_file_exists
    
    local needs_fix=0
    check_package_restrictions
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        print_current_status
        
        echo -e "\n${YELLOW}Proceed with fix? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_package_restrictions
            verify_restrictions
            echo -e "\n${GREEN}Fix completed. Please:${NC}"
            echo -e "1. Review package access restrictions"
            echo -e "2. Test application functionality"
            echo -e "3. Restart Tomcat to apply changes"
            echo -e "\n${YELLOW}[WARNING] Package restrictions may affect application functionality${NC}"
        else
            echo -e "\n${YELLOW}Fix cancelled by user${NC}"
        fi
    else
        echo -e "\n${GREEN}All checks passed. No fix needed.${NC}"
    fi
}

main