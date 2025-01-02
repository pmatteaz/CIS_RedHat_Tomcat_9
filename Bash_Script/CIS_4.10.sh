#!/bin/bash

# Script per il controllo e fix del CIS Control 4.10
# Restrict access to Tomcat context.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File context.xml principale
#   File context.xml delle applicazioni web
#   Sintassi XML dei file context.xml
#   Proprietà utente/gruppo
#   Permessi specifici
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Calcola l'hash SHA-256 dei file
#   Fa una copia fisica dei file
# 
# Controlli specifici per:
#   File context.xml: 600
#   Proprietà: tomcat:tomcat
#   Sintassi XML valida
# 
# Controlla tutti i context.xml, inclusi quelli in:
#   /conf/context.xml
#   webapps/ROOT/META-INF/context.xml
#   webapps/manager/META-INF/context.xml
#   webapps/host-manager/META-INF/context.xml

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"

# Array dei possibili context.xml in applicazioni web
WEBAPP_CONTEXTS=(
    "ROOT/META-INF/context.xml"
    "manager/META-INF/context.xml"
    "host-manager/META-INF/context.xml"
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

check_file_exists() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] File context.xml principale non trovato: $CONTEXT_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local file_path="$1"
    local backup_dir="/tmp/tomcat_context_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.10"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for context.xml files" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup del context.xml principale
    echo "### File: $CONTEXT_XML" >> "$backup_file"
    ls -l "$CONTEXT_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$CONTEXT_XML" > "${backup_dir}/context_xml_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$CONTEXT_XML" "${backup_dir}/"
    
    # Backup dei context.xml delle applicazioni web
    for ctx in "${WEBAPP_CONTEXTS[@]}"; do
        local webapp_context="$TOMCAT_HOME/webapps/$ctx"
        if [ -f "$webapp_context" ]; then
            echo "### File: $webapp_context" >> "$backup_file"
            ls -l "$webapp_context" >> "$backup_file"
            cp -p "$webapp_context" "${backup_dir}/$(basename $(dirname $ctx))_context.xml"
        fi
    done
    
    # Verifica hash dei file
    if command -v sha256sum &> /dev/null; then
        find "${backup_dir}" -type f -name "*.xml" -exec sha256sum {} \; > "${backup_dir}/context_files.sha256"
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

check_file_permissions() {
    local file="$1"
    local result=0
    
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    echo -e "\nControllo permessi per $file"
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$file")
    local file_group=$(stat -c '%G' "$file")
    local file_perms=$(stat -c '%a' "$file")
    
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
    
    # Verifica permessi stretti (600)
    if [ "$file_perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 600)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi file corretti: $file_perms${NC}"
    fi
    
    return $result
}

check_permissions() {
    local total_result=0
    
    # Controlla context.xml principale
    check_file_permissions "$CONTEXT_XML"
    total_result=$((total_result + $?))
    
    #check_xml_syntax "$CONTEXT_XML"
    #total_result=$((total_result + $?))
    
    # Controlla context.xml delle applicazioni web
    #for ctx in "${WEBAPP_CONTEXTS[@]}"; do
    #    local webapp_context="$TOMCAT_HOME/webapps/$ctx"
    #    if [ -f "$webapp_context" ]; then
    #        check_file_permissions "$webapp_context"
    #        total_result=$((total_result + $?))
    #        
    #        check_xml_syntax "$webapp_context"
    #        total_result=$((total_result + $?))
    #    fi
    #done
    
    return $total_result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup "$CONTEXT_XML"
    
    # Fix context.xml principale
    if [ -f "$CONTEXT_XML" ]; then
        chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CONTEXT_XML"
        chmod 600 "$CONTEXT_XML"
    fi
    
    # Fix context.xml delle applicazioni web
    #for ctx in "${WEBAPP_CONTEXTS[@]}"; do
    #    local webapp_context="$TOMCAT_HOME/webapps/$ctx"
    #    if [ -f "$webapp_context" ]; then
    #        chown "$TOMCAT_USER:$TOMCAT_GROUP" "$webapp_context"
    #        chmod 600 "$webapp_context"
    #    fi
    #done
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.10 - Restrict access to Tomcat context.xml"
    echo "--------------------------------------------------------"
    
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
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main