FROM ubuntu:18.04 AS build

RUN apt-get update && apt-get install -y \
    g++ \
    build-essential \
    git \
    curl \
    python-minimal

ENV METEOR_ALLOW_SUPERUSER=true \
    DEPLOY_DIR=/var/www/rocket.chat

RUN curl https://install.meteor.com/ |sed 's/2.3.2/2.2/'| sh

COPY . /usr/src/app/.
WORKDIR /usr/src/app/

RUN meteor npm install

RUN meteor build --server-only --directory $DEPLOY_DIR

FROM node:12.22.1-buster-slim

LABEL maintainer="buildmaster@rocket.chat"

WORKDIR /app
COPY --from=build /var/www/rocket.chat .

# dependencies
RUN groupadd -g 65533 -r rocketchat \
    && useradd -u 65533 -r -g rocketchat rocketchat \
    && mkdir -p /app/uploads \
    && chown rocketchat:rocketchat /app/uploads \
    && apt-get update \
    && apt-get install -y --no-install-recommends fontconfig

# --chown requires Docker 17.12 and works only on Linux
ADD --chown=rocketchat:rocketchat . /app

RUN aptMark="$(apt-mark showmanual)" \
    && apt-get install -y --no-install-recommends g++ make python ca-certificates \
    && cd /app/bundle/programs/server \
    && npm install \
    && apt-mark auto '.*' > /dev/null \
    && apt-mark manual $aptMark > /dev/null \
    && find /usr/local -type f -executable -exec ldd '{}' ';' \
       | awk '/=>/ { print $(NF-1) }' \
       | sort -u \
       | xargs -r dpkg-query --search \
       | cut -d: -f1 \
       | sort -u \
       | xargs -r apt-mark manual \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && npm cache clear --force

USER rocketchat

VOLUME /app/uploads
WORKDIR /app/bundle
# needs a mongoinstance - defaults to container linking with alias 'mongo'
ENV DEPLOY_METHOD=docker \
    NODE_ENV=production \
    MONGO_URL=mongodb://mongo:27017/rocketchat \
    HOME=/tmp \
    PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    Accounts_AvatarStorePath=/app/uploads

EXPOSE 3000
CMD ["node", "main.js"]