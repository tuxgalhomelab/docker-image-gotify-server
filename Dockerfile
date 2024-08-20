# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS with-scripts

COPY scripts/start-gotify-server.sh /scripts/

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG GOTIFY_SERVER_VERSION

# hadolint ignore=DL4006,SC2086
RUN --mount=type=bind,target=/scripts,from=with-scripts,source=/scripts \
    set -E -e -o pipefail \
    && homelab install unzip \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    # Download and install the release. \
    && mkdir -p /tmp/gotify-server \
    && PKG_ARCH="$(dpkg --print-architecture)" \
    && curl \
        --silent \
        --fail \
        --location \
        --remote-name \
        --output-dir /tmp/gotify-server https://github.com/gotify/server/releases/download/${GOTIFY_SERVER_VERSION:?}/gotify-linux-${PKG_ARCH:?}.zip \
    && pushd /tmp/gotify-server \
    && unzip gotify-linux-${PKG_ARCH:?}.zip \
    && popd \
    && mkdir -p /opt/gotify-server-${GOTIFY_SERVER_VERSION:?} \
    && ln -sf /opt/gotify-server-${GOTIFY_SERVER_VERSION:?} /opt/gotify-server \
    && cp /tmp/gotify-server/gotify-linux-${PKG_ARCH:?} /opt/gotify-server/gotify-server \
    && ln -sf /opt/gotify-server/gotify-server /opt/bin/gotify-server \
    # Set up the gotify-server config and data directories. \
    && mkdir -p /config /data \
    # Copy the start-gotify-server.sh script. \
    && cp /scripts/start-gotify-server.sh /opt/gotify-server/ \
    && ln -sf /opt/gotify-server/start-gotify-server.sh /opt/bin/start-gotify-server \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} \
        /opt/gotify-server-${GOTIFY_SERVER_VERSION:?} \
        /opt/gotify-server \
        /opt/bin/gotify-server \
        /opt/bin/start-gotify-server \
        /config \
        /data \
    # Clean up. \
    && rm -rf /tmp/gotify-server \
    && homelab remove unzip \
    && homelab cleanup

# Expose just the TLS port used by Gotify server.
EXPOSE 443

# Health check the /health endpoint (the expectation is that the
# HTTP port 80 is redirected to the TLS port 443).
HEALTHCHECK \
    --start-period=15s --timeout=3s --interval=30s \
    CMD \
        curl \
        --silent \
        --fail \
        --location \
        --show-error \
        --insecure http://localhost/health

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-gotify-server"]
STOPSIGNAL SIGTERM
