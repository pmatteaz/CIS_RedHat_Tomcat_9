#!/bin/bash

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funzione per stampare intestazioni delle sezioni
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# 2.4	    Disable X-Powered-By HTTP Header and Rename the Server Value for all Connectors
print_section "2.4 Disable X-Powered-By HTTP Header and Rename the Server Value for all Connectors"
./CIS_2.4.sh
# 2.5	    Disable client facing Stack Traces
print_section "2.5 Disable client facing Stack Traces"
./CIS_2.5.sh
# 2.7	    Ensure Sever Header is Modified To Prevent Information Disclosure
print_section "2.7 Ensure Sever Header is Modified To Prevent Information Disclosure"
./CIS_2.7.sh
# 3.1	    Set a nondeterministic Shutdown command value
print_section "3.1 Set a nondeterministic Shutdown command value"
./CIS_3.1.sh
# 3.2	    Disable the Shutdown port
print_section "3.2 Disable the Shutdown port"
./CIS_3.2.sh
# 4.1	    Restrict access to $CATALINA_HOME
print_section "4.1 Restrict access to \$CATALINA_HOME"
./CIS_4.1.sh
# 4.2	    Restrict access to $CATALINA_BASE
print_section "4.2 Restrict access to \$CATALINA_BASE"
./CIS_4.2.sh
# 4.3	    Restrict access to Tomcat configuration directory
print_section "4.3 Restrict access to Tomcat configuration directory"
./CIS_4.3.sh
# 4.4	    Restrict access to Tomcat logs directory
print_section "4.4 Restrict access to Tomcat logs directory"
./CIS_4.4.sh
# 4.5	    Restrict access to Tomcat temp directory
print_section "4.5 Restrict access to Tomcat temp directory"
./CIS_4.5.sh
# 4.6	    Restrict access to Tomcat binaries directory
print_section "4.6 Restrict access to Tomcat binaries directory"
./CIS_4.6.sh
# 4.7	    Restrict access to Tomcat web application directory
print_section "4.7 Restrict access to Tomcat web application directory"
./CIS_4.7.sh
# 4.8	    Restrict access to Tomcat catalina.properties
print_section "4.8 Restrict access to Tomcat catalina.properties"
./CIS_4.8.sh
# 4.9	    Restrict access to Tomcat catalina.policy
print_section "4.9 Restrict access to Tomcat catalina.policy"
./CIS_4.9.sh
# 4.10	Restrict access to Tomcat context.xml
print_section "4.10 Restrict access to Tomcat context.xml"
./CIS_4.10.sh
# 4.11	Restrict access to Tomcat logging.properties
print_section "4.11 Restrict access to Tomcat logging.properties"
./CIS_4.11.sh
# 4.12	Restrict access to Tomcat server.xml
print_section "4.12 Restrict access to Tomcat server.xml"
./CIS_4.12.sh
# 4.13	Restrict access to Tomcat tomcat-users.xml
print_section "4.13 Restrict access to Tomcat tomcat-users.xml"
./CIS_4.13.sh
# 4.14	Restrict access to Tomcat web.xml
print_section "4.14 Restrict access to Tomcat web.xml"
./CIS_4.14.sh
# 5.2	    Use LockOut Realms
print_section "5.2 Use LockOut Realms"
./CIS_5.2.sh
# 6.2	    Ensure SSLEnabled is set to True for Sensitive Connectors
print_section "6.2 Ensure SSLEnabled is set to True for Sensitive Connectors"
./CIS_6.2.sh
# 6.3	    Ensure scheme is set accurately
print_section "6.3 Ensure scheme is set accurately"
./CIS_6.3.sh
# 6.4	    Ensure secure is set to true only for SSL-enabled Connectors
print_section "6.4 Ensure secure is set to true only for SSL-enabled Connectors"
./CIS_6.4.sh
# 7.1	    Application specific logging
print_section "7.1 Application specific logging"
./CIS_7.1.sh
# 7.2	    Specify file handler in logging.properties files
print_section "7.2 Specify file handler in logging.properties files"
./CIS_7.2.sh
# 7.3	    Ensure className is set correctly in context.xml
print_section "7.3 Ensure className is set correctly in context.xml"
./CIS_7.3.sh
# 7.5	    Ensure pattern in context.xml is correct
print_section "7.5 Ensure pattern in context.xml is correct"
./CIS_7.5.sh
# 7.6	    Ensure directory in logging.properties is a secure location
print_section "7.6 Ensure directory in logging.properties is a secure location"
./CIS_7.6.sh
# 8.1	    Restrict runtime access to sensitive packages
print_section "8.1 Restrict runtime access to sensitive packages"
./CIS_8.1.sh
# 10.2	Restrict access to the web administration application
#print_section "10.2 Restrict access to the web administration application"
#./CIS_10.2.sh
# 10.9	Configure connectionTimeout
print_section "10.9 Configure connectionTimeout"
./CIS_10.9.sh
# 10.10	Configure maxHttpHeaderSize
print_section "10.10 Configure maxHttpHeaderSize"
./CIS_10.10.sh
# 10.11	Force SSL for all applications
#print_section "10.11 Force SSL for all applications"
#./CIS_10.11.sh
# 10.14	Do not allow cross context requests
print_section "10.14 Do not allow cross context requests"
./CIS_10.14.sh
# 10.15	Do not resolve hosts on logging valves
print_section "10.15 Do not resolve hosts on logging valves"
./CIS_10.15.sh
# 10.16	Enable memory leak listener
print_section "10.16 Enable memory leak listener"
./CIS_10.16.sh
# 10.17	Setting Security Lifecycle Listener
print_section "10.17 Setting Security Lifecycle Listener"
./CIS_10.17.sh
# 10.18	Use the logEffectiveWebXml and metadata-complete settings for deploying applications in production
print_section "10.18 Use the logEffectiveWebXml and metadata-complete settings for deploying applications in production"
./CIS_10.18.sh