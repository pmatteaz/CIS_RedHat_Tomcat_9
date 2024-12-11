#!/bin/bash

# Script per il controllo e fix del CIS Control 10.11
# Force SSL for all applications
#
# Lo script implementa le seguenti funzionalità:
# Verifica configurazione SSL:
#   Connettore HTTPS in server.xml
#   Protocolli SSL/TLS abilitati
#   Cipher suites sicure
#   Security constraints in web.xml
# 
# Configurazione SSL completa:
#   Generazione certificato self-signed (se necessario)
#   Configurazione connettore HTTPS
#   Impostazione security constraints
#   Applicazione delle best practices di sicurezza
# 
# Funzionalità aggiuntive:
#   Backup dei file modificati
#   Verifica permessi
#   Configurazione TLS 1.2/1.3
#   Cipher suites sicure

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"
WEBAPPS_DIR="$TOMCAT_HOME/conf/Catalina/localhost"
WEB_XML="$TOMCAT_HOME/conf/web.xml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configurazione SSL
SSL_CONFIG='
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true"
               scheme="https" secure="true" sslProtocol="TLS"
               keystoreFile="conf/ssl/keystore.jks"
               keystorePass="changeit"
               clientAuth="false"
               sslEnabledProtocols="TLSv1.2,TLSv1.3"
               ciphers="TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256" />'

# Security constraint configuration
SECURITY_CONSTRAINT='
    <security-constraint>
        <web-resource-collection>
            <web-resource-name>Entire Application</web-resource-name>
            <url-pattern>/*</url-pattern>
        </web-resource-collection>
        <user-data-constraint>
            <transport-guarantee>CONFIDENTIAL</transport-guarantee>
        </user-data-constraint>
    </security-constraint>'

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

create_backup() {
    local file="$1"
    local backup_dir="/tmp/tomcat_ssl_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup di $file..."
    
    mkdir -p "$backup_dir"
    cp -p "$file" "$backup_dir/"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" > "${backup_dir}/$(basename "$file").sha256"
    fi
    
    echo "# Backup created: $(date)" > "$backup_file"
    echo "# Original file: $file" >> "$backup_file"
    ls -l "$file" >> "$backup_file"
    
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_ssl_configuration() {
    local result=0
    
    echo "Controllo configurazione SSL..."
    
    # Verifica connettore SSL
    if ! grep -q "SSLEnabled=\"true\"" "$SERVER_XML"; then
        echo -e "${YELLOW}[WARN] Connettore SSL non configurato in server.xml${NC}"
        result=1
    else
        # Verifica protocolli SSL
        if ! grep -q "sslEnabledProtocols=\".*TLSv1.2.*TLSv1.3" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Protocolli SSL non configurati correttamente${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Protocolli SSL configurati correttamente${NC}"
        fi
        
        # Verifica cipher suites
        if ! grep -q "ciphers=\"TLS_ECDHE" "$SERVER_XML"; then
            echo -e "${YELLOW}[WARN] Cipher suites non configurati in modo sicuro${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Cipher suites configurati correttamente${NC}"
        fi
    fi
    
    # Verifica web.xml globale
    if [ -f "$WEB_XML" ]; then
        if ! grep -q "<transport-guarantee>CONFIDENTIAL</transport-guarantee>" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Security constraint CONFIDENTIAL non configurato in web.xml globale${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Security constraint configurato in web.xml globale${NC}"
        fi
    fi
    
    # Verifica web.xml delle applicazioni
    echo -e "\nControllo configurazioni SSL delle applicazioni..."
    find "$TOMCAT_HOME/webapps" -name "web.xml" -type f | while read -r app_web_xml; do
        if ! grep -q "<transport-guarantee>CONFIDENTIAL</transport-guarantee>" "$app_web_xml"; then
            echo -e "${YELLOW}[WARN] Security constraint CONFIDENTIAL non configurato in: $app_web_xml${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Security constraint configurato in: $app_web_xml${NC}"
        fi
    done
    
    return $result
}

generate_self_signed_cert() {
    local keystore_dir="$TOMCAT_HOME/conf/ssl"
    local keystore_file="$keystore_dir/keystore.jks"
    
    if [ ! -d "$keystore_dir" ]; then
        mkdir -p "$keystore_dir"
    fi
    
    if [ ! -f "$keystore_file" ]; then
        echo "Generazione certificato self-signed..."
        keytool -genkey -alias tomcat -keyalg RSA -keysize 2048 \
                -keystore "$keystore_file" -validity 365 \
                -storepass changeit \
                -dname "CN=localhost, OU=Development, O=Company, L=City, ST=State, C=IT"
        
        chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$keystore_dir"
        chmod 700 "$keystore_dir"
        chmod 600 "$keystore_file"
        
        echo -e "${GREEN}[OK] Certificato self-signed generato${NC}"
        echo -e "${YELLOW}[WARN] Sostituire il certificato self-signed con uno valido in produzione${NC}"
    fi
}

fix_ssl_configuration() {
    echo "Applicazione configurazioni SSL..."
    
    # Backup dei file
    create_backup "$SERVER_XML"
    [ -f "$WEB_XML" ] && create_backup "$WEB_XML"
    
    # Genera certificato self-signed se necessario
    generate_self_signed_cert
    
    # Configura SSL connector in server.xml
    if ! grep -q "SSLEnabled=\"true\"" "$SERVER_XML"; then
        # Aggiungi connettore SSL dopo l'ultimo Connector esistente
        sed -i "/<Connector.*>/a\\$SSL_CONFIG" "$SERVER_XML"
    fi
    
    # Configura security constraint in web.xml globale
    if [ -f "$WEB_XML" ]; then
        if ! grep -q "<transport-guarantee>CONFIDENTIAL</transport-guarantee>" "$WEB_XML"; then
            # Aggiungi security constraint prima di </web-app>
            sed -i "/<\/web-app>/i\\$SECURITY_CONSTRAINT" "$WEB_XML"
        fi
    fi
    
    # Configura security constraint in tutte le applicazioni
    find "$TOMCAT_HOME/webapps" -name "web.xml" -type f | while read -r app_web_xml; do
        if ! grep -q "<transport-guarantee>CONFIDENTIAL</transport-guarantee>" "$app_web_xml"; then
            create_backup "$app_web_xml"
            sed -i "/<\/web-app>/i\\$SECURITY_CONSTRAINT" "$app_web_xml"
            echo -e "${GREEN}[OK] Security constraint aggiunto a: $app_web_xml${NC}"
        fi
    done
    
    # Imposta permessi corretti
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    [ -f "$WEB_XML" ] && chown "$TOMCAT_USER:$TOMCAT_GROUP" "$WEB_XML" && chmod 600 "$WEB_XML"
    
    echo -e "${GREEN}[OK] Configurazione SSL completata${NC}"
}

main() {
    echo "Controllo CIS 10.11 - Force SSL for all applications"
    echo "------------------------------------------------"
    
    check_root
    
    local needs_fix=0
    
    check_ssl_configuration
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_ssl_configuration
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Assicurarsi di sostituire il certificato self-signed con uno valido${NC}"
            echo -e "${YELLOW}NOTA: Verificare che le applicazioni funzionino correttamente con SSL${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main