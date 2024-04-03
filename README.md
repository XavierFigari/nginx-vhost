# nginx-vhost

Bash script to create a virtual host configuration for Nginx web server.
If a PHP installation is found, il also creates a basic fastcgi config for php files. For now, the 'fastcgi_pass' directive in the server configuration points to a generic "unix:/var/run/php/php-fpm.sock" file, that should normally be a link to the last version of PHP installed on the system. Future versions will allow to choose a specific php-fpm socket.

After creation, the web site is available on http://hostname and can be edited in /var/www/hostname 

Files permissions in /var/www are set to the bare minimum : files owned and writable only by the user, group www-data so that Nginx can read, and no permissions for other.

## Functionality
Creates an Nginx virtual host running on localhost (127.0.0.1)
- creates a configuration file in /etc/nginx/sites-available (with PHP basic config if found)
- creates a link from sites-enabled to that file
- creates a host name in /etc/hosts to point to localhost. A backup is done in /etc/hosts_backup/.
- creates a directory under /var/www with the appropriate permissions
- tests if the new host is reachable with a curl command

### Permissions in /var/www
By default, the following permissions are applied to the newly created folder in /var/www/hostname :
- change user to the user that runs the script with sudo (not root). A future version will allow to set owner user with an argument.
- change group of files and directories to www-data (to enable Nginx to read them)

The access rights are set this way :
```
- user  : rwx (7) on dirs, rw- (6) on files : can modify dirs and files`
- group : r-x (5) on dirs, r-- (4) on files : group is www-data : can only read
- other : --- (0) on dirs, --- (0) on files : no permissions at all
```
On top of that, set the SGID bit (2) so that files created inside will inherit group www-data

## Installation
You can put the script anywhere and run it with root privileges.

## Usage
In the installation directory, just type :

`sudo ./nginx-vhost.sh -n <hostname>`

## To Do
- add some more checks
- add an option to choose a specific PHP version
- test php fastcgi connection
- add an option to select the user that owns /var/www/hostname (default : calling user $SUDO_USER)
- add an option to clean-up lefttovers and/or remove an existing vhost (already implemented in case an error is found while running the script, but it would be nice to call it with a specific option).
- adapt it to Apache
