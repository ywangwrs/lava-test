FROM php:7.0-apache

# Install basic tools
RUN apt-get update && apt-get install --yes --no-install-recommends \
    tzdata \
    apt-transport-https \
    wget \
    git \
    git-email \
    python3 \
    gnuplot-x11 \
    jq \
    sendmail \
    mutt \
 && apt-get clean \
 && ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime \
 && git config --global user.email "lpdtest@windriver.com" \
 && git config --global user.name "LPD Test"

# Install lava-tool
RUN echo "deb https://images.validation.linaro.org/staging-repo jessie-backports main" > /etc/apt/sources.list.d/lava.list \
 && wget https://images.validation.linaro.org/staging-repo/staging-repo.key.asc \
 && apt-key add staging-repo.key.asc \
 && apt-get update && apt-get install --yes --no-install-recommends lava-tool \
 && apt-get clean

ADD .muttrc /var/www/
ADD .muttrc /root/

# Give HOME access permission of www-data user
RUN cd /var/www \
 && git clone https://github.com/WindRiver-OpenSourceLabs/ci-scripts.git \
 && cd ci-scripts \
 && make setup \
 && chown -R www-data:www-data /var/www

CMD ["apache2-foreground"]
