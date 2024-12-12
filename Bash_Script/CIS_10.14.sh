#!/bin/bash

# Script per il controllo e fix del CIS Control 10.14
# Do not allow cross context requests
#
# Lo script implementa le seguenti funzionalità:
# Verifica delle configurazioni cross context:
#   Context.xml globale
#   Context.xml delle singole applicazioni
#   Web.xml delle applicazioni
#   Parametri correlati alla sicurezza
# 
# Controlli per:
#   Attributo crossContext
#   Configurazioni nei context-param
#   Permessi dei file
#   Vulnerabilità correlate
# 
# Funzionalità di correzione:
#   Disabilita il cross context globalmente
#   Rimuove configurazioni pericolose
#   Imposta permessi sicuri
#   Backup di tutti i file modificati

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CONTEXT_XML="$TOMCAT_HOME/conf/context.xml"
WEBAPPS_DIR="$TOMCAT_HOME/webapps"

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

check_files_exist() {
    if [ ! -f "$CONTEXT_XML" ]; then
        echo -e "${RED}[ERROR] File context.xml non trovato: $CONTEXT_XML${NC}"
        exit 1
    fi
    
    if [ ! -d "$WEBAPPS_DIR" ]; then
        echo -e "${RED}[ERROR] Directory webapps non trovata: $WEBAPPS_DIR${NC}"
        exit 1
    fi
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_crosscontext_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.14"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    # Crea directory di backup
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup for $file" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
    echo >> "$backup_file"
    
    # Backup dei permessi attuali
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

check_cross_context() {
    local result=0
    
    echo "Controllo configurazioni cross context..."
    
    # Controlla context.xml globale
    echo "Controllo $CONTEXT_XML..."
    if grep -q "crossContext=\"true\"" "$CONTEXT_XML"; then
        echo -e "${YELLOW}[WARN] Cross context abilitato globalmente in context.xml${NC}"
        result=1
    else
        echo -e "${GREEN}[OK] Cross context non abilitato globalmente${NC}"
    fi
    
    # Controlla context.xml delle applicazioni
    echo -e "\nControllo context.xml delle applicazioni..."
    find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
        if grep -q "crossContext=\"true\"" "$ctx_file"; then
            echo -e "${YELLOW}[WARN] Cross context abilitato in: $ctx_file${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Cross context non abilitato in: $ctx_file${NC}"
        fi
    done
    
    # Controlla web.xml delle applicazioni per potenziali vulnerabilità correlate
    echo -e "\nControllo configurazioni web.xml..."
    find "$WEBAPPS_DIR" -name "web.xml" -type f | while read -r web_xml; do
        # Cerca configurazioni potenzialmente pericolose
        if grep -q "<param-name>crossContext</param-name>" "$web_xml"; then
            echo -e "${YELLOW}[WARN] Trovata configurazione cross context in: $web_xml${NC}"
            result=1
        fi
    done
    
    return $result
}

fix_cross_context() {
    echo "Correzione configurazioni cross context..."
    
    # Fix context.xml globale
    create_backup "$CONTEXT_XML"
    if grep -q "crossContext=\"true\"" "$CONTEXT_XML"; then
        sed -i 's/crossContext="true"/crossContext="false"/' "$CONTEXT_XML"
        echo -e "${GREEN}[OK] Disabilitato cross context in context.xml globale${NC}"
    fi
    
    # Fix context.xml delle applicazioni
    find "$WEBAPPS_DIR" -name "context.xml" -type f | while read -r ctx_file; do
        create_backup "$ctx_file"
        if grep -q "crossContext=\"true\"" "$ctx_file"; then
            sed -i 's/crossContext="true"/crossContext="false"/' "$ctx_file"
            echo -e "${GREEN}[OK] Disabilitato cross context in: $ctx_file${NC}"
        fi
    done
    
    # Fix web.xml delle applicazioni
    find "$WEBAPPS_DIR" -name "web.xml" -type f | while read -r web_xml; do
        if grep -q "<param-name>crossContext</param-name>" "$web_xml"; then
            create_backup "$web_xml"
            # Rimuovi l'intera configurazione del parametro crossContext
            sed -i '/<param-name>crossContext<\/param-name>/,/<\/context-param>/d' "$web_xml"
            echo -e "${GREEN}[OK] Rimossa configurazione cross context da: $web_xml${NC}"
        fi
    done
    
    # Imposta i permessi corretti
    find "$WEBAPPS_DIR" -name "context.xml" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$WEBAPPS_DIR" -name "context.xml" -type f -exec chmod 600 {} \;
    find "$WEBAPPS_DIR" -name "web.xml" -type f -exec chown "$TOMCAT_USER:$TOMCAT_GROUP" {} \;
    find "$WEBAPPS_DIR" -name "web.xml" -type f -exec chmod 600 {} \;
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CONTEXT_XML"
    chmod 600 "$CONTEXT_XML"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
}

main() {
    echo "Controllo CIS 10.14 - Do not allow cross context requests"
    echo "-----------------------------------------------------"
    
    check_root
    check_files_exist
    
    local needs_fix=0
    
    check_cross_context
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_cross_context
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare che le applicazioni funzionino correttamente${NC}"
            echo -e "${YELLOW}NOTA: Potrebbe essere necessario aggiornare le applicazioni che richiedono cross context${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main