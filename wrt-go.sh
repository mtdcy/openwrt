#!/bin/bash -e
# shellcheck disable=SC2015
# shellcheck disable=SC2129

i18n="${i18n:-zh-cn}"
DL="${DL:-/nfs/public/packages}"
WORKDIR="$(pwd -P)"
ARCH=${ARCH:-x86_64}

CR="${CR:-mcr.io}"
IMAGE="${IMAGE:-wrt-go/builder}"

ART="${ART:-/nfs/public/wrt-go/releases}"
[[ "$ART" =~ releases$ ]] || ART="$ART/releases"

info () {
    echo -e "==\\033[31m $(date '+%Y/%m/%d %H:%M:%S'): $* \\033[0m" >&2
}

beep() {
    echo -e '\a'
}

usage() {
    cat < EOF
$(basename "$0") Copyright \(c\) 2024, mtdcy.chen@gmail.com

Usage:
    "$(basename "$0")" [options]

    Try \'"$(basename "$0")" <menuconfig|download|compile>\'

EOF
}

if ! which docker; then
    info "Please install docker first"
    exit 1
fi

# branch: 24.10
# tag: 24.10.0
branch_tag_name() {
    git describe --tags --exact-match 2> /dev/null ||
    git symbolic-ref -q --short HEAD \
        | sed -e 's/openwrt-//' -e 's/^v//'
}

# prepare_docker_image <version>
prepare_docker_image() {
    if [ -z "$(docker images -q "$IMAGE:$1" 2>/dev/null)" ]; then
        if ! docker pull "$CR/$IMAGE:$1"; then
            info "build docker image $CR/$IMAGE:$*"
            docker build -t "$IMAGE:$1"                     \
                --build-arg VERSION="$1"                    \
                --build-arg TZ="$(cat /etc/timezone)"       \
                --build-arg MIRROR=http://mirrors.mtdcy.top \
                -f wrt-go/Dockerfile .
            docker image tag "$IMAGE:$1" "$CR/$IMAGE:$1"
            docker image push "$CR/$IMAGE:$1"
        else
            docker image tag "$CR/$IMAGE:$1" "$IMAGE:$1"
        fi

    fi
}

run() {
    # nameless container which allow multiple instances.
    # Notes:
    #   1. wsl2 docker bridge network has big performance issue.
    #   2. mkdir before volume mount to avoid permission issues.
    prepare_docker_image "$(branch_tag_name)"

    info "$*"
    mkdir -p "$DL" "$ART" dl artifacts
    test -t 1 && tty='-it' || tty='-i'
    docker run --rm "$tty"                          \
        -u "$(id -u):$(id -g)"                      \
        -v /etc/passwd:/etc/passwd:ro               \
        -v /etc/group:/etc/group:ro                 \
        -v /etc/localtime:/etc/localtime:ro         \
        -v "$WORKDIR:$WORKDIR"                      \
        -v "$WORKDIR/wrt-go/files:$WORKDIR/files"   \
        -v "$(realpath "$DL"):$WORKDIR/dl"          \
        -v "$(realpath "$ART"):$WORKDIR/artifacts"  \
        --network host                              \
        -w "$WORKDIR"                               \
        "$IMAGE:$(branch_tag_name)" "$@"
}

