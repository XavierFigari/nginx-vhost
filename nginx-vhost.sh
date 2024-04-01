#!/bin/bash

# nginx-vhost.sh

# This Bash script creates a virtual host that can be ran by Nginx/php-fpm in a local development environment.
# It creates the necessary files and hooks that enable Nginx to route "http://hostname" http requests
# to a simple web site created in /var/www/hostname.
# As this involves many steps that may fail depending on your Nginx and PHP installation, many verifications are
# made along the script. I may have missed some of them, please feel free to report any bugs.
# Because this script is modifying files under /etc and /var, it must be ran with root privileges.

# This is free and open source software.

# TO DO :
#
# - allow user to choose php-fpm version. For now, the 'fastcgi_pass' directive in the server configuration
# points to a generic "unix:/var/run/php/php-fpm.sock" file, that should normally be a link to the last
# version of PHP installed on the system. I haven't made any check on that.
# - add some checks on PHP execution. For now, I only check HTML execution.

# Author : Xavier Figari, april 2024.

# Enable debug mode by running your script as TRACE=1 ./script.sh instead of ./script.sh
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

# COLOR                   #  RGB
#BLACK="$(tput setaf 0)"   #  0, 0, 0
#GREEN="$(tput setaf 2)"   #  0,max,0
#YELLOW="$(tput setaf 3)"  #  max,max,0
#BLUE="$(tput setaf 4)"    #  0,0,max
#MAGENTA="$(tput setaf 5)" #  max,0,max
#CYAN="$(tput setaf 6)"    #  0,max,max
#WHITE="$(tput setaf 7)"   #  max,max,max

RED="$(tput setaf 1)"     #  max,0,0
NOCOLOR="$(tput sgr0)"

################################################################################
### This script must be run with root privileges
################################################################################
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error:${NOCOLOR} This script must be run with root privileges. Type :"
    echo "sudo $0 $@"
    exit 1
fi

################################################################################
### User must belong to group www-data
################################################################################
# Well, technically not for running this script, but necessary afterwards.
if id -nG | grep -qw www-data; then
    echo "You must belong to www-data group. Add yourself with :"
    echo "    sudo usermod -a -G www-data $LOGNAME"
    echo "Then log out and log back in so changes are applied."
    echo "Make sure you belong to www-data with :"
    echo "    id -nG | grep www-data"
    exit 1
fi

################################################################################
### Some display functions
################################################################################

printUsage() {
    echo
    echo $(basename $0)
    echo
    echo "USAGE :"
    echo "    $(basename $0) -n <vhostName>"
    echo
    echo "DESCRIPTION :"
    echo
    echo "    Creates a virtual host for Nginx, accessible through https://vhostName"
    echo
    echo "    The following actions will be executed :"
    echo
    echo "    - create a vhost configuration file for Nginx in /etc/nginx/sites-available/vhostName.conf"
    echo "    - create a link from  /etc/nginx/sites-enabled to this config file"
    echo "    - add a line in /etc/hosts to resolve vhostName to local host (127.0.0.1)"
    echo "    - stop Apache service (if running, to avoid conflicts on port 80), start Nginx service"
    echo "    - test if site is reachable and returns HTTP 200 status."
    echo
    exit 1
}

