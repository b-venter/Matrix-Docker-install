
# Hardening security

1. Synapse
2. Docker

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
Note that federation by default allows every domain. Should you wish to keep your homeserver private and yet be joined to one or more other specific homeservers, ensure you are specific about it. (And regarding why your own domain must be present, see this [bug](https://github.com/matrix-org/synapse/issues/6635))
```
# Restrict federation to the following whitelist of domains.                      
# N.B. we recommend also firewalling your federation listener to limit            
# inbound federation traffic as early as possible, rather than relying                 
# purely on this application-layer restriction.  If not specified, the        
# default is to whitelist everything.                                           
#                                                                                                 
federation_domain_whitelist:                                                                                                         
  - matrix.example.com                                                     
                                
```
Note that [delegation](https://github.com/matrix-org/synapse/blob/master/docs/delegate.md) may also be involved.

## Docker
### Docker socket access
It is just good practice to secure access to the docker socket so as to reduce the possibility that a container can be used to reach the host. However, since Traefik requires access to the docker socket - and it is Internet facing - even more diligence is needed.Therefore, we will:
1. Using Tecnativa's "Docker Socket proxy"
2. Enable TLS access to docker

### [Tecnativa's "Docker Socket proxy"](https://github.com/Tecnativa/docker-socket-proxy)


### Enabling TLS access to docker
The [Docker document](https://docs.docker.com/engine/security/https/) provides much of the basis for enabling TLS. However, using RancherOS simplifies this (you can refer to this [link](https://rancher.com/docs/os/v1.x/en/configuration/setting-up-docker-tls/) as well).  
```
sudo ros config set rancher.docker.tls true
sudo ros tls gen --server -H localhost -H <hostname1> -H <hostname2> ... -H <hostnameN>
sudo system-docker restart docker
```
