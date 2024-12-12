ARG VERSION

# tools
FROM mcr.io/ghcr.io/openwrt/tools:openwrt-$VERSION AS tools

FROM ubuntu:22.04
LABEL maintainer="mtdcy.chen@gmail.com"

# ENV & ARG variables
ARG TZ=Asia/Shanghai
ARG LANG=en_US.UTF-8
ARG VERSION
ARG MIRROR=""

ENV TZ=${TZ}
ENV LANG=${LANG}
ENV LC_ALL=${LANG}
ENV LANGUAGE=${LANG}
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /opt

# prepare #1
RUN test -n "${MIRROR}" &&                              \
    sed -e "s|http://archive.ubuntu.com|${MIRROR}|g"    \
        -e "s|http://security.ubuntu.com|${MIRROR}|g"   \
        -i /etc/apt/sources.list || true;               \
    apt-get update &&                                   \
    apt-get install -y -q locales tzdata &&             \
    sed -i "/C.UTF-8/s/^# //g" /etc/locale.gen &&       \
    sed -i "/$LANG/s/^# //g" /etc/locale.gen &&         \
    locale-gen &&                                       \
    ln -svf /usr/share/zoneinfo/$TZ /etc/localtime &&   \
    echo "$TZ" > /etc/timezone

# prepare #2
RUN apt-get install -y -q --ignore-missing              \
    ack antlr3 asciidoc autoconf automake autopoint     \
    binutils bison build-essential bzip2 ccache clang   \
    cmake cpio curl device-tree-compiler ecj fastjar    \
    flex gawk gettext gcc-multilib g++-multilib git     \
    gnutls-dev gperf haveged help2man intltool          \
    lib32gcc-s1 libc6-dev-i386 libelf-dev libglib2.0-dev\
    libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev      \
    libncurses-dev libpython3-dev libreadline-dev       \
    libssl-dev libtool libyaml-dev libz-dev lld llvm    \
    lrzsz mkisofs msmtp nano ninja-build p7zip          \
    p7zip-full patch pkgconf python3 python3-pip        \
    python3-ply python3-docutils python3-pyelftools     \
    qemu-utils re2c rsync scons squashfs-tools          \
    subversion swig texinfo uglifyjs upx-ucl unzip vim  \
    wget xmlto xxd zlib1g-dev zstd python2 libdb-dev

# prepare #3
COPY --from=tools --chmod=0755 /prebuilt_tools /opt/tools
COPY wrt-go/toolchains-$VERSION.txt /opt/toolchains.txt
RUN IFS=';'; while read -r dir url; do \
        echo "fetch toolchain $dir <= $url"; \
        mkdir -p $dir && cd $dir && \
        case "$url" in \
            *.tar.zst)  curl -sL $url | tar --zstd -x --strip-components=1 ;; \
            *.tar.xz)   curl -sL $url | tar -xJ --strip-components=1 ;; \
            *.tar.*)    curl -sL $url | tar -x --strip-components=1 ;; \
        esac && \
        mv toolchain-* toolchain && cd -; \
    done < toolchains.txt

# clear
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# use bash as default shell
RUN ln -sfv /bin/bash /bin/sh
