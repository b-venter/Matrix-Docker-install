# Matrix user password
This well documented by [Matrix](https://github.com/matrix-org/synapse#password-reset). I am adding this purely because I am not that familiar with Potsgres.

## Create a hash of the new / reset password, using the Synapse tool:
```
docker exec -ti synapse bash
hash_password
New password:
Confirm password:
$S@O$mernandomgibberishforthehashwhichyoumustcopy
exit
```
*Copy the hash before exiting.*

## Change the password in the database:
`docker exec -it postgres psql -U synapse`  
`\c matrix` (connect to matrix database)  
```
UPDATE users SET password_hash='$S@O$mernandomgibberishforthehashwhichyoumustcopy'
    WHERE name='@user:matrix.example.com';
```
`\q` (exit)  

Password has been reset!
