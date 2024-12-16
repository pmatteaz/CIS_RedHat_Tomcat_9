#!/bin/bash

# Script per il controllo e fix del CIS Control 4.11
# Restrict access to Tomcat logging.properties
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File logging.properties
#   Directory padre (conf)
#   Proprietà utente/gruppo
#   Permessi specifici
# 
# Verifica della configurazione di logging:
#   Presenza handlers obbligatori
#   Uso appropriato dei livelli di logging
#   Presenza di handlers potenzialmente non sicuri
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Salva le configurazioni critiche
#   Calcola l'hash SHA-256 del file
# 
# Controlli specifici per:
#   File logging.properties: 600
#   Directory padre: 750
#   Proprietà: tomcat:tomcat

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
LOGGING_PROPS="$TOMCAT_HOME/conf/logging.properties"

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
    if [ ! -f "$LOGGING_PROPS" ]; then
        echo -e "${RED}[ERROR] File logging.properties non trovato: $LOGGING_PROPS${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_logging_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.11"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for logging.properties" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
    ls -l "$LOGGING_PROPS" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$LOGGING_PROPS" > "${backup_dir}/logging_properties_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$LOGGING_PROPS" "${backup_dir}/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$LOGGING_PROPS" > "${backup_dir}/logging.properties.sha256"
    fi
    
    # Verifica delle configurazioni di logging critiche
    echo "### Critical Logging Settings" >> "$backup_file"
    grep -E "^handlers|^.handlers|^java.util.logging" "$LOGGING_PROPS" >> "$backup_file"
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_logging_configuration() {
    local result=0
    
    echo "Verifica configurazione logging..."
    
    # Verifica presenza configurazioni critiche
    if ! grep -qE "^[hH]andlers[[:space:]]*=" "$LOGGING_PROPS"; then
        echo -e "${YELLOW}[WARN] Configurazione handlers non trovata${NC}"
        result=1
    fi
    
    # Verifica presenza configurazioni di logging inappropriate
    if grep -qE "[cC]onsole[hH]andler" "$LOGGING_PROPS"; then
        echo -e "${YELLOW}[WARN] ConsoleHandler trovato - considerare la rimozione in produzione${NC}"
        result=1
    fi
    
    # Verifica livelli di logging
    if grep -q "\.level = FINE\|\.level = FINER\|\.level = FINEST" "$LOGGING_PROPS"; then
        echo -e "${YELLOW}[WARN] Trovati livelli di logging dettagliati - considerare di aumentare il livello in produzione${NC}"
        result=1
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi logging.properties..."
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$LOGGING_PROPS")
    local file_group=$(stat -c '%G' "$LOGGING_PROPS")
    local file_perms=$(stat -c '%a' "$LOGGING_PROPS")
    
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
    
    # Verifica directory padre
    local parent_dir=$(dirname "$LOGGING_PROPS")
    local parent_owner=$(stat -c '%U' "$parent_dir")
    local parent_group=$(stat -c '%G' "$parent_dir")
    local parent_perms=$(stat -c '%a' "$parent_dir")
    
    echo -e "\nControllo directory padre ($parent_dir):"
    
    if [ "$parent_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Proprietario directory padre non corretto: $parent_owner (dovrebbe essere $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Proprietario directory padre corretto: $parent_owner${NC}"
    fi
    
    if [ "$parent_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Gruppo directory padre non corretto: $parent_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Gruppo directory padre corretto: $parent_group${NC}"
    fi
    
    if [ "$parent_perms" != "750" ]; then
        echo -e "${YELLOW}[WARN] Permessi directory padre non corretti: $parent_perms (dovrebbero essere 750)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi directory padre corretti: $parent_perms${NC}"
    fi
    
    return $result
}

fix_permissions() {
    echo "Applicazione correzioni permessi..."
    
    # Crea backup prima di applicare le modifiche
    create_backup
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$LOGGING_PROPS"
    
    # Imposta permessi stretti
    chmod 600 "$LOGGING_PROPS"
    
    # Correggi permessi directory padre
    local parent_dir=$(dirname "$LOGGING_PROPS")
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$parent_dir"
    chmod 750 "$parent_dir"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.11 - Restrict access to Tomcat logging.properties"
    echo "--------------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    check_logging_configuration
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare manualmente la configurazione del logging per sicurezza${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main