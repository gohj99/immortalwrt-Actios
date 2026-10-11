#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 当前 immortalwrt/packages 的 libudev-zero 声明了 +libevdev，
# 但 libevdev 依赖 feeds 中不存在的 input-support，导致 rmtfs 被 defconfig 清除。
# rmtfs 只链接 libudev，不需要 libevdev；移除这个错误的可选依赖。
UDEV_ZERO_MK=package/feeds/packages/libudev-zero/Makefile
if [ ! -f "$UDEV_ZERO_MK" ]; then
  echo "ERROR: expected libudev-zero package Makefile at $UDEV_ZERO_MK"
  exit 1
fi
sed -i '/^[[:space:]]*DEPENDS:=[[:space:]]*+libevdev[[:space:]]*$/d' "$UDEV_ZERO_MK"
if grep -q 'DEPENDS:.*libevdev' "$UDEV_ZERO_MK"; then
  echo "ERROR: failed to remove the unsupported libevdev dependency from libudev-zero"
  exit 1
fi
echo "OK: removed libudev-zero's unsupported libevdev dependency"

# 修改默认IP地址
#sed -i 's/192.168.1.1/192.168.100.1/g' package/base-files/files/bin/config_generate


# 修改默认主题为 argon（路径不存在时跳过，不中断编译）
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# 启用 IPv4 策略路由（直接写入内核 platform config，绕过 make defconfig 的依赖检查）
# CONFIG_KERNEL_IP_ADVANCED_ROUTER 在 OpenWrt Config.in 中无对应 wrapper，必须用此方式
#for cfg in target/linux/msm89xx/config-*; do
#  grep -q 'CONFIG_IP_ADVANCED_ROUTER' "$cfg" || echo 'CONFIG_IP_ADVANCED_ROUTER=y' >> "$cfg"
#  grep -q 'CONFIG_IP_MULTIPLE_TABLES' "$cfg" || echo 'CONFIG_IP_MULTIPLE_TABLES=y' >> "$cfg"
#done


# 临时添加的插件
# git clone https://github.com/lkiuyu/luci-app-cpu-perf package/luci-app-cpu-perf
# git clone https://github.com/lkiuyu/luci-app-cpu-status package/luci-app-cpu-status
# git clone https://github.com/gSpotx2f/luci-app-cpu-status-mini package/luci-app-cpu-status-mini
# git clone https://github.com/lkiuyu/luci-app-temp-status package/luci-app-temp-status
# git clone https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus
