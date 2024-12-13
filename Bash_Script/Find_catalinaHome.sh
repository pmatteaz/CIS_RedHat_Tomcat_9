#!/bin/bash
##
## test funzione
##

find_tomcat_home() {
    # Lista dei possibili percorsi di installazione di Tomcat
    local possible_paths=(
        "/usr/share/tomcat"
        "/usr/local/tomcat"
        "/opt/tomcat"
        "/var/lib/tomcat"
        "$HOME/tomcat"
        "/usr/share/tomcat*"
        "/usr/local/tomcat*"
        "/opt/tomcat*"
    )

    # Prima controlla se CATALINA_HOME è già impostato
    if [ ! -z "$CATALINA_HOME" ]; then
        if [ -d "$CATALINA_HOME" ]; then
            echo "$CATALINA_HOME"
            return 0
        fi
    fi

    # Poi controlla se TOMCAT_HOME è impostato
    if [ ! -z "$TOMCAT_HOME" ]; then
        if [ -d "$TOMCAT_HOME" ]; then
            echo "$TOMCAT_HOME"
            return 0
        fi
    fi

    # Cerca nei percorsi comuni
    for path in "${possible_paths[@]}"; do
        # Espandi il path se contiene wildcard
        for expanded_path in $path; do
            if [ -d "$expanded_path" ] && [ -f "$expanded_path/bin/catalina.sh" ]; then
                echo "$expanded_pat"
                return 0
            fi
        done
    done

    # Cerca nel filesystem usando find (limitato a directory più comuni per efficienza)
    # echo "Cercando Tomcat nel filesystem..."
    local found_path=$(find /users /usr /opt /var /home -maxdepth 6 -type f -name "catalina.sh" 2>/dev/null | head -n 1)

    if [ ! -z "$found_path" ]; then
        local tomcat_path=$(dirname "$(dirname "$found_path")")
        echo "$tomcat_path"
        return 0
    fi

    # Se non viene trovato
    echo "ERRORE: Non è stato possibile trovare l'installazione di Tomcat"
    return 1
}

# Funzione wrapper per esportare la variabile
set_tomcat_home() {
    local tomcat_path=$(find_tomcat_home)
    if [ $? -eq 0 ]; then
        export CATALINA_HOME="$tomcat_path"
        echo "CATALINA_HOME impostato a: $CATALINA_HOME"
        return 0
    else
        return 1
    fi
}

find_tomcat_user(){
    CATALINA_USER=$(ps -ef | grep [t]omcat | awk '{print $1}')
    CATALINA_GROUP=$(id $CATALINA_USER | cut -d'(' -f3 |cut -d')' -f1)
    if [[ -n $CATALINA_USER && -n $CATALINA_GROUP ]]; then
        export CATALINA_USER
        export CATALINA_GROUP
        return 0
    else
        return 1 
    fi
}

set_tomcat_user() {
 find_tomcat_user
 if [ $? -eq 0 ]; then
        echo "CATALINA_USER  impostato a: $CATALINA_USER"
        echo "CATALINA_GROUP impostato a: $CATALINA_GROUP"
        return 0
    else
        return 1
    fi
}

set_tomcat_home
set_tomcat_user
