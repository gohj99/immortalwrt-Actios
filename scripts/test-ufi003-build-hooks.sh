#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UPSTREAM_ROOT="${UPSTREAM_ROOT:-$(CDPATH= cd -- "$ROOT/../openstick-feeds-check" && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

grep -q "^config state 'main'$" "$ROOT/files/etc/config/openstick_apn"

mkdir -p \
	"$TMP/package/feeds/packages/libudev-zero" \
	"$TMP/package/feeds/openstick/openstick-tweaks/files" \
	"$TMP/package/feeds/openstick/qmi-modem-410-init/files" \
	"$TMP/files/usr/bin"

printf '%s\n' 'DEPENDS:= +libevdev' >"$TMP/package/feeds/packages/libudev-zero/Makefile"
cp "$UPSTREAM_ROOT/utils/openstick-tweaks/files/openstick_tweak" \
	"$TMP/package/feeds/openstick/openstick-tweaks/files/openstick_tweak"
cp "$UPSTREAM_ROOT/utils/qmi-modem-410-init/files/qmi_auto_activate.sh" \
	"$TMP/package/feeds/openstick/qmi-modem-410-init/files/qmi_auto_activate.sh"
cp "$ROOT/files/usr/bin/openstick-apn-sync" "$TMP/files/usr/bin/openstick-apn-sync"
# Windows checkouts may expose CRLF even though Git stores these shell scripts
# with LF. Normalize the fixtures to match the Linux build runner.
sed -i 's/\r$//' \
	"$TMP/package/feeds/openstick/openstick-tweaks/files/openstick_tweak" \
	"$TMP/package/feeds/openstick/qmi-modem-410-init/files/qmi_auto_activate.sh"
printf '%s\n' 'CONFIG_TARGET_msm89xx_msm8916_DEVICE_openstick-ufi003=y' >"$TMP/.config"

(
	cd "$TMP"
	bash "$ROOT/diy-part2.sh"
)

TWEAK="$TMP/package/feeds/openstick/openstick-tweaks/files/openstick_tweak"
MONITOR="$TMP/package/feeds/openstick/qmi-modem-410-init/files/qmi_auto_activate.sh"

dash -n "$TWEAK"
dash -n "$MONITOR"
[ "$(grep -c openstick-apn-sync-hook "$MONITOR")" -eq 2 ]
! grep -q 'apk del openstick-tweaks' "$TWEAK"
grep -q '^# APN selection is asynchronous' "$TWEAK"

echo 'PASS: UFI003 build-time APN hooks'
