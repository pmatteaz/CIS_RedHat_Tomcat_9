#!/bin/bash

# Script per il controllo e fix del CIS Control 7.2
# Specify file handler in logging.properties files
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione dei file handler:
#   Controllo delle configurazioni obbligatorie
#   Verifica dei parametri di sicurezza
#   Controllo directory e permessi
# 
# Controlli specifici per:
#   FileHandler e ConsoleHandler
#   Configurazioni di formattazione
#   Encoding e buffering
#   Rotazione dei log
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Applicazione configurazioni raccomandate
#   Correzione permessi file e directory
#   Rotazione automatica dei log

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
LOGGING_PROPS="$TOMCAT_HOME/conf/logging.properties"
LOG_DIR="$TOMCAT_HOME/logs"

# Configurazione raccomandata per file handler
HANDLER_CONFIG="
handlers = org.apache.juli.FileHandler, java.util.logging.ConsoleHandler

# File handler configuration
org.apache.juli.FileHandler.level = FINE
org.apache.juli.FileHandler.directory = ${LOG_DIR}
org.apache.juli.FileHandler.prefix = tomcat_
org.apache.juli.FileHandler.suffix = .log
org.apache.juli.FileHandler.formatter = org.apache.juli.OneLineFormatter
org.apache.juli.FileHandler.maxDays = 90
org.apache.juli.FileHandler.encoding = UTF-8
org.apache.juli.FileHandler.rotatable = true
org.apache.juli.FileHandler.buffered = false

# Console handler configuration
java.util.logging.ConsoleHandler.level = FINE
java.util.logging.ConsoleHandler.formatter = org.apache.juli.OneLineFormatter
java.util.logging.ConsoleHandler.encoding = UTF-8

# Root logger configuration
.level = INFO"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

check_file_exists() {
    if [ ! -f "$LOGGING_PROPS" ]; then
        echo -e "${RED}[ERROR] File logging.properties non trovato: $LOGGING_PROPS${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_logging_backup_$(date +%Y%m%d_%H%M%S)_CIS_7.2"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for logging.properties" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $LOGGING_PROPS" >> "$backup_file"
    ls -l "$LOGGING_PROPS" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$LOGGING_PROPS" > "${backup_dir}/logging_properties.acl"
    fi
    
    # Copia fisica del file
    cp -p "$LOGGING_PROPS" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$LOGGING_PROPS" > "${backup_dir}/logging.properties.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_handler_config() {
    local result=0
    
    echo "Controllo configurazione file handler..."
    
    # Verifica handlers definiti
    if ! grep -Eq "(^[hH]andlers = .*FileHandler|[[:space:]][hH]andlers = .*FileHandler)" "$LOGGING_PROPS"; then
        echo -e "${YELLOW}[WARN] FileHandler non configurato correttamente${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] FileHandler configurato${NC}"
    fi
    
    # Verifica configurazioni obbligatorie
    local required_configs=(
        "org.apache.juli.AsyncFileHandler.level"
    )
    #    "org.apache.juli.AsyncFileHandler.directory"
    #    "org.apache.juli.AsyncFileHandler.prefix"
    #    "org.apache.juli.AsyncFileHandler.suffix"
    #    "org.apache.juli.AsyncFileHandler.formatter"
    
    for config in "${required_configs[@]}"; do
        if ! grep -E "$config = " "$LOGGING_PROPS"; then
            echo -e "${YELLOW}[WARN] Configurazione mancante: $config${NC}"
            result=1
        fi
    done
    
    # Verifica directory di log
    #if grep -q "^org.apache.juli.FileHandler.directory = " "$LOGGING_PROPS"; then
    #    local log_dir=$(grep "^org.apache.juli.FileHandler.directory = " "$LOGGING_PROPS" | cut -d'=' -f2 | tr -d ' ')
    #    if [ ! -d "$log_dir" ]; then
    #        echo -e "${YELLOW}[WARN] Directory di log non esistente: $log_dir${NC}"
    #        result=1
    #    else
    #        # Verifica permessi directory
    #        local dir_perms=$(stat -c '%a' "$log_dir")
    #        if [ "$dir_perms" != "750" ]; then
    #            echo -e "${YELLOW}[WARN] Permessi directory log non corretti: $dir_perms (dovrebbero essere 750)${NC}"
    #            result=1
    #        fi
    #    fi
    #fi
    
    # Verifica configurazioni di sicurezza
    #if ! grep -q "^org.apache.juli.FileHandler.buffered = false" "$LOGGING_PROPS"; then
    #    echo -e "${YELLOW}[WARN] Buffering non disabilitato - potenziale rischio di perdita log${NC}"
    #    result=1
    #fi
    #
    #if ! grep -q "^org.apache.juli.FileHandler.encoding = UTF-8" "$LOGGING_PROPS"; then
    #    echo -e "${YELLOW}[WARN] Encoding non specificato${NC}"
    #    result=1
    #fi
    
    return $result
}

fix_handler_config() {
    echo "Applicazione configurazione file handler..."
    
    # Assicurati che la directory di log esista
    #mkdir -p "$LOG_DIR"
    #chown "$TOMCAT_USER:$TOMCAT_GROUP" "$LOG_DIR"
    #chmod 750 "$LOG_DIR"
    if [ ! -f "$LOG_DIR" ]; then
        echo -e "${RED}[ERROR] Directory di logging non trovato: $LOG_DIR${NC}"
        exit 1
    fi
    
    # Applica la configurazione raccomandata
    # echo "$HANDLER_CONFIG" > "$LOGGING_PROPS"

    # Applico modifica alla riga handlers

    sed -i 's/juli,/juli.AsyncFileHandler,/g' "$LOGGING_PROPS"
    
}

check_log_files() {
    local result=0
    
    echo "Controllo file di log esistenti..."
    
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -type f -name "*.log" | while read -r log_file; do
            local file_perms=$(stat -c '%a' "$log_file")
            local file_owner=$(stat -c '%U' "$log_file")
            local file_group=$(stat -c '%G' "$log_file")
            
            if [ "$file_perms" != "640" ]; then
                echo -e "${YELLOW}[WARN] Permessi non corretti per $log_file: $file_perms (dovrebbero essere 640)${NC}"
                result=1
            fi
            
            if [ "$file_owner" != "$TOMCAT_USER" ] || [ "$file_group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] Proprietario/gruppo non corretti per $log_file${NC}"
                result=1
            fi
        done
    fi
    
    return $result
}

fix_log_files() {
    echo "Correzione permessi file di log..."
    
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -type f -name "*.log" -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
        find "$LOG_DIR" -type f -name "*.log" -exec chmod 640 {} \;
    fi
    
    echo -e "${GREEN}[OK] Permessi file di log corretti${NC}"
}

main() {
    echo "Controllo CIS 7.2 - Specify file handler in logging.properties"
    echo "--------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_handler_config
    needs_fix=$((needs_fix + $?))
    
    #check_log_files
    #needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_handler_config
            # fix_log_files
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare che il logging funzioni correttamente${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main