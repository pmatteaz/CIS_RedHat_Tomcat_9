#!/bin/bash

# Script per il controllo e fix del CIS Control 10.17
# Security Lifecycle Listener
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione di sicurezza:
#   Controllo presenza del SecurityListener
#   Verifica impostazione minimumUmask
#   Verifica checkedOsUsers
#   Controllo umask del sistema
# 
# Funzionalità di correzione:
#   Configurazione del SecurityListener in server.xml
#   Impostazione umask corretto (0007)
#   Configurazione automatica in setenv.sh
# 
# Sistema di backup:
#   Backup di server.xml prima delle modifiche
#   Backup con timestamp
#   Verifica dell'integrità tramite hash

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

# Configurazione del Security Lifecycle Listener
SECURITY_LISTENER='<Listener className="org.apache.catalina.security.SecurityListener" minimumUmask="0007" checkedOsUsers="tomcat" />'

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
    local backup_dir="/tmp/tomcat_security_listener_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.17"
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
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
    echo -e "${YELLOW}[INFO] Conservare questo backup per eventuale ripristino${NC}"
}

check_umask() {
    local current_umask=$(umask)
    if [ "$current_umask" != "0007" ]; then
        echo -e "${YELLOW}[WARN] umask corrente ($current_umask) non è 0007${NC}"
        return 1
    else
        echo -e "${GREEN}[OK] umask corrente è corretto (0007)${NC}"
        return 0
    fi
}

check_security_listener() {
    local result=0
    
    echo "Controllo Security Lifecycle Listener..."
    
    # Verifica presenza del SecurityListener
    if ! grep -q "org.apache.catalina.security.SecurityListener" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] SecurityListener non configurato${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] SecurityListener trovato${NC}"
        
        # Verifica minimumUmask
        if ! grep -q 'minimumUmask="0007"' "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] minimumUmask non configurato correttamente${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] minimumUmask configurato correttamente${NC}"
        fi
        
        # Verifica checkedOsUsers
        if ! grep -q "checkedOsUsers=\"$TOMCAT_USER\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] checkedOsUsers non configurato correttamente${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] checkedOsUsers configurato correttamente${NC}"
        fi
    fi
    
    return $result
}

fix_umask() {
    echo "Configurazione umask..."
    
    # Aggiungi configurazione umask ai file di avvio di Tomcat
    local setenv_file="$TOMCAT_HOME/bin/setenv.sh"
    
    if [ ! -f "$setenv_file" ]; then
        echo "#!/bin/bash" > "$setenv_file"
        echo "umask 0007" >> "$setenv_file"
        chmod +x "$setenv_file"
        echo -e "${GREEN}[OK] Creato $setenv_file con umask 0007${NC}"
    else
        if ! grep -q "umask 0007" "$setenv_file"; then
            echo "umask 0007" >> "$setenv_file"
            echo -e "${GREEN}[OK] Aggiunto umask 0007 a $setenv_file${NC}"
        fi
    fi
    
    # Imposta umask per la sessione corrente
    umask 0007
}

fix_security_listener() {
    echo "Configurazione Security Lifecycle Listener..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # Rimuovi eventuali configurazioni esistenti del SecurityListener
    sed -i '/<Listener.*SecurityListener.*\/>/d' "$SERVER_XML"
    
    # Aggiungi il nuovo SecurityListener dopo il tag Server
    sed -i "/<Server/a\\    $SECURITY_LISTENER" "$SERVER_XML"
    
    echo -e "${GREEN}[OK] SecurityListener configurato${NC}"
    
    # Verifica la configurazione
    if grep -q "org.apache.catalina.security.SecurityListener" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Verifica configurazione completata${NC}"
    else
        echo -e "${RED}[ERROR] Errore nella configurazione del SecurityListener${NC}"
    fi
}

main() {
    echo "Controllo CIS 10.17 - Security Lifecycle Listener"
    echo "-----------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_umask
    needs_fix=$((needs_fix + $?))
    
    check_security_listener
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_umask
            fix_security_listener
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare che il SecurityListener sia caricato correttamente nei log${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main