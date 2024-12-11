#!/bin/bash

# Script per il controllo e fix del CIS Control 7.1
# Application specific logging
#
# Lo script implementa le seguenti funzionalità:
# Verifica del logging specifico per applicazione:
#   Controllo configurazione logging.properties per ogni app
#   Verifica directory log separate
#   Controllo permessi e proprietà
# 
# Configurazione per ogni applicazione:
#   Logging separato
#   Rotazione dei log
#   Pattern di logging specifici
#   Livelli di log appropriati
# 
# Sistema completo:
#   Backup delle configurazioni
#   Directory log separate per app
#   Rotazione automatica dei log
#   Permessi corretti<

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
LOGS_DIR="$TOMCAT_HOME/logs"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Template per logging.properties specifico dell'applicazione
APP_LOGGING_TEMPLATE="handlers = 1catalina.org.apache.juli.FileHandler, 2localhost.org.apache.juli.FileHandler, java.util.logging.ConsoleHandler

.handlers = 1catalina.org.apache.juli.FileHandler

############################################################
# Handler specific properties.
# Describes specific configuration info for Handlers.
############################################################

1catalina.org.apache.juli.FileHandler.level = FINE
1catalina.org.apache.juli.FileHandler.directory = \${catalina.base}/logs/APP_NAME
1catalina.org.apache.juli.FileHandler.prefix = APP_NAME_
1catalina.org.apache.juli.FileHandler.formatter = org.apache.juli.OneLineFormatter
1catalina.org.apache.juli.FileHandler.rotatable = true
1catalina.org.apache.juli.FileHandler.maxDays = 90
1catalina.org.apache.juli.FileHandler.encoding = UTF-8
1catalina.org.apache.juli.FileHandler.buffered = false

2localhost.org.apache.juli.FileHandler.level = FINE
2localhost.org.apache.juli.FileHandler.directory = \${catalina.base}/logs/APP_NAME
2localhost.org.apache.juli.FileHandler.prefix = localhost_APP_NAME_
2localhost.org.apache.juli.FileHandler.formatter = org.apache.juli.OneLineFormatter
2localhost.org.apache.juli.FileHandler.rotatable = true
2localhost.org.apache.juli.FileHandler.maxDays = 90
2localhost.org.apache.juli.FileHandler.encoding = UTF-8
2localhost.org.apache.juli.FileHandler.buffered = false

java.util.logging.ConsoleHandler.level = FINE
java.util.logging.ConsoleHandler.formatter = org.apache.juli.OneLineFormatter
java.util.logging.ConsoleHandler.encoding = UTF-8

############################################################
# Application specific logging
############################################################

org.apache.catalina.core.ContainerBase.[Catalina].[localhost].level = INFO
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].handlers = 2localhost.org.apache.juli.FileHandler