# prepare_feeds [revision or branch]
prepare_feeds() {
    info "prepare feeds and packages"
    . wrt-go/config-packages

    local revision branch
    revision="$1"
    if [ -n "$revision" ]; then
        info "checkout $revision"
        git checkout "$revision"
        branch="$(git rev-parse --abbrev-ref HEAD)"

        # Replace all src-git with src-git-full: https://openwrt.org/docs/guide-developer/feeds#feed_configuration
        sed -e "/^src-git\S*/s//src-git-full/" feeds.conf.default > feeds.conf
    else
        cat feeds.conf.default > feeds.conf
    fi

    # using local mirrors
    if curl --fail -s https://git.mtdcy.top/ > /dev/null; then
        sed -e 's@https://git.openwrt.org/feed/packages.git@https://git.mtdcy.top/mirrors/openwrt-packages.git@' \
            -e 's@https://git.openwrt.org/project/luci.git@https://git.mtdcy.top/mirrors/openwrt-luci.git@' \
            -e 's@https://git.openwrt.org/feed/routing.git@https://git.mtdcy.top/mirrors/openwrt-routing.git@' \
            -e 's@https://git.openwrt.org/feed/telephony.git@https://git.mtdcy.top/mirrors/openwrt-telephony.git@' \
            -e 's@https://github.com/openwrt/packages.git@https://git.mtdcy.top/mirrors/openwrt-packages.git@' \
            -e 's@https://github.com/openwrt/luci.git@https://git.mtdcy.top/mirrors/openwrt-luci.git@' \
            -e 's@https://github.com/openwrt/routing.git@https://git.mtdcy.top/mirrors/openwrt-routing.git@' \
            -e 's@https://github.com/openwrt/telephony.git@https://git.mtdcy.top/mirrors/openwrt-telephony.git@' \
            -e 's@https://github.com/mtdcy/openwrt-packages.git@https://git.mtdcy.top/mtdcy/openwrt-packages.git@' \
            -e 's@https://github.com/mtdcy/openwrt-luci.git@https://git.mtdcy.top/mtdcy/openwrt-luci.git@' \
            -e 's@https://github.com/immortalwrt/packages.git@https://git.mtdcy.top/mirrors/immortalwrt-packages.git@' \
            -e 's@https://github.com/immortalwrt/luci.git@https://git.mtdcy.top/mirrors/immortalwrt-luci.git@' \
            -e 's@https://github.com/jjm2473/packages.git@https://git.mtdcy.top/mirrors/istoreos-packages.git@' \
            -e 's@https://github.com/jjm2473/luci.git@https://git.mtdcy.top/mirrors/istoreos-luci.git@' \
            -e '/istore.git/d' \
            -e '/jjm2473/d' \
            -i feeds.conf

        if [ -d package/wrt-go ]; then
            git -C package/wrt-go pull --force --rebase
            git -C package/wrt-go submodule update --recursive
        else
            git clone https://git.mtdcy.top/mtdcy/openwrt-luci-packages.git package/wrt-go
            git -C package/wrt-go submodule update --init --recursive
        fi
    else
        for pkg in "${EXTERNAL_PACKAGES[@]}"; do
            info "prepare $pkg"
            IFS=';' read -r pkg url branch <<< "$pkg"
            if [ -d "package/$pkg" ]; then
                git -C "package/$pkg" pull --rebase --recurse-submodules
            elif [ -n "$branch" ]; then
                git clone -b "$branch" "$url" "package/$pkg"
            else
                git clone "$url" "package/$pkg"
            fi
        done
    fi

    if [ -n "$revision" ]; then
        run ./scripts/feeds update -a

        # Edit every line of feeds.conf in a loop to set the chosen revision hash
        sed -n -e "/^src-git\S*\s/{s///;s/\s.*$//p}" feeds.conf |
            while read -r FEED_ID; do
                REV_DATE="$(git log -1 --format=%cd --date=iso8601-strict)"
                REV_HASH="$(git -C feeds/${FEED_ID} rev-list -n 1 --before=${REV_DATE} "$branch")"

                info "set $FEED_ID to $REV_HASH($REV_DATE)"
                sed -i -e "/\s${FEED_ID}\s.*\.git$/s/$/^${REV_HASH}/" feeds.conf
            done
    fi

    run ./scripts/feeds update -a -f
    run ./scripts/feeds install -a -f

    info "patch feeds"
    for file in wrt-go/patches/*; do
        info "apply patch $file"
        patch -p1 -N -r - < "$file" > /dev/null || true
    done
}

filter_out_apps() {
    # remove all packages
    sed -e '/CONFIG_PACKAGE_luci-app-.*$/d' \
        -e '/CONFIG_PACKAGE_luci-i18n-.*$/d' \
        -e '/CONFIG_LUCI_LANG_.*$/d'
}

# prepare_config [target]
prepare_config() {
    [ -f .config ] && cp .config .config.old || true

    local target subtarget
    if [ -n "$1" ]; then
        [ -d "$1" ] || [ -f "$1" ] || {
            info "unknown target $1"
            return 1
        }

        # target/linux/x86/64
        # target/linux/rockchip/rk35xx/target.mk
        IFS='/' read -r _ _ target subtarget _ <<< "$1"
        info "prepare for $target/$subtarget"

        cat << EOF > .config
CONFIG_TARGET_${target}=y
CONFIG_TARGET_${target}_$subtarget=y
CONFIG_TARGET_MULTI_PROFILE=y
EOF
        case "${target}_$subtarget" in
            x86_64)
                echo "CONFIG_TARGET_x86_64_DEVICE_generic=y" >> .config
                ;;
        esac
    elif [ ! -f .config ]; then
        cat << EOF > .config
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
EOF
    fi

    # override configs
    cat wrt-go/config-defaults >> .config

    # default: set all override packages as module
    if [ -d package/wrt-go ]; then
        for app in package/wrt-go/*; do
            echo "CONFIG_PACKAGE_$(basename "$app")=m" >> .config
        done
    fi

    # default: i18n
    if [ -n "$i18n" ]; then
        case "$i18n" in
            zh-cn)
                # TODO: move these to uci-defaults
                sed -i "s:timezone .*$:timezone 'CST-8':" wrt-go/files/etc/config/system
                sed -i "s:zonename .*$:zonename 'Asia/Shanghai':" wrt-go/files/etc/config/system
                echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
                ;;
            zh-tw)
                echo "CONFIG_LUCI_LANG_zh_Hant=y" >> .config
                ;;
            *)
                echo "CONFIG_LUCI_LANG_$i18n=y"   >> .config
                ;;
        esac
        echo "CONFIG_PACKAGE_luci-i18n-base-$i18n=y"  >> .config
    fi

    # defaults: builtin packages
    for x in "${CONFIG_PACKAGES[@]}"; do
        case "$x" in
            \#*) ;; # comments
            CONFIG_*=*) echo "$x" >> .config ;;
            CONFIG_*)   echo "$x=y" >> .config ;;
            *=*)        echo "CONFIG_PACKAGE_$x" >> .config ;;
            luci-app-*)
                echo "CONFIG_PACKAGE_$x=y" >> .config
                [ -n "$i18n" ] && echo "CONFIG_PACKAGE_${x/app-/i18n-}-$i18n=y" >> .config || true
                ;;
            *)
                echo "CONFIG_PACKAGE_$x=y" >> .config
                ;;
        esac
    done

    # version repo
    cat << EOF >> .config
CONFIG_IMAGEOPT=y
CONFIG_VERSIONOPT=y
CONFIG_VERSION_DIST="Wrt-Go"
CONFIG_VERSION_HOME_URL="https://wrt-go.mtdcy.top"
CONFIG_VERSION_REPO="https://wrt-go.mtdcy.top/releases/$(branch_tag_name)"
EOF

    # hacking
    sed -i '/^.*istoreos-files/d' .config

    run make defconfig
}

# prepare_tools
prepare_tools() {
    if run rsync -a --chown "$(id -u):$(id -g)" /opt/tools/ ./; then
        run ./scripts/ext-tools.sh --refresh
    else
        run make tools/install -j"$(nproc)" BUILD_LOG=1
    fi
}

prepare_toolchain() {
    local arch
    IFS='=' read -r _ arch <<< "$(grep TARGET_ARCH_PACKAGES .config)"
    run ./scripts/ext-toolchain.sh \
        --toolchain "/opt/$(xargs <<< "$arch")/toolchain" \
        --overwrite-config --config .config
}

# filter command line options
options=()
args=()
revision=""
target=""

# special commands
case "$1" in
    help)   usage   ; exit ;;
    shell)  run bash; exit ;;
    rsync) # rsync <dest>
        dest="${2:-.}"
        rsync -av --delete "$(dirname "$0")/wrt-go/" "$dest/wrt-go/"
        cp -v "$0" "$dest/"
        exit
        ;;
    save) # save <path/to/config>
        config="${2:-wrt-go/config.new}"
        run ./scripts/diffconfig.sh | filter_out_apps > "$config"
        exit
        ;;
    checkout) # checkout <revision>
        revision="$2"
        test -n "$revision" || {
            info "checkout needs a branch/tag name or commit id"
            exit 1
        }
        options+=(clean prepare) # always do a clean
        ;;
esac

# filter options
while [ $# -gt 0 ]; do
    if [ -f "$1" ] && [[ "$1" =~ /config- ]]; then
        info "copy config $1"
        filter_out_apps < "$1" > .config
        options+=(prepare)
    elif [[ "$1" =~ ^https?:// ]] || [[ "$1" =~ ^ftp:// ]]; then
        info "fetch config $1"
        curl -L "$1" | filter_out_apps > .config
        options+=(prepare)
    elif [[ "$1" =~ ^target/linux/ ]]; then
        info "select $1"
        target="$1"
        options+=(clean prepare)
    elif [[ "$1" =~ ^-j[0-9]+ ]]; then
        args+=("$1")
    else
        options+=("$1")
    fi
    shift
done

# defaults:
#  1. built with single thread;
[[ "${args[*]}" =~ -j[0-9]+ ]] || args+=("-j1")

args+=(BUILD_LOG=1)

# dedup
options=($(printf "%s\n" "${options[@]}"))

for x in "${options[@]}"; do
    case "$x" in
        noop)           exit 0;;

        verbose)        args+=(V=s) ;;
        debug)          args=(-j1 V=sc) ;;
        ignore_errors)  args+=(-i) ;;

        prepare)
            prepare_feeds "$revision"
            prepare_config "$target"
            prepare_tools
            prepare_toolchain
            ;;

        clean)
            run make clean
            docker rmi -f "$(docker images -q "$IMAGE:$(branch_tag_name)")" || true
            ;;
        dirclean)       run make dirclean ;;
        distclean)      ;; # never do distclean, dl will be cleared
        download)       run make download "${args[@]}";;
        defconfig)      run make defconfig ;;
        menuconfig)     run make menuconfig ;;
        tools)          run make tools/install "${args[@]}" ;;
        package/*)      run make "${x%/}"/{clean,compile} "${args[@]}" ;;
        build)
            rm -rf bin build_dir/target-*/root*/ || true
            run make world "${args[@]}"
            info "sync artifacts to $ART/$(branch_tag_name)"
            mkdir -p "$ART/$(branch_tag_name)"
            run rsync -a bin/ "artifacts/$(branch_tag_name)/"
            ;;

        # make kernel_menuconfig CONFIG_TARGET=subtarget
        kernel)         run make kernel_menuconfig CONFIG_TARGET="$TARGET" ;;
        *)              info "unknown option $x, abort" ;;
    esac
done

beep

# vim:ft=sh:ff=unix:fenc=utf-8:et:ts=4:sw=4:sts=4
