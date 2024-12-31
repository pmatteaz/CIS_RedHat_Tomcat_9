#!/bin/bash

print_uncommented_xml() {
    local xml_file="$1"
    
    if [ ! -f "$xml_file" ]; then
        echo "Errore: Il file $xml_file non esiste"
        return 1
    fi
    
    # Usa sed per rimuovere i commenti XML
    # -e: permette multiple operazioni
    # 's/PATTERN/REPLACEMENT/': sostituisce il pattern con il replacement
    # '/<!--/,/-->/d': elimina tutto ciò che si trova tra <!-- e -->
    sed -e 's/<!--.*-->//g' \
        -e '/<!--/,/-->/d' \
        -e '/^[[:space:]]*$/d' \
        "$xml_file"
}

# Esempio di utilizzo:
# print_uncommented_xml "file.xml"