printStrAndDots() {
    strLength=${#1}
    dotLength=$((80 - $strLength))
    printf "%s " "$1"
    printf '%0.s.' $(seq 1 $dotLength)
    printf " "
    # sleep 0.3
}

function box_out() {
    # Nice function from https://unix.stackexchange.com/questions/70615/bash-script-echo-output-in-box#70616
    local s=("$@") b w
    for l in "${s[@]}"; do
        ((w < ${#l})) && {
            b="$l"
            w="${#l}"
        }
    done
    tput setaf 3
    echo "
+-${b//?/-}-+
| ${b//?/ } |"
    for l in "${s[@]}"; do
        printf '| %s%*s%s |\n' "$(tput sgr 0)" "-$w" "$l" "$(tput setaf 3)"
    done
    echo "| ${b//?/ } |
+-${b//?/-}-+"
    tput sgr 0
}

function echoError() {
    echo
    local s="$*"
    tput setaf 1
    echo "+-${s//?/-}-+
| ${s//?/ } |
| $(tput setaf 5)$s$(tput setaf 1) |
| ${s//?/ } |
+-${s//?/-}-+"
    tput sgr 0
}

################################################################################
### Parse command line arguments
################################################################################

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
    box_out "Creating Nginx configuration for host name = $hostName"
    echo
else
    printUsage
    exit 1
fi

################################################################################
### Set some variables and functions
################################################################################

# vhost configuration file : WARNING : must end with ".conf" to be loaded by Nginx
# unless specified otherwise in /etc/nginx/nginx.conf
nginxConfig=/etc/nginx/sites-available/$hostName.conf
nginxConfigEnabled=/etc/nginx/sites-enabled/$hostName.conf
nginxConfigCandidate=/etc/nginx/sites-available/$hostName.conf.candidate
wwwDir=/var/www/$hostName

backup_dir=/etc/hosts_backup

mkbackupdir() {
    if [[ ! -d "${backup_dir}" ]]; then
        mkdir 2>/dev/null "${backup_dir}"
    fi
}

backupEtcHosts() {
    mkbackupdir
    NOW=$(date +"%Y-%m-%d_%Hh%Mm%Ss")
    cp -p /etc/hosts $backup_dir/hosts-${NOW}
}

cleanup() {
    mkbackupdir
    NOW=$(date +"%Y-%m-%d_%Hh%Mm%Ss")
    cp -p /etc/hosts $backup_dir/hosts-${NOW}
    grep -v $hostName $backup_dir/hosts-${NOW} >/etc/hosts
    echo -e "\n/etc/hosts cleaned up. Backups are in $backup_dir"

    rm $nginxConfig
    echo -e "Removed $nginxConfig"
    rm $nginxConfigEnabled
    echo -e "Removed $nginxConfigEnabled"
    rm -r $wwwDir
    echo -e "Removed $wwwDir"
}

printDebugAndExit() {
    printDebug
    read -r -p "Do you want me to clean up modified files before exiting (y/n) ? " -n1 answer 2>&1 || :
    if [[ "${answer}" == "y" ]]; then
        echo
        cleanup
    fi
    echo -e "\nExiting..."
    echo
    exit 1
}

printDebug() {
    echo
    echo "---------------------------------------------------------------------------------------------------"
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
    echo "---------------------------------------------------------------------------------------------------"
    echo
}

################################################################################
### Test if PHP and Nginx are installed
################################################################################

## Check PHP version
printStrAndDots "Checking if PHP is installed"
phpVersion=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
if [ -z $phpVersion ]; then
    echo "PHP is not installed."
else
    echo "yes : PHP version = $phpVersion"
fi

## Check nginx is installed
printStrAndDots "Checking if Nginx is installed"
nginxVersion=$(nginx -v |& awk '{print $3}')
if [ -z $nginxVersion ]; then
    echo "no !"
    echoError "Nginx is not installed. Install nginx before running this script."
    exit 1
else
    echo "yes : Nginx version = $nginxVersion"
fi

################################################################################
### Create Nginx host config file
################################################################################

printStrAndDots "Creating host configuration in $nginxConfig"

if [ -f $nginxConfig ]; then
    echo "failed !"
    echoError "Error : file $nginxConfig already exists."
    printDebugAndExit
fi

if [ -f $nginxConfigCandidate ]; then
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

# append php-fpm/fastcgi basic config if PHP is installed
if [ ! -z $phpVersion ]; then
    cat >>$nginxConfigCandidate <<EOF2
    location ~\.php$ {
        fastcgi_param SCRIPT_FILENAME "$document_root$fastcgi_script_name";
        fastcgi_param QUERY_STRING    "$query_string";
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }
EOF2
fi

# print final curly brace :
echo "}" >>$nginxConfigCandidate

## Let's print out the config file and ask for user permission before continuing :
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

################################################################################
## Enable the website
################################################################################
printStrAndDots "Enabling the web site : creating link from sites-available to sites-enabled"
if ln -s $nginxConfig /etc/nginx/sites-enabled/; then
    echo "Done."
else
    echoError "Please remove link /etc/nginx/sites-enabled/$nginxConfig and restart this script"
    printDebugAndExit
fi

################################################################################
## Create web directory in /var/www
################################################################################

if [ -d $wwwDir ]; then
    echoError "Directory $wwwDir already exists. Remove or rename it before running this script."
    printDebugAndExit
fi

if [ ! -d /var/www ]; then
    echoError "Directory /var/www does not exist. Are you sure Nginx is installed ?"
    printDebugAndExit
fi

printStrAndDots "Creating $wwwDir"
mkdir $wwwDir
echo "Done."


################################################################################
### Create sample test page
################################################################################
# Don't bother with HTML tags, a simple text is enough. It simplifies testing.
# Note : a php test page should be made too to verify php-fpm !

indexFilename=$wwwDir/index.html
printStrAndDots "Creating test file : $indexFilename"

echo "$hostName" >$indexFilename
echo "If you see this message, it means Nginx was able" >>$indexFilename
echo "to route http://$hostName to $wwwDir" >>$indexFilename
echo "You can now modify your web site under $wwwDir" >>$indexFilename

echo "Done."

################################################################################
### Set rwx permissions
################################################################################
# let's assume the user who's running this script (with sudo) should be the owner of files and dirs in /var/www
# In a future version, an option should be added to set the user.
runningUser=${SUDO_USER:-${USER}}
printStrAndDots "Changing owner and group of $wwwDir to $runningUser:www-data"
chown -R $runningUser:www-data $wwwDir
echo "Done."

# let's set permissions as follows :
# - user  : rwx (7) on dirs, rw- (6) on files : can modify dirs and files
# - group : r-x (5) on dirs, r-- (4) on files : group is www-data : can only read
# - other : --- (0) on dirs, --- (0) on files : no permissions at all
# On top of that, set the GUID bit (2) so that files created inside will inherit group www-data
printStrAndDots "Changing r/w permissions on $wwwDir (dirs:2750 files:640)"
sudo find $wwwDir -type d -exec chmod 2750 {} \;
sudo find $wwwDir -type f -exec chmod 640 {} \;
echo "Done."

################################################################################
### Create a line in /etc/hosts
################################################################################
printStrAndDots "Creating a line in /etc/hosts to link localhost to $hostName"
# as a precaution, backup the hosts file before touching it.
backupEtcHosts
# Create a simple link from hostName to localhost :
echo "127.0.0.1		$hostName" >>/etc/hosts
echo "Done."

################################################################################
### Stop Apache service if it's running
################################################################################
printStrAndDots "Stopping Apache service"
if pidof apache2 >/dev/null; then
    service apache2 stop
    echo "Done."
else
    echo "Not necessary."
fi

################################################################################
### Reload Nginx service to actualize configuration
################################################################################
printStrAndDots "Restarting nginx service"
if ! systemctl reload-or-restart nginx.service; then
    echo
    echoError "nginx service cannot be restarted. Check config file : $nginxConfig"
    printDebugAndExit
fi

# Make sure it's active
if systemctl is-active --quiet nginx.service; then
    echo "Done. Active."
else
    echo
    echoError "Nginx service is not active, it could not be restarted. Check /var/log/nginx/error.log"
    printDebugAndExit
fi

################################################################################
### Final test
################################################################################

printStrAndDots "Accessing $hostName with curl"

# Get the first line of "curl -Is", that should start with the HTTP response. Remove trailing Carriage Return.
curlResponse=$(curl -Is $hostName | head -1 | sed 's/\r//')

# If we get an "HTTP/1.1 200 OK" response, we're on the right track !
if [[ $curlResponse = "HTTP/1.1 200 OK" ]]; then
    # One last check : the page content should start with our host name (because we wrote it above)
    # If it doesn't, it means that Nginx was unable to parse the vhost config file,
    # and does not redirect http request to the right /var/www/hostname root.
    if [[ $(curl $hostName 2>/dev/null | head -1 | sed 's/\r//') == $hostName ]]; then
        echo
        # printDebug
        echo
        # Display web page in green :
        tput setaf 2
        echo "°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°"
        curl "$hostName"
        echo "°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°°"
        echo
        echo "Everything looks good !"
        echo
        tput sgr 0
    else
        echoError "Server $hostName can be reached, but doesn't redirect to $wwwDir"
        echo
        echo "This might be due to an error in the Nginx config file : $nginxConfig"
        echo "Run 'curl $hostName' manually and check for errors in /var/log/nginx/error.log"
        printDebugAndExit
    fi
else
    echoError "Something went wrong... Cannot reach local website at $hostName"
    echo
    echo "What you can do :"
    echo "- check file and dir permissions under $wwwDir"
    echo "- make sure /etc/hosts contains '127.0.0.1 $hostName'"
    echo "- check nginx error log : tail /var/log/nginx/error.log"
    echo
    printDebugAndExit
fi
