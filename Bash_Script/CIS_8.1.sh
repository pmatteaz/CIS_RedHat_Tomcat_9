#!/bin/bash

# Script per il controllo e fix del CIS Control 8.1
# Restrict runtime access to sensitive packages
#
# Lo script implementa le seguenti funzionalità:
# Verifica della configurazione:
#   Controllo dei permessi del file catalina.policy
#   Verifica delle protezioni per pacchetti sensibili
#   Analisi delle configurazioni di sicurezza
# 
# Protezione dei pacchetti sensibili:
#   sun.*
#   org.apache.catalina.*
#   org.apache.tomcat.*
#   java.security.*
#   javax.security.*
# 
# Sistema di correzione:
#   Backup completo della configurazione
#   Applicazione dei permessi corretti
#   Generazione di una nuova policy di sicurezza

# Configurazione predefinita
TOMCAT_HOME=${CATALINA_HOME:-/usr/share/tomcat}
TOMCAT_USER=${TOMCAT_USER:-tomcat}
TOMCAT_GROUP=${TOMCAT_GROUP:-tomcat}
CATALINA_POLICY="$TOMCAT_HOME/conf/catalina.policy"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Lista dei pacchetti sensibili da proteggere
SENSITIVE_PACKAGES=(
    "sun."
    "org.apache.catalina.core"
    "org.apache.catalina.security"
    "org.apache.catalina.users"
    "org.apache.catalina.authenticator"
    "org.apache.tomcat.util"
    "java.security"
    "java.lang.SecurityManager"
    "javax.security"
)

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}[ERROR] Questo script deve essere eseguito come root${NC}"
        exit 1
    fi
}

check_file_exists() {
    if [ ! -f "$CATALINA_POLICY" ]; then
        echo -e "${RED}[ERROR] File catalina.policy non trovato: $CATALINA_POLICY${NC}"
        exit 1
    fi
}

create_backup() {
    local backup_dir="/tmp/tomcat_policy_backup_$(date +%Y%m%d_%H%M%S)_CIS_8.1"
    local backup_file="${backup_dir}/backup_info.txt"
    
    echo "Creazione backup della configurazione..."
    
    mkdir -p "$backup_dir"
    
    # Salva informazioni sui permessi attuali
    echo "# Backup permissions for catalina.policy" > "$backup_file"
    echo "# Created: $(date)" >> "$backup_file"
    echo "# Original file: $CATALINA_POLICY" >> "$backup_file"
    ls -l "$CATALINA_POLICY" >> "$backup_file"
    
    # Backup dei permessi usando getfacl
    if command -v getfacl &> /dev/null; then
        getfacl "$CATALINA_POLICY" > "${backup_dir}/catalina_policy.acl"
    fi
    
    # Copia fisica del file
    cp -p "$CATALINA_POLICY" "$backup_dir/"
    
    # Verifica hash del file
    if command -v sha256sum &> /dev/null; then
        sha256sum "$CATALINA_POLICY" > "${backup_dir}/catalina.policy.sha256"
    fi
    
    # Crea un tarball del backup
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    echo -e "${GREEN}[OK] Backup creato in: ${backup_dir}.tar.gz${NC}"
}

check_policy_permissions() {
    echo "Controllo permessi di catalina.policy..."
    
    local file_owner=$(stat -c '%U' "$CATALINA_POLICY")
    local file_group=$(stat -c '%G' "$CATALINA_POLICY")
    local file_perms=$(stat -c '%a' "$CATALINA_POLICY")
    
    local result=0
    
    if [ "$file_owner" != "$TOMCAT_USER" ]; then
        echo -e "${YELLOW}[WARN] Proprietario file non corretto: $file_owner (dovrebbe essere $TOMCAT_USER)${NC}"
        result=1
    fi
    
    if [ "$file_group" != "$TOMCAT_GROUP" ]; then
        echo -e "${YELLOW}[WARN] Gruppo file non corretto: $file_group (dovrebbe essere $TOMCAT_GROUP)${NC}"
        result=1
    fi
    
    if [ "$file_perms" != "600" ]; then
        echo -e "${YELLOW}[WARN] Permessi file non corretti: $file_perms (dovrebbero essere 600)${NC}"
        result=1
    fi
    
    return $result
}

