# Keeping containers updated
Always take a snapshot (to allow for rollback)
[Setup environment variables](https://github.com/b-venter/Matrix-Docker-install#setup-environment-variables)

## Updating Synapse  
1. `docker stop synapse` (where "synapse" is the name of your matrix server contaner)
2. `docker rm synapse` (delete container)
3. `docker pull matrixdotorg/synapse` (pull latest container image)
4. [Create new container] (https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#7-synapse-engine)
5. Test by loading https://synapse.matrix.example.com/

## Updating Traefik
1. `docker stop proxy`
2. `docker rm proxy`
3. `docker pull traefik:v2.3` (Always specify a version, rather than using 'latest', which might introduce incompatabilities)
4. [Create container](https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#setup-traefik)
5. If using **tecnativa**, [add to the second network.](https://github.com/b-venter/Matrix-Docker-install/blob/master/Hardening.md#traefik---docker-socket-via-proxy)
6. Test by perusing `docker logs proxy`, https://synapse.matrix.example.com, https://element.matrix.example.com, etc.
