# Keeping containers updated
* Always take a snapshot (to allow for rollback)  
* [Setup environment variables](https://github.com/b-venter/Matrix-Docker-install#setup-environment-variables)  

## RancherOS / BurmillaOS
1. `sudo ros os list`
2. `sudo ros os upgrade`
3. Restart when prompted

## Updating Synapse  
1. `docker stop synapse` (where "synapse" is the name of your matrix server contaner)
2. `docker rm synapse` (delete container)
3. `docker pull matrixdotorg/synapse` (pull latest container image)
4. [Create new container] (https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#7-synapse-engine)
5. Test by loading https://synapse.matrix.example.com/  
6. Can also test https://matrix.example.com/_matrix/federation/v1/version

## Updating Traefik
1. `docker stop proxy`
2. `docker rm proxy`
3. `docker pull traefik:v2.3` (Always specify a version, rather than using 'latest', which might introduce incompatabilities)
4. [Create container](https://github.com/b-venter/Matrix-Docker-install/blob/master/README.md#setup-traefik)
5. If using **tecnativa**, [add to the second network.](https://github.com/b-venter/Matrix-Docker-install/blob/master/Hardening.md#traefik---docker-socket-via-proxy)
6. Test by perusing `docker logs proxy`, https://synapse.matrix.example.com, https://element.matrix.example.com, etc.

## Update Element web server
### Website update
1. `cd /opt/matrix/nginx/riot/versions`
2. Get the latest Element web: sudo wget https://github.com/vector-im/element-web/releases/download/v1.9.7/element-v1.9.7.tar.gz
3. Extract: sudo tar -xvzf element-v1.9.7.tar.gz and then remove sudo rm element-v1.9.7.tar.gz
4. Remove the old symlink: `sudo rm /opt/matrix/nginx/riot/riot-web`
5. Add new symlink: sudo ln -s /opt/matrix/nginx/riot/versions/element-v1.9.7 /opt/matrix/nginx/riot/riot-web (This will allow you change versions merely by updating the symlink.)
6. `docker restart nginx`
7. Test by loading https://element.matrix.example.com.

### NGINX Container update

## Update ACME
1. docker exec -ti acme apk -U upgrade

## Update PostgreSQL
*Currently in progress. Not tested yet.  
With PostgreSQL 9.6 support being [droppped](https://matrix.org/blog/2021/11/30/synapse-1-48-0-released), it is time to get out of my comfort zone and upgrade my DB*  
1. Ensure Synapse is on 1.48 or close (in this example, it must be new enough to support PostgreSQL 14)
2. Create a new directory so that two pg databases can co-exist: `sudo mkdir -p /opt/matrix/pgdata14`
3. Create a parallel pg database ([like in the setup](https://github.com/b-venter/Matrix-Docker-install#6-postgres-db-for-matrix), but:
   - remember to export your [ENV variables] (https://github.com/b-venter/Matrix-Docker-install#setup-environment-variables) and take a snapshot beforehand.
   - use docker postgreSQL image of v14.
   - mount the independent volume */opt/matrix/pgdata14*
   - use a new name for the container
   - the password for your postgres can be the same as the old pg, or new. Later we will update Synapse config anyway.
   - `docker run -d --restart=unless-stopped --network=web --name=postgres14 -v /opt/matrix/pgdata14:/var/lib/postgresql/data -l "traefik.enable=false" --env POSTGRES_PASSWORD=SameMassivelyLongPassword --env POSTGRES_USER=synapse postgres:14`
4. Stop synapse so that there are no new events, etc being sent to DB. e.g. `docker stop synapse`
5. Dump db from old pg to new pg ([reference](https://davejansen.com/how-to-dump-and-restore-a-postgresql-database-from-a-docker-container/))
   - `docker exec -i postgres /bin/bash -c "PGPASSWORD=pg_password pg_dump --username synapse matrix" | docker exec -i postgres14 /bin/bash -c "PGPASSWORD=pg_password psql --username synapse matrix"`
6. Now we edit Synapse's config file: `sudo vi /opt/matrix/synapse/homeserver.yaml`, go to the **database** entries and update the ***host*** to the new pg container (e.g. postgres14). Note: update password if changed.
7. `docker start synapse`

Hope that works. Should be testing it soon. But if it fails, here is the rollback:
1. `docker stop synapse`
2. `sudo vi /opt/matrix/synapse/homeserver.yaml` an restore the old pg database host (and password if needed).
3. `docker start synapse`