check_policy_content() {
    echo "Controllo configurazioni di sicurezza..."
    
    local result=0
    
    # Verifica la presenza della sezione di default
    if ! grep -q "grant {" "$CATALINA_POLICY"; then
        echo -e "${YELLOW}[WARN] Sezione grant predefinita non trovata${NC}"
        result=1
    fi
    
    # Controlla i pacchetti sensibili
    for package in "${SENSITIVE_PACKAGES[@]}"; do
        if ! grep -q "permission java.security.AllPermission \"$package\*\"" "$CATALINA_POLICY"; then
            echo -e "${YELLOW}[WARN] Protezione non trovata per il pacchetto: $package${NC}"
            result=1
        fi
    done
    
    # Verifica altre configurazioni di sicurezza importanti
    if ! grep -q "SecurityManager" "$CATALINA_POLICY"; then
        echo -e "${YELLOW}[WARN] Configurazione SecurityManager non trovata${NC}"
        result=1
    fi
    
    if grep -q "permission java.security.AllPermission;" "$CATALINA_POLICY"; then
        echo -e "${YELLOW}[WARN] Trovato AllPermission generico - potenziale rischio di sicurezza${NC}"
        result=1
    fi
    
    return $result
}

fix_policy_permissions() {
    echo "Correzione permessi di catalina.policy..."
    
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$CATALINA_POLICY"
    chmod 600 "$CATALINA_POLICY"
    
    echo -e "${GREEN}[OK] Permessi corretti applicati${NC}"
}

fix_policy_content() {
    echo "Applicazione configurazioni di sicurezza..."
    
    # Crea un file temporaneo per le modifiche
    local temp_file=$(mktemp)
    
    # Aggiungi header
    cat > "$temp_file" << EOL
// Catalina.policy - Security Policy for Tomcat
// Generated by CIS compliance script

// Default permissions
grant {
    // Basic runtime permissions
    permission java.io.FilePermission "\${catalina.base}${/}-", "read";
    permission java.util.PropertyPermission "*", "read";
    
    // Minimal network permissions
    permission java.net.SocketPermission "localhost:1024-65535", "listen";
    permission java.net.SocketPermission "*:1024-65535", "accept,connect";
};

EOL
    
    # Aggiungi protezioni per pacchetti sensibili
    for package in "${SENSITIVE_PACKAGES[@]}"; do
        cat >> "$temp_file" << EOL
// Protect $package
grant codeBase "file:\${catalina.home}/bin/-" {
    permission java.security.AllPermission "$package*";
};
grant codeBase "file:\${catalina.home}/lib/-" {
    permission java.security.AllPermission "$package*";
};

EOL
    done
    
    # Aggiungi configurazioni aggiuntive di sicurezza
    cat >> "$temp_file" << EOL
// Web application permissions
grant {
    // Minimal set of permissions for web applications
    permission java.lang.RuntimePermission "getClassLoader";
    permission java.lang.RuntimePermission "setContextClassLoader";
    
    // File system permissions
    permission java.io.FilePermission "\${catalina.base}/webapps${/}-", "read";
    permission java.io.FilePermission "\${catalina.base}/work${/}-", "read,write,delete";
    
    // Session related permissions
    permission java.lang.RuntimePermission "accessClassInPackage.org.apache.tomcat.util.http.mapper";
};
EOL
    
    # Sostituisci il file originale
    mv "$temp_file" "$CATALINA_POLICY"
    
    # Imposta i permessi corretti
    fix_policy_permissions
    
    echo -e "${GREEN}[OK] Configurazioni di sicurezza applicate${NC}"
}

main() {
    echo "Controllo CIS 8.1 - Restrict runtime access to sensitive packages"
    echo "------------------------------------------------------------"
    
    check_root
    check_file_exists
    
    local needs_fix=0
    
    check_policy_permissions
    needs_fix=$((needs_fix + $?))
    
    check_policy_content
    needs_fix=$((needs_fix + $?))
    
    if [ $needs_fix -gt 0 ]; then
        echo -e "\n${YELLOW}Sono stati rilevati problemi. Vuoi procedere con il fix? (y/n)${NC}"
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_backup
            fix_policy_content
            echo -e "\n${GREEN}Fix completato.${NC}"
            echo -e "${YELLOW}NOTA: Riavviare Tomcat per applicare le modifiche${NC}"
            echo -e "${YELLOW}NOTA: Verificare il corretto funzionamento delle applicazioni${NC}"
            echo -e "${YELLOW}NOTA: Potrebbe essere necessario personalizzare ulteriormente le policy${NC}"
        else
            echo -e "\n${YELLOW}Fix annullato dall'utente${NC}"
        fi
    else
        echo -e "\n${GREEN}Tutti i controlli sono passati. Nessun fix necessario.${NC}"
    fi
}

main