#!/bin/bash

# Script per il controllo e fix del CIS Control 7.5
# Ensure pattern in context.xml is correct
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei pattern in context.xml:
#   Controllo configurazioni Resources
#   Verifica JarScanner settings
#   Controllo Manager settings
#   Identificazione pattern insicuri
# 
# Controlli specifici:
#   cachingAllowed e cacheMaxSize
#   scanManifest, scanAllFiles e scanAllDirectories
#   pathname e antiResourceLocking
#   allowLinking e crossContext
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Applicazione pattern raccomandati
#   Verifica sintassi XML
#   Correzione di tutte le applicazioni web

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
WEBAPPS_DIR="$TOMCAT_HOME/webapps"

# Pattern raccomandato per CachingAllowed e CacheMaxSize
RECOMMENDED_PATTERN='
    <Resources cachingAllowed="false" cacheMaxSize="0" />
    <JarScanner scanManifest="false" scanAllFiles="true" scanAllDirectories="true" />
    <Manager pathname="" antiResourceLocking="false" />'

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
    local backup_dir="/tmp/tomcat_context_backup_$(date +%Y%m%d_%H%M%S)_CIS_7.5"
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

check_context_pattern() {
    local file="$1"
    local result=0
    
    echo "Controllo pattern in $file..."
    
    # Verifica Resources tag
    if ! grep -q "<Resources.*cachingAllowed=\"false\".*cacheMaxSize=\"0\"" "$file"; then
        echo -e "${YELLOW}[WARN] Configurazione Resources non corretta o mancante${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Configurazione Resources corretta${NC}"
    fi
    
    # Verifica JarScanner tag
    if ! grep -q "<JarScanner.*scanManifest=\"false\".*scanAllFiles=\"true\".*scanAllDirectories=\"true\"" "$file"; then
        echo -e "${YELLOW}[WARN] Configurazione JarScanner non corretta o mancante${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Configurazione JarScanner corretta${NC}"
    fi
    
    # Verifica Manager tag
    if ! grep -q "<Manager.*pathname=\"\".*antiResourceLocking=\"false\"" "$file"; then
        echo -e "${YELLOW}[WARN] Configurazione Manager non corretta o mancante${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Configurazione Manager corretta${NC}"
    fi
    
    # Verifica altri pattern di sicurezza
    if grep -q "allowLinking=\"true\"" "$file"; then
        echo -e "${YELLOW}[WARN] allowLinking è impostato a true - potenziale rischio di sicurezza${NC}"
        result=1
    fi
    
    if grep -q "crossContext=\"true\"" "$file"; then
        echo -e "${YELLOW}[WARN] crossContext è impostato a true - potenziale rischio di sicurezza${NC}"
        result=1
    fi
    
    return $result
}

fix_context_pattern() {
    local file="$1"
    
    echo "Correzione pattern in $file..."
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Leggi il file e mantieni la struttura esistente
    while IFS= read -r line; do
        if [[ $line =~ \</Context\> ]]; then
            # Aggiungi le configurazioni raccomandate prima della chiusura del tag Context
            echo "$RECOMMENDED_PATTERN" >> "$temp_file"
            echo "$line" >> "$temp_file"
        elif [[ $line =~ \<Resources || $line =~ \<JarScanner || $line =~ \<Manager ]]; then
            # Salta le configurazioni esistenti che verranno sostituite
            continue
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$file"
    
    # Sostituisci il file originale
    mv "$temp_file" "$file"
    
    # Imposta permessi corretti
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$file"
    chmod 600 "$file"
    
    echo -e "${GREEN}[OK] Pattern corretto applicato${NC}"
}

check_webapp_contexts() {
    local result=0
    
    echo "Controllo context.xml nelle applicazioni web..."
    
    # Cerca tutti i context.xml nelle applicazioni web
    find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
        echo -e "\nControllo $ctx_file..."
        check_context_pattern "$ctx_file"
        result=$((result + $?))
    done
    
    return $result
}

fix_webapp_contexts() {
    echo "Correzione context.xml nelle applicazioni web..."
    
    # Correggi tutti i context.xml nelle applicazioni web
    find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
        echo -e "\nCorrezione $ctx_file..."
        create_backup "$ctx_file"
        fix_context_pattern "$ctx_file"
    done
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
    echo "Controllo CIS 7.5 - Ensure pattern in context.xml is correct"
    echo "-------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_context_pattern "$CONTEXT_XML"
    needs_fix=$?
    
    check_webapp_contexts
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup "$CONTEXT_XML"
            fix_context_pattern "$CONTEXT_XML"
            fix_webapp_contexts
            
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