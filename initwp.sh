#!/bin/bash

# mute CMD from official wordpress image
sed -i -e 's/^exec "$@"/#exec "$@"/g' /usr/local/bin/docker-entrypoint.sh

# execute bash script from official wordpress image
docker-entrypoint.sh apache2-foreground

# execute CMD
exec "$@"

# changing ownership of wp-content and plugins is necessary because any VOLUME mounted in the plugins/themes
# directory will recursively change permissions to root:root, causing wp-cli to fail on plugin install
chown www-data:www-data /var/www/html/wp-content
chown www-data:www-data /var/www/html/wp-content/plugins
chown www-data:www-data /var/www/html/wp-content/themes
chown www-data:www-data /var/www/html/wp-content/languages

table=wp_commentmeta # arbitrary table to check
if [ $(mysql -N -s --user=${WORDPRESS_DB_USER} --password=${WORDPRESS_DB_PASSWORD} --host=${DB_HOST} -e \
    "select count(*) from information_schema.tables where \
        table_schema='${DB_NAME}' and table_name='${table}';") -eq 1 ]; then
    echo "Wordpress tables already exist. Skipping database dump and plugin/theme installs..."
else
    echo "Wordpress tables don't exist. Looking for dump file..."
    if [ -e /tmp/db.sql ]; then
        echo "Found dump file. Dumping pre-configured db into Wordpress install..."
        mysql --user=$WORDPRESS_DB_USER --password=$WORDPRESS_DB_PASSWORD --host=$DB_HOST $DB_NAME </tmp/db.sql
        echo "Dump complete."

        echo "Replacing old url (${OLD_URL}) with container address (localhost:${DOCKER_CONTAINER_PORT})"
        php dbsearchreplace/srdb.cli.php -h db \
            -n ${DB_NAME} \
            -u ${WORDPRESS_DB_USER} \
            -p ${WORDPRESS_DB_PASSWORD} \
            -s "${OLD_URL}" -r "localhost:${DOCKER_CONTAINER_PORT}"
        
        echo "Replacing https with http for local development"
        php dbsearchreplace/srdb.cli.php -h db \
            -n ${DB_NAME} \
            -u ${WORDPRESS_DB_USER} \
            -p ${WORDPRESS_DB_PASSWORD} \
            -s "https://localhost:${DOCKER_CONTAINER_PORT}" -r "http://localhost:${DOCKER_CONTAINER_PORT}"

        active_plugins=($(php get_active_plugins.php ${WORDPRESS_DB_USER} ${WORDPRESS_DB_PASSWORD} ${DB_NAME}))
        for plugin in "${active_plugins[@]}"; do
            wp plugin install $plugin
        done

        IFS=',' read -ra PLUGINS <<<"$DOWNLOAD_PLUGINS"
        if [ "$DOWNLOAD_PLUGINS" ]; then
            echo "Installing necessary plugins via wp-cli..."
        fi
        for plugin in "${PLUGINS[@]}"; do
            wp plugin install $plugin
        done

        echo "Installing and activating Japanese language pack."
        wp language core install ja
        wp site switch-language ja
    else
        echo "Dump file doesn't exist. Skipping."
        echo "Without a dump file plugins/themes can't be installed with wp-cli because there is no install. Skipping."
    fi

    if [ "$PROPRIETARY_DOWNLOAD" = "true" ]; then
        IFS=',' read -ra FTP_PLUGINS_FULLPATHS <<<"$DLPROP_PLUGINS_FULLPATHS"
        IFS=',' read -ra FTP_THEMES_FULLPATHS <<<"$DLPROP_THEMES_FULLPATHS"

        echo "Pulling non-free plugins/themes from proprietary FTP server via lftp. This may take some time..."
        mkdir -p plugins && cd plugins
        for path in "${FTP_PLUGINS_FULLPATHS[@]}"; do
            lftp -c "open -u $PROPRIETARY_FTPUSER,$PROPRIETARY_FTPPASSWORD $PROPRIETARY_FTPHOST; mget ${path};"
        done
        cd ../
        cp -a plugins/. /var/www/html/wp-content/plugins/

        mkdir -p themes && cd themes
        for path in "${FTP_THEMES_FULLPATHS[@]}"; do
            lftp -c "open -u $PROPRIETARY_FTPUSER,$PROPRIETARY_FTPPASSWORD $PROPRIETARY_FTPHOST; mget ${path};"
        done
        cd ../
        cp -a themes/. /var/www/html/wp-content/themes/

        cd /var/www/html/wp-content/plugins
        plugins=($(find . -maxdepth 1 -name '*.zip'))
        echo "Extracting downloaded plugins..."
        for zipfile in "${plugins[@]}"; do
            echo "Extracting $zipfile"
            unzip -q "$zipfile"
            rm "$zipfile"
        done

        cd /var/www/html/wp-content/themes
        themes=($(find . -maxdepth 1 -name '*.zip'))
        echo "Extracting downloaded themes..."
        for zipfile in "${themes[@]}"; do
            echo "Extracting $zipfile"
            unzip -q "$zipfile"
            rm "$zipfile"
        done
    else
        echo "No proprietary plugins/themes specified for install. Skipping"
    fi
fi
echo "Setup complete!"
exec apache2-foreground
