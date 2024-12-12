#!/bin/bash

# Script per il controllo e fix del CIS Control 10.2
# Restrict access to the web administration application
#
# Lo script implementa le seguenti funzionalità:
# Verifica delle applicazioni manager:
#   Presenza delle applicazioni manager e host-manager
#   Permessi delle directory
#   Configurazioni di sicurezza
# 
# Controlli di sicurezza:
#   RemoteAddrValve per limitare gli accessi
#   Ruoli e utenti in tomcat-users.xml
#   Permessi dei file di configurazione
# 
# Due opzioni di correzione:
#   Configurazione sicura mantenendo le applicazioni
#   Rimozione completa delle applicazioni manager

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
MANAGER_DIR="$TOMCAT_HOME/webapps/manager"
HOST_MANAGER_DIR="$TOMCAT_HOME/webapps/host-manager"
TOMCAT_USERS_XML="$TOMCAT_HOME/conf/tomcat-users.xml"
MANAGER_CONTEXT="$TOMCAT_HOME/conf/Catalina/localhost/manager.xml"
HOST_MANAGER_CONTEXT="$TOMCAT_HOME/conf/Catalina/localhost/host-manager.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configurazione per il context.xml
CONTEXT_CONFIG='<?xml version="1.0" encoding="UTF-8"?>
<Context antiResourceLocking="false" privileged="false">
    <Valve className="org.apache.catalina.valves.RemoteAddrValve"
           allow="127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />
    <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>'

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_manager_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.2"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup per $file..."
    
    mkdir -p "$backup_dir"
    
    if [ -f "$file" ]; then
        cp -p "$file" "$backup_dir/"
        echo "# Backup of $file - $(date)" >> "$backup_file"
        ls -l "$file" >> "$backup_file"
        
        if command -v sha256sum &> /dev/null; then
            sha256sum "$file" > "${backup_dir}/$(basename "$file").sha256"
        fi
    fi
    
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_manager_installation() {
    local result=0
    
    echo "Controllo installazione applicazioni manager..."
    
    # Verifica presenza delle applicazioni manager
    if [ -d "$MANAGER_DIR" ]; then
        echo -e "${YELLOW}[WARN] Applicazione manager presente${NC}"
        
        # Verifica permessi
        local perms=$(stat -c '%a' "$MANAGER_DIR")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Permessi directory manager non corretti: $perms${NC}"
            result=1
        fi
    fi
    
    if [ -d "$HOST_MANAGER_DIR" ]; then
        echo -e "${YELLOW}[WARN] Applicazione host-manager presente${NC}"
        
        # Verifica permessi
        local perms=$(stat -c '%a' "$HOST_MANAGER_DIR")
        if [ "$perms" != "750" ]; then
            echo -e "${YELLOW}[WARN] Permessi directory host-manager non corretti: $perms${NC}"
            result=1
        fi
    fi
    
    return $result
}

check_manager_security() {
    local result=0
    
    echo "Controllo configurazioni di sicurezza manager..."
    
    # Verifica configurazioni RemoteAddrValve
    for context_file in "$MANAGER_CONTEXT" "$HOST_MANAGER_CONTEXT"; do
        if [ -f "$context_file" ]; then
            if ! grep -q "RemoteAddrValve" "$context_file"; then
                echo -e "${YELLOW}[WARN] RemoteAddrValve non configurato in $context_file${NC}"
                result=1
            elif ! grep -q "allow=\"127\\." "$context_file"; then
                echo -e "${YELLOW}[WARN] RemoteAddrValve potrebbe non essere configurato correttamente${NC}"
                result=1
            fi
        else
            echo -e "${YELLOW}[WARN] File context non trovato: $context_file${NC}"
            result=1
        fi
    done
    
    # Verifica ruoli e utenti
    if [ -f "$TOMCAT_USERS_XML" ]; then
        if grep -qi "role=\"manager-gui\"" "$TOMCAT_USERS_XML"; then
            echo -e "${YELLOW}[WARN] Trovati utenti con ruolo manager-gui${NC}"
            result=1
        fi
        if grep -qi "role=\"admin-gui\"" "$TOMCAT_USERS_XML"; then
            echo -e "${YELLOW}[WARN] Trovati utenti con ruolo admin-gui${NC}"
            result=1
        fi
    fi
    
    return $result
}

fix_manager_security() {
    echo "Applicazione configurazioni di sicurezza manager..."
    
    # Crea directory per i context file se non esiste
    mkdir -p "$(dirname "$MANAGER_CONTEXT")"
    mkdir -p "$(dirname "$HOST_MANAGER_CONTEXT")"
    
    # Configura context files
    for context_file in "$MANAGER_CONTEXT" "$HOST_MANAGER_CONTEXT"; do
        create_backup "$context_file"
        echo "$CONTEXT_CONFIG" > "$context_file"
        chown "$TOMCAT_USER:$TOMCAT_GROUP" "$context_file"
        chmod 600 "$context_file"
    done
    
    # Correggi permessi delle directory manager se esistono
    if [ -d "$MANAGER_DIR" ]; then
        chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$MANAGER_DIR"
        chmod -R 750 "$MANAGER_DIR"
    fi
    
    if [ -d "$HOST_MANAGER_DIR" ]; then
        chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$HOST_MANAGER_DIR"
        chmod -R 750 "$HOST_MANAGER_DIR"
    fi
    
    echo -e "${GREEN}[OK] Configurazioni di sicurezza applicate${NC}"
}

remove_manager_apps() {
    echo "Rimozione applicazioni manager..."
    
    # Rimuovi le applicazioni manager
    for dir in "$MANAGER_DIR" "$HOST_MANAGER_DIR"; do
        if [ -d "$dir" ]; then
            create_backup "$dir"
            rm -rf "$dir"
            echo -e "${GREEN}[OK] Rimossa directory: $dir${NC}"
        fi
    done
    
    # Rimuovi i file WAR se presenti
    for war in "$MANAGER_DIR.war" "$HOST_MANAGER_DIR.war"; do
        if [ -f "$war" ]; then
            create_backup "$war"
            rm -f "$war"
            echo -e "${GREEN}[OK] Rimosso file WAR: $war${NC}"
        fi
    done
}

main() {
    echo "Controllo CIS 10.2 - Restrict access to the web administration application"
    echo "----------------------------------------------------------------------"
    
    check_root
    
    local needs_fix=0
    
    check_manager_installation
    needs_fix=$((needs_fix + $?))
    
    check_manager_security
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Seleziona l'azione da eseguire:${NC}"
        echo "1) Applica configurazioni di sicurezza (mantieni manager)"
        echo "2) Rimuovi completamente le applicazioni manager"
        echo "3) Annulla"
        read -p "Scelta (1-3): " choice
        
        case $choice in
            1)
                fix_manager_security
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare l'accesso alle applicazioni manager${NC}"
                ;;
            2)
                remove_manager_apps
                echo -e "\n${GREEN}Rimozione completata.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per completare la rimozione${NC}"
                ;;
            *)
                echo -e "\n${YELLOW}Operazione annullata dall'utente${NC}"
                ;;
        esac
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main