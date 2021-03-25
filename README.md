# Matrix homeserver with Docker and Traefik(2.2)
[Dockerising](https://www.docker.com/) a full [Matrix](https://matrix.org/) server with [Element (Riot)](https://element.io/) messaging, [coTURN](https://github.com/coturn/coturn) NAT traversal and [Traefik(v2.2)](https://traefik.io/traefik/) proxy on [RancherOS](https://rancher.com/docs/os/v1.x/en/) and [Digital Ocean](https://www.digitalocean.com/).

Much of what I post here was gained with information from Jon Neverland's posts [here](https://jonnev.se/matrix-homeserver-synapse-v0-99-1-1-with-traefik/), [here](https://jonnev.se/riot-web-for-matrix-with-docker-and-traefik/) and [here](https://jonnev.se/traefik-with-docker-and-lets-encrypt/).

#### Contents:
1. [Introduction and overview](#1-introduction-and-overview)  
2. [Docker by means of RancherOS](#2-docker-by-means-of-rancheros)  
3. [DNS Setup](#3-dns-setup)  
4. [Controlling the Traefik(v2.2)](#4-controlling-the-traefikv22)  
5. [NGINX for web (incl. Element)](#5-nginx-for-web-incl-element)  
6. [Postgres db for Matrix](#6-postgres-db-for-matrix)  
7. [Synapse engine](#7-synapse-engine)  
8. [Overcoming NAT with coTURN](#8-overcoming-nat-with-coturn)  
9. [Adding a standalone ACME for non-HTTP certificates](#9-adding-a-standalone-acme-for-non-http-certificates)  
10. [Other references](#10-other-references)  

# 1. Introduction and overview
Using RancherOS gives us a lightweight docker-ready base to work from. Traefik adds easy reverse-proxy and ACME certificate management (once you have conquered Traefik logic). I also added a standalone ACME - since coTURN is not behind Traefik, has no web service but needs a certificate for TLS.
Behind Traefik runs the typical Matrix setup:
- PostgreSQL
- Synapse
- Nginx serving Synapse and Element pages
The final piece is only required for voice and video calls: coTURN
~~Note that this setup does not include federation to other matrix servers, but once you have mastered this part, adding federation shouldn't be too hard.~~

This is diagrammed below:
```
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
                                  
```

# 2. Docker by means of RancherOS 
[home](#contents)  
## With DigitalOcean
Setting up RancherOS is super simple with Digital Ocean:
1. Create droplet > Container distributions > Select RancherOS
2. For a small install, I used 2GB / 1CPU / 50GB SSD / 2TB tansfer option
3. Select datacenter location
4. NB!! Add SSH keys (you can only login to RancherOS with SSH trusted keys)
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
  Note that the file must include the *#cloud-config*. You can find your local machine's ssh keys by running the command `cat ~/.ssh/id_rsa.pub`.  
3. Boot from the downloaded RancherOS iso. When it starts up you will be automatically logged in.  
4. Before commencing with the install, copy the **cloud-config.yml** file. I use `wget` to download it from a web server (obviously you would not leave it there once you have downloaded it!!).  
5. Now the install can commence. Run `sudo ros install -c cloud-config.yml -d /dev/sda` to install to disk. Once it reboots, you can no longer log in via the console, but need to use SSH (hence the reason you had to copy the file across).
   There are ways of setting a password. Just use Google...
   
#### First step - create the network
Use the command `docker network create web` to create the network called "web". (See diagram above).
 
 # 3. DNS Setup 
 [home](#contents)  
 Create A-records (CNAME could also be used) as follows:

IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | matrix.example.com | *Base reference/domain*
203.0.113.5 | synapse.matrix.example.com | *Matrix/Synapse*
203.0.113.5 | element.matrix.example.com | *Nginx*
203.0.113.5 | turn.matrix.example.com | *coTURN*


# 4. Controlling the Traefik(v2.2) 
[home](#contents)  
### Setup environment variables
This is to make your life easier. Traefik requires the domain names to be indicated with backticks. If you use a **yml** file, that is no problem, but if you are passing the arguments directly on the command line shell (*which is how I am doing it here*), then the shell will interpret the backticks and break things. So, rather set them as environment variables e.g.:
```
export MY_DOMAIN=\`matrix.example.com\`
export MY_DOMAIN_ALT=matrix.example.com
export MY_DOMAIN_SYN=\`synapse.matrix.example.com\`
export MY_DOMAIN_RIO=\`element.matrix.example.com\`
export MY_DOMAIN_COT=\`turn.matrix.example.com\`

echo $MY_DOMAIN
```

### Setup Traefik
This [v1-to-v2](https://docs.traefik.io/migration/v1-to-v2/) reference may come in handy to those used to <v2.
1. Create the folders and files that will be mounted as volumes to Traefik's container.
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
***[Entry Points](https://docs.traefik.io/routing/entrypoints/):*** This assigns ports that Traefik will monitor to a named variable and declare the protocol (by default, TCP). In the above configuration, we have two entry points (Port *80*, TCP belongs to entry point *web*, Port *443*, TCP belongs to entry point *websecure*). In addition, we redirect port *80* to the entry point *"websecure"*. This redirects all HTTP requests to HTTPS.  
***[Providers](https://docs.traefik.io/routing/providers/docker/#configuration-examples):*** Used to help Traefik implement docker provider specifics. Although we are using RancherOS, we are not using Rancher. We are using RancherOS as a lightweight docker host. But our containers are deployed with docker.  
***[ACME](https://docs.traefik.io/https/acme/):*** Used for automatic certificate management. Traefik will apply for and maintain your certificates. My example uses Let's Encrypt. Note that the *staging* server is enabled and the *production* is hashed out. This is to allow you to get the certificates and routing sorted without hitting the *production's* cap. Since we are storing the certificates in an attached volume, even if you remove and re-add the Traefik container, the certificates will not be automatically deleted.  
***[API](https://docs.traefik.io/operations/api/):*** This provides a web interface which can be useful to understanding how Traefik works, what is running, etc. It is disabled in the above file as I do not recommend using it in production, but feel free to enable it when testing on VirtualBox or similar safe environments. It is reachable on port 8080 by default.  


2. Creating the container
  You can do this using `docker-compose`, but I have opted for full command line to understand the options better and provide verbosity. You can easily take these options into a **yaml** file.
  
`docker run -d --restart=unless-stopped --network=web --name=proxy -p 80:80 -p 443:443 -v /var/run/docker.sock:/var/run/docker.sock -v /opt/traefik/traefik.toml:/traefik.toml -v /opt/traefik/acme.json:/acme.json traefik:v2.2 --configFile=/traefik.toml`

  **[docker run](https://docs.docker.com/engine/reference/commandline/run/) options**: You can review all the options, but here is a run down of the most important:  
  `--restart=unless-stopped` - causes the container to start automatically after errors or a reboot of the Host.  
  `--network=web` - attach the container to the network created earlier.  
  `--name=proxy` - the container and process name.  
  `-v` - attach/mount local folders/files to the container.  
  `-p 80:80 -p 443:443` - expose these ports from the host to the container. So anything that reaches the host on ports 80 or 443 will be presented to **proxy** (the name of our Traefik container).  
  `--configFile=/traefik.toml` - Placing an option after the container allows you to pass commands or arguments to it. In this case, we are advising Traefik to read the config file we have mounted to it.  
  Final note: if you want to access the API and have enabled it in the config file, also rememebr to pass '-p 8080:8080' when creating the container.

3. Run `docker ps` to see that it is running, and that the ports have been passed to it.

# 5. NGINX for web (incl. Element) 
[home](#contents)  
### First some prep work
Why are we adding Nginx before Synapse? It gives an easy to use, little config, method to test our Traefik proxy and more.
Let's start with creating the files and volumes for Nginx:  
```
sudo mkdir -p /opt/matrix/nginx/riot
sudo mkdir /opt/matrix/nginx/riot/config
sudo mkdir /opt/matrix/nginx/riot/versions
```
Then download the latest [Element (Riot)](https://github.com/vector-im/riot-web/releases) code. I found that un-tar'ing the code was a mission on RancherOS. So instead:
1. Download it to my local machine, un-tar it and then zip it.  
2. Copy the zip to the container (e.g. scp) and move it to **/opt/matrix/nginx/riot/versions**.  
3. `unzip` the compressed files.  

`sudo ln -s /opt/matrix/nginx/riot/versions/riot-v1.7.5-rc.1 /opt/matrix/nginx/riot/riot-web`  
This will allow you change versions merely by updating the symlink.  
```
sudo cp /opt/matrix/nginx/riot/riot-web/config.sample.json /opt/matrix/nginx/riot/config/config.json
sudo vi /opt/matrix/nginx/riot/config/config.json
```
Edit the following code in **config.json** to get Element's setup to Synapse prepared:
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
  listen        80 default_server;
  server_name   matrix.example.com;
```
We also need it to server the Matrix server status page:  
```
# Traefik -> nginx -> synapse
 location /_matrix {
    proxy_pass http://synapse:8008;
    proxy_set_header X-Forwarded-For $remote_addr;
    client_max_body_size 128m;
  }
 }
```
And then reference the Element web page (for https://element.matrix.example.com)
```
server {
  listen        80;
  server_name   element.matrix.example.com;
    root /usr/share/nginx/html/;
}
```

### [Adding the well-known URI](https://github.com/matrix-org/synapse/blob/master/INSTALL.md#client-well-known-uri)  
This will make it easier for client applications to locate your server:  
`sudo mkdir -p /opt/matrix/nginx/www/.well-known/matrix`
`sudo vi /opt/matrix/nginx/www/.well-known/matrix/server`
```
{
  "m.server": "synapse.matrix.example.com:443"
}
```
`sudo vi /opt/matrix/nginx/www/.well-known/matrix/client`
```
{
  "m.homeserver": {
    "base_url": "https://matrix.example.com"
  }
}
```
The matrix.conf file will need the following added after `location /_matrix {...}` part of the file:
```
 location /.well-known/matrix/ {
    root /var/www/;
    default_type application/json;
    add_header Access-Control-Allow-Origin  *;
  }
```

Here is a full example of the matrix.conf file:
```
server {
  listen         80 default_server;
  server_name    matrix.example.com;

 # Traefik -> nginx -> synapse
 location /_matrix {
    proxy_pass http://synapse:8008;
    proxy_set_header X-Forwarded-For $remote_addr;
    client_max_body_size 128m;
  }

  location /.well-known/matrix/ {
    root /var/www/;
    default_type application/json;
    add_header Access-Control-Allow-Origin  *;
  }
  
}

server {
  listen        80;
  server_name   element.matrix.example.com;
    root /usr/share/nginx/html/;
}
```

### And now for the fun part - adding the docker image!
`docker run -d --restart=unless-stopped --network=web --name=nginx -l "traefik.enable=true" -l "traefik.http.routers.nginx.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)" -l "traefik.http.routers.nginx.entrypoints=web" -l "traefik.http.services.nginx.loadbalancer.passhostheader=true" -l "traefik.http.middlewares.nginx-redirect-websecure.redirectscheme.scheme=https" -l "traefik.http.routers.nginx.middlewares=nginx-redirect-websecure" -l "traefik.http.routers.nginx-websecure.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)" -l "traefik.http.routers.nginx-websecure.entrypoints=websecure" -l "traefik.http.routers.nginx-websecure.tls=true" -l "traefik.http.routers.nginx-websecure.tls.certresolver=letsencrypt" -v /opt/matrix/nginx/matrix.conf:/etc/nginx/conf.d/matrix.conf -v /opt/matrix/nginx/riot/riot-web:/usr/share/nginx/html/ -v /opt/matrix/nginx/riot/config/config.json:/usr/share/nginx/html/config.json -v /opt/matrix/nginx/www:/var/www nginx`  
That is a long command, so let's break it down a bit:  
  **docker run** options:  
  1. We also connnect it to network "web" created earlier.
  2. We named is "nginx".
  3. We mounted volumes (`-v`).
  4. *And we added labels!* (`-l`)...let's chat about those labels.

**[Traefik and Docker Labels](https://docs.traefik.io/providers/docker/#routing-configuration-with-labels)**
Most use a **docker-compose.yaml**, but to take some of the mystery away from how `dcoker-compose` works, I have presented all as CLI arguments.  
`-l "traefik.enable=true"` - [This](https://docs.traefik.io/routing/providers/docker/#traefikenable) tells Traefik that you container must be evaluated and routes added.  
`-l "traefik.http.routers.nginx.entrypoints=web"` - [This](https://docs.traefik.io/routing/routers/#entrypoints) is used to link an entry port to a router. Note that the name "nginx" is the name of the router and does not have to match the container name (although it does make life a bit easier).  
`-l "traefik.http.routers.nginx.rule=Host($MY_DOMAIN) || Host($MY_DOMAIN_RIO)"` - [This](https://docs.traefik.io/routing/routers/#rule) tells Traefik to evaluate the host name (FQDN) that comes on that port. If the name matches this rule, then this router will be used. `&&` for AND, `||` for OR.  
   *Note two things:* (1) The Host name must be unique to the rule. (2) It must be in **[backticks](#setup-environment-variables)!**  
`-l "traefik.http.services.nginx.loadbalancer.passhostheader=true"` - [This](https://docs.traefik.io/routing/services/#pass-host-header) tells the service attached to the router (used to be known as the *backend*) to pass the Host Header to the container this label is attached to.  
- So as a summary at this point, we have used a number of labels to say: "Watch port 80 for Host X or Host Y, and pass on the Header".  

The *middleware* can be used to process  data between the Entry point /Rule and Service. In this case, we use it to redirect all HTTP traffic to HTTPS.

The `nginx-websecure` labels follow the same rules, but note the following:  
`-l "traefik.http.routers.nginx-websecure.tls=true"` - enables TLS options for the Traefik router "nginx-websecure". It iwll also terminate TLs, meaning it will pass non-TLS traffic to the container unless specified otherwise.  
`-l "traefik.http.routers.nginx-websecure.tls.certresolver=letsencrypt"` - as a further option, Traefik is told to manage the certificate from the ACME specified in [the config file](#setup-traefik) (here the *letsencrypt* value matches the acme value *letsencrypt*.acme).  
- These two labels are responsible for mannaging certificates. Of which domains? Those mentioned in the Host(?) rules. If there is a && or ||, all Host names will be included in the single certificate requested: in the [SAN](https://docs.traefik.io/https/acme/#domain-definition).  

**Test** by opening the URL to http://element.matrix.example.com. For errors, run `docker logs proxy` or `docker logs nginx`.  Your test should reveal:
1. That http is redirected to htttps
2. The certificate is from Let's Encrypt staging ("FAKE")[See link](https://letsencrypt.org/docs/staging-environment/#root-certificate)
3. And Nginx is serving your web page.

***If all is good:***
 * Stop the container for Traefik (`docker stop proxy`)
 * Edit the traefik.toml (`sudo vi /opt/traefik/traefik.toml`)
 * Hash-out the staging CA and uncomment the production CA server.
 * Delete, recreate and chmod **acme.json** file to remove the test certificates
 * Start Traefik (`docker start proxy`)
 * Reload your page and you should have a valid certificate.
 
# 6. Postgres db for Matrix 
[home](#contents)  
Matrix requires a database to store conversations, etc. You can use the built in sqlite, but for production you really want PostgreSQL in place.

1. Generate a secure password (e.g with [APG](https://software.opensuse.org/package/apg))
2. Create the docker container: `docker run -d --restart=unless-stopped --network=web --name=postgres -v /opt/matrix/pgdata:/var/lib/postgresql/data -l "traefik.enable=false" --env POSTGRES_PASSWORD=SomeMassivelyLongPassword --env POSTGRES_USER=synapse postgres:9.6.4`
3. A database is created, but not with the specifications we want, so:
 * Connect to the container's psql with the user you specified in 'POSTGRES_USER': `docker exec -it postgres psql -U synapse`
 * Create a suitable database (change the DATABASE name and OWNER as per your install, or just use as I did):
 ```
 CREATE DATABASE matrix
 ENCODING 'UTF8'
 LC_COLLATE='C'
 LC_CTYPE='C'
 template=template0
 OWNER synapse;
 ```
 * `\q` - to quit
 
 So now we have a database ready to connect to. And note that it is not (1) exposed to the host network (`-p`), nor (2) is Traefik proxying anything for it (`traefik.enable=false`).

# 7. Synapse engine 
[home](#contents)  
Now for the heart of our project - [Synapse](https://matrix.org/).

`docker run -d --restart=unless-stopped --network=web --name=synapse -l "traefik.enable=true" -l "traefik.http.routers.synapse.rule=Host($MY_DOMAIN_SYN)" -l "traefik.http.services.synapse.loadbalancer.server.port=8008" -l "traefik.http.middlewares.synapse-redirect-websecure.redirectscheme.scheme=https" -l "traefik.http.routers.synapse.middlewares=synapse-redirect-websecure" -l "traefik.http.routers.synapse-websecure.rule=Host($MY_DOMAIN_SYN)" -l "traefik.http.routers.synapse-websecure.tls=true" -l "traefik.http.routers.synapse-websecure.entrypoints=websecure" -l "traefik.http.routers.synapse-websecure.tls=true" -l "traefik.http.routers.synapse-websecure.tls.certresolver=letsencrypt" -v /opt/matrix/synapse:/data  matrixdotorg/synapse`

Most  of the data here is by now easy to understand from the aforementioned facts. However, note the following:  
`-l "traefik.http.services.synapse.loadbalancer.server.port=8008"` - we tellTraefik to redirect / reverse proxy from 80 and 443 to Synapse's 8008 port.  

Next, we need to generate Synapse's  config file:  
`docker run -v /opt/matrix/synapse:/data --rm  -e SYNAPSE_SERVER_NAME=matrix.example.com -e SYNAPSE_REPORT_STATS=yes matrixdotorg/synapse generate`

Edit the file: `sudo vi /opt/matrix/synapse/homeserver.yaml` to have the following data reflected:
```
server_name: "matrix.example.com"
use_presence: true
listeners:
  - port: 8008
    tls: false
    bind_addresses: ['0.0.0.0']
    type: http
    x_forwarded: true

    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2 
  args:
    user: synapse
    password: SomeMassivelyLongPassword
    database: matrix
    host: postgres

enable_registration: true

max_upload_size: "100M"


```
* You can choose to enable presence or not by setting to "true" or "false".  
* Since it's running in a container we need to listen to 0.0.0.0. The port is only exposed on the host and put behind reverse proxy.
* *psycopg2* is a python postgres connector that needs to be specified as it.
* User and Password was specified when creating the [PostgreSQL container](https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#6-postgres-db-for-matrix).
* The database 'host' parameter refers to the host/container name of the PostgreSQL container.  
* Set the maximum allowable size for attachments (photos, video clips, etc)

**Nginx** needs to be updated `sudo vi /opt/matrix/nginx/matrix.conf` by prepending the following:
```
server {
  listen         80 default_server;
  server_name    matrix.example.com;

 # Traefik -> nginx -> synapse
 location /_matrix {
    proxy_pass http://synapse:8008;
    proxy_set_header X-Forwarded-For $remote_addr;
    client_max_body_size 128m;
  }
  
}
```
This allows requests to *synapse.matrix.example.com:443* to be proxied to the synapse container, port 8008.

Restart all affected containers:
* `docker restart nginx`
* `docker restart synapse`

You can toggle the *enable_registration* option to control when / if people can create an account. Just restart the *synapse* container to re-read the config.

**Time to test:** Load the synapse.matrix.exmple.com URL - you should get a confirmation page that matrix is up and running. Then load the Element URL (element.matrix.example.com) and choose "Create Account". You will either be able to create an account or will get a message saying "Registration is disabled".


# 8. Overcoming NAT with coTURN 
[home](#contents)  
At this point you should have been able create accounts, login with the app and send messages. And if you are on the same network, calling will also work. But calling to fellow accounts on different networks will be a problem. Enter coTURN...

*client1*<---|--RTP--|-->TURN_SERVER<----|---RTP--|--->*client2*

coTURN does not reside on the "web" network. Because of issues encountered with port forwarding, I have installed it direct on the ["host" network](https://docs.docker.com/network/host/).


`sudo mkdir -p /opt/certs`  
`sudo mkdir -p /opt/coturn`  
`sudo vi /opt/coturn/turnserver.conf`  

Add the following to the file:
```
listening-port=3478
tls-listening-port=5349
#As a test, you can leave listening-ip out and see with "docker logs coturn" what coturn auto detects.
listening-ip=203.0.113.5
external-ip=203.0.113.5
min-port=63000
max-port=63059
use-auth-secret
static-auth-secret=AgainCreatedByAPasswordGenerator

realm=turn.matrix.example.com
user-quota=12
total-quota=1200
no-tcp-relay

# Hash out certs initially to test standard tcp connection.
# TLS certificates, including intermediate certs.
# For Let's Encrypt certificates, use `fullchain.pem` here.
#cert=/opt/turn.matrix.example.com/fullchain.cer
# TLS private key file
#pkey=opt/turn.matrix.example.com/turn.matrix.example.com.key

stdout
no-cli

denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
```
Now to install the coTURN container:  
`docker run -d --restart=unless-stopped --network=host --name=coturn -v /opt/coturn/turnserver.conf:/etc/turnserver.conf -v /opt/certs:/opt -v /opt/coturn/pcap:/tmp instrumentisto/coturn -c /etc/turnserver.conf`
 * This has no labels for Traefik since we are not using Traefik to proxy anything for it.

#### Integrate with SYNAPSE
`sudo vi /opt/matrix/synapse/homeserver.yaml`  
Edit the following area:
```
## Turn ##
turn_uris: [ "turn:turn.matrix.example.com?transport=tcp", "turns:turn.matrix.example.com?transport=tcp" ]
turn_shared_secret: "AgainCreatedByAPasswordGenerator"
turn_user_lifetime: 86400000
turn_allow_guests: true
```
And restart synapse container to update the config: `docker restart synapse`  
*You will also need to force close and re-open your Element client (web/Android/iOS) to read the updated config*

#### Enabling TLS
1. See [Standalone ACME](#9-adding-a-standalone-acme-for-non-http-certificates) regarding getting certificates.
2. Remove the hashes in `sudo vi /opt/matrix/synapse/homeserver.yaml` for TLS
```
# For Let's Encrypt certificates, use `fullchain.pem` here.
cert=/opt/turn.matrix.example.com/fullchain.cer
# TLS private key file
pkey=opt/turn.matrix.example.com/turn.matrix.example.com.key
```
3. You can force only TLS communication in the same file by changing the TURN URI to only use Secure TURN (default port of TURNS is 5349):
```
turn_uris: [ "turns:turn.matrix.example.com?transport=tcp" ]
```
Remember to restart synapse: `docker restart synapse` and to force restart your Element app.  
***NOTE:** WebRTC and COTURN have issues on Android and iOS with TLS on TURN when using Let's Encrypt. The media of WebRTC is encrypted regardless, but some signalling is present on standard TCP/UDP. While this bug exists, calls via TURNS might not work. See [Open issues](#webrtc-and-coturn).*

# 9. Adding a standalone ACME for non-HTTP certificates 
[home](#contents)  
coTURN offers TLS and DTLS to further protect the already encrypted WebRTC. However this requires a certificate, for which we have the following limitations: 
 * We can't use port 80 and 443 because Traefik controls those, but does not control TLS for coTURN
 * Most ACME agents need to use either port **80** or **443**.

The solution is:
1. To have a container whose port 443 is passed directly to it from Traefik using coTURN's URL (*turn.matrix.example.com*).
2. To share the certificates with coTURN container via a shared volume since they do not share network "web".

To accomplish this, we use a standard **Alpine** image, and install **acme.sh** on it:  
`docker run -d --restart=unless-stopped --network=web --name=acme -it --expose 443 -l "traefik.enable=true" -l "traefik.tcp.routers.myacme.entrypoints=websecure" -l "traefik.tcp.routers.myacme.rule=HostSNI($MY_DOMAIN_COT)" -l "traefik.tcp.routers.myacme.service=myacme" -l "traefik.tcp.routers.myacme.tls=true" -l "traefik.tcp.routers.myacme.tls.passthrough=true" -l "traefik.tcp.services.myacme.loadbalancer.server.port=443" -v /opt/certs:/opt alpine`  

So this container is monitored by Traefik (`-l "traefik.enable=true"`), but:  
 - `-l "traefik.tcp.routers.myacme.rule=HostSNI($MY_DOMAIN_COT)"` - ensures that all *turn.matrix.example.com:443* requests go to container "acme".  
 Note that this is a *tcp* router, not http or https.  
 - `-l "traefik.tcp.routers.myacme.tls.passthrough=true"` - tells Traefik to ***NOT*** terminate the SSL connection by it, but rather pass it through to "acme"  
 - `--expose 443` - tells docker to expose on the LAN port 443 (normally done automatically as services run, but no service is running on 443)
 - `-v /opt/certs` - we are sharing this folder with "acme" and "coturn"
 
 #### To install acme.sh
 1. Setup Alpine package manager: `docker exec -ti acme apk update`
 2. Install acme.sh: `docker exec -ti acme apk add --upgrade acme.sh`
 
 
 Before going further, now is a good time to test that port 443, since **openssl** has been installed with the above command.  
 Server side: `docker exec -ti acme openssl s_server -accept 443 -nocert -cipher aNULL`  
 Now on you own machine / client PC: `openssl s_client -connect turn.matrix.example.com:443 -cipher aNULL`  
 Once you have tested that requests are passing direct to your "acme" container, finish requesting the certificates.
 
 3. `docker exec -ti acme acme.sh --issue --alpn -d turn.matrix.example.com`
 
 #### Make the certificates available to "coturn"
 1. `docker exec -ti acme mkdir -p /opt/turn.matrix.example.com`
 2. `docker exec -ti acme sh`
 3. `cp /root/.acme.sh/turn.matrix.example.com/fullchain.cer /opt/turn.matrix.example.com/`
 4. `cp /root/.acme.sh/turn.matrix.example.com/turn.matrix.example.com.key  /opt/turn.matrix.example.com/`
 *You will need to restart your "coturn" container to detect the new certificates.*  
 `docker logs coturn` will show whether coTURN has detected and accepted the certificate and key.

# 10. Other references
[home](#contents)  
[Postgre and Synapse](https://github.com/matrix-org/synapse/blob/master/docs/postgres.md)  
[TURN Server example](https://www.informaticar.net/install-turn-server-for-synapse-matrix-on-centos-rhel/)  
[Matrix guides](https://matrix.org/docs/develop/)  
[coturn github](https://github.com/coturn/coturn/wiki/turnserver)  
[Synapse and TURN](https://github.com/matrix-org/synapse/blob/master/docs/turn-howto.md)  
[Traefik v1 to v2](https://docs.traefik.io/migration/v1-to-v2/)  
[Synapse on Docker](https://github.com/matrix-org/synapse/blob/master/docs/turn-howto.md)  

# 11. Open issues
#### WebRTC and coTURN
https://bugs.chromium.org/p/webrtc/issues/detail?id=11710&q=label%3AEngTriaged  
https://groups.google.com/g/discuss-webrtc/c/4MmARU0XYqc?pli=1  
https://github.com/vector-im/riot-android/issues/3299  

