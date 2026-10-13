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
# protocol does not import that modem-side value automatically. Install an APN
# synchronizer into the existing SIM-refresh monitor instead of querying the
# modem from uci-defaults, which runs before ModemManager is ready.
if grep -q '^CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003=y$' .config; then
  # scripts/feeds installs a package from utils/openstick-tweaks as
  # package/feeds/openstick/openstick-tweaks (the category is omitted).
  # Keep the source-tree path as a fallback for alternate feed installers.
  OPENSTICK_TWEAK=""
  for candidate in \
    package/feeds/openstick/openstick-tweaks/files/openstick_tweak \
    package/feeds/openstick/utils/openstick-tweaks/files/openstick_tweak \
    feeds/openstick/utils/openstick-tweaks/files/openstick_tweak; do
    if [ -f "$candidate" ]; then
      OPENSTICK_TWEAK="$candidate"
      break
    fi
  done
  if [ -z "$OPENSTICK_TWEAK" ]; then
    echo "ERROR: could not find OpenStick defaults (openstick_tweak) after feed installation"
    exit 1
  fi
  APN_BLOCK=$(cat <<'EOF'
# APN selection is asynchronous. qmi_auto_activate invokes
# openstick-apn-sync when the SIM becomes ready or changes.
uci set network.modem.iptype='ipv4'
EOF
)

  if ! grep -q '^# APN selection is asynchronous' "$OPENSTICK_TWEAK"; then
    awk -v apn_block="$APN_BLOCK" '
      !inserted && $0 ~ /^uci set network[.]modem[.]iptype=/ && $0 ~ /ipv4v6/ {
        printf "%s\n", apn_block
        inserted=1
        next
      }
      { print }
    ' "$OPENSTICK_TWEAK" > "$OPENSTICK_TWEAK.tmp" && mv "$OPENSTICK_TWEAK.tmp" "$OPENSTICK_TWEAK"
  fi

  grep -q '^# APN selection is asynchronous' "$OPENSTICK_TWEAK" || {
    echo "ERROR: failed to add dynamic SIM APN selection to OpenStick defaults"
    exit 1
  }
  # The firmware uses opkg, not Alpine's apk. Leaving this command in the
  # uci-default script makes it return 127, so OpenWrt runs it on every boot.
  sed -i '/apk del openstick-tweaks/d' "$OPENSTICK_TWEAK"

  APN_SYNC=files/usr/bin/openstick-apn-sync
  if [ ! -f "$APN_SYNC" ]; then
    echo "ERROR: missing UFI003 APN synchronizer: $APN_SYNC"
    exit 1
  fi
  chmod 0755 "$APN_SYNC"

  QMI_AUTO_ACTIVATE=""
  for candidate in \
    package/feeds/openstick/qmi-modem-410-init/files/qmi_auto_activate.sh \
    package/feeds/openstick/utils/qmi-modem-410-init/files/qmi_auto_activate.sh \
    feeds/openstick/utils/qmi-modem-410-init/files/qmi_auto_activate.sh; do
    if [ -f "$candidate" ]; then
      QMI_AUTO_ACTIVATE="$candidate"
      break
    fi
  done
  if [ -z "$QMI_AUTO_ACTIVATE" ]; then
    echo "ERROR: could not find qmi_auto_activate.sh after feed installation"
    exit 1
  fi

  if ! grep -q 'openstick-apn-sync-hook' "$QMI_AUTO_ACTIVATE"; then
    awk '
      !startup_hook && /^echo "设备: / {
        print
        print "# openstick-apn-sync-hook: initial SIM present at boot"
        print "/usr/bin/openstick-apn-sync --wait 120 >/dev/null 2>&1 &"
        startup_hook=1
        next
      }
      {
        print
        if (!refresh_hook && $0 ~ /^[[:space:]]*start_activation_background[[:space:]]*$/) {
          print "                # openstick-apn-sync-hook: SIM inserted or replaced"
          print "                /usr/bin/openstick-apn-sync --expect-change --wait 120 >/dev/null 2>&1 &"
          refresh_hook=1
        }
      }
      END {
        if (!startup_hook || !refresh_hook)
          exit 2
      }
    ' "$QMI_AUTO_ACTIVATE" > "$QMI_AUTO_ACTIVATE.tmp" && \
      mv "$QMI_AUTO_ACTIVATE.tmp" "$QMI_AUTO_ACTIVATE"
  fi

  grep -q 'initial SIM present at boot' "$QMI_AUTO_ACTIVATE" && \
    grep -q 'SIM inserted or replaced' "$QMI_AUTO_ACTIVATE" || {
      echo "ERROR: failed to hook UFI003 APN synchronization into qmi_auto_activate"
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
