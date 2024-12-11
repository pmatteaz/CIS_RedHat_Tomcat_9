#!/bin/bash
#
# Script per il controllo e fix del CIS Control 2.5
# Disable client facing Stack Traces
#
#Lo script implementa le seguenti funzionalità:
# Verifica la presenza di pagine di errore personalizzate
# Controlla la configurazione della gestione degli errori in web.xml
# Se necessario, offre l'opzione di fix automatico che:
# Crea pagine di errore base (404.jsp, 500.jsp, error.jsp)
# Configura il mapping degli errori in web.xml
#
# Crea backup dei file prima delle modifiche
# Lo script verifica e implementa:
# Gestione generica delle eccezioni (Throwable)
# Pagine di errore personalizzate per 404 e 500
# Configurazione appropriata in web.xml
#

TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
WEB_XML="$TOMCAT_HOME/conf/web.xml"
ERROR_PAGES=(
    "/error/404.jsp"
    "/error/500.jsp"
    "/error/error.jsp"
)

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_tomcat_home() {
    if [ ! -d "$TOMCAT_HOME" ]; then
        echo -e "${RED}[ERROR] Directory Tomcat non trovata: $TOMCAT_HOME${NC}"
        exit 1
    fi
}

check_error_pages() {
    local result=0
    local webapps_dir="$TOMCAT_HOME/webapps"
    
    # Verifica la presenza delle pagine di errore personalizzate
    for page in "${ERROR_PAGES[@]}"; do
        if ! find "$webapps_dir" -type f -name "$(basename "$page")" | grep -q .; then
            echo -e "${YELLOW}[WARN] Pagina di errore personalizzata non trovata: $page${NC}"
            result=1
        else
            echo -e "${GREEN}[OK] Pagina di errore personalizzata trovata: $page${NC}"
        fi
    done
    
    return $result
}

check_error_handling() {
    local result=0
    
    # Verifica la configurazione di error-page in web.xml
    if grep -q "<error-page>" "$WEB_XML"; then
        echo -e "${GREEN}[OK] Configurazione error-page presente in web.xml${NC}"
        
        # Verifica specifiche configurazioni di error-page
        if ! grep -q "<exception-type>java.lang.Throwable</exception-type>" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Gestione generica delle eccezioni non configurata${NC}"
            result=1
        fi
        
        if ! grep -q "<error-code>404</error-code>" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Gestione errore 404 non configurata${NC}"
            result=1
        fi
        
        if ! grep -q "<error-code>500</error-code>" "$WEB_XML"; then
            echo -e "${YELLOW}[WARN] Gestione errore 500 non configurata${NC}"
            result=1
        fi
    else
        echo -e "${YELLOW}[WARN] Nessuna configurazione error-page trovata${NC}"
        result=1
    fi
    
    return $result
}

create_error_pages() {
    local webapps_dir="$TOMCAT_HOME/webapps/ROOT"
    
    # Crea directory per le pagine di errore se non esiste
    mkdir -p "$webapps_dir/error"
    
    # Crea pagine di errore di base
    cat > "$webapps_dir/error/404.jsp" << 'EOF'
<%@ page isErrorPage="true" %>
<!DOCTYPE html>
<html>
<head><title>404 - Pagina non trovata</title></head>
<body>
    <h2>Pagina non trovata</h2>
    <p>La risorsa richiesta non è disponibile.</p>
</body>
</html>
EOF

    cat > "$webapps_dir/error/500.jsp" << 'EOF'
<%@ page isErrorPage="true" %>
<!DOCTYPE html>
<html>
<head><title>500 - Errore interno</title></head>
<body>
    <h2>Errore interno del server</h2>
    <p>Si è verificato un errore durante l'elaborazione della richiesta.</p>
</body>
</html>
EOF

    cat > "$webapps_dir/error/error.jsp" << 'EOF'
<%@ page isErrorPage="true" %>
<!DOCTYPE html>
<html>
<head><title>Errore</title></head>
<body>
    <h2>Si è verificato un errore</h2>
    <p>Si prega di riprovare più tardi.</p>
</body>
</html>
EOF

    echo -e "${GREEN}[OK] Pagine di errore create${NC}"
}

fix_error_handling() {
    # Backup del file
    cp "$WEB_XML" "${WEB_XML}.bak"
    
    # Aggiunge configurazioni error-page se non presenti
    if ! grep -q "<error-page>" "$WEB_XML"; then
        sed -i '/<\/web-app>/i \
    <!-- Error Pages Configuration -->\
    <error-page>\
        <exception-type>java.lang.Throwable</exception-type>\
        <location>/error/error.jsp</location>\
    </error-page>\
    <error-page>\
        <error-code>404</error-code>\
        <location>/error/404.jsp</location>\
    </error-page>\
    <error-page>\
        <error-code>500</error-code>\
        <location>/error/500.jsp</location>\
    </error-page>' "$WEB_XML"
        
        echo -e "${GREEN}[OK] Configurazioni error-page aggiunte a web.xml${NC}"
    else
        echo -e "${YELLOW}[WARN] Configurazioni error-page già presenti, verifica manualmente${NC}"
    fi
}

main() {
    echo "Controllo CIS 2.5 - Disable client facing Stack Traces"
    echo "----------------------------------------------------"
    
    check_tomcat_home
    
    local needs_fix=0
    
    check_error_pages
    needs_fix=$((needs_fix + $?))
    
    check_error_handling
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_error_pages
            fix_error_handling
            echo -e "\n${GREEN}Fix completato. Riavviare Tomcat per applicare le modifiche.${NC}"
            echo -e "${YELLOW}NOTA: Personalizza le pagine di errore secondo le tue esigenze${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main