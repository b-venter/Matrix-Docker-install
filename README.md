# Matrix-Docker-install
Installing full Matrix, Element (Riot) and coTURN with Docker and Traefik(v2)

Jump to:
1. Introducction and overview
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
An easy guide is found on the Rancher website [here](https://rancher.com/docs/os/v1.x/en/quick-start-guide/) and [here](https://rancher.com/docs/os/v1.x/en/installation/server/install-to-disk/)
But it consists of the following:
1. [Download the RancherOS iso](https://rancher.com/rancher-os)
2. Create the **cloud-config.yml** file with the following content:
```
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAA...
``` 
 ... Note that the file must include the *#cloud-config*. You can find your ssh keys by running the command `cat ~/.ssh/id_rsa.pub`.
 3.