# Set the following to FINE to log all web application activity
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].[/APP_NAME].level = FINE
org.apache.catalina.core.ContainerBase.[Catalina].[localhost].[/APP_NAME].handlers = 2localhost.org.apache.juli.FileHandler"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_applog_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    if [ -f "$file" ]; then
        cp -p "$file" "$backup_dir/"
        echo "# Backup of $file - $(date)" >> "$backup_file"
        ls -l "$file" >> "$backup_file"
    fi
    
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_app_logging() {
    local app_dir="$1"
    local app_name=$(basename "$app_dir")
    local result=0
    
    echo -e "\nControllo configurazione logging per $app_name..."
    
    # Verifica directory di log dell'applicazione
    local app_log_dir="$LOGS_DIR/$app_name"
    if [ ! -d "$app_log_dir" ]; then
        echo -e "${YELLOW}[WARN] Directory log dell'applicazione non trovata: $app_log_dir${NC}"
        result=1
    else
        # Verifica permessi directory
        local dir_perms=$(stat -c '%a' "$app_log_dir")
        if [ "$dir_perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Permessi directory log non corretti: $dir_perms${NC}"
            result=1
        fi
    fi
    
    # Verifica logging.properties dell'applicazione
    local app_logging_props="$app_dir/WEB-INF/classes/logging.properties"
    if [ ! -f "$app_logging_props" ]; then
        echo -e "${YELLOW}[WARN] File logging.properties non trovato per l'applicazione${NC}"
        result=1
    else
        # Verifica configurazioni necessarie
        if ! grep -q "handlers.*FileHandler" "$app_logging_props"; then
            echo -e "${YELLOW}[WARN] FileHandler non configurato correttamente${NC}"
            result=1
        fi
        
        if ! grep -q "directory.*=.*${app_name}" "$app_logging_props"; then
            echo -e "${YELLOW}[WARN] Directory di log non configurata specificatamente per l'applicazione${NC}"
            result=1
        fi
    fi
    
    return $result
}

fix_app_logging() {
    local app_dir="$1"
    local app_name=$(basename "$app_dir")
    
    echo "Configurazione logging per $app_name..."
    
    # Crea directory di log specifica per l'applicazione
    local app_log_dir="$LOGS_DIR/$app_name"
    mkdir -p "$app_log_dir"
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$app_log_dir"
    chmod 750 "$app_log_dir"
    
    # Crea o aggiorna logging.properties
    local app_logging_props="$app_dir/WEB-INF/classes/logging.properties"
    mkdir -p "$(dirname "$app_logging_props")"
    
    # Sostituisci il placeholder APP_NAME con il nome reale dell'applicazione
    echo "$APP_LOGGING_TEMPLATE" | sed "s/APP_NAME/$app_name/g" > "$app_logging_props"
    
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$app_logging_props"
    chmod 640 "$app_logging_props"
    
    echo -e "${GREEN}[OK] Configurazione logging completata per $app_name${NC}"
}

check_log_rotation() {
    local result=0
    
    echo "Controllo configurazione rotazione log..."
    
    # Verifica configurazione logrotate
    if [ -d "/etc/logrotate.d" ]; then
        if [ ! -f "/etc/logrotate.d/tomcat" ]; then
            echo -e "${YELLOW}[WARN] Configurazione logrotate non trovata${NC}"
            result=1
        fi
    else
        echo -e "${YELLOW}[WARN] Directory logrotate.d non trovata${NC}"
        result=1
    fi
    
    return $result
}

configure_log_rotation() {
    echo "Configurazione rotazione log..."
    
    # Crea configurazione logrotate per Tomcat
    cat > "/etc/logrotate.d/tomcat" << EOF
$LOGS_DIR/*/*.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    create 640 $TOMCAT_USER $TOMCAT_GROUP
    sharedscripts
    postrotate
        if [ -f $TOMCAT_HOME/bin/shutdown.sh ]; then
            $TOMCAT_HOME/bin/shutdown.sh
            sleep 5
            $TOMCAT_HOME/bin/startup.sh
        fi
    endscript
}
EOF
    
    chmod 644 "/etc/logrotate.d/tomcat"
    
    echo -e "${GREEN}[OK] Configurazione rotazione log completata${NC}"
}

main() {
    echo "Controllo CIS 7.1 - Application specific logging"
    echo "---------------------------------------------"
    
    check_root
    
    local needs_fix=0
    
    # Controlla ogni applicazione web
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            check_app_logging "$app_dir"
            needs_fix=$((needs_fix + $?))
        fi
    done
    
    # Controlla rotazione log
    check_log_rotation
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            # Fix per ogni applicazione
            for app_dir in "$WEBAPPS_DIR"/*; do
                if [ -d "$app_dir" ]; then
                    create_backup "$app_dir/WEB-INF/classes/logging.properties"
                    fix_app_logging "$app_dir"
                fi
            done
            
            # Configura rotazione log
            configure_log_rotation
            
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare che il logging funzioni correttamente per ogni applicazione${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main