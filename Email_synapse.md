# Adding email for Synapse (Matrix homeserver)
In order to facilitate password resets, notification e-mails, etc, you will need to provide SMTP access to your Synapse instance. More details - or as reference - see [this link](https://github.com/matrix-org/synapse/blob/develop/UPGRADE.rst#configure-smtp-in-synapse).

You will need to edit `/opt/matrix/synapse/homeserver.yaml`.  
**public_baseurl**: https://matrix.example.com/  
**smtp_host**: example.com (mail.example.com, etc)  
**smtp_port**: 587  
**smtp_user**: "matrix@example.com"  
**smtp_pass**: "SOMETHING COMPLEX"  
**notif_from**: "Your Friendly %(app)s homeserver <matrix@example.com>"  
**client_base_url**: "http://riot.matrix.example.com"  

Restart synapse: `docker restart synapse`  

Restart your element app and test adding an e-mail for your account (*Settings* -> *General* -> *Emails and phone numbers*)
