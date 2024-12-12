#!/bin/bash

# Script per il controllo e fix del CIS Control 10.18
# Use logEffectiveWebXml and metadata-complete settings for deploying applications in production
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione per ogni applicazione web:
#   Controllo metadata-complete in web.xml
#   Controllo logEffectiveWebXml in context.xml locale
#   Controllo logEffectiveWebXml in context.xml globale
# 
# Funzionalità di fix:
#   Imposta metadata-complete="true" in web.xml
#   Imposta logEffectiveWebXml="true" in context.xml locali
#   Configura il context.xml globale
#   Crea i file di configurazione se mancanti
# 
# Sistema di backup:
#   Backup di web.xml e context.xml prima delle modifiche
#   Backup con timestamp
#   Compressione dei backup

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
WEBAPPS_DIR="$TOMCAT_HOME/webapps"
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"

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

check_directories() {
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] Directory webapps non trovata: $WEBAPPS_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local app_dir="$1"
    local backup_dir="/tmp/tomcat_webapp_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.18"
    
    echo "Creazione backup della configurazione per $(basename "$app_dir")..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Backup web.xml e context.xml se esistono
    if [ -f "$app_dir/WEB-INF/web.xml" ]; then
        cp -p "$app_dir/WEB-INF/web.xml" "$backup_dir/"
    fi
    
    if [ -f "$app_dir/META-INF/context.xml" ]; then
        cp -p "$app_dir/META-INF/context.xml" "$backup_dir/"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_webapp_settings() {
    local app_dir="$1"
    local result=0
    
    echo -e "\nControllo configurazioni per $(basename "$app_dir")..."
    
    # Controlla web.xml
    local web_xml="$app_dir/WEB-INF/web.xml"
    if [ -f "$web_xml" ]; then
        echo "Controllo web.xml..."
        
        # Verifica metadata-complete
        if ! grep -q 'metadata-complete="true"' "$web_xml"; then
            echo -e "${YELLOW}[WARN] metadata-complete non impostato a true in web.xml${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] metadata-complete correttamente configurato${NC}"
        fi
    else
        echo -e "${YELLOW}[WARN] web.xml non trovato${NC}"
        result=1
    fi
    
    # Controlla context.xml locale
    local context_xml="$app_dir/META-INF/context.xml"
    if [ -f "$context_xml" ]; then
        echo "Controllo context.xml locale..."
        
        # Verifica logEffectiveWebXml
        if ! grep -q 'logEffectiveWebXml="true"' "$context_xml"; then
            echo -e "${YELLOW}[WARN] logEffectiveWebXml non impostato a true in context.xml${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] logEffectiveWebXml correttamente configurato${NC}"
        fi
    else
        echo -e "${YELLOW}[INFO] context.xml locale non trovato, controllare configurazione globale${NC}"
    fi
    
    return $result
}

fix_webapp_settings() {
    local app_dir="$1"
    
    # Crea backup prima delle modifiche
    create_backup "$app_dir"
    
    # Fix web.xml
    local web_xml="$app_dir/WEB-INF/web.xml"
    if [ -f "$web_xml" ]; then
        echo "Correzione web.xml..."
        
        # Aggiungi o aggiorna metadata-complete
        if grep -q "metadata-complete=" "$web_xml"; then
            sed -i 's/metadata-complete="[^"]*"/metadata-complete="true"/' "$web_xml"
        else
            sed -i '/<web-app/s/>/ metadata-complete="true">/' "$web_xml"
        fi
    fi
    
    # Fix context.xml locale
    local context_xml="$app_dir/META-INF/context.xml"
    if [ -f "$context_xml" ]; then
        echo "Correzione context.xml locale..."
        
        # Aggiungi o aggiorna logEffectiveWebXml
        if grep -q "logEffectiveWebXml=" "$context_xml"; then
            sed -i 's/logEffectiveWebXml="[^"]*"/logEffectiveWebXml="true"/' "$context_xml"
        else
            sed -i '/<Context/s/>/ logEffectiveWebXml="true">/' "$context_xml"
        fi
    else
        # Crea context.xml se non esiste
        mkdir -p "$app_dir/META-INF"
        echo '<?xml version="1.0" encoding="UTF-8"?>
<Context logEffectiveWebXml="true">
</Context>' > "$context_xml"
    fi
    
    echo -e "${GREEN}[OK] Configurazioni corrette applicate${NC}"
}

fix_global_context() {
    echo "Verifica configurazione globale context.xml..."
    
    # Backup del context.xml globale
    if [ -f "$CONTEXT_XML" ]; then
        cp -p "$CONTEXT_XML" "${CONTEXT_XML}.bak"
        
        # Aggiungi o aggiorna logEffectiveWebXml nel context.xml globale
        if grep -q "logEffectiveWebXml=" "$CONTEXT_XML"; then
            sed -i 's/logEffectiveWebXml="[^"]*"/logEffectiveWebXml="true"/' "$CONTEXT_XML"
        else
            sed -i '/<Context/s/>/ logEffectiveWebXml="true">/' "$CONTEXT_XML"
        fi
        
        echo -e "${GREEN}[OK] Configurazione globale aggiornata${NC}"
    else
        echo '<?xml version="1.0" encoding="UTF-8"?>
<Context logEffectiveWebXml="true">
</Context>' > "$CONTEXT_XML"
        echo -e "${GREEN}[OK] Creato nuovo context.xml globale${NC}"
    fi
}

main() {
    echo "Controllo CIS 10.18 - logEffectiveWebXml and metadata-complete settings"
    echo "-------------------------------------------------------------------"
    
    check_root
    check_directories
    
    local needs_fix=0
    
    # Controlla ogni applicazione web
    for app_dir in "$WEBAPPS_DIR"/*; do
        if [ -d "$app_dir" ]; then
            check_webapp_settings "$app_dir"
            needs_fix=$((needs_fix + $?))
        fi
    done
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            # Fix configurazione globale
            fix_global_context
            
            # Fix per ogni applicazione
            for app_dir in "$WEBAPPS_DIR"/*; do
                if [ -d "$app_dir" ]; then
                    fix_webapp_settings "$app_dir"
                fi
            done
            
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