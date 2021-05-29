#!/bin/sh

# Sample file for "acme" machine. Replace example.com with your domain
# Schedule this with crontab to run once a week
# It works in harmony with certs_coturn.sh on "coturn" machine.

coturndom='turn.matrix.example.com'

acme.sh --issue --alpn -d "$coturndom"

echo 'Checking if newer cert exists...'               
                                       
#find 'path to possibly new' -newer 'path to existing'                           
if [ "$(find /root/.acme.sh/$coturndom/fullchain.cer -newer /opt/$coturndom/)" ];
then                                                                             
        echo "Newer found...copying across to /opt/$coturndom"        
        cp "/root/.acme.sh/$coturndom/fullchain.cer" "/opt/$coturndom/"
else                                                                  
        echo "None newer. Ending."                             
fi
