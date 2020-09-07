# Matrix-Docker-install
Installing full Matrix, Element (Riot) and coTURN with Docker and Traefik(v2)

Jump to:
1. Introduction and overview
2. Docker by means of RancherOS
3. DNS Setup
4. Controlling the Traefik(v2)
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
 ... Note that the file must include the *#cloud-config*. You can find your ssh keys by running the command `cat ~/.ssh/id_rsa.pub`.
 3. Boot from the downloaded RancherOS iso. When it starts up you will be autmatically logged.
 4. Before commencing with the install, copy the **cloud-config.yml** file. I use `wget` to download it from a web server (obviously you would not leave it thereonce you have downloaded it!!).
 5. Now the install can commence. Run `sudo ros install -c cloud-config.yml -d /dev/sda` to install to disk. Once it reboots, you can no longer log in via the console, but need to use SSH (hence the reason you had to copy the file across).
 ... There are ways of setting a password. Just use Google...
 
 # 3. DNS Setup
 Create A-records (CNAME could also be used) as follows:

IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | matrix.example.com | *Base reference/domain*
203.0.113.5 | synapse.matrix.example.com | *Matrix/Synapse*
203.0.113.5 | element.matrix.example.com | *Nginx*
203.0.113.5 | turn.matrix.example.com | *coTURN*


# 4. Controlling the Traefik(v2)
## Setup environment variables
This is to make your life easier. Traefik requires the domain names to be indicated with backticks. If you use a **yml** file, that is no problem, but if you are passing the arguments directly on the command line shell (*which is how I am doing it here*), then the shell will interprest teh backticks. So, rather set them as environment variables, e.g.:
```
export MY_DOMAIN=\`matrix.example.com\`
export MY_DOMAIN_ALT=matrix.example.com
export MY_DOMAIN_SYN=\`synapse.matrix.example.com\`
export MY_DOMAIN_RIO=\`element.matrix.example.com\`
export MY_DOMAIN_COT=\`turn.matrix.example.com\`
```
