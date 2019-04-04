#!/bin/bash

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\e[33m'
NC='\033[0m'

INFO="${CYAN}[info]${NC}"
WARN="${YELLOW}[warning]${NC}"
FATAL="${RED}[fatal]${NC}"

NETWORK_NAME=wp-dev-instances
export DOCKER_BRIDGE_IP=$(docker network inspect bridge -f '{{ (index .IPAM.Config 0).Gateway }}')

command -v jq >/dev/null 2>&1 || {
    echo >&2 "'jq' is required to parse the JSON config file. Please install it. https://stedolan.github.io/jq/download"
    exit 1
}

runContainer() {
    i=$1 # config index

    config=$(cat wp-instances.json | jq -r --arg index "$i" '.[$index | tonumber]')
    project_name=$(echo $config | jq -r '.["project-name"]')
    WP_PORT=$(echo $config | jq -r '.["container-port"]')
    OLD_URL=$(echo $config | jq -r '.["old-url"]')
    DOWNLOAD_PLUGINS=$(echo $config | jq -r '.["download-plugins"]')

    # proprietary plugins and themes data
    PROPRIETARY_DOWNLOAD=$(echo $config | jq -r '.["download-proprietary-plugins-themes"]')
    DLPROP_PLUGINS=$(echo $config | jq -r '.["proprietary-plugin-zipfiles"]')
    DLPROP_PLUGINS_PATH=$(echo $config | jq -r '.["proprietery-pluginspath"]')
    DLPROP_THEMES=$(echo $config | jq -r '.["proprietary-theme-zipfiles"]')
    DLPROP_THEMES_PATH=$(echo $config | jq -r '.["proprietery-themespath"]')
    PROPRIETARY_FTPHOST=$(echo $config | jq -r '.["proprietary-ftphost"]')
    PROPRIETARY_FTPUSER=$(echo $config | jq -r '.["proprietary-ftpuser"]')
    PROPRIETARY_FTPPASSWORD=$(echo $config | jq -r '.["proprietary-ftppassword"]')
    PROPRIETARY_PLUGINSPATH=$(echo $config | jq -r '.["proprietary-pluginspath"]')
    PROPRIETARY_THEMESPATH=$(echo $config | jq -r '.["proprietary-themespath"]')

    # proprietary plugins list contruction
    propplugincount=$(echo $DLPROP_PLUGINS | jq -r '. | length')
    propplugincount=$(($propplugincount - 1))
    proppluginsfull=()
    plugini=0
    while [ $plugini -le $propplugincount ]; do
        pname=$(echo $DLPROP_PLUGINS | jq -r --arg index "$plugini" '.[$index | tonumber]')
        fl="$PROPRIETARY_PLUGINSPATH/$pname.zip"
        proppluginsfull+=("$fl")
        plugini=$(($plugini + 1))
    done
    printf -v DLPROP_PLUGINS_FULLPATHS ',%s' "${proppluginsfull[@]}"
    DLPROP_PLUGINS_FULLPATHS=${DLPROP_PLUGINS_FULLPATHS:1}

    # proprietary themes list contruction
    propthemecount=$(echo $DLPROP_THEMES | jq -r '. | length')
    propthemecount=$(($propthemecount - 1))
    propthemesfull=()
    themei=0
    while [ $themei -le $propthemecount ]; do
        tname=$(echo $DLPROP_THEMES | jq -r --arg index "$themei" '.[$index | tonumber]')
        fl="$PROPRIETARY_PLUGINSPATH/$pname.zip"
        propthemesfull+=($PROPRIETARY_THEMESPATH/$tname.zip)
        themei=$(($themei + 1))
    done
    printf -v DLPROP_THEMES_FULLPATHS ',%s' "${propthemesfull[@]}"
    DLPROP_THEMES_FULLPATHS=${DLPROP_THEMES_FULLPATHS:1}

    # free plugins list contruction
    downloadplugincount=$(echo $DOWNLOAD_PLUGINS | jq -r '. | length')
    downloadplugincount=$(($downloadplugincount - 1))
    downloadplugins=()
    plugini=0
    while [ $plugini -le $downloadplugincount ]; do
        downloadplugins+=($(echo $DOWNLOAD_PLUGINS | jq -r --arg index "$plugini" '.[$index | tonumber]'))
        plugini=$(($plugini + 1))
    done
    printf -v DOWNLOAD_PLUGINS ',%s' "${downloadplugins[@]}"
    DOWNLOAD_PLUGINS=${DOWNLOAD_PLUGINS:1}

    DB_CONTAINER_NAME=${project_name}_dev_db
    PMA_CONTAINER_NAME=${project_name}_dev_pma
    WP_CONTAINER_NAME=${project_name}_dev_wp
    PROJECT_NAME=$project_name

    if [ -z $WP_PORT ]; then
        WP_PORT=$((8000 + $i))
    fi

    volumes=()
    plugincount=$(echo $config | jq -r '.["local-plugins"] | length')
    plugincount=$(($plugincount - 1))
    plugini=0
    while [ $plugini -le $plugincount ]; do
        ppath=$(echo $config | jq -r --arg index "$plugini" '.["local-plugins"][$index | tonumber]')
        if [ -d $ppath ]; then
            pbasename=${ppath##*/}
            volumes+=(-v $ppath:/var/www/html/wp-content/plugins/$pbasename)
        else
            printf "${WARN} ${WHITE}Local plugin folder at ${CYAN}${ppath}${WHITE} doesn't exist. Skipping volume mount.${NC}\n"
        fi
        plugini=$(($plugini + 1))
    done

    themecount=$(echo $config | jq -r '.["local-themes"] | length')
    themecount=$(($themecount - 1))
    themei=0
    while [ $themei -le $themecount ]; do
        tpath=$(echo $config | jq -r --arg index "$themei" '.["local-themes"][$index | tonumber]')
        if [ -d $tpath ]; then
            tbasename=${tpath##*/}
            volumes+=(-v $tpath:/var/www/html/wp-content/themes/$tbasename)
        else
            printf "${WARN} ${WHITE}Local theme folder at ${CYAN}${tpath}${WHITE} doesn't exist. Skipping volume mount.${NC}\n"
        fi
        themei=$(($themei + 1))
    done

    mysqldump=$(echo $config | jq -r '.["mysql-dumpfile"]')
    if [ ! -z $mysqldump ]; then
        if [ -e $mysqldump ]; then
            volumes+=(-v $mysqldump:/tmp/db.sql)
        else
            printf "${WARN} ${WHITE}Local MySQL dump file at ${CYAN}${mysqldump}${WHITE} doesn't exist. Skipping volume mount.${NC}\n"
        fi
    fi

    volumes+=(-v ${project_name}_languages:/var/www/html/wp-content/languages:rw)
    volumes+=(-v ${project_name}_plugins:/var/www/html/wp-content/plugins:rw)
    volumes+=(-v ${project_name}_themes:/var/www/html/wp-content/themes:rw)

    docker run --name=${WP_CONTAINER_NAME} -p ${WP_PORT}:80 \
        ${volumes[@]} \
        --env WP_CLI_CACHE_DIR=/var/www/html/.wp-cli/cache \
        --env XDEBUG_CONFIG=remote_host=${DOCKER_BRIDGE_IP} \
        --env ENVIRONMENT=development \
        --env DOCKER_BRIDGE_IP=${DOCKER_BRIDGE_IP} \
        --env DOCKER_CONTAINER_PORT=${WP_PORT} \
        --env OLD_URL=${OLD_URL} \
        --env DB_HOST=aivec_wp_mysql \
        --env DB_NAME=${PROJECT_NAME} \
        --env DOWNLOAD_PLUGINS=${DOWNLOAD_PLUGINS} \
        --env PROPRIETARY_DOWNLOAD=${PROPRIETARY_DOWNLOAD} \
        --env DLPROP_PLUGINS_FULLPATHS=${DLPROP_PLUGINS_FULLPATHS} \
        --env DLPROP_THEMES_FULLPATHS=${DLPROP_THEMES_FULLPATHS} \
        --env PROPRIETARY_FTPHOST=${PROPRIETARY_FTPHOST} \
        --env PROPRIETARY_FTPUSER=${PROPRIETARY_FTPUSER} \
        --env PROPRIETARY_FTPPASSWORD=${PROPRIETARY_FTPPASSWORD} \
        --env PROPRIETARY_PLUGINSPATH=${PROPRIETARY_PLUGINSPATH} \
        --env PROPRIETARY_THEMESPATH=${PROPRIETARY_THEMESPATH} \
        --env WORDPRESS_DEBUG=1 \
        --env WORDPRESS_DB_NAME=${PROJECT_NAME} \
        --env WORDPRESS_DB_HOST=aivec_wp_mysql \
        --env WORDPRESS_DB_USER=root \
        --env WORDPRESS_DB_PASSWORD=root \
        --network=${NETWORK_NAME}_default \
        --restart always wordpress_devenv
}

stopContainer() {
    i=$1 # config index

    config=$(cat wp-instances.json | jq -r --arg index "$i" '.[$index | tonumber]')
    project_name=$(echo $config | jq -r '.["project-name"]')
    WP_CONTAINER_NAME=${project_name}_dev_wp
    docker stop $WP_CONTAINER_NAME
    docker rm $WP_CONTAINER_NAME
}

projectcount=$(cat wp-instances.json | jq -r '. | length')
projectcount=$(($projectcount - 1))
projects=()
declare -A indexmap

i=0
while [ $i -le $projectcount ]; do
    pname=$(cat wp-instances.json | jq -r --arg index "$i" '.[$index | tonumber]["project-name"]')
    indexmap[$pname]=$i
    projects+=($pname)
    i=$(($i + 1))
done
projects+=("all")

PS3='Select a project: '
select selectedproject in "${projects[@]}"; do
    echo -e "\n"
    break
done

while true; do
    read -p "1) Run Containers
2) Stop Containers
3) Wipe Mysql db and re-dump
q) quit
Select an operation to perform for '$selectedproject': " answer
    case $answer in
    [1]*)
        #docker inspect wordpress_devenv:latest >/dev/null 2>&1 ||
        #    echo -e "\n${INFO} ${WHITE}Custom Wordpress image does not exist. Building...${NC}" &&
        #    docker build -t wordpress_devenv:latest \
        #        --build-arg DOCKER_BRIDGE_IP=${DOCKER_BRIDGE_IP} .

        docker build -t wordpress_devenv:latest \
                --build-arg DOCKER_BRIDGE_IP=${DOCKER_BRIDGE_IP} .

        echo -e "\n${INFO} ${WHITE}Running Container(s)...${NC}"
        docker-compose -p ${NETWORK_NAME} -f docker-compose.db.yml up -d
        if [ "$selectedproject" == 'all' ]; then
            i=0
            while [ $i -le $projectcount ]; do
                runContainer "$i"
                i=$(($i + 1))
            done
        else
            runContainer "${indexmap[$selectedproject]}"
        fi
        exit
        ;;
    [2]*)
        echo -e "\n${INFO} ${WHITE}Stopping Container(s)...${NC}"
        if [ "$selectedproject" == 'all' ]; then
            i=0
            while [ $i -le $projectcount ]; do
                stopContainer "$i"
                i=$(($i + 1))
            done
            docker-compose -p ${NETWORK_NAME} -f docker-compose.db.yml down
        else
            stopContainer "${indexmap[$selectedproject]}"
        fi
        exit
        ;;
    [3]*)
        echo -e "\n${INFO} ${WHITE}Not yet implemented. Aborting.${NC}"
        # echo -e "Wiping Mysql database and re-dumping with dump file...\n"
        exit
        ;;
    [Qq]*)
        echo -e "\nBye."
        exit
        ;;
    *) echo "Please select one of 1, 2, 3, or q" ;;
    esac
done
