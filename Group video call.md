# Intro
Element recently released **[Element Call](https://element.io/blog/introducing-native-matrix-voip-with-element-call/)**, a web app that allows uses the matrix protocol to setup a group video call. Currently this is not supported by the Element apps (web or mobile) natively, but it certainly seems to be getting closer. What makes it really smart is the fact that even screensharing is supported - and the app is only in beta.  

The challenge is setting up Element Call for yourself. The instructions are basic and tends towards those with monolithic installs. But the source code (https://github.com/vector-im/element-call) shows a Dockerfile...which if you have followed the other notes in the repo, is exactly what we are looking for!

## The plan
Currently my setup has gone from the [original](https://github.com/b-venter/Matrix-Docker-install/tree/master#1-introduction-and-overview) to the [hardened setup](https://github.com/b-venter/Matrix-Docker-install/blob/master/Hardening.md#docker-socket-access).  

The container build on the Element Call page houses everything in one container: the application and the web server (NGINX). All communication witht he Synapse server takes place through API calls. With that in mind, it will be ideal to (1) have Traefik still terminate TLS connections, and (2) from there route the traffic to our Element Call container:


                  22   (80,443)                (All other ports)
    -------------------|----|-------------------------------|------------------------
                            :           RANCHEROS           |      [docker.sock]
    ------------------------|-------------------------------|----------|--------------
                            :                              /           |
                            |                            /             |
                            :             COTURN----<host>             |
                 [riot]     |       (5349, 3478, 63000-63059)          |      
                   NGINX    :                                          |
                        \   |  ELEMENT_CALL                            |
                         \  :  /                                       |
         [matrix]         \ | /                                (2375)  |
          SYNAPSE---------<web>------PROXY[traefik]           DOCKERPROXY
                           /         (80,443) \                   /
                          /                    \                 /
                         /                      \---<private>---/
                        /                       /
                   POSTGRES                    /
                                            ACME(443)-optional
                                            


  
## Implementation
Get a local copy of the source code using `git clone https://github.com/vector-im/element-call.git`.  

### Customising
The default app settings point to Element's hosted service. So we need to edit the source files a little bit. Edit **~/scripts/dockerbuild.sh** and change `DEFAULT_HOMESERVER` (I changed mine to *synapse.matrix.example.com*, but just *matrix.example.com* should work fine too) and `PRODUCT_NAME` (this is just the title of the web app page).  

We may also need to edit the **~/Dockerfile**. For example, I am not running [buildx](https://docs.docker.com/buildx/working-with-buildx/), so I needed to remove the `--platform=$BUILDPLATFORM` entry.

### Build and export
The file settings are now ready for our deployment. Time to build. Assuming your present working directory is where the **Dockerfile** is:  
`sudo docker build --tag element_call .`  
- The full stop at the end is important
- If you created a docker group then the sudo may not be necessary.

Once the build completes, give it a test run with `sudo docker run element_call`. While it is running, in a terminal discover the container id with `sudo docker container ls --all`. We need that id to export the container. By the way, you want to choose to save the image rather than export it. Check out this server fault [thread](https://serverfault.com/questions/757210/no-command-specified-from-re-imported-docker-image-container).  

Export the image using `sudo docker export 53942d04560e > element_call.tar`. Copy this file to your RancherOS, BurmillaOS or whatever you are using for your docker setup.

### Import
If you do not have a container registry - like me - you will likely just copy the **tar** file to your server. You can now import it with `docker import --change 'CMD ["nginx","-g","daemon off;"]' /home/rancher/element_call.tar element_call:latest`. The `--change` is necessary as per the server fault link before. Without it, the container will just start and exit when you run it. You can confirm that the import was successful with `docker images`.

### Running
As per the [beginning](https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#3-dns-setup), we need to specify a DNS entry to reach the app.  
IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | call.matrix.example.com | *Element call*

When that exists and is reachable - even just a 404 is fine - set the FQDN as a envirnment variable: `export MY_DOMAIN_CALL=\`call.matrix.example.com\`. Now we can run the container:
```bash
docker run -d --restart=unless-stopped --network=web --name=element_call --expose 8080 -l "traefik.enable=true"  -l "traefik.http.routers.call.rule=Host($MY_DOMAIN_CALL)"  -l "traefik.http.routers.call.entrypoints=web" -l "traefik.http.services.call.loadbalancer.passhostheader=true" -l "traefik.http.middlewares.call-redirect-websecure.redirectscheme.scheme=https" -l "traefik.http.routers.call.middlewares=call-redirect-websecure" -l "traefik.http.routers.call-websecure.rule=Host($MY_DOMAIN_CALL)" -l "traefik.http.routers.call-websecure.entrypoints=websecure" -l "traefik.http.routers.call-websecure.tls=true" -l "traefik.http.routers.call-websecure.tls.certresolver=letsencrypt" element_call
```
Verify that Traefik has the certificate loaded: `sudo cat /opt/traefik/acme.json | grep call`. If that shows fine and `docker ps` indicates the container is running, browse to the FQDN. Login with your Matrix username and password and start a Video call!!
