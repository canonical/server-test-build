#!/bin/bash
# Build a set of packages on a release in a container
#
# Used to test that packages in the archive are still buildable and do
# not fail to build (FTBFS).
#
# Copyright 2017 Canonical Ltd.
# Joshua Powers <josh.powers@canonical.com>
set -eu

error() { echo "$@" 1>&2; }

usage() {
    cat <<EOF
Usage: ${0##*/} RELEASE SRC_PACKAGE[s]...
For a supported release, download and build package(s) from the
archive in a container.

Examples:
    * ${0##*/} bionic vim
    * ${0##*/} xenial ant qemu-kvm
    * ${0##*/} bionic exim4 iotop htop pep8 qemu uvtool
EOF
}

bad_usage() { usage 1>&2; [ $# -eq 0 ] || error "$@"; return 1; }

cleanup() {
    if [ "$(lxc list "$NAME" --columns n --format=csv)" == "$NAME" ]; then
        lxc delete --force "$NAME"
    fi
}

exec_container() {
    local name=$1
    shift
    lxc exec "$name" -- "$@"
}

launch_container() {
    local name=$1 release=$2
    shift 2

    if [ "$(lxc list "$name" --columns n --format=csv)" == "$name" ]; then
        lxc delete --force "$name"
    fi

    lxc launch ubuntu-daily:"$release" "$name" ||
        error "Failed to start '$release' container named '$name'"

    check_networking

    exec_container "$name" sh -c "apt-get update"
    exec_container "$name" sh -c "DEBIAN_FRONTEND=noninteractive apt-get upgrade --assume-yes"
    exec_container "$name" sh -c "DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes ubuntu-dev-tools"

    lxc snapshot "$name" base_image
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
    local name=$1 package=$2 release=$3
    shift 3

    lxc restore "$name" base_image

    check_networking

    exec_container "$name" pull-lp-source "$package" "$release"
    exec_container "$name" apt-get update
    exec_container "$name" sh -c "DEBIAN_FRONTEND=noninteractive apt-get build-dep --assume-yes $package"
}

build_package() {
    local name=$1 package=$2 log_dir=$3
    shift 3

    set +e
    START=$(date +%s)
    
    lxc exec "$name" -- sh -c "cd $package-*/ && dpkg-buildpackage -j4 -us -uc" &> "$log_dir/$package.log"
    
    echo $? > "$log_dir/$package.result"

    END=$(date +%s)
    echo $((END-START)) > "$log_dir/$package.time"

    set -e
}

main () {
    local short_opts="h"
    local long_opts="help"
    local getopt_out=""
    local getopt_out=$(getopt --name "${0##*/}" \
        --options "${short_opts}" --long "${long_opts}" -- "$@") &&
        eval set -- "${getopt_out}" ||
        { bad_Usage; return; }

    local cur=""
    local next=""

        while [ $# -ne 0 ]; do
            cur="${1:-}"; next="${2:-}";
            case "$cur" in
                -h|--help) usage; exit 0;;
                --) shift; break;;
            esac
            shift;
    done

    [ $# -gt 1 ] || bad_usage "error: must provide at least a release and one source package"

    release=$1; shift
    SUPPORTED_RELEASES=($(distro-info --supported | tr '\r\n' ' '))
    if [[ ! " ${SUPPORTED_RELEASES[@]} " =~ " ${release} " ]]; then
        bad_usage "error: not a supported release"
    fi

    local date=$(date +%Y%m%d-%H%m%S)
    local name=build-$release-$date
    local log_dir=logs/$release-$date

    mkdir -p "$log_dir"
    trap cleanup EXIT

    launch_container "$name" "$release"

    for package in "$@"; do
        setup_container "$name" "$package" "$release"
        build_package "$name" "$package" "$log_dir"
    done

}

main "$@"

# vi: ts=4 expandtab
