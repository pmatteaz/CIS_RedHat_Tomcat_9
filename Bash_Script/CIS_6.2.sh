#!/bin/bash

# Script per il controllo e fix del CIS Control 6.2
# Ensure SSLEnabled is set to True for Sensitive Connectors
#
# Lo script implementa le seguenti funzionalità:
# Verifica dei connettori sensibili:
#  Identificazione porte che richiedono SSL
#  Controllo configurazione SSL completa
#  Verifica protocolli e cipher suites
# 
# Controlli specifici per:
#   SSLEnabled="true"
#   Protocolli TLS sicuri
#   Cipher suites raccomandate
#   Configurazioni di sicurezza aggiuntive
# 
# 
# Sistema di correzione:
#   Backup delle configurazioni
#   Applicazione configurazioni SSL sicure
#   Rimozione configurazioni non sicure
#   Verifica sintassi XML

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Porte sensibili che richiedono SSL
SENSITIVE_PORTS=(
    "8443"  # HTTPS default
    "8009"  # AJP default
    "443"   # HTTPS standard
)

# Configurazione SSL raccomandata
SSL_CONFIG="SSLEnabled=\"true\" maxThreads=\"150\" scheme=\"https\" secure=\"true\" 
           clientAuth=\"false\" sslProtocol=\"TLS\" 
           sslEnabledProtocols=\"TLSv1.2,TLSv1.3\"
           ciphers=\"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256\""

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
    local backup_dir="/tmp/tomcat_ssl_backup_$(date +%Y%m%d_%H%M%S)_CIS_6.2"
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

check_ssl_configuration() {
    local result=0
    
    echo "Controllo configurazione SSL dei connettori..."
    
    # Estrai e analizza ogni connettore
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            echo -e "\nAnalisi connettore:"
            echo "$line"
            
            local port=""
            local is_sensitive=0
            
            # Estrai porta del connettore
            if [[ $line =~ port=\"([0-9]+)\" ]]; then
                port="${BASH_REMATCH[1]}"
                
                # Verifica se è una porta sensibile
                for sensitive_port in "${SENSITIVE_PORTS[@]}"; do
                    if [ "$port" = "$sensitive_port" ]; then
                        is_sensitive=1
                        break
                    fi
                done
            fi
            
            # Controlla configurazione SSL per porte sensibili
            if [ $is_sensitive -eq 1 ]; then
                if ! [[ $line =~ SSLEnabled=\"true\" ]]; then
                    echo -e "${YELLOW}[WARN] Connettore sulla porta $port non ha SSL abilitato${NC}"
                    result=1
                else
                    # Verifica configurazioni SSL aggiuntive
                    if ! [[ $line =~ sslProtocol=\"TLS\" ]]; then
                        echo -e "${YELLOW}[WARN] sslProtocol non configurato correttamente per porta $port${NC}"
                        result=1
                    fi
                    
                    if ! [[ $line =~ sslEnabledProtocols=\".*TLSv1\.2.*\" ]]; then
                        echo -e "${YELLOW}[WARN] TLSv1.2 non abilitato per porta $port${NC}"
                        result=1
                    fi
                    
                    if ! [[ $line =~ secure=\"true\" ]]; then
                        echo -e "${YELLOW}[WARN] attributo secure non impostato per porta $port${NC}"
                        result=1
                    fi
                fi
            fi
            
            # Controlla configurazioni non sicure
            if [[ $line =~ SSLEnabled=\"true\" ]]; then
                if [[ $line =~ allowUnsafeLegacyRenegotiation=\"true\" ]]; then
                    echo -e "${YELLOW}[WARN] Rinegoziazione legacy non sicura abilitata${NC}"
                    result=1
                fi
            fi
        fi
    done < "$SERVER_XML"
    
    return $result
}

fix_ssl_configuration() {
    echo "Correzione configurazione SSL..."
    
    local temp_file=$(mktemp)
    
    while IFS= read -r line; do
        if [[ $line =~ \<Connector ]]; then
            local port=""
            local is_sensitive=0
            
            # Estrai porta
            if [[ $line =~ port=\"([0-9]+)\" ]]; then
                port="${BASH_REMATCH[1]}"
                
                # Verifica se è una porta sensibile
                for sensitive_port in "${SENSITIVE_PORTS[@]}"; do
                    if [ "$port" = "$sensitive_port" ]; then
                        is_sensitive=1
                        break
                    fi
                done
            fi
            
            if [ $is_sensitive -eq 1 ]; then
                # Rimuovi configurazioni SSL esistenti
                line=$(echo "$line" | sed -E 's/SSLEnabled="[^"]*"//g')
                line=$(echo "$line" | sed -E 's/sslProtocol="[^"]*"//g')
                line=$(echo "$line" | sed -E 's/sslEnabledProtocols="[^"]*"//g')
                line=$(echo "$line" | sed -E 's/secure="[^"]*"//g')
                line=$(echo "$line" | sed -E 's/ciphers="[^"]*"//g')
                
                # Aggiungi nuova configurazione SSL
                line=$(echo "$line" | sed 's/>/ '"$SSL_CONFIG"'>/')
            fi
            
            # Rimuovi configurazioni non sicure
            line=$(echo "$line" | sed 's/allowUnsafeLegacyRenegotiation="true"//')
        fi
        echo "$line" >> "$temp_file"
    done < "$SERVER_XML"
    
    mv "$temp_file" "$SERVER_XML"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione SSL corretta${NC}"
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
    echo "Controllo CIS 6.2 - Ensure SSLEnabled is set to True for Sensitive Connectors"
    echo "------------------------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_ssl_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_ssl_configuration
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Verificare il funzionamento delle connessioni SSL${NC}"
                echo -e "${YELLOW}NOTA: Assicurarsi che i certificati SSL siano configurati correttamente${NC}"
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