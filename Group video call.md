# Intro
Element recently released **[Element Call](https://element.io/blog/introducing-native-matrix-voip-with-element-call/)**, a web app that uses the matrix protocol to setup a group video call. Currently this is not supported by the Element apps (web or mobile) natively, but it certainly seems to be getting closer. What makes it really smart is the fact that even screensharing is supported - and the app is only in beta.  

The challenge is setting up Element Call on your own homeserver. The instructions tend towards those with monolithic installs. But the source code (https://github.com/vector-im/element-call) shows a Dockerfile...which if you have followed the other notes in this repo, is exactly what we are looking for!

## The plan
Currently my setup has gone from the [original](https://github.com/b-venter/Matrix-Docker-install/tree/master#1-introduction-and-overview) to the [hardened setup](https://github.com/b-venter/Matrix-Docker-install/blob/master/Hardening.md#docker-socket-access).  

The container build on the Element Call page houses everything in one container: the application and the web server (NGINX). All communication with the Synapse server takes place through API calls. With that in mind, it will be ideal to (1) have Traefik still terminate TLS connections, and (2) from there route the traffic to our Element Call container:


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
The default app settings point to Element's hosted service. So we need to edit the source files a little bit (yes, I use VI. Yuu can use nano, etc):
```bash
cd element-call
cp config/config.sample.json public/config.json
vi public/config.json
```
Edit the file similar to what you did for Element Web:
>{
>  "default_server_config": {
>      "m.homeserver": {
>            "base_url": "https://synapse.matrix.example.com",
>                  "server_name": "matrix.example.com"
>      }
>    }
> }

Now you need to generate the built bundles for distribution
```bash
yarn
yarn build
```

### Build and export
The files and settings are now ready for our deployment. Time to build. Assuming your present working directory is where the **Dockerfile** is:  
`sudo docker build --tag element_call .`  
- The full stop at the end is important
- If you created a docker group then the sudo may not be necessary.

Once the build completes, give it a test run with `sudo docker run element_call`. While it is running, in a terminal discover the container id with `sudo docker container ls --all`. We need that id to export the container. By the way, you want to choose to save the image rather than export it. Check out this server fault [thread](https://serverfault.com/questions/757210/no-command-specified-from-re-imported-docker-image-container).  

Export the image using `sudo docker export 53942d04560e > element_call.tar`. Copy this file to your RancherOS, BurmillaOS or whatever you are using for your docker setup.

### Import
If you do not have a container registry - like me - you will likely just copy the **tar** file to your server. You can now import it with `docker import --change 'CMD ["nginx","-g","daemon off;"]' /home/rancher/element_call.tar element_call:0.3.4`. The `--change` is necessary as per the server fault link before. Without it, the container will just start and exit when you run it. I recommend adding a version tag in harmony with the release from Element Call's repository. You can confirm that the import was successful with `docker images`.

### Running
As per the [beginning](https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#3-dns-setup), we need to specify a DNS entry to reach the app.  
IP | URL | Service that will be using it
--- | --- | ---
203.0.113.5 | call.matrix.example.com | *Element call*

When that exists and is reachable - even just a 404 is fine - set the FQDN as a envirnment variable: 
```bash
export MY_DOMAIN_CALL=\`call.matrix.example.com\` 
```
Now we can run the container:
`docker run -d --restart=unless-stopped --network=web --name=element_call --expose 8080 -l "traefik.enable=true"  -l "traefik.http.routers.call.rule=Host($MY_DOMAIN_CALL)"  -l "traefik.http.routers.call.entrypoints=web" -l "traefik.http.services.call.loadbalancer.passhostheader=true" -l "traefik.http.middlewares.call-redirect-websecure.redirectscheme.scheme=https" -l "traefik.http.routers.call.middlewares=call-redirect-websecure" -l "traefik.http.routers.call-websecure.rule=Host($MY_DOMAIN_CALL)" -l "traefik.http.routers.call-websecure.entrypoints=websecure" -l "traefik.http.routers.call-websecure.tls=true" -l "traefik.http.routers.call-websecure.tls.certresolver=letsencrypt" element_call:0.3.4`  

Verify that Traefik has the certificate loaded: `sudo cat /opt/traefik/acme.json | grep call` (where *call* is part of the FQDN call.matrix.example.com). If that shows fine and `docker ps` indicates the container is running, browse to the FQDN - which would be https://call.matrix.example.com. No :8080, etc, because that is being handled by Traefik. Login with your Matrix username and password and start a Video call!!

### Updating
Just a few notes for easy reference if you are updating:
 - follow the steps for **Implementation, Customising and Building** with the latest Element Call source
 - backup the old element_call.tar
 - delete the previous image: `docker image ls --all` and `docker image rm ID-OF-OLD-IMAGE`
 - import the new version:
 - `docker import --change 'CMD ["nginx","-g","daemon off;"]' /home/rancher/element_call.tar element_call:x.y.z`
 - stop and delete the current container: `docker stop synapse` and `docker rm synapse`
 - follow the steps in **Running**: export your DNS, run the ontainer

### Allowing dynamic joining of Element Call sessions without having to login
This uses the "guest" login feature. **Note** that to my knowledge it is not currently possible to have guest access enabled without enabling general registration. Which for a private homeserver is not ideal, but the reasons will become apparent soon.

Guest login works by generating a random registration without password. So if `enable_registration` is set to ***false***, then guest login will not work. With that in mind, here are the steps:

**homeserver.yaml**:
1. `enable_registration: true`
2. `enable_registration_without_verification: true`
3. `allow_guest_access: true`
4. `turn_allow_guests: false`

In the video room you created, set the *Room Access* to **Public**.

References:  
https://matrix-org.github.io/synapse/v1.59/usage/configuration/config_documentation.html  
https://matrix.org/docs/guides/creating-a-simple-read-only-matrix-client  
https://matrix.org/blog/2019/11/09/avoiding-unwelcome-visitors-on-private-matrix-servers  
