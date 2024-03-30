# nginx-vhost
Bash script to create quickly a web environment for a local host on Nginx.

## Functionality
Creates a virtual host on the local host (127.0.0.1)
- creates a configuration file in /etc/nginx/sites-available
- creates a link from sites-enabled to that file
- creates a host name in /etc/hosts to point to localhost
- creates a directory under /var/www with the correct permissions
- tests if the new host is reachable with a curl command

## Installation
You can put the script anywhere and run it.

## Usage
In the installation directory, just type :
`sudo ./nginx-vhost -n <hostname>`

## To Do
- add some more checks
- add an option to clean-up lefttovers and/or remove an existing vhost
- ask for confirmation before running touchy commands (like editing the /etc/hosts file)
- make a backup of /etc/hosts before modifying it

