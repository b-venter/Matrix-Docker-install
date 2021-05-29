#!/bin/sh

# Sample file for "coturn" machine. Replace example.com with your domain
# Schedule this with crontab to run every hour.
# It works in harmony with certs_acme.sh on "coturn" machine.

coturndom='turn.matrix.example.com'

echo 'Checking if newer cert exists...'               
                                       
#find 'path to possibly new' -newer 'path to existing'                           
if [ "$(find /root/.acme.sh/$coturndom/fullchain.cer -newer /opt/$coturndom/)" ];
then                                                                             
        echo "Newer found...copying across to /opt/$coturndom"        
        cp "/root/.acme.sh/$coturndom/fullchain.cer" "/opt/$coturndom/"
else                                                                  
        echo "None newer. Ending."                             
fi

echo "Q" | openssl s_client -connect turn.matrix.workshop86.com:5349 2>/dev/null | openssl x509 -noout -dates

cat /opt/turn.matrix.workshop86.com/fullchain.cer | openssl x509 -noout -enddate
