
# Hardening security

1. [Synapse](#synapse)
2. [Docker](#docker)
3. [coTURN](#enabling-dtls-on-coturn)
4. [RancherOS](#rancheros)

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
```

                  22   (80,443)                (All other ports)
    -------------------|----|-------------------------------|------------------------
                            :           RANCHEROS           |      [docker.sock]
    ------------------------|-------------------------------|----------|--------------
                            :                              /           |
                            |                             /            |
                            :                            /             |
                 [riot]     |             COTURN----<host>             |
                   NGINX    :       (5349, 3478, 63000-63059)          |
                        \   |                                          |
                         \  :                                          |
         [matrix]         \ |                                  (2375)  |
          SYNAPSE---------<web>------PROXY[traefik]           DOCKERPROXY
                           /         (80,443) \                   /
                          /                    \                 /
                         /                      \---<private>---/
                        /                       /
                   POSTGRES                    /
                                            ACME(443)-optional
                     
```

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
* The **proxy** container is connected to ***two*** networks.

#### Testing
You can (1) add ***curl*** to the Traefik container or (2) install a temporary container. Below uses option 2:  
`docker run -d --restart=unless-stopped -it --name alpine --network=private alpine`  
`docker exec -ti alpine apk update`  
`docker exec -ti alpine apk add --upgrade curl`  
`docker exec -ti alpine curl http://dockerproxy:2375/containers/json` - This successfully display JSON data.  
`docker exec -ti alpine curl http://dockerproxy:2375/networks` - This should provide Error 403 Forbidden.  
`docker stop alpine`  
`docker rm alpine` - Stop and delete the temporary container.  

## Enabling DTLS on coTURN
### Enabling TLS
1. See [Standalone ACME](#adding-a-standalone-acme-for-non-http-certificates) regarding getting certificates first.
2. Remove the hashes in `sudo vi /opt/coturn/turnserver.conf` for TLS
```
# For Let's Encrypt certificates, use `fullchain.pem` here.
cert=/opt/turn.matrix.example.com/fullchain.cer
# TLS private key file
pkey=opt/turn.matrix.example.com/turn.matrix.example.com.key
```
3. You can force only TLS communication in the `/opt/matrix/synapse/homeserver.yaml` file by changing the TURN URI to only use Secure TURN (default port of TURNS is 5349):
```
turn_uris: [ "turns:turn.matrix.example.com?transport=tcp" ]
```
Remember to restart synapse: `docker restart synapse` and to force restart your Element app, so that the config can be read.  
***NOTE:** WebRTC and COTURN have issues on Android and iOS with TLS on TURN when using Let's Encrypt. The media of WebRTC is encrypted regardless, but some signalling is present on standard TCP/UDP. While this bug exists, calls via TURNS might not work. See [Open issues](#webrtc-and-coturn).*

### Adding a standalone ACME for non-HTTP certificates 
coTURN offers TLS and DTLS to further protect the already encrypted WebRTC. However this requires a certificate, for which we have the following limitations: 
 * We can't use port 80 and 443 because Traefik controls those, but does not control TLS for coTURN
 * Most ACME agents need to use either port **80** or **443**.

The solution is:
1. To have a container whose port 443 is passed directly to it from Traefik using coTURN's URL (*turn.matrix.example.com*).
2. To share the certificates with coTURN container via a shared volume since they do not share a network.  

To accomplish this, we use a standard **Alpine** image, and install **acme.sh** on it:  
`docker run -d --restart=unless-stopped --network=private --name=acme -it --expose 443 -l "traefik.enable=true" -l "traefik.tcp.routers.myacme.entrypoints=websecure" -l "traefik.tcp.routers.myacme.rule=HostSNI($MY_DOMAIN_COT)" -l "traefik.tcp.routers.myacme.service=myacme" -l "traefik.tcp.routers.myacme.tls=true" -l "traefik.tcp.routers.myacme.tls.passthrough=true" -l "traefik.tcp.services.myacme.loadbalancer.server.port=443" -v /opt/certs:/opt alpine`  

So this container is monitored by Traefik (`-l "traefik.enable=true"`), but:  
 - `-l "traefik.tcp.routers.myacme.rule=HostSNI($MY_DOMAIN_COT)"` - ensures that all *turn.matrix.example.com:443* requests go to container "acme".  
 Note that this is a *tcp* router, not http or https.  
 - `-l "traefik.tcp.routers.myacme.tls.passthrough=true"` - tells Traefik to ***NOT*** terminate the SSL connection by it, but rather pass it through to "acme"  
 - `--expose 443` - tells docker to expose on the LAN port 443 (normally done automatically as services run, but no service is running on 443)
 - `-v /opt/certs` - we are sharing this folder with "acme" and "coturn"
 - `--network=private` - we have placed this in the isolated network "private" with dockerproxy, because it needs to request a restart of the coTURN container when a new certificate is installed.
 
 ### To install acme.sh
 1. Setup Alpine package manager: `docker exec -ti acme apk update`
 2. Install acme.sh: `docker exec -ti acme apk add --upgrade acme.sh`
 3. Your dockerproxy needs to bee edited to allow acme to request the restart of a container:  
 ```bash
docker stop dockerproxy
docker rm dockerproxy
docker run -d --restart=unless-stopped --privileged --name dockerproxy --network=private -v /var/run/docker.sock:/var/run/docker.sock --expose 2375 --env CONTAINERS=1 --env POST=1 --env ALLOW_RESTART=1 tecnativa/docker-socket-proxy
 ```
 
 
 Before going further, now is a good time to test that port 443, since **openssl** has been installed with the above command.  
 Server side: `docker exec -ti acme openssl s_server -accept 443 -nocert -cipher aNULL`  
 Now on you own machine / client PC: `openssl s_client -connect turn.matrix.example.com:443 -cipher aNULL`  
 Once you have tested that requests are passing direct to your "acme" container, finish requesting the certificates.
 
 
 ### Make the certificates available to "coturn"
 1. See the shell script "certs_acme.sh". This script is meant to automate getting the certificates on the acme container, copying the certificates to where the coTURN container looks for its certificates (the shared volume /opt/certs) and restarting the coTURN container so that the new certificates are used.
 2. Edit the file and place it in /opt/certs (from rancherOS perspective. /opt from acme container perspective).
 3. Test it by running it: `docker exec -ti acme ./opt/certs_acme.sh`
 4. If the above was successful, then certificates have been requested, installed and coTURN has been restarted.
 5. Add the script to the acme container's crontab.

## RancherOS  
### Moving to BurmillaOS
Since RancherOS is no longer beng maintained, it is a huge security risk to continue running it - even though it is such a convenient and nifty OS. Fortunately the chaps have created [BurmillaOS](https://burmillaos.org/), which is provides a community version of good ol' RancherOS. Especially great is the [in situ upgrade](https://burmillaos.org/docs/installation/upgrading/):  
1. `sudo ros config set rancher.upgrade.url https://raw.githubusercontent.com/burmilla/releases/v1.9.x/releases.yml`
2. `sudo ros os upgrade`
3. `sudo ros console switch default`

The only "hiccup" was an error when running docker commands (e.g. docker ps). In my case, it simply required a second reboot.
