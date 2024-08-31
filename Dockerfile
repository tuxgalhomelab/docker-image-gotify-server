# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG

ARG GO_IMAGE_NAME
ARG GO_IMAGE_TAG
FROM ${GO_IMAGE_NAME}:${GO_IMAGE_TAG} AS builder

ARG NVM_VERSION
ARG NVM_SHA256_CHECKSUM
ARG IMAGE_NODEJS_VERSION
ARG YARN_VERSION
ARG GOTIFY_SERVER_VERSION

COPY scripts/start-gotify-server.sh /scripts/
COPY patches /patches

# hadolint ignore=DL4006,SC3040,SC3009
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install build-essential git \
    && homelab install-node \
        ${NVM_VERSION:?} \
        ${NVM_SHA256_CHECKSUM:?} \
        ${IMAGE_NODEJS_VERSION:?} \
    # Download gotify-server repo. \
    && homelab download-git-repo \
        https://github.com/gotify/server \
        ${GOTIFY_SERVER_VERSION:?} \
        /root/gotify-server-build \
    && pushd /root/gotify-server-build \
    # Apply the patches. \
    && (find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p2 -i) \
    && source /opt/nvm/nvm.sh \
    && npm install -g yarn@${YARN_VERSION:?} \
    # Build UI for Gotify server. \
    && pushd ui && PUPPETEER_SKIP_DOWNLOAD=true yarn && popd && make build-js \
    # Build Gotify server. \
    && go mod tidy \
    && CGO_ENABLED=1 GOOS=linux go build \
        -a \
        -ldflags="-X main.Version=${GOTIFY_SERVER_VERSION#v} -X main.BuildDate=$(date "+%F-%T") -X main.Commit=$(git rev-parse --verify HEAD) -X main.Mode=prod" \
        . \
    && popd \
    && mkdir -p /output/{bin,scripts,configs} \
    # Copy the build artifacts. \
    && cp /root/gotify-server-build/server /output/bin \
    && cp /scripts/* /output/scripts

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG GOTIFY_SERVER_VERSION

# hadolint ignore=DL4006,SC2086,SC3009
RUN --mount=type=bind,target=/gotify-server-build,from=builder,source=/output \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/gotify-server-${GOTIFY_SERVER_VERSION:?}/bin /data/gotify-server/{config,data} \
    && cp /gotify-server-build/bin/server /opt/gotify-server-${GOTIFY_SERVER_VERSION:?}/bin/gotify-server \
    && ln -sf /opt/gotify-server-${GOTIFY_SERVER_VERSION:?} /opt/gotify-server \
    && ln -sf /opt/gotify-server/bin/gotify-server /opt/bin/gotify-server \
    # Copy the start-gotify-server.sh script. \
    && cp /gotify-server-build/scripts/start-gotify-server.sh /opt/gotify-server/ \
    && ln -sf /opt/gotify-server/start-gotify-server.sh /opt/bin/start-gotify-server \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} \
        /opt/gotify-server-${GOTIFY_SERVER_VERSION:?} \
        /opt/gotify-server \
        /opt/bin/{gotify-server,start-gotify-server} \
        /data/gotify-server \
    # Clean up. \
    && homelab cleanup

# Expose just the TLS port used by Gotify server.
EXPOSE 443

# Health check the /health endpoint (the expectation is that the
# HTTP port 80 is redirected to the TLS port 443).
HEALTHCHECK \
    --start-period=15s --interval=30s --timeout=3s \
    CMD homelab healthcheck-service http://localhost/health

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-gotify-server"]
STOPSIGNAL SIGTERM
