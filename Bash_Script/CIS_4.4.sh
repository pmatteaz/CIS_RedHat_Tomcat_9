#!/bin/bash

# Fa già tutto la 4.2
# Script per il controllo e fix del CIS Control 4.4
# Restrict access to Tomcat logs directory
#


# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
CATALINA_BASE=${CATALINA_HOME}
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
LOGS_DIR="$TOMCAT_HOME/logs"

# Tipi di file di log comuni
LOG_FILES=(
    "catalina.out"
    "catalina.*.log"
    "localhost.*.log"
    "host-manager.*.log"
    "manager.*.log"
    "access_log.*"
)

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

check_tomcat_user() {
    if ! id "$TOMCAT_USER" &>/dev/null; then
        echo -e "${RED}[ERROR] Utente Tomcat ($TOMCAT_USER) non trovato${NC}"
        exit 1
    fi
    
    if ! getent group "$TOMCAT_GROUP" &>/dev/null; then
        echo -e "${RED}[ERROR] Gruppo Tomcat ($TOMCAT_GROUP) non trovato${NC}"
        exit 1
    fi
}

check_directory_exists() {
    if [ ! -d "$LOGS_DIR" ]; then
        echo -e "${RED}[ERROR] Directory logs non trovata: $LOGS_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_logs_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.4"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $LOGS_DIR" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup della directory logs
    echo "### Directory: $LOGS_DIR" >> "$backup_file"
    ls -laR "$LOGS_DIR" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl -R "$LOGS_DIR" > "${backup_dir}/logs_acl.txt"
    fi
    
    # Non copiamo i file di log per risparmiare spazio, salviamo solo i permessi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_log_rotation() {
    local result=0
    
    echo "Controllo configurazione log rotation..."
    
    # Verifica se logrotate è installato
    if ! command -v logrotate &> /dev/null; then
        echo -e "${YELLOW}[WARN] logrotate non è installato${NC}"
        result=1
    else
        # Verifica configurazione logrotate per Tomcat
        if [ -f "/etc/logrotate.d/tomcat" ]; then
            echo -e "${GREEN}[OK] Configurazione logrotate per Tomcat trovata${NC}"
        else
            echo -e "${YELLOW}[WARN] Configurazione logrotate per Tomcat non trovata${NC}"
            result=1
        fi
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi directory logs..."
    
    # Controlla directory logs
    local dir_owner=$(stat -c '%U' "$LOGS_DIR")
    local dir_group=$(stat -c '%G' "$LOGS_DIR")
    local dir_perms=$(stat -c '%a' "$LOGS_DIR")
    
    echo -e "\nControllo $LOGS_DIR:"
    
    if [ "$dir_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Proprietario directory non corretto: $dir_owner (dovrebbe essere $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Proprietario directory corretto: $dir_owner${NC}"
    fi
    
    if [ "$dir_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Gruppo directory non corretto: $dir_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Gruppo directory corretto: $dir_group${NC}"
    fi
    
    if [ "$dir_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Permessi directory non corretti: $dir_perms (dovrebbero essere 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi directory corretti: $dir_perms${NC}"
    fi
    
    # Controlla file di log
    echo -e "\nControllo file di log:"
    for pattern in "${LOG_FILES[@]}"; do
        find "$LOGS_DIR" -name "$pattern" -type f | while read -r logfile; do
            local file_owner=$(stat -c '%U' "$logfile")
            local file_group=$(stat -c '%G' "$logfile")
            local file_perms=$(stat -c '%a' "$logfile")
            
            echo -e "\nFile: $(basename "$logfile")"
            
            if [ "$file_owner" != "$TOMCAT_USER" ]; then
                echo -e "${YELLOW}[WARN] Proprietario file non corretto: $file_owner (dovrebbe essere $TOMCAT_USER)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Proprietario file corretto: $file_owner${NC}"
            fi
            
            if [ "$file_group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] Gruppo file non corretto: $file_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Gruppo file corretto: $file_group${NC}"
            fi
            
            if [ "$file_perms" != "640" ]; then
                echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 640)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Permessi file corretti: $file_perms${NC}"
            fi
        done
    done
    
    return $result
}

setup_logrotate() {
    if command -v logrotate &> /dev/null; then
        echo "Configurazione logrotate per Tomcat..."
        
        cat > "/etc/logrotate.d/tomcat" << EOF
$LOGS_DIR/*.log $LOGS_DIR/catalina.out {
    copytruncate
    daily
    rotate 7
    compress
    delaycompress
    missingok
    create 640 $TOMCAT_USER $TOMCAT_GROUP
}
EOF
        echo -e "${GREEN}[OK] Configurazione logrotate creata/aggiornata${NC}"
    fi
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi permessi directory logs
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$LOGS_DIR"
    chmod 750 "$LOGS_DIR"
    
    # Correggi permessi file di log
    find "$LOGS_DIR" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$LOGS_DIR" -type f -exec chmod 640 {} \;
    
    # Configura logrotate se necessario
    setup_logrotate
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.4 - Restrict access to Tomcat logs directory"
    echo "--------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_directory_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    #check_log_rotation
    #needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per assicurarsi che tutti i file siano accessibili${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main