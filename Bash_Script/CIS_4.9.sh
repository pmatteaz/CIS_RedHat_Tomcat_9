#!/bin/bash

# Script per il controllo e fix del CIS Control 4.9
# Restrict access to Tomcat catalina.policy
#
# Lo script implementa le seguenti funzionalità:
# Verifica dettagliata delle autorizzazioni per:
#   File catalina.policy
#   Directory padre (conf)
#   Proprietà utente/gruppo
#   Permessi specifici
#   Immutabilità del file
# 
# Include una funzione di backup completa che:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Mantiene le ACL se disponibili
#   Calcola l'hash SHA-256 del file
#   Fa una copia fisica del file
# 
# Verifica della sintassi del file policy:
#   Usa policytool se disponibile
#   Controlla errori di sintassi
# 
# Controlli specifici per:
#   File catalina.policy: 600
#   Directory padre: 750
#   Proprietà: tomcat:tomcat
#   Attributo immutabile

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CATALINA_POLICY="$TOMCAT_HOME/conf/catalina.policy"

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
    if [ ! -f "$CATALINA_POLICY" ]; then
        echo -e "${RED}[ERROR] File catalina.policy non trovato: $CATALINA_POLICY${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_catalinapolicy_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/permissions_backup.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for catalina.policy" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
    ls -l "$CATALINA_POLICY" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$CATALINA_POLICY" > "${backup_dir}/catalina_policy_acl.txt"
    fi
    
    # Copia fisica del file
    cp -p "$CATALINA_POLICY" "${backup_dir}/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$CATALINA_POLICY" > "${backup_dir}/catalina.policy.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_policy_syntax() {
    local result=0
    
    echo "Verifica sintassi policy file..."
    
    if command -v $JAVA_HOME/bin/policytool &> /dev/null; then
        # Verifica sintattica usando policytool (se disponibile)
        if ! $JAVA_HOME/bin/policytool -import "$CATALINA_POLICY" &> /dev/null; then
            echo -e "${YELLOW}[WARN] Il file policy potrebbe contenere errori di sintassi${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Sintassi file policy verificata${NC}"
        fi
    else
        echo -e "${YELLOW}[INFO] policytool non disponibile, skip verifica sintassi${NC}"
    fi
    
    return $result
}

check_permissions() {
    local result=0
    
    echo "Controllo permessi catalina.policy..."
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$CATALINA_POLICY")
    local file_group=$(stat -c '%G' "$CATALINA_POLICY")
    local file_perms=$(stat -c '%a' "$CATALINA_POLICY")
    
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
    
    # Verifica directory padre
    local parent_dir=$(dirname "$CATALINA_POLICY")
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
    
    # Verifica immutabilità del file
    if command -v lsattr &> /dev/null; then
        local immutable=$(lsattr "$CATALINA_POLICY" 2>/dev/null | cut -c5)
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
        chattr -i "$CATALINA_POLICY" 2>/dev/null
    fi
    
    # Correggi proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_POLICY"
    
    # Imposta permessi stretti
    chmod 600 "$CATALINA_POLICY"
    
    # Correggi permessi directory padre
    local parent_dir=$(dirname "$CATALINA_POLICY")
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$parent_dir"
    chmod 750 "$parent_dir"
    
    # Imposta immutabilità
    if command -v chattr &> /dev/null; then
        chattr +i "$CATALINA_POLICY"
        echo -e "${GREEN}[OK] File impostato come immutabile${NC}"
    fi
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_permissions
}

main() {
    echo "Controllo CIS 4.9 - Restrict access to Tomcat catalina.policy"
    echo "-----------------------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_permissions
    needs_fix=$?
    
    check_policy_syntax
    needs_fix=$((needs_fix + $?))
    
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