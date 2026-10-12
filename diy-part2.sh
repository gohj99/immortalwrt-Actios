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

# The UFI003 modem reports an initial EPS APN, but netifd's modemmanager
# protocol does not import that modem-side value automatically. Resolve the
# APN from the active SIM on first boot instead of baking in one carrier.
if grep -q '^CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003=y$' .config; then
  OPENSTICK_TWEAK=package/feeds/openstick/utils/openstick-tweaks/files/openstick_tweak
  if [ ! -f "$OPENSTICK_TWEAK" ]; then
    echo "ERROR: expected OpenStick defaults at $OPENSTICK_TWEAK"
    exit 1
  fi
  APN_BLOCK=$(cat <<'EOF'
# A normal SIM exposes IMSI/MCC/MNC, not an APN string. Read the modem's
# configured initial bearer APN first; use the operator table only as a
# fallback for cards whose modem profile does not expose one.
SIM_OPERATOR=""
MODEM_APN=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  SIM_OPERATOR="$(mmcli -i any --output-keyvalue 2>/dev/null | grep 'sim.properties.operator-code' | cut -d: -f2- | tr -d '[:space:]' | head -n1)"
  MODEM_APN="$(mmcli -m any --output-keyvalue 2>/dev/null | grep 'modem.3gpp.eps.initial-bearer-apn' | cut -d: -f2- | tr -d '[:space:]' | head -n1)"
  [ -n "$SIM_OPERATOR" ] && [ "$SIM_OPERATOR" != "--" ] && break
  sleep 2
done

# Prefer the modem's configured initial bearer APN. This path is independent
# of country and operator, so a non-Chinese carrier works when its modem
# profile supplies an APN.
case "$MODEM_APN" in
  ""|"--")
    case "$SIM_OPERATOR" in
      46000|46002|46004|46007|46008|46015|46020)
        SIM_APN='cmnet'
        ;;
      46001|46006|46009)
        SIM_APN='3gnet'
        ;;
      46003|46005|46011|46012)
        SIM_APN='ctlte'
        ;;
      46013)
        SIM_APN='cbnet'
        ;;
      *)
        SIM_APN=""
        ;;
    esac
    ;;
  *)
    SIM_APN="$MODEM_APN"
    ;;
esac

if [ -n "$SIM_APN" ]; then
  uci set network.modem.apn="$SIM_APN"
else
  uci -q delete network.modem.apn
fi
uci set network.modem.iptype='ipv4'
EOF
)

  if ! grep -q '^# Select the data APN from the SIM operator' "$OPENSTICK_TWEAK"; then
    awk -v apn_block="$APN_BLOCK" '
      !inserted && $0 ~ /^uci set network[.]modem[.]iptype=/ && $0 ~ /ipv4v6/ {
        printf "%s\n", apn_block
        inserted=1
        next
      }
      { print }
    ' "$OPENSTICK_TWEAK" > "$OPENSTICK_TWEAK.tmp" && mv "$OPENSTICK_TWEAK.tmp" "$OPENSTICK_TWEAK"
  fi

  grep -q '^# Select the data APN from the SIM operator' "$OPENSTICK_TWEAK" || {
    echo "ERROR: failed to add dynamic SIM APN selection to OpenStick defaults"
    exit 1
  }
  echo "OK: configured dynamic SIM APN selection for UFI003"
fi

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
