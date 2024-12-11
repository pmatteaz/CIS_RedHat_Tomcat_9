#!/bin/bash

# Script per il controllo e fix del CIS Control 4.13
# Restrict access to Tomcat tomcat-users.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File tomcat-users.xml
#   Proprietà utente/gruppo
#   Permessi specifici
#   Immutabilità del file
# 
# Controlli di sicurezza per:
#   Username comuni/default
#   Password in chiaro
#   Ruoli privilegiati
#   Sintassi XML
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Analizza le configurazioni utente (senza esporre password)
#   Calcola l'hash SHA-256 del file

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
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
    local backup_dir="/tmp/tomcat_users_backup_$(date +%Y%m%d_%H%M%S)"
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
    
    # Analisi delle configurazioni utente (con password offuscate)
    echo "### User Configuration Analysis" >> "$backup_file"
    grep -v "password=" "$TOMCAT_USERS_XML" >> "$backup_file"
    echo "Number of users configured:" >> "$backup_file"
    grep -c "<user " "$TOMCAT_USERS_XML" >> "$backup_file"
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_xml_syntax() {
    local result=0
    
    echo "Verifica sintassi XML..."
    
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$TOMCAT_USERS_XML" 2>/dev/null; then
            echo -e "${YELLOW}[WARN] File tomcat-users.xml contiene errori di sintassi XML${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Sintassi XML corretta${NC}"
        fi
    else
        echo -e "${YELLOW}[INFO] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    
    return $result
}

check_users_security() {
    local result=0
    
    echo "Verifica configurazioni di sicurezza utenti..."
    
    # Verifica presenza utenti default
    if grep -qiE "username=\"(admin|manager|root|tomcat)\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}[WARN] Rilevati username comuni/default${NC}"
        result=1
    fi
    
    # Verifica password in chiaro
    if grep -q "password=\"[^\"]*\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}[WARN] Rilevate password in chiaro${NC}"
        result=1
    fi
    
    # Verifica ruoli privilegiati
    if grep -qiE "roles=\".*manager.*\"" "$TOMCAT_USERS_XML"; then
        echo -e "${YELLOW}[WARN] Rilevati ruoli manager${NC}"
        result=1
    fi
    
    return $result
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
    
    # Verifica immutabilità del file
    if command -v lsattr &> /dev/null; then
        local immutable=$(lsattr "$TOMCAT_USERS_XML" 2>/dev/null | cut -c5)
        if [ "$immutable" != "i" ]; then
            echo -e "${YELLOW}[WARN] File non è impostato come immutabile${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] File è impostato come immutabile${NC}"
        fi
    fi
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Rimuovi immutabilità se presente
    if command -v chattr &> /dev/null; then
        chattr -i "$TOMCAT_USERS_XML" 2>/dev/null
    fi
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$TOMCAT_USERS_XML"
    
    # Imposta permessi stretti
    chmod 600 "$TOMCAT_USERS_XML"
    
    # Imposta immutabilità
    if command -v chattr &> /dev/null; then
        chattr +i "$TOMCAT_USERS_XML"
        echo -e "${GREEN}[OK] File impostato come immutabile${NC}"
    fi
    
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
    
    check_xml_syntax
    needs_fix=$((needs_fix + $?))
    
    check_users_security
    needs_fix=$((needs_fix + $?))
    
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