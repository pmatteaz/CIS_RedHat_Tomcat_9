#!/bin/bash

# Script per il controllo e fix del CIS Control 4.7
# Restrict access to Tomcat web application directory
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   Directory webapps principale
#   Directory delle applicazioni web individuali
#   File web.xml di ogni applicazione
#   Directory sensibili (manager, host-manager, ecc.)
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva tutti i permessi attuali
#   Mantiene le ACL se disponibili
#   Fa una lista delle applicazioni installate
# 
# Controlli specifici per:
#   Directory webapps e sottodirectory: 750
#   File delle applicazioni: 640
#   File web.xml: 640
#   Proprietà: tomcat:tomcat
# 
# Attenzione particolare per directory sensibili:
#   manager
#   host-manager
#   admin
#   ROOT

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
WEBAPP_DIR="$TOMCAT_HOME/webapps"

# Directory sensibili da controllare specificamente
SENSITIVE_DIRS=(
    "manager"
    "host-manager"
    "admin"
    "ROOT"
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
    if [ ! -d "$WEBAPP_DIR" ]; then
        echo -e "${RED}[ERROR] Directory webapps non trovata: $WEBAPP_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_webapps_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.7"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $WEBAPP_DIR" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup della directory webapps
    echo "### Directory: $WEBAPP_DIR" >> "$backup_file"
    ls -laR "$WEBAPP_DIR" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl -R "$WEBAPP_DIR" > "${backup_dir}/webapps_acl.txt"
    fi
    
    # Lista delle applicazioni web installate
    echo "### Installed Web Applications" >> "$backup_file"
    for app in "$WEBAPP_DIR"/*; do
        if [ -d "$app" ]; then
            echo "$(basename "$app")" >> "$backup_file"
        fi
    done
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_webapp_xml_permissions() {
    local result=0
    
    echo "Controllo permessi file web.xml delle applicazioni..."
    
    find "$WEBAPP_DIR" -name "web.xml" -type f | while read -r file; do
        local file_owner=$(stat -c '%U' "$file")
        local file_group=$(stat -c '%G' "$file")
        local file_perms=$(stat -c '%a' "$file")
        
        echo -e "\nFile: $file"
        
        if [ "$file_owner" != "$TOMCAT_USER" ]; then
            echo -e "${YELLOW}[WARN] Proprietario web.xml non corretto: $file_owner (dovrebbe essere $TOMCAT_USER)${NC}"
            result=1
        fi
        
        if [ "$file_group" != "$TOMCAT_GROUP" ]; then
            echo -e "${YELLOW}[WARN] Gruppo web.xml non corretto: $file_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
            result=1
        fi
        
        if [ "$file_perms" != "640" ]; then
            echo -e "${YELLOW}[WARN] Permessi web.xml non corretti: $file_perms (dovrebbero essere 640)${NC}"
            result=1
        fi
    done
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi directory webapps..."
    
    # Controlla directory webapps principale
    local dir_owner=$(stat -c '%U' "$WEBAPP_DIR")
    local dir_group=$(stat -c '%G' "$WEBAPP_DIR")
    local dir_perms=$(stat -c '%a' "$WEBAPP_DIR")
    
    echo -e "\nControllo $WEBAPP_DIR:"
    
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
    
    # Controllo specifico per directory sensibili
    echo -e "\nControllo directory sensibili:"
    for dir in "${SENSITIVE_DIRS[@]}"; do
        if [ -d "$WEBAPP_DIR/$dir" ]; then
            local sens_owner=$(stat -c '%U' "$WEBAPP_DIR/$dir")
            local sens_group=$(stat -c '%G' "$WEBAPP_DIR/$dir")
            local sens_perms=$(stat -c '%a' "$WEBAPP_DIR/$dir")
            
            echo -e "\nDirectory: $dir"
            
            if [ "$sens_owner" != "$TOMCAT_USER" ] || [ "$sens_group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] Proprietario/gruppo directory sensibile non corretto: $WEBAPP_DIR/$dir${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Proprietario e gruppo directory sensibile corretti${NC}"
            fi
            
            if [ "$sens_perms" != "750" ]; then
                echo -e "${YELLOW}[WARN] Permessi directory sensibile non corretti: $sens_perms${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Permessi directory sensibile corretti${NC}"
            fi
        fi
    done
    
    # Controllo web.xml
    check_webapp_xml_permissions
    result=$((result + $?))
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi permessi directory webapps principale
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$WEBAPP_DIR"
    chmod 750 "$WEBAPP_DIR"
    
    # Correggi permessi di tutte le applicazioni web
    find "$WEBAPP_DIR" -type d -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$WEBAPP_DIR" -type d -exec chmod 750 {} \;
    find "$WEBAPP_DIR" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$WEBAPP_DIR" -type f -exec chmod 640 {} \;
    
    # Correggi specificamente i file web.xml
    find "$WEBAPP_DIR" -name "web.xml" -type f -exec chmod 640 {} \;
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.7 - Restrict access to Tomcat web application directory"
    echo "-------------------------------------------------------------------"
    
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
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per assicurarsi che tutte le applicazioni funzionino correttamente${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main