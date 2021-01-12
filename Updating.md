#Updating Synapse
1. Take a snapshot (to allow for rollback)
2. [Setup environment variables](https://github.com/b-venter/Matrix-Docker-install#setup-environment-variables)
3. `docker stop synapse` (where "synapse" is the name of your matrix server contaner)
4. `docker rm synapse` (delete container)
5. `docker pull matrixdotorg/synapse` (pull latest container image)
6. [Create new container] (https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#7-synapse-engine)
7. Test by loading https://synapse.matrix.example.com/
