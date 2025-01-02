#!/bin/bash

# Script per il controllo e fix del CIS Control 4.15
# Restrict access to jaspic-providers.xml
#
# Lo script implementa le seguenti funzionalità per il controllo CIS 4.15:
# Verifica dei permessi:
#   Controlla che il proprietario sia l'utente tomcat
#   Controlla che il gruppo sia tomcat
#   Verifica che i permessi siano impostati a 600
# 
# Funzionalità di backup:
#   Crea un backup con timestamp
#   Salva i permessi attuali
#   Genera hash SHA-256 del file
#   Crea un archivio compresso del backup
# 
# Correzione:
#   Imposta il proprietario corretto (tomcat)
#   Imposta il gruppo corretto (tomcat)
#   Imposta i permessi a 600
# 
# Verifica:
#   Controlla che le modifiche siano state applicate correttamente
#   Fornisce feedback sullo stato delle operazioni

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
JASPIC_PROVIDERS_XML="$TOMCAT_HOME/conf/jaspic-providers.xml"

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

create_backup() {
    local backup_dir="/tmp/tomcat_jaspic_backup_$(date +%Y%m%d_%H%M%S)_CIS_4.15"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for jaspic-providers.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $JASPIC_PROVIDERS_XML" >> "$backup_file"
    ls -l "$JASPIC_PROVIDERS_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$JASPIC_PROVIDERS_XML" > "${backup_dir}/jaspic_providers.acl"
    fi
    
    # Copia fisica del file
    cp -p "$JASPIC_PROVIDERS_XML" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$JASPIC_PROVIDERS_XML" > "${backup_dir}/jaspic-providers.xml.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_permissions() {
    local result=0
    echo "Controllo permessi di jaspic-providers.xml..."
    
    # Controlla proprietario e gruppo
    local file_owner=$(stat -c '%U' "$JASPIC_PROVIDERS_XML")
    local file_group=$(stat -c '%G' "$JASPIC_PROVIDERS_XML")
    local file_perms=$(stat -c '%a' "$JASPIC_PROVIDERS_XML")
    
    if [ "$file_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Proprietario file non corretto: $file_owner (dovrebbe essere $TOMCAT_USER)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Proprietario file corretto${NC}"
    fi
    
    if [ "$file_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Gruppo file non corretto: $file_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Gruppo file corretto${NC}"
    fi
    
    if [ "$file_perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 600)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi file corretti${NC}"
    fi
    
    return $result
}

fix_permissions() {
    echo "Applicazione permessi corretti..."
    
    # Backup prima delle modifiche
    create_backup
    
    # Imposta proprietario e gruppo
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$JASPIC_PROVIDERS_XML"
    
    # Imposta permessi corretti
    chmod 600 "$JASPIC_PROVIDERS_XML"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
}

verify_permissions() {
    if check_permissions; then
        echo -e "${GREEN}[OK] Verifica permessi completata con successo${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Verifica permessi fallita${NC}"
        return 1
    fi
}

main() {
    echo "Controllo CIS 4.15 - Restrict access to jaspic-providers.xml"
    echo "--------------------------------------------------------"
    
    check_root
        
    local needs_fix=0
    check_permissions
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_permissions
            if verify_permissions; then
                echo -e "\n${GREEN}Fix completato con successo.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            else
                echo -e "\n${RED}[ERROR] Fix non completato correttamente${NC}"
                echo -e "${YELLOW}Si consiglia di ripristinare il backup e verificare manualmente${NC}"
            fi
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main