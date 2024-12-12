#!/bin/bash

# Script per il controllo e fix del CIS Control 4.14
# Restrict access to Tomcat web.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File web.xml principale in /conf
#   Tutti i web.xml nelle applicazioni web
#   Proprietà utente/gruppo
#   Permessi specifici
# 
# Controlli di sicurezza per:
#   Sintassi XML
#   Configurazioni di sicurezza
#   Debug mode
#   Security constraints
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp di tutti i web.xml
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Mantiene la struttura delle directory
#   Calcola gli hash SHA-256 dei file

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
CONF_WEB_XML="$TOMCAT_HOME/conf/web.xml"

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

check_files_exist() {
    if [ ! -f "$CONF_WEB_XML" ]; then
        echo -e "${RED}[ERROR] File web.xml principale non trovato: $CONF_WEB_XML${NC}"
        exit 1
    fi
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] Directory webapps non trovata: $WEBAPPS_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_webxml_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.14"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for web.xml files" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup del web.xml principale
    echo "### Main web.xml configuration" >> "$backup_file"
    ls -l "$CONF_WEB_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$CONF_WEB_XML" > "${backup_dir}/conf_webxml_acl.txt"
    fi
    
    # Copia fisica del file principale
    cp -p "$CONF_WEB_XML" "${backup_dir}/conf_web.xml"
    
    # Backup di tutti i web.xml nelle applicazioni
    find "$WEBAPPS_DIR" -name "web.xml" -type f | while read -r webapp_xml; do
        echo "### Web Application web.xml: $webapp_xml" >> "$backup_file"
        ls -l "$webapp_xml" >> "$backup_file"
        
        if command -v getfacl &> /dev/null; then
            getfacl "$webapp_xml" > "${backup_dir}/$(echo "$webapp_xml" | sed 's/\//_/g')_acl.txt"
        fi
        
        # Crea struttura directory per il backup
        local rel_path=${webapp_xml#$WEBAPPS_DIR/}
        local backup_path="$backup_dir/webapps/$rel_path"
        mkdir -p "$(dirname "$backup_path")"
        cp -p "$webapp_xml" "$backup_path"
    done
    
    # Verifica hash dei file
    if command -v sha256sum &> /dev/null; then
        find "$backup_dir" -type f -name "web.xml" -exec sha256sum {} \; > "${backup_dir}/web_xml_files.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_xml_syntax() {
    local file="$1"
    local result=0
    
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$file" 2>/dev/null; then
            echo -e "${YELLOW}[WARN] File $file contiene errori di sintassi XML${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Sintassi XML corretta per $file${NC}"
        fi
    else
        echo -e "${YELLOW}[INFO] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    
    return $result
}

check_web_xml_security() {
    local file="$1"
    local result=0
    
    # Verifica configurazioni di sicurezza comuni
    if ! grep -q "<security-constraint>" "$file"; then
        echo -e "${YELLOW}[WARN] Nessun security-constraint trovato in $file${NC}"
        result=1
    fi
    
    # Verifica presenza di configurazioni sensibili
    if grep -q "debug=\"true\"" "$file"; then
        echo -e "${YELLOW}[WARN] Debug mode abilitato in $file${NC}"
        result=1
    fi
    
    return $result
}

check_permissions() {
    local file="$1"
    local result=0
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$file")
    local file_group=$(stat -c '%G' "$file")
    local file_perms=$(stat -c '%a' "$file")
    
    echo -e "\nControllo permessi per $file:"
    
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
    local file="$1"
    
    if [ ! -f "$file" ]; then
        return
    fi
    
    echo "Correzione permessi per $file..."
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    
    # Imposta permessi stretti
    chmod 600 "$file"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati a $file${NC}"
}

fix_all_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Fix web.xml principale
    fix_permissions "$CONF_WEB_XML"
    
    # Fix web.xml delle applicazioni
    find "$WEBAPPS_DIR" -name "web.xml" -type f | while read -r webapp_xml; do
        fix_permissions "$webapp_xml"
    done
    
    echo -e "${GREEN}[OK] Permessi corretti applicati a tutti i file web.xml${NC}"
}

check_all() {
    local total_result=0
    
    # Controllo web.xml principale
    echo "Controllo web.xml principale..."
    check_permissions "$CONF_WEB_XML"
    total_result=$((total_result + $?))
    
    check_xml_syntax "$CONF_WEB_XML"
    total_result=$((total_result + $?))
    
    check_web_xml_security "$CONF_WEB_XML"
    total_result=$((total_result + $?))
    
    # Controllo web.xml delle applicazioni
    echo -e "\nControllo web.xml delle applicazioni..."
    find "$WEBAPPS_DIR" -name "web.xml" -type f | while read -r webapp_xml; do
        check_permissions "$webapp_xml"
        total_result=$((total_result + $?))
        
        check_xml_syntax "$webapp_xml"
        total_result=$((total_result + $?))
        
        check_web_xml_security "$webapp_xml"
        total_result=$((total_result + $?))
    done
    
    return $total_result
}

main() {
    echo "Controllo CIS 4.14 - Restrict access to Tomcat web.xml"
    echo "-------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_files_exist
    
    local needs_fix=0
    
    check_all
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_all_permissions
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare manualmente le configurazioni di sicurezza${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main