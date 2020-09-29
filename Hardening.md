
# Hardening security

1. [Synapse](#synapse)
2. [Docker](#docker)

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
2. Set Traefik to connect via Docker Socket proxy


                  22   (80,443)                (All other ports)
    -------------------|----|-------------------------------|------------------------
                            :           RANCHEROS           |
    ------------------------|-------------------------------|-------------------------
                            :                              /
                            |                             /
                            :                            /
                 [riot]     |             COTURN----<host>
                   NGINX    :       (5349, 3478, 63000-63059)
                        \   |                                
                         \  :  
         [matrix]         \ |                                  (2375)
          SYNAPSE---------<web>------PROXY[traefik]           DOCKERPROXY
                           / \      (80,443) \                   /
                          /   \               \                 /
                         /     \               \---<private>---/
                        /       \
                     ACME     POSTGRES
                     
                     

#### [Tecnativa's "Docker Socket proxy"](https://github.com/Tecnativa/docker-socket-proxy)
The idea is that the **socket proxy** be connected to via a non-public linked network. So:  
`docker network create private`  
Next, we install the **socket proxy** container:
`docker run -d --restart=unless-stopped --privileged --name dockerproxy --network=private -v /var/run/docker.sock:/var/run/docker.sock --expose 2375 --env CONTAINERS=1 tecnativa/docker-socket-proxy`  
Regarding the above:  
* `--network` It is connected to the newly connected *private* network (and currently is the only container on that network).
* `--env` We have set a environment variable that will allow queries relating to CONTAINERS [as per Tecnativa](https://github.com/Tecnativa/docker-socket-proxy#not-always-needed) and [Docker API](https://docs.docker.com/engine/api/v1.40/#operation/ContainerList).  
* `-v` Naturally, this container needs to connect to Docker Socket.  

#### [Traefik - Docker Socket via proxy](https://chriswiegman.com/2019/11/protecting-your-docker-socket-with-traefik-2/)
Now on to modifying Traefik:  
`sudo vi /opt/traefik/traefik.toml`  
Ensure it contains the following:  
```
[providers.docker]
  exposedByDefault = false
  endpoint = "tcp://dockerproxy:2375"
  network = "private"

```
Finally, we need to adjust the parameters of the **proxy** container:  
`docker stop proxy`  
`docker rm proxy`  
`docker run -d --restart=unless-stopped --network=web --name=proxy -p 80:80 -p 443:443 -v /opt/traefik/traefik.toml:/traefik.toml -v /opt/traefik/acme.json:/acme.json traefik:v2.2 --configFile=/traefik.toml`  
`docker network connect private proxy`  

Note that:
* The Docker socket is no longer mounted as a *volume*.
* The **proxy** container is conencted to ***two*** networks.

#### Testing
You can (1) add ***curl*** to the Traefik container or (2) install a temporary container. Below uses option 2:  
`docker run -d --restart=unless-stopped -it --name alpine --network=private alpine`  
`docker exec -ti alpine apk update`  
`docker exec -ti alpine apk add --upgrade curl`  
`docker exec -ti alpine curl http://dockerproxy:2375/containers/json` - This successfully display JSON data.  
`docker exec -ti alpine curl http://dockerproxy:2375/networks` - This should provide Error 403 Forbidden.  
`docker stop alpine`  
`docker rm alpine` - Stop and delete the temporary container.  
