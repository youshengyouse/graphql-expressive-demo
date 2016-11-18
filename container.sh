#!/bin/sh
#
# A control-script for managing the docker-infrastructure components for Intranet
# The first parameter is the action name

action=$1

# All other arguments are parameters
if [ "$#" -gt "1" ]; then
shift
parameters=$@
fi

# Paths
SCRIPTNAME=$(basename $0)
SCRIPTPATH=$(readlink -f "$0" 2>/dev/null)
if [ "$?" != 0 ]; then
    if [ ! -f "docker-compose.yml" ]; then
	>&2 echo " The $SCRIPTNAME-script will only work if you execute it from the project directory itself."
	exit 1
    fi
    SCRIPTPATH="$(pwd -P)/$SCRIPTNAME"
fi
PROJECTPATH=$(dirname "$SCRIPTPATH")

# Switch into the project directory
cd $PROJECTPATH

# Mandatory Tools
DOCKER="$(which docker)"
if [ -z "$DOCKER" ];
then
    echo "'docker' was not found on your system." >&2
    exit 1
fi

DOCKERCOMPOSE=$(which docker-compose)
if [ -z "$DOCKERCOMPOSE" ];
then
    echo "'docker-compose' was not found on your system." >&2
    exit 1
fi

# Utils
XARGS="$(which xargs)"
GREP="$(which grep)"
SED="$(which sed)"

#########################################################################
# Get the full container name for the given container type (e.g. "php")
# Arguments:
#  CONTAINER_TYPE
# Returns:
#  The full name of the (first) container with the given type
#########################################################################

getContainerNameByType() {
    # abort if no type is specified
    local CONTAINER_TYPE="$1"
    if [ -z "$CONTAINER_TYPE" ];
    then
        echo "No container type specified. Please specifiy a container type (e.g. php, installer, mysql, nginx, ...)."  >&2
        return 1
    fi

    # check if xargs is available
    if [ -z "$XARGS" ];
    then
        echo "The tool 'xargs' was not found on your system." >&2
        return 1
    fi

    # check if grep is available
    if [ -z "$GREP" ];
    then
        echo "The tool 'grep' was not found on your system." >&2
        return 1
    fi

    # check if sed is available
    if [ -z "$SED" ];
    then
        echo "The tool 'sed' was not found on your system." >&2
        return 1
    fi

    local containerName=$("$DOCKER" ps -q | "$XARGS" "$DOCKER" inspect --format '{{.Name}}' | "$GREP" "$CONTAINER_TYPE" | "$SED" 's:/::' | "$GREP" "$CONTAINER_TYPE_1")
    echo $containerName
    return 0
}

executeComposer() {
    local containerType="web"
    local containerName=$(getContainerNameByType $containerType)
    if [ -z "$containerName" ];
    then
        echo "Cannot determine the name of the container." >&2
        return 1
    fi

    "$DOCKER" exec $containerName /var/www/html/composer.phar --working-dir="/var/www/html" $@
    return 0
}

executePhp() {
    local containerType="web"
    local containerName=$(getContainerNameByType $containerType)
    if [ -z "$containerName" ];
    then
        echo "Cannot determine the name of the container." >&2
        return 1
    fi

    "$DOCKER" exec $containerName /usr/local/bin/php -f $@
    return 0
}

executePhpDebug() {
    local containerType="web"
    local containerName=$(getContainerNameByType $containerType)
    if [ -z "$containerName" ];
    then
        echo "Cannot determine the name of the container." >&2
        return 1
    fi
    #php -r 'echo E_ALL & ~E_NOTICE & ~E_WARNING;' => 32757
    #per eseguire il debug è necessario settare come remote host il gateway di docker
    #https://sandro-keil.de/blog/2015/10/05/docker-php-xdebug-cli-debugging/
    "$DOCKER" exec -u "$DEVUSER" $containerName /usr/local/bin/php -d xdebug.remote_host=172.17.0.1 -d error_reporting=32757 -f $@
    return 0
}

enterContainer() {
    local containerType="$1"
    if [ -z "$containerType" ];
    then
        echo "No container type specified. Please specifiy a container type (e.g. php, installer, mysql, nginx, ...)."  >&2
        return 1
    fi

    local containerName=$(getContainerNameByType $containerType)
    if [ -z "$containerName" ];
    then
        echo "Cannot determine the name of the container." >&2
        return 1
    fi

    "$DOCKER" exec -ti $containerName bash
    return 0
}

start() {
    "$DOCKERCOMPOSE" up -d && "$DOCKERCOMPOSE" logs
}

stop() {
    "$DOCKERCOMPOSE" stop
}

restart() {
    "$DOCKERCOMPOSE" restart
}

status() {
    "$DOCKERCOMPOSE" ps
}

stats() {
    # check if sed is available
    if [ -z "$SED" ];
    then
        echo "Stats requires 'sed'. The tool was not found on your system." >&2
        return 1
    fi
    echo "$DOCKER"
    "$DOCKER" ps -q | "$XARGS" "$DOCKER" inspect --format '{{.Name}}' | "$SED" 's:/::' | "$XARGS" "$DOCKER" stats
}

composer() {
    executeComposer $parameters
}

php() {
    executePhp $parameters
}

debug() {
    executePhpDebug $parameters
}

enter() {
    enterContainer $parameters
}

destroy() {
    "$DOCKERCOMPOSE" stop
    "$DOCKERCOMPOSE" rm --force
}

case "$action" in
    start)
    start
    ;;

    stop)
    stop
    ;;

    restart)
    restart
    ;;

    status)
    status
    ;;

    stats)
    stats
    ;;

    composer)
    composer
    ;;

    php)
    php
    ;;

    debug)
    debug
    ;;

    enter)
    enter
    ;;

    destroy)
    destroy
    ;;

    *)
    echo "usage : $0 start|stop|restart|status|stats|magerun|composer|php|debug|enter|destroy
  start      Starts the docker containers (and triggers the
             installation if magento is not yet installed)
  stop       Stops all docker containers
  restart    Restarts all docker containers
  status     Prints the status of all docker containers
  stats      Displays live resource usage statistics of all containers
  composer   Executes composer in the application root directory
  php        Execute php cli from container
  debug      Debug php cli from container
  enter      Enters the bash of a given container type (e.g. php, mysql)
  destroy    Stops all containers and removes all data
"
    ;;
esac

exit 0                                                                 
