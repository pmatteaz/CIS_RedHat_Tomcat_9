#!/bin/bash

# Script per il controllo e fix del CIS Control 4.5
# Restrict access to Tomcat temp directory
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
# 
# Directory temp principale
# Tutto il contenuto della directory temp
# Proprietà utente/gruppo
# Permessi specifici
# 
# Include una funzione di backup completa che:
# Crea un backup con timestamp
# Salva tutti i permessi attuali
# Mantiene le ACL se disponibili
# 
# Verifica la configurazione in catalina.properties:
# Controlla java.io.tmpdir
# Aggiorna la configurazione se necessario
# 
# Controlli specifici per:
# Directory temp: 750
# File nella directory temp: 640
# Proprietà: tomcat:tomcat
# 
# Funzionalità di pulizia:
# Rimuove file temporanei vecchi
# Opzione di pulizia anche se i permessi sono corretti

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
TEMP_DIR="$TOMCAT_HOME/temp"

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
    if [ ! -d "$TEMP_DIR" ]; then
        echo -e "${RED}[ERROR] Directory temp non trovata: $TEMP_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_temp_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.5"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $TEMP_DIR" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup della directory temp
    echo "### Directory: $TEMP_DIR" >> "$backup_file"
    ls -laR "$TEMP_DIR" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl -R "$TEMP_DIR" > "${backup_dir}/temp_acl.txt"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_temp_configuration() {
    local result=0
    
    # Verifica la configurazione della directory temp in catalina.properties
    local catalina_props="$TOMCAT_HOME/conf/catalina.properties"
    
    if [ -f "$catalina_props" ]; then
        if ! grep -q "^java.io.tmpdir=" "$catalina_props"; then
            echo -e "${YELLOW}[WARN] java.io.tmpdir non configurato in catalina.properties${NC}"
            result=1
        else
            local configured_temp=$(grep "^java.io.tmpdir=" "$catalina_props" | cut -d= -f2)
            if [ "$configured_temp" != "$TEMP_DIR" ]; then
                echo -e "${YELLOW}[WARN] java.io.tmpdir non punta alla directory temp corretta${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] java.io.tmpdir configurato correttamente${NC}"
            fi
        fi
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi directory temp..."
    
    # Controlla directory temp
    local dir_owner=$(stat -c '%U' "$TEMP_DIR")
    local dir_group=$(stat -c '%G' "$TEMP_DIR")
    local dir_perms=$(stat -c '%a' "$TEMP_DIR")
    
    echo -e "\nControllo $TEMP_DIR:"
    
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
    
    # Controlla contenuto della directory temp
    if [ -n "$(ls -A "$TEMP_DIR")" ]; then
        echo -e "\nControllo contenuto directory temp:"
        find "$TEMP_DIR" -mindepth 1 -print0 | while IFS= read -r -d '' item; do
            local item_owner=$(stat -c '%U' "$item")
            local item_group=$(stat -c '%G' "$item")
            local item_perms=$(stat -c '%a' "$item")
            
            if [ "$item_owner" != "$TOMCAT_USER" ] || [ "$item_group" != "$TOMCAT_GROUP" ]; then
                echo -e "${YELLOW}[WARN] File/directory con proprietario/gruppo non corretto: $item${NC}"
                result=1
            fi
            
            if [ -d "$item" ] && [ "$item_perms" != "750" ]; then
                echo -e "${YELLOW}[WARN] Directory con permessi non corretti: $item ($item_perms)${NC}"
                result=1
            elif [ -f "$item" ] && [ "$item_perms" != "640" ]; then
                echo -e "${YELLOW}[WARN] File con permessi non corretti: $item ($item_perms)${NC}"
                result=1
            fi
        done
    fi
    
    return $result
}

fix_temp_configuration() {
    local catalina_props="$TOMCAT_HOME/conf/catalina.properties"
    
    if [ -f "$catalina_props" ]; then
        # Backup del file
        cp "$catalina_props" "${catalina_props}.bak"
        
        # Aggiorna o aggiungi la configurazione java.io.tmpdir
        if grep -q "^java.io.tmpdir=" "$catalina_props"; then
            sed -i "s|^java.io.tmpdir=.*|java.io.tmpdir=$TEMP_DIR|" "$catalina_props"
        else
            echo "java.io.tmpdir=$TEMP_DIR" >> "$catalina_props"
        fi
        
        echo -e "${GREEN}[OK] Configurazione temp directory aggiornata in catalina.properties${NC}"
    fi
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi permessi directory temp
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$TEMP_DIR"
    chmod 750 "$TEMP_DIR"
    
    # Correggi permessi contenuto directory temp
    find "$TEMP_DIR" -mindepth 1 -print0 | while IFS= read -r -d '' item; do
        chown "$TOMCAT_USER:$TOMCAT_GROUP" "$item"
        if [ -d "$item" ]; then
            chmod 750 "$item"
        else
            chmod 640 "$item"
        fi
    done
    
    # Configura temp directory in catalina.properties
    fix_temp_configuration
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

cleanup_temp() {
    echo "Pulizia directory temp..."
    
    # Rimuovi file più vecchi di 24 ore
    find "$TEMP_DIR" -mindepth 1 -mtime +1 -delete
    
    echo -e "${GREEN}[OK] Pulizia completata${NC}"
}

main() {
    echo "Controllo CIS 4.5 - Restrict access to Tomcat temp directory"
    echo "--------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_directory_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    check_temp_configuration
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            cleanup_temp
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
        
        echo -e "\nVuoi eseguire comunque la pulizia della directory temp? (y/n)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cleanup_temp
        fi
    fi
}

main