#!/bin/bash

### This script must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must have root privileges. Type :"
    echo "sudo $0 $@"
    exit 1
fi

### User must belong to group www-data
if id -nG | grep -qw www-data; then
    echo "You must belong to www-data group. Add yourself with :"
    echo "    sudo usermod -a -G www-data $LOGNAME"
    echo "Then log out and log back in so changes are applied."
    echo "Make sure you belong to www-data with :"
    echo "    id -nG | grep www-data"
    exit 1
fi

### Some display functions
printUsage() {
    echo "USAGE :"
    echo "    $(basename $0) -n <vhostName>"
    echo
    echo "Creates a virtual host for Nginx."
    echo
    echo "The name provided with the '-n' argument will be used to access the host through https://vhostName".
    echo "The following actions will be executed :"
    echo
    echo "- create a vhost configuration file for Nginx in /etc/nginx/sites-available"
    echo "- create a link from  /etc/nginx/sites-enabled to this config file"
    echo "- add a line in /etc/hosts to point local host (127.0.0.1) to the vhostName"
    echo "- stop Apache service, start Nginx service, check site access."
    echo
    exit 1
}

printStrAndDots() {
    strLength=${#1}
    dotLength=$((80 - $strLength))
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
    *)
        echo
        printUsage
        exit 1
        ;;
    esac
done
shift "$(($OPTIND - 1))"

if [ -n "$hostName" ]; then
    echo
    echo "|-----------------------------------------------------------"
    echo "| Creating Nginx configuration for host name = $hostName"
    echo "|-----------------------------------------------------------"
    echo
else
    printUsage
    exit 1
fi

#### Set some variables and debug function

# vhost configuration file : WARNING : must end with ".conf" to be loaded by Nginx unless
# specified otherwise in /etc/nginx/nginx.conf
nginxConfig=/etc/nginx/sites-available/$hostName.conf
nginxConfigEnabled=/etc/nginx/sites-enabled/$hostName.conf
nginxConfigCandidate=/etc/nginx/sites-available/$hostName.conf.candidate
wwwDir=/var/www/$hostName

printDebugAndExit() {
    printDebug
    exit 1
}

printDebug() {
    echo
    echo "* The following files may have been modified : enter the following commands to edit them manually :"
    echo
    echo "sudo vim $nginxConfig"
    echo "sudo vim /etc/hosts"
    echo
    echo "* To clean up :"
    echo
    echo "Clean up /etc/hosts : remove this line manually : 127.0.0.1 $hostName"
    echo
    echo "sudo rm $nginxConfig"
    echo "sudo rm $nginxConfigEnabled"
    echo "sudo rm -r $wwwDir"
    echo
}

#### Prerequisites

## Check PHP version
printStrAndDots "Checking if PHP is installed"
phpVersion=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
if [ -z $phpVersion ]; then
    echo "PHP is not installed."
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
#printStrAndDots "Checking /var/www belongs to group www-data"
#if [ "$(stat -c "%G" /var/www)" == "www-data" ]; then
#    echo "yes"
#else
#    echo "no, changing it..."
#    chgrp www-data /var/www
#    exit 1
#fi

#### Create Nginx host config file

printStrAndDots "Creating host configuration in $nginxConfig"

if [ -f $nginxConfig ]; then
    echo "failed !"
    echoError "Error : file $nginxConfig already exists. \nChoose another host name or remove this file manually and run this script again."
    printDebugAndExit
fi

if [ -f $nginxConfigCandidate ] ; then
    rm $nginxConfigCandidate
fi

# create vhost config file

cat >$nginxConfigCandidate <<EOF
server {
  listen 80;
  server_name $hostName;
  index index.html;
  root /var/www/$hostName;
EOF

# append PHP fpm config if PHP is installed
if [ ! -z $phpVersion ]; then
  cat >>$nginxConfigCandidate <<EOF2
  location ~\.php$ {
      include snippets/fastcgi-php.conf;
      fastcgi_pass unix:/var/run/php/php-fpm.sock;
  }
EOF2
fi

# print final brace :
echo "}" >>$nginxConfigCandidate

## Let's print out the config file and ask for user permission before continuing :
#echo
#echo
#echo "Nginx vhost config file candidate :"
#echo "-----------------------------------"
#cat $nginxConfigCandidate
#echo
#echo "Is this correct ?"
#PS3="Type 1, 2 or 3 : "; select yn in "Yes" "No - abort" "Edit file"; do
#    case $yn in
#        "Yes" ) mv $nginxConfigCandidate $nginxConfig; break;;
#        "No - abort" ) echo "Exiting..." ; printDebugAndExit;;
#        "Edit file" ) echo "Make edits to this file manually"; $EDITOR $nginxConfigCandidate; mv $nginxConfigCandidate $nginxConfig; break ;
#    esac
#done
mv "$nginxConfigCandidate" "$nginxConfig"
echo "Done."

## Enable the website
printStrAndDots "Enabling the web site : creating link from sites-available to sites-enabled"
if ln -s $nginxConfig /etc/nginx/sites-enabled/ ; then
    echo "Done."
else
    echoError "Please remove link /etc/nginx/sites-enabled/$nginxConfig and restart this script"
    printDebugAndExit
fi

#### Create web directory


if [ -d $wwwDir ]; then
    echoError "Directory $wwwDir already exists. Remove or rename it before running this script."
    printDebugAndExit
fi

if [ ! -d /var/www ]; then
    echoError "Directory /var/www does not exist. Are you sure Nginx is installed ?"
    printDebugAndExit
fi

printStrAndDots "Creating $wwwDir"
mkdir -p $wwwDir
echo "Done."

printStrAndDots "Changing group to www-data on $wwwDir"
chgrp -R www-data $wwwDir
echo "Done."

printStrAndDots "Changing r/w permissions on $wwwDir (dirs:2750 files:640)"
sudo find $wwwDir -type d -exec chmod 2750 {} \;
sudo find $wwwDir -type f -exec chmod 640 {} \;
echo "Done."

### Create sample test page

indexFilename=$wwwDir/index.html
printStrAndDots "Creating test file : $indexFilename"

echo "Vhost $hostName is setup." >$indexFilename
echo "Modify it under $wwwDir" >>$indexFilename

# not necessary as rights previously set above : chown www-data:www-data $indexFilename

echo "Done."

### Create a line in /etc/hosts
printStrAndDots "Creating a line in /etc/hosts to link localhost to $hostName"
echo "127.0.0.1		$hostName" >>/etc/hosts
echo "Done."

### Stop Apache service
printStrAndDots "Stopping Apache service"
if pidof apache2 >/dev/null; then
    service apache2 stop
    echo "Done."
else
    echo "Not necessary."
fi

### Reload Nginx service to actualize configuration
printStrAndDots "Restarting nginx service"
if systemctl reload-or-restart nginx.service; then
    echo "Done."
else
    echo
    echoError "nginx service cannot be restarted. Check config file : $nginxConfig"
    printDebugAndExit
fi

# Make sure it's active
if systemctl is-active --quiet nginx.service; then
   # ok
else
    echoError "nginx service is not active"
    printDebugAndExit
fi

### Test page
echo
echo "|---------|"
echo "| Testing |"
echo "|---------|"
echo
printStrAndDots "Accessing $hostName with curl"
if [[ $(curl -Is "$hostName" | head -1) == "HTTP/1.1 200 OK" ]] ; then
    echo
    printDebug
    echo
    echo "°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°"
    curl "$hostName"
    echo "°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°"
    echo
    echo "Everything looks good !"
    echo
else
    echoError "Something went wrong... Cannot reach local website at $hostName"
    printDebugAndExit
fi

