#!/bin/bash
set -euo pipefail

echo "=========================================="
echo " [customize.sh] 开始应用 N828 自定义配置"
echo "=========================================="

CONFIG=".config"
[ -f "$CONFIG" ] || { echo "❌ .config 不存在，当前目录：$(pwd)"; exit 1; }

# ---------- 工具函数 ----------
disable_pkg() {
    local pkg="$1"
    sed -i "/^CONFIG_PACKAGE_${pkg}=/d" "$CONFIG"
    grep -q "^# CONFIG_PACKAGE_${pkg} is not set" "$CONFIG" || \
        echo "# CONFIG_PACKAGE_${pkg} is not set" >> "$CONFIG"
}

enable_pkg() {
    local pkg="$1"
    sed -i "/^# CONFIG_PACKAGE_${pkg} is not set/d" "$CONFIG"
    sed -i "/^CONFIG_PACKAGE_${pkg}=m/d" "$CONFIG"
    grep -q "^CONFIG_PACKAGE_${pkg}=y" "$CONFIG" || \
        echo "CONFIG_PACKAGE_${pkg}=y" >> "$CONFIG"
}

set_config() {
    local key="$1" val="$2"
    sed -i "/^${key}=/d" "$CONFIG"
    echo "${key}=${val}" >> "$CONFIG"
}

# ---------- 1. LuCI 重组：保留登录/系统/网络/无线/防火墙/状态，去掉软件包页 ----------
echo ">>> 重组 LuCI：拆分元包，保留核心管理界面..."
disable_pkg "luci-mod-admin-full"
disable_pkg "luci-app-opkg"
disable_pkg "luci-proto-ipv6"
disable_pkg "luci-proto-ppp"

enable_pkg "luci-base"
enable_pkg "luci-theme-bootstrap"
enable_pkg "luci-mod-system"
enable_pkg "luci-mod-network"
enable_pkg "luci-mod-status"
enable_pkg "luci-app-firewall"
enable_pkg "luci-compat"

# ---------- 2. 移除 opkg（4M Flash 极限精简，LuCI 软件包页已随之禁用） ----------
echo ">>> 移除 opkg..."
disable_pkg "opkg"

# ---------- 3. 用户空间 IPv6 精简（保留 kmod-ipv6 / kmod-ip6tables 给 dnsmasq） ----------
echo ">>> 移除用户空间 IPv6 组件..."
disable_pkg "odhcp6c"
disable_pkg "odhcpd"
disable_pkg "odhcpd-ipv6only"
disable_pkg "ip6tables"
disable_pkg "6relayd"

# ---------- 4. 移除其他非必需包 ----------
echo ">>> 移除其他非必需包..."
disable_pkg "kmod-usb-storage"
disable_pkg "kmod-usb-serial"
disable_pkg "kmod-usb-serial-option"
disable_pkg "usb-modeswitch"
disable_pkg "comgt"
disable_pkg "b43-firmware"
disable_pkg "zd1211-firmware"

# ---------- 5. 可选：zram-swap（32M 内存按需开启，4M Flash 下谨慎） ----------
# enable_pkg "zram-swap"
# enable_pkg "kmod-zram"

# ---------- 6. 编译优化（不覆盖 TARGET_OPTIMIZATION，RT3052F 为 24KEc） ----------
echo ">>> 追加编译优化配置..."
set_config "CONFIG_STRIP_KERNEL_EXPORTS" "y"
set_config "CONFIG_USE_MKLIBS" "y"

# ---------- 7. 应用额外补丁（仓库根目录 extra-patches/） ----------
WS="${GITHUB_WORKSPACE:-$(pwd)}"
if [ -d "${WS}/extra-patches" ]; then
    echo ">>> 应用额外补丁..."
    for p in "${WS}"/extra-patches/*.patch; do
        [ -f "$p" ] || continue
        echo "  应用: $(basename "$p")"
        patch -p1 < "$p" || echo "  ⚠️ 补丁失败，跳过"
    done
fi

# ---------- 8. 修改默认系统参数 ----------
echo ">>> 修改默认系统参数..."
# hostname 必须改 config_generate，否则首次启动会被覆盖
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i "s/hostname='OpenWrt'/hostname='N828'/" package/base-files/files/bin/config_generate
else
    echo "  ⚠️ 未找到 config_generate，跳过 hostname 修改"
fi
# 时区兜底改 files/etc/config/system
if [ -f "package/base-files/files/etc/config/system" ]; then
    sed -i "s/option zonename 'UTC'/option zonename 'Asia\/Shanghai'/" \
        package/base-files/files/etc/config/system 2>/dev/null || true
fi

echo "=========================================="
echo " [customize.sh] 配置应用完成"
echo "=========================================="
