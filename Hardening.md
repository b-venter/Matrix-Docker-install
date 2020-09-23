
# Hardening security

1. Synapse
2. Docker socket

## Synapse  
### Public Rooms
The setup as covered in the README.md does not have federation. However, as one might enable it (and, just as good security!), it is best not to allow easy access to public rooms. This requires manually editing (as discussed on the [Matrix blog](https://matrix.org/blog/2019/11/09/avoiding-unwelcome-visitors-on-private-matrix-servers)):  
`sudo vi /opt/matrix/synapse/homeserver.yaml`  
```
# If set to 'true', removes the need for authentication to access the server's
# public rooms directory through the client API, meaning that anyone can          
# query the room directory. Defaults to 'false'.                            
#                                                                           
allow_public_rooms_without_auth: false
# If set to 'true', allows any other homeserver to fetch the server's public
# rooms directory via federation. Defaults to 'false'.             
#                                                                     
allow_public_rooms_over_federation: false 
```

### White list federation servers
