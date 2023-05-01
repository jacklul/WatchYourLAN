#!/bin/bash
#shellcheck disable=SC2001,SC2155

ARCHITECTURES_TO_BUILD=( "linux/amd64" "linux/386" "linux/arm64" "linux/arm/7" "linux/arm/6" "linux/arm/5" )

###################################

PKGDIR="/opt/watchyourlan"
ROOTDIR="$(readlink -f "$GITHUB_WORKSPACE/upstream")"
[ -z "$VERSION" ] && VERSION="$(echo "$1" | sed 's/v*//')"
SEMVER="$(echo "$VERSION" | grep -qE "[0-9]+.[0-9]+.[0-9]+" && echo 1 || echo 0)"

cleanup_after_build() {
    rm -fr "$PKGDIR"
    rm -fr "$PKGDIR-deb"
}

prepare_pkg_dir() {
    mkdir -p "$PKGDIR"
    cp "$ROOTDIR/configs/watchyourlan.service" "$PKGDIR/"
    cp "$ROOTDIR/configs/install.sh" "$PKGDIR/install.sh"
}

prepare_deb_dir() {
    local ARCH="$1"
    local ARM="$2"
    local DEBARCH="$ARCH"
    
    if [ -n "$ARM" ]; then
        case $ARM in
            "5")
                DEBARCH="armel"
            ;;
            "6"|"7")
                DEBARCH="armhf"
            ;;
        esac
    else
        case $ARCH in
            "386")
                DEBARCH="i386"
            ;;
            "mipsle")
                DEBARCH="mipsel"
            ;;
        esac
    fi

    mkdir -p "$PKGDIR-deb"
    mkdir -p "$PKGDIR-deb/usr/bin"
    mkdir -p "$PKGDIR-deb/lib/systemd/system"
    mkdir -p "$PKGDIR-deb/DEBIAN"

    cp "$ROOTDIR/configs/watchyourlan.service" "$PKGDIR-deb/lib/systemd/system/"
    echo "Package: watchyourlan
Version: $(echo "$VERSION" | sed 's/v*//')
Section: utils
Priority: optional
Architecture: $DEBARCH
Depends: arp-scan
Maintainer: aceberg <aceberg_a@proton.me>
Description: Lightweight network IP scanner with web GUI
" > "$PKGDIR-deb/DEBIAN/control"
    echo "systemctl daemon-reload" > "$PKGDIR-deb/DEBIAN/postinst"
    
    chmod 755 -R "$PKGDIR-deb/DEBIAN"
}

###################################

set -e
umask 0022

export CGO_ENABLED=0

for ARCHITECTURE in "${ARCHITECTURES_TO_BUILD[@]}"; do
    cd "$ROOTDIR/cmd/WatchYourLAN/"

    export GOOS="$(echo "$ARCHITECTURE" | cut -d/ -f 1)"
    export GOARCH="$(echo "$ARCHITECTURE" | cut -d/ -f 2)"
    export GOARM="$(echo "$ARCHITECTURE" | cut -d/ -f 3)"

    ! echo "$GOOS" | grep -q "linux\|windows" && { echo "Unsupported OS target: $GOOS"; exit 1; }

    [ -n "$GOARM" ] && PKGSUFFIX="$GOOS-$GOARCH-v$GOARM" || PKGSUFFIX="$GOOS-$GOARCH"

    echo "Building for $ARCHITECTURE..."
    go build -o "$ROOTDIR/watchyourlan-$1-$PKGSUFFIX" .

    prepare_pkg_dir

    cp "$ROOTDIR/watchyourlan-$1-$PKGSUFFIX" "$PKGDIR/watchyourlan"
    cd "$(dirname "$PKGDIR")"

    if [ "$GOOS" = "linux" ]; then
        echo "Packing into watchyourlan-$1-$PKGSUFFIX.tar.gz..."
        tar czf "$GITHUB_WORKSPACE/watchyourlan-$1-$PKGSUFFIX.tar.gz" "$(basename "$PKGDIR")"

        echo "Packing into watchyourlan-$1-$PKGSUFFIX.zip..."
        zip -qr "$GITHUB_WORKSPACE/watchyourlan-$1-$PKGSUFFIX.zip" "$(basename "$PKGDIR")"

        if [ "$SEMVER" = "1" ]; then
            echo "Packing into watchyourlan-$1-$PKGSUFFIX.deb..."
            prepare_deb_dir "$GOARCH" "$GOARM"
            cp "$ROOTDIR/watchyourlan-$1-$PKGSUFFIX" "$PKGDIR-deb/usr/bin/watchyourlan"
            dpkg-deb --build --root-owner-group -Z gzip "$PKGDIR-deb" "$GITHUB_WORKSPACE/watchyourlan-$1-$PKGSUFFIX.deb"
        fi
    elif [ "$GOOS" = "windows" ]; then
        mv "$PKGDIR/watchyourlan" "$PKGDIR/watchyourlan.exe"

        echo "Packing into watchyourlan-$1-$PKGSUFFIX.zip..."
        zip -qr "$GITHUB_WORKSPACE/watchyourlan-$1-$PKGSUFFIX.zip" "$PKGDIR/watchyourlan.exe"
    fi

    cleanup_after_build
done
