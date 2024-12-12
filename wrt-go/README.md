# OpenWRT-builder

scripts for building OpenWRT

### 改进之处

- 编译打包大部分工具为全功能版本（-full）；
- 编译fw3/iptables，以兼容docker和大部分app；
- 安装openssh-server/nginx/docker，以及网络和shell常用工具；
- /var不再链接到/tmp，因此只打包ext4，支持rootfs可读写；
- 自动扩展root分区大小为全盘（首次开机会自动重启两次）；
- 默认lan为dhcp，同时也可以通过172.31.100.1进行连接；

---

## 虚拟机/x86_64 特别版

基于[immortalwrt](https://github.com/immortalwrt/immortalwrt):v23.05.4

### 如何编译

```shell
#1. 准备
git clone https://git.mtdcy.top/mtdcy/gh-immortalwrt.git immortalwrt
cd immortalwrt
rsync -av /path/to/OpenWRT-builder/ ./

#2. 环境变量
export NJOBS=1 # 首次编译多线程容易出错
export DL=/path/to/your/package/dl
export ARC=/path/to/your/release/23.05.4-full-iptables

#3. 配置
./build-openwrt.sh v23.05.4 # 切换分支
./build-openwrt.sh https://mirrors.mtdcy.top/immortalwrt/releases/23.05.4/targets/x86/64/config.buildinfo menuconfig
# Base system => enable dnsmasq-full with  ipset
#             => enable firewall and disable firewall4
# Network->Firewall => disable all nft related settings

./scripts/diffconfig.sh > settings/config-23.05.4-full-iptables-x86_64

#4. 编译
./build-openwrt.sh settings/config-23.05.4-full-iptables-x86_64 verbose build
```

---

## Rockchip/H68k 特别版

基于[lede-rockchip](https://github.com/DHDAXCW/lede-rockchip)

```shell
#1. 准备
git clone https://git.mtdcy.top/mtdcy/gh-lede-rockchip.git lede-rockchip
cd immortalwrt
rsync -av /path/to/OpenWRT-builder/ ./

#2. 环境变量
export DL=/path/to/your/package/dl
export ARC=/path/to/your/release/dir

#3. 编译
./build-openwrt.sh build
```

---

## 注意事项

### `WARNING: Makefile 'package/feeds/packages/openssh/Makefile' has a dependency on 'libfido2', which does not exist`

**如果出现以上WARNING，最好的办法是删除本地代码，重新再来！！！***
