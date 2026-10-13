#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SYNC="$ROOT/files/usr/bin/openstick-apn-sync"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/run" "$TMP/state"
touch "$TMP/wwan0qmi0"

cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" != -q ] || shift
cmd="$1"
shift
case "$cmd" in
	get)
		case "$1" in
			network.modem.apn) file="$MOCK_STATE/current" ;;
			openstick_apn.main) file="$MOCK_STATE/section" ;;
			openstick_apn.main.managed_apn) file="$MOCK_STATE/managed" ;;
			openstick_apn.main.sim_identity) file="$MOCK_STATE/identity" ;;
			openstick_apn.main.operator) file="$MOCK_STATE/operator" ;;
			*) exit 1 ;;
		esac
		[ -f "$file" ] || exit 1
		cat "$file"
		;;
	set)
		key="${1%%=*}"
		value="${1#*=}"
		case "$key" in
			network.modem.apn) file="$MOCK_STATE/current" ;;
			openstick_apn.main) file="$MOCK_STATE/section" ;;
			openstick_apn.main.managed_apn) file="$MOCK_STATE/managed" ;;
			openstick_apn.main.sim_identity) file="$MOCK_STATE/identity" ;;
			openstick_apn.main.operator) file="$MOCK_STATE/operator" ;;
			*) exit 1 ;;
		esac
		printf '%s\n' "$value" >"$file"
		;;
	commit) ;;
	*) exit 1 ;;
esac
EOF

cat >"$TMP/bin/qmicli" <<'EOF'
#!/bin/sh
case "$*" in
	*--dms-uim-get-imsi*)
		[ -n "${MOCK_IMSI:-}" ] || exit 1
		printf "UIM IMSI retrieved:\n\tIMSI: '%s'\n" "$MOCK_IMSI"
		;;
	*--wds-get-default-settings=3gpp*)
		[ -n "${MOCK_PROFILE_APN:-}" ] || exit 1
		printf "Default settings retrieved:\n\tAPN: '%s'\n" "$MOCK_PROFILE_APN"
		;;
	*) exit 1 ;;
esac
EOF

cat >"$TMP/bin/mmcli" <<'EOF'
#!/bin/sh
[ "${MOCK_MMCLI_DOWN:-0}" -ne 1 ] || exit 1
case "$1" in
	-i)
		[ -n "${MOCK_IMSI:-}" ] || exit 1
		printf 'sim.properties.imsi : %s\nsim.properties.operator-code : %s\n' \
			"$MOCK_IMSI" "${MOCK_OPERATOR:-}"
		;;
	-m)
		printf 'modem.3gpp.eps.initial-bearer.settings.apn : %s\n' \
			"${MOCK_PROFILE_APN:---}"
		;;
	*) exit 1 ;;
esac
EOF

cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$TMP/bin/ubus" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MOCK_STATE/ubus_calls"
EOF

chmod +x "$TMP/bin/uci" "$TMP/bin/qmicli" "$TMP/bin/mmcli" \
	"$TMP/bin/logger" "$TMP/bin/ubus"
export PATH="$TMP/bin:$PATH"
export MOCK_STATE="$TMP/state"
export RUN_DIR="$TMP/run"
export QMI_DEVICE="$TMP/wwan0qmi0"

assert_file()
{
	actual="$(cat "$1" 2>/dev/null || true)"
	[ "$actual" = "$2" ] || {
		echo "FAIL: $1: expected '$2', got '$actual'" >&2
		exit 1
	}
}

# First boot with a China Telecom SIM: operator mapping beats a stale profile.
export MOCK_IMSI=460113940590517 MOCK_OPERATOR=46011 MOCK_PROFILE_APN=ctwap
export MOCK_MMCLI_DOWN=1
"$SYNC" --wait 0
assert_file "$MOCK_STATE/current" ctlte
assert_file "$MOCK_STATE/managed" ctlte
assert_file "$MOCK_STATE/identity" 460113940590517
assert_file "$MOCK_STATE/ubus_calls" 'call network reload'
export MOCK_MMCLI_DOWN=0

# Replacing it with a China Mobile SIM updates an automatically managed APN.
export MOCK_IMSI=460001234567890 MOCK_OPERATOR=46000 MOCK_PROFILE_APN=ctlte
"$SYNC" --expect-change --wait 0
assert_file "$MOCK_STATE/current" cmnet
assert_file "$MOCK_STATE/managed" cmnet
assert_file "$MOCK_STATE/identity" 460001234567890
[ "$(wc -l <"$MOCK_STATE/ubus_calls")" -eq 2 ]

# A manually configured private/IoT APN is never overwritten.
printf '%s\n' private.iot >"$MOCK_STATE/current"
export MOCK_IMSI=460119999999999 MOCK_OPERATOR=46011 MOCK_PROFILE_APN=ctlte
"$SYNC" --expect-change --wait 0
assert_file "$MOCK_STATE/current" private.iot
assert_file "$MOCK_STATE/managed" cmnet
[ "$(wc -l <"$MOCK_STATE/ubus_calls")" -eq 2 ]

# First boot without a SIM leaves APN unset; inserting one later configures it.
rm -f "$MOCK_STATE"/*
export MOCK_IMSI= MOCK_OPERATOR= MOCK_PROFILE_APN=
"$SYNC" --wait 0
[ ! -e "$MOCK_STATE/current" ] || {
	echo 'FAIL: APN was created without a SIM' >&2
	exit 1
}

export MOCK_IMSI=460113940590517 MOCK_OPERATOR=46011 MOCK_PROFILE_APN=ctlte
"$SYNC" --expect-change --wait 0
assert_file "$MOCK_STATE/current" ctlte

echo 'PASS: openstick APN synchronization scenarios'
