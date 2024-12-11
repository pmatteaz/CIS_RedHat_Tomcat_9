#!/bin/bash

# Script per il controllo e fix del CIS Control 6.3
# Ensure scheme is set accurately
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei connettori:
#   Controllo scheme per connettori SSL e non-SSL
#   Verifica coerenza tra SSL e scheme
#   Controllo proxyPort per connettori HTTPS
# 
# Controlli specifici:
#   SSL abilitato richiede scheme="https"
#   Non-SSL richiede scheme="http"
#   Verifica configurazioni proxy correlate
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Correzione automatica degli scheme
#   Aggiunta proxyPort se necessario
#   Verifica sintassi XML

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
    local backup_dir="/tmp/tomcat_scheme_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $SERVER_XML" >> "$backup_file"
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

check_scheme_configuration() {
    local result=0
    
    echo "Controllo configurazione scheme dei connettori..."
    
    # Estrai e analizza ogni connettore
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            echo -e "\nAnalisi connettore:"
            echo "$line"
            
            local has_ssl=0
            local has_scheme=0
            local scheme_value=""
            
            # Controlla se il connettore ha SSL abilitato
            if [[ $line =~ SSLEnabled=\"true\" ]]; then
                has_ssl=1
            fi
            
            # Controlla se l'attributo scheme è presente e il suo valore
            if [[ $line =~ scheme=\"([^\"]+)\" ]]; then
                has_scheme=1
                scheme_value="${BASH_REMATCH[1]}"
            fi
            
            # Verifica la corretta configurazione
            if [ $has_ssl -eq 1 ]; then
                if [ $has_scheme -eq 0 ]; then
                    echo -e "${YELLOW}[WARN] Connettore SSL senza attributo scheme${NC}"
                    result=1
                elif [ "$scheme_value" != "https" ]; then
                    echo -e "${YELLOW}[WARN] Connettore SSL con scheme=\"$scheme_value\" (dovrebbe essere https)${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Connettore SSL con scheme corretto${NC}"
                fi
                
                # Verifica altre configurazioni SSL correlate
                if ! [[ $line =~ proxyPort=\"443\" ]]; then
                    echo -e "${YELLOW}[WARN] Connettore SSL senza proxyPort=\"443\"${NC}"
                fi
            else
                if [ $has_scheme -eq 1 ] && [ "$scheme_value" = "https" ]; then
                    echo -e "${YELLOW}[WARN] Connettore non-SSL con scheme=\"https\"${NC}"
                    result=1
                elif [ $has_scheme -eq 0 ] || [ "$scheme_value" != "http" ]; then
                    echo -e "${YELLOW}[WARN] Connettore non-SSL dovrebbe avere scheme=\"http\"${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Connettore non-SSL con scheme corretto${NC}"
                fi
            fi
        fi
    done < "$SERVER_XML"
    
    return $result
}

fix_scheme_configuration() {
    echo "Correzione configurazione scheme..."
    
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            if [[ $line =~ SSLEnabled=\"true\" ]]; then
                # Connettore SSL: imposta scheme="https"
                if [[ $line =~ scheme=\"[^\"]+\" ]]; then
                    line=$(echo "$line" | sed 's/scheme="[^"]*"/scheme="https"/')
                else
                    line=$(echo "$line" | sed 's/>/ scheme="https">/')
                fi
                
                # Aggiungi proxyPort se mancante
                if ! [[ $line =~ proxyPort=\"443\" ]]; then
                    line=$(echo "$line" | sed 's/>/ proxyPort="443">/')
                fi
            else
                # Connettore non-SSL: imposta scheme="http"
                if [[ $line =~ scheme=\"[^\"]+\" ]]; then
                    line=$(echo "$line" | sed 's/scheme="[^"]*"/scheme="http"/')
                else
                    line=$(echo "$line" | sed 's/>/ scheme="http">/')
                fi
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione scheme corretta${NC}"
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

main() {
    echo "Controllo CIS 6.3 - Ensure scheme is set accurately"
    echo "-----------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_scheme_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_scheme_configuration
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle connessioni HTTP/HTTPS${NC}"
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