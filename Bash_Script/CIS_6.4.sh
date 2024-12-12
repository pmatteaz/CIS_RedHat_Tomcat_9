#!/bin/bash

# Script per il controllo e fix del CIS Control 6.4
# Ensure secure is set to true only for SSL-enabled Connectors
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei connettori in server.xml:
#   Controllo attributo secure per connettori SSL
#   Verifica della corretta configurazione SSL
#   Controllo di attributi correlati alla sicurezza
# 
# Controlli specifici per:
#   SSLEnabled="true" richiede secure="true"
#   Rimozione di secure="true" per connettori non SSL
#   Protocolli e configurazioni SSL correlate
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Modifica attributi dei connettori
#   Verifica della sintassi XML

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
    local backup_dir="/tmp/tomcat_secure_backup_$(date +%Y%m%d_%H%M%S)_CIS_6.4"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $SERVER_XML" >> "$backup_file"
    ls -l "$SERVER_XML" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$SERVER_XML" > "${backup_dir}/server_xml.acl"
    fi
    
    # Copia fisica del file
    cp -p "$SERVER_XML" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$SERVER_XML" > "${backup_dir}/server.xml.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_connectors() {
    local result=0
    
    echo "Controllo configurazione connettori..."
    
    # Estrai e analizza ogni connettore
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            echo -e "\nAnalisi connettore:"
            echo "$line"
            
            local has_ssl=0
            local has_secure=0
            local secure_value=""
            
            # Controlla se il connettore ha SSL abilitato
            if [[ $line =~ SSLEnabled=\"true\" ]]; then
                has_ssl=1
            fi
            
            # Controlla se l'attributo secure è presente e il suo valore
            if [[ $line =~ secure=\"([^\"]+)\" ]]; then
                has_secure=1
                secure_value="${BASH_REMATCH[1]}"
            fi
            
            # Verifica la corretta configurazione
            if [ $has_ssl -eq 1 ]; then
                if [ $has_secure -eq 0 ]; then
                    echo -e "${YELLOW}[WARN] Connettore SSL senza attributo secure${NC}"
                    result=1
                elif [ "$secure_value" != "true" ]; then
                    echo -e "${YELLOW}[WARN] Connettore SSL con secure=\"$secure_value\" (dovrebbe essere true)${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Connettore SSL configurato correttamente${NC}"
                fi
            else
                if [ $has_secure -eq 1 ] && [ "$secure_value" = "true" ]; then
                    echo -e "${YELLOW}[WARN] Connettore non-SSL con secure=\"true\"${NC}"
                    result=1
                else
                    echo -e "${GREEN}[OK] Connettore non-SSL configurato correttamente${NC}"
                fi
            fi
            
            # Verifica altre configurazioni di sicurezza correlate
            if [ $has_ssl -eq 1 ]; then
                if ! [[ $line =~ protocol=\"HTTP/1\.1\" ]]; then
                    echo -e "${YELLOW}[WARN] Protocollo non specificato per connettore SSL${NC}"
                    result=1
                fi
                
                if ! [[ $line =~ sslProtocol=\"TLS\" ]]; then
                    echo -e "${YELLOW}[WARN] sslProtocol non specificato o non impostato a TLS${NC}"
                    result=1
                fi
            fi
        fi
    done < "$SERVER_XML"
    
    return $result
}

fix_connectors() {
    echo "Correzione configurazione connettori..."
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Processa il file riga per riga
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            if [[ $line =~ SSLEnabled=\"true\" ]]; then
                # Connettore SSL: imposta secure="true"
                if [[ $line =~ secure=\"[^\"]+\" ]]; then
                    line=$(echo "$line" | sed 's/secure="[^"]*"/secure="true"/')
                else
                    line=$(echo "$line" | sed 's/>/ secure="true">/')
                fi
                
                # Assicurati che le altre configurazioni SSL siano presenti
                if ! [[ $line =~ protocol=\"HTTP/1\.1\" ]]; then
                    line=$(echo "$line" | sed 's/>/ protocol="HTTP\/1.1">/')
                fi
                if ! [[ $line =~ sslProtocol=\"TLS\" ]]; then
                    line=$(echo "$line" | sed 's/>/ sslProtocol="TLS">/')
                fi
            else
                # Connettore non-SSL: rimuovi secure="true" se presente
                line=$(echo "$line" | sed 's/ secure="true"//')
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    # Sostituisci il file originale
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione connettori corretta${NC}"
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
    echo "Controllo CIS 6.4 - Ensure secure is set to true only for SSL-enabled Connectors"
    echo "----------------------------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_connectors
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_connectors
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle connessioni SSL${NC}"
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