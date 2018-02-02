#!/bin/bash
# Build a set of packages on a release in a container
#
# Used to test that packages in the archive are still buildable and do
# not fail to build (FTBFS).
#
# Copyright 2017 Canonical Ltd.
# Joshua Powers <josh.powers@canonical.com>
set -eux

PACKAGE=$1
RELEASE=$2
DATE=$(date +%Y%m%d-%H%m%S)
NAME=build-$RELEASE-$DATE
LOG_DIR=logs/$RELEASE-$DATE

error() { echo "$@" 1>&2; }

cleanup() {
    lxc delete --force "$NAME"
}

exec_container() {
    local name="$1"
    shift
    lxc exec "$name" -- "$@"
}

launch_container() {
    if [ "$(lxc list "$NAME" --columns n --format=csv)" == "$NAME" ]; then
        lxc delete --force "$NAME"
    fi

    lxc launch ubuntu-daily:"$RELEASE" "$NAME" ||
        error "Failed to start '$RELEASE' container named '$NAME'"

    check_networking

    exec_container "$NAME" sh -c "apt-get update"
    exec_container "$NAME" sh -c "DEBIAN_FRONTEND=noninteractive apt-get upgrade --assume-yes"
    exec_container "$NAME" sh -c "DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes ubuntu-dev-tools"

    lxc snapshot "$NAME" base_image
}

check_networking(){
    exec_container "$NAME" sh -c '
        i=0
        while [ $i -lt 60 ]; do
            getent hosts archive.ubuntu.com && exit 0
            sleep 2
        done' 2>&1

    ret=$?
    if [ "$ret" -ne 0 ]; then
        error "Waiting for network in container '$NAME' failed"
    fi
}

setup_container() {
    lxc restore "$NAME" base_image

    check_networking

    exec_container "$NAME" pull-lp-source "$PACKAGE" "$RELEASE"
    exec_container "$NAME" apt-get update
    exec_container "$NAME" sh -c "DEBIAN_FRONTEND=noninteractive apt-get build-dep --assume-yes $PACKAGE"
}

build_package() {
    START=$(date +%s)
    lxc exec "$NAME" -- sh -c "cd $PACKAGE-*/ && dpkg-buildpackage -j4 -us -uc" &> "$LOG_DIR/$PACKAGE.log"
    echo $? > "$LOG_DIR/$PACKAGE.result"
    END=$(date +%s)
    echo $((END-START)) > "$LOG_DIR/$PACKAGE.time"
}


if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
fi
mkdir "$LOG_DIR"

trap cleanup EXIT

launch_container
setup_container
build_package
