#!/bin/bash

# Script per il controllo e fix del CIS Control 4.3
# Restrict access to Tomcat configuration directory
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
# 
# Directory conf principale
# File di configurazione critici
# Proprietà utente/gruppo
# Permessi specifici
# 
# Include una funzione di backup completa che:
# Crea un backup con timestamp
# Salva tutti i permessi attuali
# Mantiene le ACL se disponibili
# Fa una copia fisica dei file di configurazione
# Crea un archivio compresso
# 
# Controlli specifici per:
# Directory conf: 700
# File di configurazione: 600
# Proprietà: tomcat:tomcat

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CONF_DIR="$TOMCAT_HOME/conf"

# File critici di configurazione
CRITICAL_FILES=(
    "server.xml"
    "web.xml"
    "context.xml"
    "tomcat-users.xml"
    "catalina.properties"
    "catalina.policy"
    "logging.properties"
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
    if [ ! -d "$CONF_DIR" ]; then
        echo -e "${RED}[ERROR] Directory di configurazione non trovata: $CONF_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_conf_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $CONF_DIR" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup della directory conf
    echo "### Directory: $CONF_DIR" >> "$backup_file"
    ls -laR "$CONF_DIR" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl -R "$CONF_DIR" > "${backup_dir}/conf_acl.txt"
    fi
    
    # Copia fisica dei file di configurazione
    mkdir -p "${backup_dir}/conf"
    cp -pr "$CONF_DIR"/* "${backup_dir}/conf/"
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi directory di configurazione..."
    
    # Controlla directory conf
    local dir_owner=$(stat -c '%U' "$CONF_DIR")
    local dir_group=$(stat -c '%G' "$CONF_DIR")
    local dir_perms=$(stat -c '%a' "$CONF_DIR")
    
    echo -e "\nControllo $CONF_DIR:"
    
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
    
    if [ "$dir_perms" != "700" ]; then
        echo -e "${YELLOW}[WARN] Permessi directory non corretti: $dir_perms (dovrebbero essere 700)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi directory corretti: $dir_perms${NC}"
    fi
    
    # Controlla file critici
    echo -e "\nControllo file di configurazione critici:"
    for file in "${CRITICAL_FILES[@]}"; do
        if [ -f "$CONF_DIR/$file" ]; then
            local file_owner=$(stat -c '%U' "$CONF_DIR/$file")
            local file_group=$(stat -c '%G' "$CONF_DIR/$file")
            local file_perms=$(stat -c '%a' "$CONF_DIR/$file")
            
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
            
            if [ "$file_perms" != "600" ]; then
                echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 600)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Permessi file corretti: $file_perms${NC}"
            fi
        fi
    done
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi permessi directory conf
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CONF_DIR"
    chmod 700 "$CONF_DIR"
    
    # Correggi permessi file di configurazione
    find "$CONF_DIR" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$CONF_DIR" -type f -exec chmod 600 {} \;
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.3 - Restrict access to Tomcat configuration directory"
    echo "-----------------------------------------------------------------"
    
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