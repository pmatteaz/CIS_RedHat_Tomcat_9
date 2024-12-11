#!/bin/bash

# Script per il controllo e fix del CIS Control 10.16
# Enable Memory Leak Listener
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione:
#   Controllo presenza del Memory Leak Listener
#   Verifica posizione ottimale nel server.xml
#   Controllo impostazioni JVM correlate
# 
# Funzionalità di correzione:
#   Configurazione del Memory Leak Listener
#   Impostazione logging GC
#   Configurazione JVM ottimale
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

# Configurazione del Memory Leak Listener
MEMORY_LEAK_LISTENER='<Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />'

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
    local backup_dir="/tmp/tomcat_memory_leak_backup_$(date +%Y%m%d_%H%M%S)"
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

check_memory_leak_configuration() {
    local result=0
    
    echo "Controllo configurazione Memory Leak Listener..."
    
    # Verifica presenza del Memory Leak Listener
    if ! grep -q "org.apache.catalina.core.JreMemoryLeakPreventionListener" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Memory Leak Listener non configurato${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Memory Leak Listener trovato${NC}"
        
        # Verifica posizione corretta (dovrebbe essere tra i primi listener)
        local listener_line=$(grep -n "JreMemoryLeakPreventionListener" "$SERVER_XML" | cut -d: -f1)
        local server_line=$(grep -n "<Server" "$SERVER_XML" | cut -d: -f1)
        
        if [ $((listener_line - server_line)) -gt 10 ]; then
            echo -e "${YELLOW}[WARN] Memory Leak Listener potrebbe non essere nella posizione ottimale${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Memory Leak Listener in posizione corretta${NC}"
        fi
    fi
    
    return $result
}

check_jvm_settings() {
    local result=0
    
    echo "Controllo impostazioni JVM correlate..."
    
    # Verifica CATALINA_OPTS per impostazioni di memoria correlate
    if [ -f "$TOMCAT_HOME/bin/setenv.sh" ]; then
        if ! grep -q "gc.log" "$TOMCAT_HOME/bin/setenv.sh"; then
            echo -e "${YELLOW}[WARN] GC logging non configurato${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] GC logging configurato${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN] setenv.sh non trovato, impossibile verificare le impostazioni JVM${NC}"
        result=1
    fi
    
    return $result
}

fix_memory_leak_listener() {
    echo "Configurazione Memory Leak Listener..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # Rimuovi eventuali configurazioni esistenti del Memory Leak Listener
    sed -i '/<Listener.*JreMemoryLeakPreventionListener.*\/>/d' "$SERVER_XML"
    
    # Aggiungi il nuovo Memory Leak Listener dopo il tag Server
    sed -i "/<Server/a\\    $MEMORY_LEAK_LISTENER" "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Memory Leak Listener configurato${NC}"
    
    # Verifica la configurazione
    if grep -q "org.apache.catalina.core.JreMemoryLeakPreventionListener" "$SERVER_XML"; then
        echo -e "${GREEN}[OK] Verifica configurazione completata${NC}"
    else
        echo -e "${RED}[ERROR] Errore nella configurazione del Memory Leak Listener${NC}"
    fi
}

configure_jvm_settings() {
    echo "Configurazione impostazioni JVM..."
    
    local setenv_file="$TOMCAT_HOME/bin/setenv.sh"
    
    # Crea o aggiorna setenv.sh
    if [ ! -f "$setenv_file" ]; then
        echo "#!/bin/bash" > "$setenv_file"
    fi
    
    # Aggiungi configurazioni GC logging se non presenti
    if ! grep -q "gc.log" "$setenv_file"; then
        echo 'CATALINA_OPTS="$CATALINA_OPTS -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:$CATALINA_BASE/logs/gc.log"' >> "$setenv_file"
    fi
    
    chmod +x "$setenv_file"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$setenv_file"
    
    echo -e "${GREEN}[OK] Impostazioni JVM configurate${NC}"
}

main() {
    echo "Controllo CIS 10.16 - Enable Memory Leak Listener"
    echo "-----------------------------------------------"
    
    check_root
    check_tomcat_user
    check_file_exists
    
    local needs_fix=0
    
    check_memory_leak_configuration
    needs_fix=$?
    
    check_jvm_settings
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_memory_leak_listener
            configure_jvm_settings
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Monitorare i log GC per verificare il corretto funzionamento${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main