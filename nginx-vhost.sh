#!/bin/bash

### This script must be run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must have root privileges. Type :"
   echo "sudo $0 $@" 
   exit 1
fi

### User must belong to group www-data
if [ $(groups | grep www-data) ]; then
   echo "You must belong to www-data group. Add yourself with :"
   echo "    sudo usermod -a -G www-data $LOGNAME"
   echo "Then log out and log back in so changes are applied."
   echo "Make sure you belong to www-data with :" 
   echo "    groups"
   exit 1
fi

### Some useful functions
printUsage() {
    echo "USAGE :"
    echo "    $(basename $0) -n <vhostName>"
    echo 
    echo "Creates a virtual host for Nginx."
    echo "The name provided with the '-n' argument will be used to access the host through https://vhostName".
    echo "The following actions are executed :"
    echo "- create a vhost configuration file for Nginx in /etc/nginx/sites-available"
    echo "- create a link from  /etc/nginx/sites-enabled to this config file"
    echo "- add a line in /etc/hosts to point local host (127.0.0.1) to the vhostName"
    exit 1
}

printStrAndDots() {
    strLength=${#1}
    dotLength=$((80-$strLength))
    printf "%s " "$1"
    printf '%0.s.' $(seq 1 $dotLength)
    printf " "
    sleep 0.5
}

echoError() {
    echo ""
    echo "******************** ERROR ********************"
    printf "$1\n"
    echo "***********************************************"
}

### Parse command line arguments 

while getopts 'n:' opt; do
  case "$opt" in
    n)
      # Check if the next argument exists and does not start with a '-'
      if [ -n "$OPTARG" ] && [[ $OPTARG != -* ]]; then
        hostName="$OPTARG"
      else
        # If the next argument is another option or doesn't exist, 
        # reset the index so that getopts processes it correctly
        OPTIND=$((OPTIND - 1))
      fi
      ;;
  esac
done
shift "$(($OPTIND -1))"

if [ -n "$hostName" ]; then
    echo "Creating Nginx configuration for host name = $hostName"
    echo "============================================================"
else
    printUsage
    exit 1
fi

#### Set some variables and debug function

nginxConfig=/etc/nginx/sites-available/$hostName
wwwDir=/var/www/$hostName

printDebug() {
    echo 
    echo "The following files will be modified : enter the following commands to edit them manually :"
    echo "sudo vim $nginxConfig"
    echo "sudo vim /etc/hosts"
    echo "* To clean up host definition :"
    echo "sudo rm $nginxConfig"
    echo "sudo rm /etc/nginx/sites-enabled/$hostName"
    echo "sudo rm -r $wwwDir"
    echo "* Remove this line from /etc/hosts : 127.0.0.1 $hostName"
    echo "grep $hostName /etc/hosts"
    echo "sudo head -n -1 /etc/hosts > tmp.txt && mv tmp.txt /etc/hosts" 
    echo "-------------------------------------------------------------"
    echo ""
}

printDebug

#### Prerequisites

## Check PHP version
printStrAndDots "Checking if PHP is installed"
phpVersion=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
if [ -z $phpVersion ]; then
    echoError "PHP is not installed. Install php before running this script."
    exit 1
else
    echo "yes : PHP version = $phpVersion"
fi

## Check nginx is installed 
printStrAndDots "Checking Nginx is installed"
nginxVersion=$(nginx -v |& awk '{print $3}')
if [ -z $nginxVersion ]; then
    echo "no !"
    echoError "Nginx is not installed. Install nginx before running this script."
    exit 1
else
    echo "yes : Nginx version = $nginxVersion"
fi

### /var/www must belong to www-data:www-data
printStrAndDots "Checking /var/www belongs to www-data:www-data"
if [ "$(stat -c "%U %G" /var/www)" == "www-data www-data" ]; then
    echo "yes"
else
    echo "no !"
    echoError "Error : change ownership of /var/www to user and group www-data\n(using 'sudo chown -R www-data:www-data /var/www')"
    exit
fi


#### Create Nginx host config

printStrAndDots "Creating host configuration in /etc/nginx/sites-available/$hostName"

if [ ! -f $nginxConfig ]; then
    cat > $nginxConfig << EOF 
server {
    listen 80;
    server_name $hostName;
    index index.html;
    root /var/www/$hostName;
    location ~\.php$ { 
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock; 
    }
}
EOF
    ## Enable the website
    ln -s $nginxConfig /etc/nginx/sites-enabled/
    echo "Done."
else
    echo "failed !"
    echoError "Error : file $nginxConfig already exists. \nChoose another host name or remove this file manually and run this scipt again."
    exit 1
fi

#### Create web directory

printStrAndDots "Creating www directory : $wwwDir"

if [ -d $wwwDir ] ; then
    echo "failed !"
    echoError "Directory $wwwDir already exists. Remove or ename it before running this script."
    exit 1
else
    if [ -d /var/www ] ; then
        mkdir -p $wwwDir
        chown www-data:www-data $wwwDir
        echo "Done."
    else
        echo
        echoError "Directory /var/www does not exist. Are you sure Nginx is installed ?"
        exit 1
    fi
fi

### Create sample test page

indexFilename=$wwwDir/index.html
printStrAndDots "Creating test file : $indexFilename"

echo "Vhost $hostName is setup." > $indexFilename
echo "Modify it under $wwwDir" >> $indexFilename

chown www-data:www-data $indexFilename

echo "Done."

### Create a line in /etc/hosts
printStrAndDots "Creating a line in /etc/hosts to link localhost to $hostname"
echo "127.0.0.1		$hostName" >> /etc/hosts;
echo "Done."

### Stop Apache service
printStrAndDots "Stopping Apache service"
if pidof apache2 > /dev/null
then
    service apache2 stop
    echo "Done."
else
    echo "No apache2 process found, service is already stopped."
fi

### Reload Nginx service to actualize configuration
printStrAndDots "Restarting nginx service .... "
if [ $(service nginx reload) ]; then
    echo 
    echoError "nginx service cannot be restarted. Check config file : $nginxConfig"
    exit 1
else
    echo "Done."
fi

### Test page
echo "Testing :"
echo "---------"
curl http://$hostName &>/dev/null
status=$?
echo "Status = $status"
if [ -z $status ]; then
    echoError "Something went wrong... Cannot reach local website at http://$hostName"
    exit 1
else
    curl http://$hostName
    echo "Everything seems good !"
fi

