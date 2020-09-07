# Matrix-Docker-install
Installing full Matrix, Element (Riot) and coTURN with Docker and Traefik(v2.2).

Much of what I post here was gained with information from Jon Neverland's posts [here](https://jonnev.se/matrix-homeserver-synapse-v0-99-1-1-with-traefik/), [here](https://jonnev.se/riot-web-for-matrix-with-docker-and-traefik/) and [here](https://jonnev.se/traefik-with-docker-and-lets-encrypt/).

**Jump to:**  
[1. Introduction and overview](#1-introduction-and-overview)  
[2. Docker by means of RancherOS](#2-docker-by-means-of-rancheros)  
[3. DNS Setup](#3-dns-setup)  
[4. Controlling the Traefik(v2.2)](#4-controlling-the-traefikv22)  
[5. NGINX for web (incl. Element)](#5-nginx-for-web-incl-element)  
[6. Postgres db for Matrix](#6-postgres-db-for-matrix)  
[7. Synapse engine](#7-synapse-engine)  
[8. Overcoming NAT with coTURN](#8-overcoming-nat-with-coturn)  
[9. Adding a standalone ACME for non-HTTP certificates](#9-adding-a-standalone-acme-for-non-http-certificates)  
[10. Other references](#10-other-references)  

# 1. Introduction and overview
Using RancherOS gives us a lightweight docker-ready base to work from. Traefik adds easy reverse-proxy and ACME certificate management (once you have conquered Traefik logic), but I have added a stanalone ACME as well - since coTURN is not behind Traefik, has no web service but we need a way to get certificates for TLS.
Behind that runs the typical Matrix setup:
- PostgreSQL
- Synapse
- Nginx serving Synapse and Element
The final piece is only required for voice and video calls: coTURN
Note that this setup does not include federation to otehr matrix servers, but once you have mastered this part, adding federation shouldn't be too hard.

This is diagrammed below:

                          22   (80,443)                (All other ports)
        -------------------|----|-------------------------------|------------------------
                                :           RANCHEROS           |
        ------------------------|-------------------------------|-------------------------
                                :                              /
                                |                             /
                                :                            /
                     [riot]     |             COTURN----<host>
                       NGINX    :               |
                            \   |       (5349, 3478, 63000-63059)
                             \  :  
             [matrix]         \ |                   
              SYNAPSE---------<web>------POSTGRES       
                               / \                  
                              /   \                 
                             /   PROXY[trafik]
                            /  (80,443)
                          ACME        
                                  
                                  
# 2. Docker by means of RancherOS 
[home](#matrix-docker-install)
## With DigitalOcean
Setting up RancherOS is super simple with Digital Ocean:
1. Create droplet > Container distributions > Select RancherOS
2. For a small install, I used 2GB / 1CPU / 50GB SSD / 2TB tansfer option
3. Select datacenter location
4. NB!! Add SSH keys (you can only login to RancherOS with SSH
5. Finish creating your droplet. SSH to it by `ssh rancher@ip.ad.re.ss`

## Bare metal / VirtualBox, etc
An easy guide is found on the Rancher website [here](https://rancher.com/docs/os/v1.x/en/quick-start-guide/) and [here](https://rancher.com/docs/os/v1.x/en/installation/server/install-to-disk/). But it consists of the following:
1. [Download the RancherOS iso](https://rancher.com/rancher-os)
2. Create the **cloud-config.yml** file with the following content:
```
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAA...
``` 
  Note that the file must include the *#cloud-config*. You can find your ssh keys by running the command `cat ~/.ssh/id_rsa.pub`.  
3. Boot from the downloaded RancherOS iso. When it starts up you will be autmatically logged.  
4. Before commencing with the install, copy the **cloud-config.yml** file. I use `wget` to download it from a web server (obviously you would not leave it thereonce you have downloaded it!!).  
5. Now the install can commence. Run `sudo ros install -c cloud-config.yml -d /dev/sda` to install to disk. Once it reboots, you can no longer log in via the console, but need to use SSH (hence the reason you had to copy the file across).
   There are ways of setting a password. Just use Google...
   
## First step - create the network
Use the command `docker network create web` to create the network called "web". (See diagram above).
 
 # 3. DNS Setup 
 [home](#matrix-docker-install)  
 Create A-records (CNAME could also be used) as follows:

IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | matrix.example.com | *Base reference/domain*
203.0.113.5 | synapse.matrix.example.com | *Matrix/Synapse*
203.0.113.5 | element.matrix.example.com | *Nginx*
203.0.113.5 | turn.matrix.example.com | *coTURN*


# 4. Controlling the Traefik(v2.2) 
[home](#matrix-docker-install)
### Setup environment variables
This is to make your life easier. Traefik requires the domain names to be indicated with backticks. If you use a **yml** file, that is no problem, but if you are passing the arguments directly on the command line shell (*which is how I am doing it here*), then the shell will interprest teh backticks. So, rather set them as environment variables, e.g.:
```
export MY_DOMAIN=\`matrix.example.com\`
export MY_DOMAIN_ALT=matrix.example.com
export MY_DOMAIN_SYN=\`synapse.matrix.example.com\`
export MY_DOMAIN_RIO=\`element.matrix.example.com\`
export MY_DOMAIN_COT=\`turn.matrix.example.com\`
```

### Setup Traefik
This [v1-to-v2](https://docs.traefik.io/migration/v1-to-v2/) reference may come in handy to those using <v2.
1. Create the folders and files that will be mounted as volumes to Taefik's container.
```
sudo mkdir /opt/traefik
sudo touch /opt/traefik/acme.json
sudo chmod 600 /opt/traefik/acme.json
sudo vi /opt/traefik/traefik.toml 
```
Add the following code to **traefik.toml**:
```
#TRAEFIK V2

[log]
  level = "DEBUG"

[entryPoints]
  [entryPoints.web]
    address = ":80"
    
    [entryPoints.web.http]
      [entryPoints.web.http.redirections]
        [entryPoints.web.http.redirections.entryPoint]
          to = "websecure"
          scheme = "https"

  [entryPoints.websecure]
    address = ":443"

[providers.docker]
  exposedbydefault = "false"

[certificatesResolvers.letsencrypt.acme]
  email = "test@example.com"
  caServer = "https://acme-staging-v02.api.letsencrypt.org/directory"
  #caServer = "https://acme-v02.api.letsencrypt.org/directory"
  storage = "acme.json"                 
  [certificatesResolvers.letsencrypt.acme.tlsChallenge]
  
[api]
  #dashboard = true
  #insecure = true
```
Let's understand the above code a bit.  
***[Entry Points](https://docs.traefik.io/routing/entrypoints/):*** This assigns ports that Traefik will monitor to a named variable and declare the protocol (by default, TCP). In the above configuration, we have two entry points (Port *80*, TCP belongs to entry point *web*, Port *443*, TCP belongs to entry point *websecure*). In addition, we reroute port *80* to the entry point *"websecure"*. This redirects all HTTP requests to HTTPS.  
***[Providers](https://docs.traefik.io/routing/providers/docker/#configuration-examples):*** Used to help Traefik implement docker provider specifics. Although we are using RancherOS, we are not using Rancher. We are using RancherOS as a lightweight docker host. But our containers are deployed with docker.  
***[ACME](https://docs.traefik.io/https/acme/):*** Used for automatic certificate management. Traefik will apply for and maintain your certificates. My example uses Let's Encrypt. Note that the *staging* server is enabled and the *production* is hashed out. This is to allow you to get the certificates and routing sorted without hitting the *production's* cap. Since we are storing the certificates in an atatched volume, even if you remove and re-add the Traefik container, the certificates will not be automatically deleted.  
***[API](https://docs.traefik.io/operations/api/):*** This provides a web interface which can be useful to understanding how Traefik works, what is running, etc. It is disabled in the above file as I do not recommend using it in production, but feel free to enable it when testing on VirtualBox or similar safe environments. It is reachable on port 8080 by default.  

2. Creating the container
  You can do this using `docker-compose`, but I have opted for full command line to understand options better and provide verbosity. You can easily take these options into a **yaml** file.
  
`docker run -d --restart=unless-stopped --network=web --name=proxy -p 80:80 -p 443:443 -v /var/run/docker.sock:/var/run/docker.sock -v /opt/traefik/traefik.toml:/traefik.toml -v /opt/traefik/acme.json:/acme.json traefik:v2.2 --configFile=/traefik.toml`

  **[docker run](https://docs.docker.com/engine/reference/commandline/run/) options**: You can review all the options, but here is a run down of the most important:  
  `--restart=unless-stopped` - causes the container to start automatically after errors or a reboot of the Host.  
  `--network=web` - attach the container to the network created earlier.  
  `--name=proxy` - the container and process name.  
  `-v` - attach/mount local folders/files to the container.  
  `-p 80:80 -p 443:443` - expose these ports from the host to the container. So anything that reaches the host on ports 80 or 443 will be presented to **proxy** (the name of our Traefik container).  
  `--configFile=/traefik.toml` - Placing an option after the container is specified allows you to pass commands or argumants to it. In this case, we are advising Traefik to read the config file we have mounted to it.  
  Final note: if you want to access the API and have enabled it in the config file, also rememebr to pass '-p 8080:8080' when creating the container.

3. Run `docker ps` to see that it is running, and that the ports have been passed to it.

# 5. NGINX for web (incl. Element) 
[home](#matrix-docker-install)  
## First some prep work
Why are we adding Nginx before Synapse? It gives an easy to use, little config, method to test our Traefik proxy and more.
Let's start with creating the files and volumes for Nginx:  
```
sudo mkdir -p /opt/matrix/nginx/riot
sudo mkdir /opt/matrix/nginx/riot/config
sudo mkdir /opt/matrix/nginx/riot/versions
```
Then download the latest [Element (Riot)](https://github.com/vector-im/riot-web/releases) code. I found that un-tar'ing the code was a mission on RancherOS. So instead I:
1. Downloaded it to my machine, un-tar'ed it and then zip'd it.  
2. Copied the zip to the container (scp) and moved it to **/opt/matrix/nginx/riot/versions**.  
3. `unzip` the compressed files.  

`sudo ln -s /opt/matrix/nginx/riot/versions/riot-v1.7.5-rc.1 /opt/matrix/nginx/riot/riot-web`  
This will allow you change versions merely by updating the symlink.  
```
sudo cp /opt/matrix/nginx/riot/riot-web/config.sample.json /opt/matrix/nginx/riot/config/config.json
sudo vi /opt/matrix/nginx/riot/config/config.json
```
Edit the following code in **config.json** to get Element's setup to synapse prepared:
```
"m.homeserver": {                                  
            "base_url": "https://synapse.matrix.example.com",        
            "server_name": "matrix.example.com"                      
        }
        
"roomDirectory": {                                                
        "servers": [                                                  
            "synapse.matrix.example.com"                                       
        ]                                                             
    }
 ```
 We need to configure Nginx to accept and present Element:
 `sudo vi /opt/matrix/nginx/matrix.conf`  
 Add the following content:
 ```
 server {
  listen        80;
  server_name   $MY_DOMAIN_RIO;
    root /usr/share/nginx/html/;
}
```

## And now for the fun part - adding the docker image!
`docker run -d --restart=unless-stopped --network=web --name=nginx -l "traefik.enable=true" -l "traefik.http.routers.nginx.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)" -l "traefik.http.routers.nginx.entrypoints=web" -l "traefik.http.services.nginx.loadbalancer.passhostheader=true" -l "traefik.http.middlewares.nginx-redirect-websecure.redirectscheme.scheme=https" -l "traefik.http.routers.nginx.middlewares=nginx-redirect-websecure" -l "traefik.http.routers.nginx-websecure.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)" -l "traefik.http.routers.nginx-websecure.tls=true" -l "traefik.http.routers.nginx-websecure.entrypoints=websecure" -l "traefik.http.routers.nginx-websecure.tls=true" -l "traefik.http.routers.nginx-websecure.tls.certresolver=letsencrypt" -v /opt/matrix/nginx/matrix.conf:/etc/nginx/conf.d/matrix.conf -v /opt/matrix/nginx/riot/riot-web:/usr/share/nginx/html/ -v /opt/matrix/nginx/riot/config/config.json:/usr/share/nginx/html/config.json nginx`  
That is a long command, so let's break it down a bit:  
  **docker run** options:  
  1. We also connnect to network "web" created earlier.
  2. We named is "nginx".
  3. We mounted volumes (`-v`).
  4. *And we added labels!* (`-l`)...let's chat about those labels.

**[Traefik and Docker Labels](https://docs.traefik.io/providers/docker/#routing-configuration-with-labels)**
Most use a **docker-compose.yaml**, but to take some of the mystery away from how `dcoker-compose` works, I have presented all as CLI arguments.  
`-l "traefik.enable=true"` - [This](https://docs.traefik.io/routing/providers/docker/#traefikenable) tells Traefik that you container must be evaluated and routes added.  
`-l "traefik.http.routers.nginx.entrypoints=web"` - [This](https://docs.traefik.io/routing/routers/#entrypoints) is used to link an entry port to a router. Note that the name "nginx" is the name of the router and does not have to match the container name (although it oes make life a bit easier).  
`-l "traefik.http.routers.nginx.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)"` - [This](https://docs.traefik.io/routing/routers/#rule) tells Traefik to evaluate the host name (FQDN) that comes on that port. If the name matches this rule, then this router will be used.
   *Note two things:* (1) Unique name, (2)must be in backticks!
 
# 6. Postgres db for Matrix 
[home](#matrix-docker-install)

# 7. Synapse engine 
[home](#matrix-docker-install)

# 8. Overcoming NAT with coTURN 
[home](#matrix-docker-install)

# 9. Adding a standalone ACME for non-HTTP certificates 
[home](#matrix-docker-install)

# 10. Other references
[home](#matrix-docker-install)  
[Postgre and Synapse](https://github.com/matrix-org/synapse/blob/master/docs/postgres.md)
