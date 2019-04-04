FROM wordpress:latest

# Add sudo in order to run wp-cli as the www-data user 
# zip and ftp are for the deployment script
RUN apt-get update && apt-get install -y sudo less mysql-client zip lftp git

# Add WP-CLI 
RUN curl -o /bin/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
COPY wp-su.sh /bin/wp
RUN chmod +x /bin/wp-cli.phar /bin/wp

ARG DOCKER_BRIDGE_IP
ENV DOCKER_BRIDGE_IP=$DOCKER_BRIDGE_IP
# Install xdebug for PHP live debugging in vscode
RUN yes | pecl install xdebug \
    && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_enable=1" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_host=${DOCKER_BRIDGE_IP}" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.profiler_enable=1" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.profiler_output_name=cachegrind.out.%t" >> /usr/local/etc/php/conf.d/xdebug.ini \
    && echo "xdebug.profiler_output_dir=/tmp" >> /usr/local/etc/php/conf.d/xdebug.ini

# COPY search-replace search-replace

RUN mkdir -p /var/www/html/.wp-cli/cache

# cleanup
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY dbsearchreplace /var/www/html/dbsearchreplace
COPY initwp.sh /usr/local/bin/initwp.sh
COPY get_active_plugins.php /var/www/html/get_active_plugins.php

ENTRYPOINT [ "initwp.sh" ]