#!/bin/bash

# Script per il controllo e fix del CIS Control 5.2
# Use LockOut Realms
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione LockOut Realm:
#   Controllo presenza LockOutRealm
#   Verifica parametri di sicurezza
#   Controllo UserDatabaseRealm nidificato
# 
# Controlli specifici per:
#   failureCount (numero tentativi falliti)
#   lockOutTime (durata del blocco)
#   cacheSize (dimensione cache)
#   permessi file correlati
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Implementazione LockOut Realm sicuro
#   Configurazione parametri raccomandati
#   Verifica sintassi XML


# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Configurazione raccomandata per LockOut Realm
LOCKOUT_REALM_CONFIG='
    <Realm className="org.apache.catalina.realm.LockOutRealm" 
           failureCount="3"
           lockOutTime="600"
           cacheSize="1000"
           cacheRemovalWarningTime="3600">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
    </Realm>'

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

check_file_exists() {
    if [ ! -f "$SERVER_XML" ]; then
        echo -e "${RED}[ERROR] File server.xml non trovato: $SERVER_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_lockout_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    mkdir -p "$backup_dir"
    
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    ls -l "$SERVER_XML" >> "$backup_file"
    
    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml.acl"
    fi
    
    cp -p "$SERVER_XML" "$backup_dir/"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi
    
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_lockout_realm() {
    local result=0
    
    echo "Controllo configurazione LockOut Realm..."
    
    # Verifica presenza LockOutRealm
    if ! grep -q "org.apache.catalina.realm.LockOutRealm" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] LockOut Realm non configurato${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] LockOut Realm trovato${NC}"
        
        # Verifica parametri di configurazione
        if ! grep -q "failureCount=\"[1-5]\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] failureCount non configurato correttamente${NC}"
            result=1
        fi
        
        if ! grep -q "lockOutTime=\"[0-9][0-9][0-9]\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] lockOutTime non configurato correttamente${NC}"
            result=1
        fi
        
        if ! grep -q "cacheSize=\"[0-9][0-9][0-9]\"" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] cacheSize non configurato${NC}"
            result=1
        fi
    fi
    
    # Verifica realm nidificato
    if ! grep -q "UserDatabaseRealm.*resourceName=\"UserDatabase\"" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] UserDatabaseRealm non configurato correttamente${NC}"
        result=1
    fi
    
    return $result
}

fix_lockout_realm() {
    echo "Applicazione configurazione LockOut Realm..."
    
    local temp_file=$(mktemp)
    local found_engine=0
    
    while IFS= read -r line; do
        echo "$line" >> "$temp_file"
        
        # Cerca il tag Engine
        if [[ $line =~ \<Engine.*\> ]]; then
            found_engine=1
            # Aggiungi LockOutRealm dopo Engine
            echo "$LOCKOUT_REALM_CONFIG" >> "$temp_file"
        fi
        
        # Se trova un Realm esistente dopo Engine, lo salta
        if [ $found_engine -eq 1 ] && [[ $line =~ \<Realm ]]; then
            # Leggi e scarta le linee fino alla chiusura del Realm
            while IFS= read -r realm_line; do
                if [[ $realm_line =~ \</Realm\> ]]; then
                    break
                fi
            done
        fi
    done < "$SERVER_XML"
    
    # Verifica che sia stato trovato il tag Engine
    if [ $found_engine -eq 0 ]; then
        echo -e "${RED}[ERROR] Tag Engine non trovato in server.xml${NC}"
        rm "$temp_file"
        return 1
    fi
    
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] LockOut Realm configurato${NC}"
}

verify_xml_syntax() {
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$SERVER_XML" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore di sintassi XML in server.xml${NC}"
            return 1
        fi
        echo -e "${GREEN}[OK] Sintassi XML corretta${NC}"
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    return 0
}

verify_user_database() {
    # Verifica tomcat-users.xml
    local users_xml="$TOMCAT_HOME/conf/tomcat-users.xml"
    if [ ! -f "$users_xml" ]; then
        echo -e "${YELLOW}[WARN] tomcat-users.xml non trovato${NC}"
        return 1
    fi
    
    # Verifica permessi
    local perms=$(stat -c '%a' "$users_xml")
    if [ "$perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi non corretti per tomcat-users.xml: $perms${NC}"
        chmod 600 "$users_xml"
    fi
    
    return 0
}

main() {
    echo "Controllo CIS 5.2 - Use LockOut Realms"
    echo "----------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_lockout_realm
    needs_fix=$?
    
    verify_user_database
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_lockout_realm
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento dell'autenticazione${NC}"
                echo -e "${YELLOW}NOTA: Monitorare i log per tentativi di accesso falliti${NC}"
            else
                echo -e "\n${RED}[ERROR] Errore durante l'applicazione delle modifiche${NC}"
                echo -e "${YELLOW}NOTA: Ripristinare il backup e verificare manualmente la configurazione${NC}"
            fi
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main