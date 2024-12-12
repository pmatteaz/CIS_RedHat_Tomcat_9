#!/bin/bash

# Script per il controllo e fix del CIS Control 4.12
# Restrict access to Tomcat server.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File server.xml
#   Proprietà utente/gruppo
#   Permessi specifici
#   Immutabilità del file
# 
# Verifica della configurazione:
#   Sintassi XML
#   Configurazioni critiche (porte, SSL, AJP)
#   Impostazioni di sicurezza
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Analizza le configurazioni sensibili
#   Calcola l'hash SHA-256 del file
# 
# Controlli specifici per:
#   File server.xml: 600
#   Proprietà: tomcat:tomcat
#   Attributo immutabile

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

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
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] File server.xml non trovato: $SERVER_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_server_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.12"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
    ls -l "$SERVER_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$SERVER_XML" "${backup_dir}/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi
    
    # Analisi configurazioni sensibili
    echo "### Sensitive Configuration Analysis" >> "$backup_file"
    echo "Connectors:" >> "$backup_file"
    grep -A 5 "<Connector" "$SERVER_XML" >> "$backup_file"
    echo "Listeners:" >> "$backup_file"
    grep -A 2 "<Listener" "$SERVER_XML" >> "$backup_file"
    
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
        if ! xmllint --noout "$SERVER_XML" 2>/dev/null; then
            echo -e "${YELLOW}[WARN] File server.xml contiene errori di sintassi XML${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Sintassi XML corretta${NC}"
        fi
    else
        echo -e "${YELLOW}[INFO] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    
    return $result
}

check_critical_settings() {
    local result=0
    
    echo "Verifica configurazioni critiche..."
    
    # Verifica shutdown port
    if grep -q 'port="8005"' "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Shutdown port default (8005) rilevata${NC}"
        result=1
    fi
    
    # Verifica presenza AJP non protetto
    if grep -q '<Connector protocol="AJP/1.3"' "$SERVER_XML" && ! grep -q 'secretRequired="true"' "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Connettore AJP senza secret rilevato${NC}"
        result=1
    fi
    
    # Verifica SSL settings
    if grep -q 'SSLEnabled="true"' "$SERVER_XML"; then
        if ! grep -q 'sslProtocol="TLS"' "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] SSL abilitato ma protocollo TLS non specificato${NC}"
            result=1
        fi
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi server.xml..."
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$SERVER_XML")
    local file_group=$(stat -c '%G' "$SERVER_XML")
    local file_perms=$(stat -c '%a' "$SERVER_XML")
    
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
        local immutable=$(lsattr "$SERVER_XML" 2>/dev/null | cut -c5)
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
        chattr -i "$SERVER_XML" 2>/dev/null
    fi
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    
    # Imposta permessi stretti
    chmod 600 "$SERVER_XML"
    
    # Imposta immutabilità
    if command -v chattr &> /dev/null; then
        chattr +i "$SERVER_XML"
        echo -e "${GREEN}[OK] File impostato come immutabile${NC}"
    fi
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.12 - Restrict access to Tomcat server.xml"
    echo "-------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    check_xml_syntax
    needs_fix=$((needs_fix + $?))
    
    check_critical_settings
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare manualmente le configurazioni critiche evidenziate${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main