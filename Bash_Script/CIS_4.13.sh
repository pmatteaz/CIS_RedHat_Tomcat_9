#!/bin/bash

# Script per il controllo e fix del CIS Control 4.13
# Restrict access to Tomcat tomcat-users.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File tomcat-users.xml
#   Proprietà utente/gruppo
#   Permessi specifici
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Calcola l'hash SHA-256 del file

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
TOMCAT_USERS_XML="$TOMCAT_HOME/conf/tomcat-users.xml"

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

check_file_exists() {
    if [ ! -f "$TOMCAT_USERS_XML" ]; then
        echo -e "${RED}[ERROR] File tomcat-users.xml non trovato: $TOMCAT_USERS_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_users_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.13"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for tomcat-users.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
    ls -l "$TOMCAT_USERS_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$TOMCAT_USERS_XML" > "${backup_dir}/tomcat_users_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$TOMCAT_USERS_XML" "${backup_dir}/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$TOMCAT_USERS_XML" > "${backup_dir}/tomcat-users.xml.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi tomcat-users.xml..."
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$TOMCAT_USERS_XML")
    local file_group=$(stat -c '%G' "$TOMCAT_USERS_XML")
    local file_perms=$(stat -c '%a' "$TOMCAT_USERS_XML")
    
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
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$TOMCAT_USERS_XML"
    
    # Imposta permessi stretti
    chmod 600 "$TOMCAT_USERS_XML"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.13 - Restrict access to Tomcat tomcat-users.xml"
    echo "---------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare manualmente le configurazioni utente per sicurezza${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main