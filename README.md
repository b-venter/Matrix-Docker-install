# Matrix-Docker-install
Installing full Matrix, Element (Riot) and coTURN with Docker and Traefik(v2.2)

Jump to:
1. Introduction and overview
2. Docker by means of RancherOS
3. DNS Setup
4. Controlling the Traefik(v2.2)
5. NGINX for web (incl. Element)
6. Postgres db for Matrix
7. Synapse engine
8. Overcoming NAT with coTURN
9. Adding a standalone ACME for non-HTTP certificates

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
 Create A-records (CNAME could also be used) as follows:

IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | matrix.example.com | *Base reference/domain*
203.0.113.5 | synapse.matrix.example.com | *Matrix/Synapse*
203.0.113.5 | element.matrix.example.com | *Nginx*
203.0.113.5 | turn.matrix.example.com | *coTURN*


# 4. Controlling the Traefik(v2.2)
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
