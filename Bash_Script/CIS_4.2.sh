#!/bin/bash

# Script per il controllo e fix del CIS Control 4.2
# Restrict access to $CATALINA_BASE
#
# Lo script implementa le seguenti funzionalità:
# Verifica le autorizzazioni per:
# 
# Tutte le directory in CATALINA_BASE
# File all'interno di queste directory
# Proprietà utente/gruppo
# Permessi specifici per directory sensibili
# 
# Include una funzione di backup completa che:
# 
# Crea un backup con timestamp
# Salva tutti i permessi attuali
# Mantiene le ACL se disponibili
# Crea un archivio compresso
# 
# Controlla:
# 
# L'esistenza dell'utente e gruppo Tomcat
# I permessi corretti per ogni directory
# Proprietà dei file
# Permessi specifici per:
# 
# conf: 700 (dir), 600 (files)
# logs, temp, work: 750 (dir), 640 (files)
# altre directory: 750 (dir), 640 (files)


# Configurazione predefinita
CATALINA_BASE=${CATALINA_BASE:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}

# Directories da proteggere in CATALINA_BASE
PROTECTED_DIRS=(
    "$CATALINA_BASE"
    "$CATALINA_BASE/bin"
    "$CATALINA_BASE/conf"
    "$CATALINA_BASE/lib"
    "$CATALINA_BASE/logs"
    "$CATALINA_BASE/temp"
    "$CATALINA_BASE/webapps"
    "$CATALINA_BASE/work"
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
    if [ ! -d "$CATALINA_BASE" ]; then
        echo -e "${RED}[ERROR] Directory CATALINA_BASE non trovata: $CATALINA_BASE${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/catalina_base_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.2"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $CATALINA_BASE" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    for dir in "${PROTECTED_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "### Directory: $dir" >> "$backup_file"
            ls -laR "$dir" >> "$backup_file"
            echo >> "$backup_file"
            
            # Backup dei permessi usando getfacl
            if command -v getfacl &> /dev/null; then
                getfacl -R "$dir" > "${backup_dir}/$(basename "$dir")_acl.txt"
            fi
        fi
    done
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi directories in CATALINA_BASE..."
    
    for dir in "${PROTECTED_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            echo -e "${YELLOW}[WARN] Directory non trovata: $dir${NC}"
            continue
        fi
        
        # Controlla proprietario e gruppo
        local owner=$(stat -c '%U' "$dir")
        local group=$(stat -c '%G' "$dir")
        local perms=$(stat -c '%a' "$dir")
        
        echo -e "\nControllo $dir:"
        
        if [ "$owner" != "$TOMCAT_USER" ]; then
            echo -e "${YELLOW}[WARN] Proprietario non corretto: $owner (dovrebbe essere $TOMCAT_USER)${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Proprietario corretto: $owner${NC}"
        fi
        
        if [ "$group" != "$TOMCAT_GROUP" ]; then
            echo -e "${YELLOW}[WARN] Gruppo non corretto: $group (dovrebbe essere $TOMCAT_GROUP)${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Gruppo corretto: $group${NC}"
        fi
        
        # Verifica permessi specifici per directory
        local expected_perms
        case "$dir" in
            "$CATALINA_BASE/conf")
                expected_perms="700"
                ;;
            "$CATALINA_BASE/logs" | "$CATALINA_BASE/temp" | "$CATALINA_BASE/work")
                expected_perms="750"
                ;;
            *)
                expected_perms="750"
                ;;
        esac
        
        if [ "$perms" != "$expected_perms" ]; then
            echo -e "${YELLOW}[WARN] Permessi non corretti: $perms (dovrebbero essere $expected_perms)${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Permessi corretti: $perms${NC}"
        fi
        
        # Controlla permessi dei file nella directory
        if [ -d "$dir" ]; then
            find "$dir" -type f -print0 | while IFS= read -r -d '' file; do
                local file_perms=$(stat -c '%a' "$file")
                local file_owner=$(stat -c '%U' "$file")
                local file_group=$(stat -c '%G' "$file")
                
                if [ "$file_owner" != "$TOMCAT_USER" ] || [ "$file_group" != "$TOMCAT_GROUP" ]; then
                    echo -e "${YELLOW}[WARN] File con proprietario/gruppo non corretto: $file${NC}"
                    result=1
                fi
                
                # Permessi più restrittivi per file in conf
                if [[ "$dir" == "$CATALINA_BASE/conf" && "$file_perms" != "600" ]]; then
                    echo -e "${YELLOW}[WARN] File in conf con permessi non corretti: $file ($file_perms)${NC}"
                    result=1
                elif [[ "$dir" != "$CATALINA_BASE/conf" && "$file_perms" -gt "640" ]]; then
                    echo -e "${YELLOW}[WARN] File con permessi troppo permissivi: $file ($file_perms)${NC}"
                    result=1
                fi
            done
        fi
    done
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    for dir in "${PROTECTED_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        
        echo "Correzione permessi per $dir"
        
        # Imposta proprietario e gruppo
        chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$dir"
        
        # Imposta permessi specifici per directory
        case "$dir" in
            "$CATALINA_BASE/conf")
                chmod 700 "$dir"
                find "$dir" -type f -exec chmod 600 {} \;
                ;;
            "$CATALINA_BASE/logs" | "$CATALINA_BASE/temp" | "$CATALINA_BASE/work")
                chmod 750 "$dir"
                find "$dir" -type f -exec chmod 640 {} \;
                ;;
            *)
                chmod 750 "$dir"
                find "$dir" -type f -exec chmod 640 {} \;
                ;;
        esac
    done
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
}

main() {
    echo "Controllo CIS 4.2 - Restrict access to \$CATALINA_BASE"
    echo "----------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_directory_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
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