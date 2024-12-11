#!/bin/bash

# Script per il controllo e fix del CIS Control 7.6
# Ensure directory in logging.properties is a secure location
#
# Lo script implementa le seguenti funzionalità:
# Verifica della sicurezza della directory di logging:
#   Controllo ubicazione della directory
#   Verifica dei permessi directory e file
#   Controllo proprietari e gruppi
#   Identificazione di location potenzialmente insicure
# 
# Controlli specifici:
#   Directory non simboliche
#   Permessi del percorso padre
#   Directory non in location temporanee
#   Permessi corretti per i file di log
# 
# Sistema di correzione:
#   Backup della configurazione
#   Creazione directory sicura se necessario
#   Impostazione permessi corretti
#   Aggiornamento logging.properties

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
LOGGING_PROPERTIES="$TOMCAT_HOME/conf/logging.properties"
DEFAULT_LOG_DIR="$TOMCAT_HOME/logs"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Lista di directory potenzialmente insicure
INSECURE_DIRS=(
    "/tmp"
    "/var/tmp"
    "/dev/shm"
    "/dev"
    "/proc"
    "/sys"
    "/run"
)

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

check_file_exists() {
    if [ ! -f "$LOGGING_PROPERTIES" ]; then
        echo -e "${RED}[ERROR] File logging.properties non trovato: $LOGGING_PROPERTIES${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_logging_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for logging.properties" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $LOGGING_PROPERTIES" >> "$backup_file"
    ls -l "$LOGGING_PROPERTIES" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$LOGGING_PROPERTIES" > "${backup_dir}/logging_properties.acl"
    fi
    
    # Copia fisica del file
    cp -p "$LOGGING_PROPERTIES" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$LOGGING_PROPERTIES" > "${backup_dir}/logging.properties.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

get_log_directory() {
    # Estrae la directory di log da logging.properties
    local log_dir=$(grep "^handlers.*FileHandler.directory" "$LOGGING_PROPERTIES" | cut -d'=' -f2-)
    
    # Rimuovi spazi iniziali e finali
    log_dir=$(echo "$log_dir" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Se non trovato, usa la directory predefinita
    if [ -z "$log_dir" ]; then
        log_dir="$DEFAULT_LOG_DIR"
    fi
    
    # Risolvi variabili d'ambiente se presenti
    log_dir=$(eval echo "$log_dir")
    
    echo "$log_dir"
}

check_directory_security() {
    local log_dir="$1"
    local result=0
    
    echo "Controllo sicurezza directory di logging: $log_dir"
    
    # Verifica se la directory esiste
    if [ ! -d "$log_dir" ]; then
        echo -e "${YELLOW}[WARN] Directory di log non esiste: $log_dir${NC}"
        result=1
    else
        # Verifica proprietario e gruppo
        local dir_owner=$(stat -c '%U' "$log_dir")
        local dir_group=$(stat -c '%G' "$log_dir")
        local dir_perms=$(stat -c '%a' "$log_dir")
        
        if [ "$dir_owner" != "$TOMCAT_USER" ]; then
            echo -e "${YELLOW}[WARN] Proprietario directory non corretto: $dir_owner (dovrebbe essere $TOMCAT_USER)${NC}"
            result=1
        fi
        
        if [ "$dir_group" != "$TOMCAT_GROUP" ]; then
            echo -e "${YELLOW}[WARN] Gruppo directory non corretto: $dir_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
            result=1
        fi
        
        if [ "$dir_perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Permessi directory non corretti: $dir_perms (dovrebbero essere 750)${NC}"
            result=1
        fi
        
        # Verifica permessi dei file di log
        find "$log_dir" -type f -name "*.log" | while read -r log_file; do
            local file_perms=$(stat -c '%a' "$log_file")
            if [ "$file_perms" != "640" ]; then
                echo -e "${YELLOW}[WARN] Permessi file log non corretti: $log_file ($file_perms)${NC}"
                result=1
            fi
        done
    fi
    
    # Verifica se la directory è in una location sicura
    for insecure_dir in "${INSECURE_DIRS[@]}"; do
        if [[ "$log_dir" == "$insecure_dir"* ]]; then
            echo -e "${YELLOW}[WARN] Directory di log in location potenzialmente insicura: $insecure_dir${NC}"
            result=1
            break
        fi
    done
    
    # Verifica se la directory è un symlink
    if [ -L "$log_dir" ]; then
        echo -e "${YELLOW}[WARN] Directory di log è un symlink${NC}"
        result=1
    fi
    
    # Verifica permessi del percorso padre
    local parent_dir=$(dirname "$log_dir")
    if [ "$parent_dir" != "/" ]; then
        local parent_perms=$(stat -c '%a' "$parent_dir")
        if [ "$parent_perms" != "750" ] && [ "$parent_perms" != "755" ]; then
            echo -e "${YELLOW}[WARN] Permessi directory padre non sicuri: $parent_perms${NC}"
            result=1
        fi
    fi
    
    return $result
}

fix_directory_security() {
    local log_dir="$1"
    
    echo "Correzione sicurezza directory di logging..."
    
    # Crea la directory se non esiste
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        echo -e "${GREEN}[OK] Directory di log creata: $log_dir${NC}"
    fi
    
    # Imposta proprietario e permessi corretti
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$log_dir"
    chmod 750 "$log_dir"
    
    # Correggi permessi dei file di log
    find "$log_dir" -type f -name "*.log" -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$log_dir" -type f -name "*.log" -exec chmod 640 {} \;
    
    # Aggiorna logging.properties se necessario
    if ! grep -q "^handlers.*FileHandler.directory" "$LOGGING_PROPERTIES"; then
        echo "handlers.1.org.apache.juli.FileHandler.directory = $log_dir" >> "$LOGGING_PROPERTIES"
    else
        sed -i "s|^handlers.*FileHandler.directory.*|handlers.1.org.apache.juli.FileHandler.directory = $log_dir|" "$LOGGING_PROPERTIES"
    fi
    
    echo -e "${GREEN}[OK] Sicurezza directory di logging configurata${NC}"
}

main() {
    echo "Controllo CIS 7.6 - Ensure directory in logging.properties is a secure location"
    echo "-------------------------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local log_dir=$(get_log_directory)
    local needs_fix=0
    
    check_directory_security "$log_dir"
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_directory_security "$log_dir"
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