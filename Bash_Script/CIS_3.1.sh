#!/bin/bash

# Script per il controllo e fix del CIS Control 3.1
# Set a nondeterministic Shutdown command value
#
# Lo script implementa le seguenti funzionalità:
# Verifica la configurazione del comando shutdown:
# 
# Controlla se è presente in server.xml
# Verifica che non sia il valore predefinito "SHUTDOWN"
# Verifica che la lunghezza sia sufficiente (minimo 20 caratteri)
# 
# Controlla i permessi del file server.xml
# Se necessario, offre l'opzione di fix automatico che:
# Genera un nuovo comando shutdown casuale e sicuro
# Aggiorna il comando in server.xml
# Salva il nuovo comando in un file separato protetto
# Corregge i permessi dei file (600)
# 
# 
# Crea backup dei file prima delle modifiche


TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Lunghezza minima per il comando di shutdown
MIN_LENGTH=20

check_tomcat_home() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] Directory Tomcat non trovata: $TOMCAT_HOME${NC}"
        exit 1
    fi
}

generate_random_string() {
    # Genera una stringa casuale di lunghezza specificata
    local length=$1
    tr -dc 'A-Za-z0-9_@#$%^&*()' < /dev/urandom | head -c "$length"
}

check_shutdown_command() {
    local result=0
    
    echo "Controllo configurazione comando shutdown..."
    
    # Estrae il valore corrente del comando shutdown
    local current_command=$(grep -oP '(?<=shutdown=")[^"]*' "$SERVER_XML")
    
    if [ -z "$current_command" ]; then
        echo -e "${YELLOW}[WARN] Comando shutdown non trovato in server.xml${NC}"
        result=1
    else
        # Verifica se il comando è quello predefinito "SHUTDOWN"
        if [ "$current_command" == "SHUTDOWN" ]; then
            echo -e "${YELLOW}[WARN] Comando shutdown è impostato al valore predefinito${NC}"
            result=1
        else
            # Verifica la lunghezza del comando
            if [ ${#current_command} -lt $MIN_LENGTH ]; then
                echo -e "${YELLOW}[WARN] Comando shutdown è troppo corto (${#current_command} caratteri)${NC}"
                result=1
            else
                echo -e "${GREEN}[OK] Comando shutdown è configurato correttamente${NC}"
                echo -e "${GREEN}[OK] Lunghezza attuale: ${#current_command} caratteri${NC}"
            fi
        fi
    fi
    
    return $result
}

check_file_permissions() {
    local result=0
    
    echo "Controllo permessi del file server.xml..."
    
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] File server.xml non trovato${NC}"
        return 1
    fi
    
    local perms=$(stat -c "%a" "$SERVER_XML")
    if [ "$perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi non corretti per server.xml: $perms (dovrebbe essere 600)${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Permessi corretti per server.xml${NC}"
    fi
    
    return $result
}

fix_shutdown_command() {
    # Backup del file
    cp "$SERVER_XML" "${SERVER_XML}.bak"
    
    # Genera un nuovo comando di shutdown
    local new_command=$(generate_random_string $((MIN_LENGTH + 10)))
    
    # Aggiorna il comando nel file server.xml
    if grep -q 'shutdown="SHUTDOWN"' "$SERVER_XML"; then
        sed -i "s/shutdown=\"SHUTDOWN\"/shutdown=\"$new_command\"/" "$SERVER_XML"
    else
        # Se il pattern esatto non viene trovato, cerca qualsiasi valore di shutdown
        sed -i "s/shutdown=\"[^\"]*\"/shutdown=\"$new_command\"/" "$SERVER_XML"
    fi
    
    echo -e "${GREEN}[OK] Comando shutdown aggiornato${NC}"
    echo -e "${YELLOW}[INFO] Nuovo comando shutdown: $new_command${NC}"
    echo -e "${YELLOW}[INFO] Salvare questo valore in un luogo sicuro${NC}"
    
    # Salva il nuovo comando in un file separato
    local secret_file="$TOMCAT_HOME/conf/.shutdown_command"
    echo "$new_command" > "$secret_file"
    chmod 600 "$secret_file"
    echo -e "${GREEN}[OK] Comando shutdown salvato in: $secret_file${NC}"
}

fix_file_permissions() {
    echo "Correzione permessi dei file..."
    
    chmod 600 "$SERVER_XML"
    echo -e "${GREEN}[OK] Permessi aggiornati per server.xml${NC}"
}

main() {
    echo "Controllo CIS 3.1 - Shutdown Command Configuration"
    echo "------------------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    
    check_shutdown_command
    needs_fix=$((needs_fix + $?))
    
    check_file_permissions
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_shutdown_command
            fix_file_permissions
            echo -e "\n${GREEN}Fix completato. Riavviare Tomcat per applicare le modifiche.${NC}"
            echo -e "${YELLOW}IMPORTANTE: Assicurarsi di salvare il nuovo comando shutdown in un luogo sicuro${NC}"
            echo -e "${YELLOW}           Il comando è stato salvato in: $TOMCAT_HOME/conf/.shutdown_command${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main