FROM wordpress:php8.3-apache

RUN apt-get update && \
    apt-get install -y curl unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -L -o /tmp/wordfence.zip https://downloads.wordpress.org/plugin/wordfence.latest-stable.zip && \
    unzip /tmp/wordfence.zip -d /usr/src/wordpress/wp-content/plugins/ && \
    rm /tmp/wordfence.zip

COPY php.ini /usr/local/etc/php/
