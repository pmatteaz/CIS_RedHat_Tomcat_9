#!/bin/bash

# Script per il controllo e fix del CIS Control 10.10
# Configure maxHttpHeaderSize
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione maxHttpHeaderSize:
#   Controlla tutti i connettori in server.xml
#   Verifica il valore configurato (8KB raccomandato)
#   Identifica connettori mancanti della configurazione
# 
# Funzionalità di correzione:
#   Imposta il valore raccomandato per tutti i connettori
#   Aggiunge il parametro se mancante
#   Verifica la sintassi XML dopo le modifiche
# 
# Sistema di backup:
#   Backup completo di server.xml
#   Salvataggio delle ACL
#   Verifica dell'integrità tramite hash

# Cerca e setta la home di tomcat
. ./Find_catalinaHome.sh

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${CATALINA_USER:-tomcat}
TOMCAT_GROUP=${CATALINA_GROUP:-tomcat}
SERVER_XML="$TOMCAT_HOME/conf/server.xml"

# Valore raccomandato per maxHttpHeaderSize (8KB)
MAX_HEADER_SIZE="8192"

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
    local backup_dir="/tmp/tomcat_header_backup_$(date +%Y%m%d_%H%M%S)_CIS_10.10"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for server.xml" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $SERVER_XML" >> "$backup_file"
    echo "# Tomcat User: $TOMCAT_USER" >> "$backup_file"
    echo "# Tomcat Group: $TOMCAT_GROUP" >> "$backup_file"
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

check_header_size() {
    local result=0
    result=1
    echo "Controllo configurazione maxHttpHeaderSize..."
    in_coordinator=1
    # Controlla tutti i connettori
    while IFS= read -r line; do
        if [[ $line =~ maxHttpHeaderSize=\"([0-9]+)\" ]]; then
                local size="$( cut -d '"' -f 2 <<< "$line" )"
                if [ "$size" -gt "$MAX_HEADER_SIZE" ]; then
                    echo -e "${YELLOW}[WARN] maxHttpHeaderSize ($size) è maggiore del valore raccomandato ($MAX_HEADER_SIZE)${NC}"
                elif [ "$size" -lt "$MAX_HEADER_SIZE" ]; then
                    echo -e "${YELLOW}[WARN] maxHttpHeaderSize ($size) è minore del valore raccomandato ($MAX_HEADER_SIZE)${NC}"  
                else
                    echo -e "${GREEN}[OK] maxHttpHeaderSize configurato correttamente${NC}"
                    result=0
                fi
            fi
               
    done < <(sed '/<!--/,/-->/d' "$SERVER_XML")
    
    return $result
}

add_max_header_size() {
    local xml_file="$1"
    
    if [ ! -f "$xml_file" ]; then
        echo "Errore: Il file $xml_file non esiste"
        return 1
    fi
    
    # Usa sed per:
    # 1. Ignora i commenti
    # 2. Trova il tag Connector che non ha già maxHttpHeaderSize
    # 3. Aggiunge maxHttpHeaderSize="8192" prima della chiusura del tag
sed -i -e '
    /<!--/,/-->/b
    /<Connector/{
        :a
        N
        /\/>/!ba
        /maxHttpHeaderSize/b
        s/\([[:space:]]*\)\/>/\1maxHttpHeaderSize="8192" \/>/
    }
' "$xml_file"
    
    echo "Modifiche applicate a $xml_file"
}


fix_header_size() {
    echo "Applicazione configurazione maxHttpHeaderSize..."
    
    # Crea backup prima delle modifiche
    create_backup
    
    # File temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Modifica ogni connettore
    # Se non esiste lo aggiungo a "$SERVER_XML"
    # Se esiste ma è diverso lo aggiorno 8192

    if ! grep -q maxHttpHeaderSize "$SERVER_XML"; then
        add_max_header_size "$SERVER_XML"
    else 
        sed -i -e 's/maxHttpHeaderSize="[0-9]*"/maxHttpHeaderSize="8192"/g' "$SERVER_XML"
    fi 
    # Sostituisci il file originale
    # mv "$temp_file" "$SERVER_XML"
    
    # Imposta permessi corretti
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$SERVER_XML"
    chmod 600 "$SERVER_XML"
    
    echo -e "${GREEN}[OK] Configurazione maxHttpHeaderSize aggiornata${NC}"
    
    # Verifica le modifiche
    echo -e "\nVerifica delle modifiche applicate:"
    check_header_size
}

verify_xml_syntax() {
    if command -v xmllint &> /dev/null; then
        if ! xmllint --noout "$SERVER_XML" 2>/dev/null; then
            echo -e "${RED}[ERROR] Errore nella sintassi XML di server.xml${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[WARN] xmllint non disponibile, impossibile verificare la sintassi XML${NC}"
    fi
    return 0
}

main() {
    echo "Controllo CIS 10.10 - Configure maxHttpHeaderSize"
    echo "---------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_header_size $SERVER_XML
    needs_fix=$?
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_header_size
            if verify_xml_syntax; then
                echo -e "\n${GREEN}Fix completato con successo.${NC}"
                echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
                echo -e "${YELLOW}NOTA: Monitorare i log per eventuali problemi con le richieste HTTP${NC}"
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