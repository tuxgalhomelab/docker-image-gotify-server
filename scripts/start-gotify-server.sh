#!/usr/bin/env bash
set -E -e -o pipefail

gotify_config="/data/gotify-server/config/config.yml"

set_umask() {
    # Configure umask to allow write permissions for the group by default
    # in addition to the owner.
    umask 0002
}

setup_gotify_config() {
    echo "Checking for existing Gotify config ..."
    echo

    if [ -f "${gotify_config:?}" ]; then
        echo "Existing Gotify configuration \"${gotify_config:?}\" found"
    else
        echo "Generating Gotify configuration at ${gotify_config:?}"
        mkdir -p "$(dirname "${gotify_config:?}")"
        cat << EOF > ${gotify_config:?}
server:
  port: 80

database:
  dialect: sqlite3
  connection: /data/gotify-server/data/gotify.db

# On database creation, gotify creates an admin user
defaultuser:
  name: testuser
  pass: testpass
passstrength: 10
uploadedimagesdir: /data/gotify-server/data/images
pluginsdir: /data/gotify-server/data/plugins
registration: false
EOF
    fi

    echo
    echo
}

start_gotify() {
    echo "Starting Gotify ..."
    echo

    cd "$(dirname "${gotify_config:?}")"
    exec gotify-server
}

set_umask
setup_gotify_config
start_gotify
