#!/bin/sh

# Sample file for "coturn" machine. Replace example.com with your domain
# Schedule this with crontab to run every hour.
# It works in harmony with certs_acme.sh on "coturn" machine.

coturndom='turn.matrix.example.com'

echo 'Checking if newer cert exists...'

active=$(echo "Q" | openssl s_client -connect $coturndom:5349 2>/dev/null | openssl x509 -noout -enddate)
filecert=$(cat /opt/$coturndom/fullchain.cer | openssl x509 -noout -enddate)

#find 'path to possibly new' -newer 'path to existing'
if [ $active==$filecert ];
then
  echo "None newer. Ending."
else
  echo "File differs and is thus newer. Restarting coturn..."
  reboot
fi
