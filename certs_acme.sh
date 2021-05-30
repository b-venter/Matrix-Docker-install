#!/bin/sh

# Sample file for "acme" machine. 
# 1. Replace example.com with your domain
# 2. Place in "acme" container, /opt/ and make executable (chmod +x)
# 2B. Or in rancher at /opt/certs/
# 3. Schedule this with crontab to run once a week
#   crontab -e
#   0 0 * * 0   ./opt/certs_acme.sh

coturndom='turn.matrix.example.com'

acme.sh --issue --alpn -d "$coturndom"

echo 'Checking if newer cert exists...'               
                                       
#find 'path to possibly new' -newer 'path to existing'                           
if [ "$(find /root/.acme.sh/$coturndom/fullchain.cer -newer /opt/$coturndom/)" ];
then                                                                             
        echo "Newer found...copying across to /opt/$coturndom"        
        cp "/root/.acme.sh/$coturndom/fullchain.cer" "/opt/$coturndom/"
        echo "Restarting TURN server..."                                                                 
        curl -X POST http://dockerproxy:2375/containers/coturn/restart                                   
        echo "Done."
else                                                                  
        echo "None newer. Ending."                             
fi
