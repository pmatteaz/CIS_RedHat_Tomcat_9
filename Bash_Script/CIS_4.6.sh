#!/bin/bash

# Script per il controllo e fix del CIS Control 4.6
# Restrict access to Tomcat binaries directory
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#  Directory bin principale
#  File binari e script critici
#  Proprietà utente/gruppo
#  Permessi specifici per tipo di file
# 
# Include una funzione di backup completa che:
#  Crea un backup con timestamp
#  Salva tutti i permessi attuali
#  Mantiene le ACL se disponibili
#  Fa un backup fisico dei file critici
# 
# Controlli specifici per:
#  Directory bin: 750
#  Script .sh: 750
#  Altri file: 640
#  Proprietà: tomcat:tomcat
# 
# Controlla una lista predefinita di file critici:
#  startup.sh, shutdown.sh
#  catalina.sh, setenv.sh
#  bootstrap.jar, tomcat-juli.jar


# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
BIN_DIR="$TOMCAT_HOME/bin"

# Lista dei file binari critici
CRITICAL_FILES=(
    "startup.sh"
    "shutdown.sh"
    "catalina.sh"
    "setenv.sh"
    "tomcat-juli.jar"
    "bootstrap.jar"
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
    if [ ! -d "$BIN_DIR" ]; then
        echo -e "${RED}[ERROR] Directory bin non trovata: $BIN_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_bin_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $BIN_DIR" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup della directory bin
    echo "### Directory: $BIN_DIR" >> "$backup_file"
    ls -laR "$BIN_DIR" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl -R "$BIN_DIR" > "${backup_dir}/bin_acl.txt"
    fi
    
    # Backup fisico dei file critici
    mkdir -p "${backup_dir}/bin"
    for file in "${CRITICAL_FILES[@]}"; do
        if [ -f "$BIN_DIR/$file" ]; then
            cp -p "$BIN_DIR/$file" "${backup_dir}/bin/"
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
    
    echo "Controllo permessi directory bin..."
    
    # Controlla directory bin
    local dir_owner=$(stat -c '%U' "$BIN_DIR")
    local dir_group=$(stat -c '%G' "$BIN_DIR")
    local dir_perms=$(stat -c '%a' "$BIN_DIR")
    
    echo -e "\nControllo $BIN_DIR:"
    
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
    
    # Controlla file critici
    echo -e "\nControllo file critici:"
    for file in "${CRITICAL_FILES[@]}"; do
        if [ -f "$BIN_DIR/$file" ]; then
            local file_owner=$(stat -c '%U' "$BIN_DIR/$file")
            local file_group=$(stat -c '%G' "$BIN_DIR/$file")
            local file_perms=$(stat -c '%a' "$BIN_DIR/$file")
            
            echo -e "\nFile: $file"
            
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
            
            # Controlla eseguibilità per script .sh
            if [[ "$file" == *.sh ]]; then
                if [ "$file_perms" != "750" ]; then
                    echo -e "${YELLOW}[WARN] Permessi script non corretti: $file_perms (dovrebbero essere 750)${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Permessi script corretti: $file_perms${NC}"
                fi
            else
                if [ "$file_perms" != "640" ]; then
                    echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 640)${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Permessi file corretti: $file_perms${NC}"
                fi
            fi
        fi
    done
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi permessi directory bin
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$BIN_DIR"
    chmod 750 "$BIN_DIR"
    
    # Correggi permessi file
    for file in "${CRITICAL_FILES[@]}"; do
        if [ -f "$BIN_DIR/$file" ]; then
            chown "$TOMCAT_USER:$TOMCAT_GROUP" "$BIN_DIR/$file"
            if [[ "$file" == *.sh ]]; then
                chmod 750 "$BIN_DIR/$file"
            else
                chmod 640 "$BIN_DIR/$file"
            fi
        fi
    done
    
    # Correggi permessi per tutti gli altri file nella directory
    find "$BIN_DIR" -type f ! -name "*.sh" -exec chmod 640 {} \;
    find "$BIN_DIR" -type f -name "*.sh" -exec chmod 750 {} \;
    find "$BIN_DIR" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.6 - Restrict access to Tomcat binaries directory"
    echo "------------------------------------------------------------"
    
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