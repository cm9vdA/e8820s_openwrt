#!/bin/bash

WORKSPACE=${PWD}
SRC_PATH=${WORKSPACE}/src/
SRC_GIT_URL=https://github.com/coolsnowwolf/lede
BIN_PATH=${SRC_PATH}/bin/targets/ramips/mt7621/

update_openwrt() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Clone OpenWrt from ${SRC_GIT_URL}"
        mkdir ${SRC_PATH} -p
        git clone ${SRC_GIT_URL} ${SRC_PATH} --depth=1
        return 0
    fi

    echo "Update OpenWrt from ${SRC_GIT_URL}"
    cd ${SRC_PATH}
    git pull
}

update_feeds() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Please Update OpenWrt First"
        return -1
    fi

    cd ${SRC_PATH}
    git checkout feeds.conf.default

    cat <<EOF >>feeds.conf.default
src-git lienol https://github.com/Lienol/openwrt-package
#src-git wifidog https://github.com/wifidog/wifidog-gateway.git
src-git kenzo https://github.com/kenzok8/openwrt-packages
src-git passwall https://github.com/xiaorouji/openwrt-passwall
src-git helloworld https://github.com/fw876/helloworld
EOF

    # 更新插件
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

make_defconfig() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Please Update OpenWrt First"
        return -1
    fi
    local index=0

    cd ${SRC_PATH}

    git checkout package/base-files/files/bin/config_generate
    let index+=1
    echo "${index}. Set Local Network Address"
    sed -i 's/192.168.1.1/10.10.10.1/g' package/base-files/files/bin/config_generate

    let index+=1
    echo "${index}. Set Host Name"
    sed -i 's/OpenWrt/E8820S/g' package/base-files/files/bin/config_generate

    let index+=1
    echo "${index}. Set Time Zone"
    sed -i "s/'UTC'/'CST-8'\n		set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

    git checkout package/kernel/mac80211/files/lib/wifi/mac80211.sh
    let index+=1
    echo "${index}. Set Open Source Driver SSID"
    sed -i 's/OpenWrt/ZTE/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh

    git checkout package/lean/mt/drivers/mt_wifi/files/mt7603.dat
    git checkout package/lean/mt/drivers/mt_wifi/files/mt7612.dat
    let index+=1
    echo "${index}. Set Closed Source Driver SSID"
    sed -i 's/OpenWrt_2G/ZTE/g' package/lean/mt/drivers/mt_wifi/files/mt7603.dat
    sed -i 's/OpenWrt_5G/ZTE_5G/g' package/lean/mt/drivers/mt_wifi/files/mt7612.dat

    git checkout ./package/lean/default-settings/files/zzz-default-settings
    let index+=1
    echo "${index}. Set Root Password To None"
    sed -i 's@.*CYXluq4wUazHjmCDBCqXF*@#&@g' ./package/lean/default-settings/files/zzz-default-settings

    git checkout package/base-files/files/etc/sysctl.conf
    let index+=1
    echo "${index}. Set nf_conntrack_max"
    sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

    # git checkout target/linux/ramips/Makefile
    # echo "${index}. Set Kernel Version To 5.10"
    # sed -i 's/5.4/5.10/g' target/linux/ramips/Makefile

    # let index+=1
    # echo "${index}. Set Default Theme"
    # sed -i 's/luci-theme-bootstrap/luci-theme-argonne/g' feeds/luci/collections/luci/Makefile

    let index+=1
    echo "${index}. Copy default config"
    \cp -f ${WORKSPACE}/config/config .config

    make defconfig
}

archive_img() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Please Update OpenWrt First"
        return -1
    fi

    local img_path=./img
    local pack_info

    rm -rf ${img_path}
    mkdir -p ${img_path}
    mv ${BIN_PATH}/*.bin ${img_path}
    mv ${BIN_PATH}/*.buildinfo ${img_path}
    mv ${BIN_PATH}/*.manifest ${img_path}
    mv ${BIN_PATH}/sha256sums ${img_path}

    # Input log
    read -p "Input Package Log:" pack_info
    echo "$pack_info" >"${img_path}/info"

    # Package
    local pack_name="openwrt_$(date +%Y%m%d_%H%M).tar.xz"
    TIME="Total Time: %E\tExit:%x" time tar cJfp ${pack_name} ${img_path}
    echo "Package To ${pack_name}"
}

make_img_download() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Please Update OpenWrt First"
        return -1
    fi

    cd ${SRC_PATH}
    make download -j8
}

make_img() {
    if [ ! -d ${SRC_PATH} ]; then
        echo "Please Update OpenWrt First"
        return -1
    fi

    cd ${SRC_PATH}
    # rm -rf ./tmp
    if [ "$1" = "debug" ]; then
        make -j1 V=s
    else
        make -j $(nproc)
    fi
    if [ $? -eq 0 ]; then
        echo "BIN PATH: ${BIN_PATH}"
        ls -lh "${BIN_PATH}"
    fi
}

prepare_closed_source() {
    cat <<EOF >package/base-files/files/etc/init.d/wifi_up
ifconfig ra0 up
ifconfig rai0 up
brctl addif br-lan ra0
brctl addif br-lan rai0"
EOF
}

show_menu() {
    local option
    echo "================ Menu Option ================"
    echo -e "\t[0]. Update"
    echo -e "\t[01] ├─Update OpenWrt"
    echo -e "\t[02] └─Update Feeds"
    echo -e "\t[1]. Use Default Config"
    echo -e "\t[2]. Menu Config"
    echo -e "\t[3]. Build"
    echo -e "\t[31] ├─Download"
    echo -e "\t[32] └─Build Image"
    echo -e "\t[33] └─Build Image(For Check Error)"
    echo -e "\t[4]. Archive"
    echo -e "\t[5]. Clean"

    read -p "Please Select: >> " option
    case ${option} in
    "0")
        update_openwrt
        update_feeds
        ;;
    "01")
        update_openwrt
        ;;
    "02")
        update_feeds
        ;;
    "1")
        make_defconfig
        ;;
    "2")
        cd ${SRC_PATH}
        make menuconfig
        ;;
    "3")
        make_img_download
        make_img
        ;;
    "31")
        make_img_download
        ;;
    "32")
        make_img
        ;;
    "33")
        make_img debug
        ;;
    "4")
        archive_img
        ;;
    "5")
        rm -rf ./tmp
        make clean
        ;;
    *)
        echo "Not Support Option: [${option}]"
        ;;
    esac
}

show_menu
