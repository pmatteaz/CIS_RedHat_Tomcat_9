#!/bin/bash

# Script per il controllo e fix del CIS Control 7.3
# Ensure className is set correctly in context.xml
#
# Lo script implementa le seguenti funzionalità:
# Verifica delle className in context.xml:
#   Controllo delle classi consentite e sicure
#   Verifica attributi obbligatori per ogni classe
#   Controllo di classi potenzialmente non sicure
# 
# Controlli specifici per:
#   JNDIRealm
#   DataSourceRealm
#   AccessLogValve
#   Altri componenti sicuri di Tomcat
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Applicazione configurazioni sicure
#   Verifica della sintassi XML
#   Correzione di tutti i context.xml delle applicazioni

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
WEBAPPS_DIR="$TOMCAT_HOME/webapps"

# Lista delle className accettate e sicure
declare -A ALLOWED_CLASSNAMES=(
    ["org.apache.catalina.realm.JNDIRealm"]="Realm"
    ["org.apache.catalina.realm.UserDatabaseRealm"]="Realm"
    ["org.apache.catalina.realm.DataSourceRealm"]="Realm"
    ["org.apache.catalina.valves.AccessLogValve"]="Valve"
    ["org.apache.catalina.valves.RemoteAddrValve"]="Valve"
    ["org.apache.catalina.valves.RemoteHostValve"]="Valve"
    ["org.apache.catalina.authenticator.BasicAuthenticator"]="Authenticator"
    ["org.apache.catalina.authenticator.DigestAuthenticator"]="Authenticator"
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

check_file_exists() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] File context.xml non trovato: $CONTEXT_XML${NC}"
        exit 1
    fi
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_context_backup_$(date +%Y%m%d_%H%M%S)_CIS_7.3"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for $file" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $file" >> "$backup_file"
    ls -l "$file" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$file" > "${backup_dir}/$(basename "$file").acl"
    fi
    
    # Copia fisica del file
    cp -p "$file" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" > "${backup_dir}/$(basename "$file").sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_classnames() {
    local file="$1"
    local result=0
    
    echo "Controllo className in $file..."
    
    # Estrai tutte le definizioni di className
    while IFS= read -r line; do
        if [[ $line =~ className=\"([^\"]+)\" ]]; then
            local class="${BASH_REMATCH[1]}"
            local found=0
            
            echo -e "\nAnalisi className: $class"
            
            # Verifica se la classe è nella lista consentita
            for allowed_class in "${!ALLOWED_CLASSNAMES[@]}"; do
                if [ "$class" == "$allowed_class" ]; then
                    found=1
                    echo -e "${GREEN}[OK] className valido: $class (${ALLOWED_CLASSNAMES[$allowed_class]})${NC}"
                    break
                fi
            done
            
            if [ $found -eq 0 ]; then
                echo -e "${YELLOW}[WARN] className non riconosciuto o potenzialmente non sicuro: $class${NC}"
                result=1
            fi
            
            # Controlli aggiuntivi di sicurezza per classi specifiche
            case "$class" in
                *"JNDIRealm")
                    if ! grep -q "userPassword" <<< "$line"; then
                        echo -e "${YELLOW}[WARN] JNDIRealm dovrebbe specificare l'attributo userPassword${NC}"
                        result=1
                    fi
                    ;;
                *"DataSourceRealm")
                    if ! grep -q "dataSourceName" <<< "$line"; then
                        echo -e "${YELLOW}[WARN] DataSourceRealm dovrebbe specificare l'attributo dataSourceName${NC}"
                        result=1
                    fi
                    ;;
                *"AccessLogValve")
                    if ! grep -q "pattern=" <<< "$line"; then
                        echo -e "${YELLOW}[WARN] AccessLogValve dovrebbe specificare un pattern di logging${NC}"
                        result=1
                    fi
                    ;;
            esac
        fi
    done < "$file"
    
    return $result
}

fix_classnames() {
    local file="$1"
    local temp_file=$(mktemp)
    
    echo "Correzione className in $file..."
    
    # Mantieni la struttura base del file
    while IFS= read -r line; do
        if [[ $line =~ className=\"([^\"]+)\" ]]; then
            local class="${BASH_REMATCH[1]}"
            local found=0
            
            # Cerca la classe nella lista consentita e applica la configurazione corretta
            for allowed_class in "${!ALLOWED_CLASSNAMES[@]}"; do
                if [[ "$class" == *"$allowed_class"* ]]; then
                    case "$allowed_class" in
                        *"JNDIRealm")
                            line=$(echo "$line" | sed 's/>/userPassword="userPassword" \/>/')
                            ;;
                        *"DataSourceRealm")
                            line=$(echo "$line" | sed 's/>/dataSourceName="jdbc\/UserDB" \/>/')
                            ;;
                        *"AccessLogValve")
                            line=$(echo "$line" | sed 's/>/pattern="%h %l %u %t &quot;%r&quot; %s %b" \/>/')
                            ;;
                    esac
                    found=1
                    break
                fi
            done
            
            if [ $found -eq 0 ]; then
                # Sostituisci con una configurazione sicura di default
                line='<Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase" />'
                echo -e "${YELLOW}[INFO] Sostituita className non sicura con configurazione di default${NC}"
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$file"
    
    # Sostituisci il file originale
    mv "$temp_file" "$file"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    chmod 600 "$file"
    
    echo -e "${GREEN}[OK] Configurazioni className corrette applicate${NC}"
}

verify_xml_syntax() {
    local file="$1"
    
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$file" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore di sintassi XML in $file${NC}"
            return 1
        fi
        echo -e "${GREEN}[OK] Sintassi XML corretta in $file${NC}"
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, skip verifica sintassi XML${NC}"
    fi
    
    return 0
}

main() {
    echo "Controllo CIS 7.3 - Ensure className is set correctly in context.xml"
    echo "---------------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    # Controlla context.xml principale
    check_classnames "$CONTEXT_XML"
    needs_fix=$?
    
    # Controlla context.xml delle applicazioni web
    find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
        check_classnames "$ctx_file"
        needs_fix=$((needs_fix + $?))
    done
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            # Fix context.xml principale
            create_backup "$CONTEXT_XML"
            fix_classnames "$CONTEXT_XML"
            
            # Fix context.xml delle applicazioni web
            find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
                create_backup "$ctx_file"
                fix_classnames "$ctx_file"
            done
            
            if verify_xml_syntax "$CONTEXT_XML"; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle applicazioni${NC}"
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