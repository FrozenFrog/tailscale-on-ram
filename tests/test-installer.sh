#!/bin/sh

set -eu

ROOT=`CDPATH= cd -- "$(dirname "$0")/.." && pwd`
WORK=`mktemp -d "${TMPDIR:-/tmp}/tailscale-enabler-test.XXXXXX"`
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

mkdir -p "$WORK/bin" "$WORK/payload"
cp "$ROOT/router/tailscale" "$ROOT/router/tailscale-init" \
	"$ROOT/router/tailscale-boot" "$ROOT/router/tailscale-openwrt-init" \
	"$WORK/payload/"

cat > "$WORK/fake-tailscaled" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	echo 1.98.8
	exit 0
fi
exec sleep 30
EOF
chmod 755 "$WORK/fake-tailscaled"

cat > "$WORK/fake-tailscaled-dying" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	echo 1.98.8
	exit 0
fi
exit 0
EOF
chmod 755 "$WORK/fake-tailscaled-dying"

for binary in \
	tailscaled-linux-mipsle-softfloat \
	tailscaled-linux-mipsle-softfloat-upx \
	tailscaled-linux-mipsle-hardfloat \
	tailscaled-linux-mipsle-hardfloat-upx \
	tailscaled-linux-mips-softfloat \
	tailscaled-linux-mips-softfloat-upx \
	tailscaled-linux-mips-hardfloat \
	tailscaled-linux-mips-hardfloat-upx \
	tailscaled-linux-mips64-softfloat \
	tailscaled-linux-mips64-hardfloat \
	tailscaled-linux-mips64le-softfloat \
	tailscaled-linux-mips64le-hardfloat \
	tailscaled-linux-armv5 \
	tailscaled-linux-armv5-upx \
	tailscaled-linux-armv7 \
	tailscaled-linux-armv7-upx; do
	cp "$WORK/fake-tailscaled" "$WORK/payload/$binary"
done
(
	cd "$WORK/payload"
	ls tailscaled-linux-* | sort | xargs sha256sum > SHA256SUMS
)

# Stand-in for the static BusyBox the installer fetches on old firmwares;
# answers `busybox true` with success and `busybox --install -s <dir>` by
# dropping a wget applet stub so the keep/remove logic can be tested.
cat > "$WORK/payload/busybox-mipsel" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--install" ]; then
	printf '#!/bin/sh\nexit 1\n' > "$3/wget"
	chmod 755 "$3/wget"
fi
exit 0
EOF
chmod 755 "$WORK/payload/busybox-mipsel"

cat > "$WORK/bin/wget" <<'EOF'
#!/bin/sh
[ "$1" = "-O" ] || exit 2
OUTPUT=$2
URL=$3
case "$URL" in
	http://dead.invalid/*) exit 1 ;;
esac
cp "$TEST_PAYLOAD/${URL##*/}" "$OUTPUT"
EOF
chmod 755 "$WORK/bin/wget"

# Mimics a firmware that ships curl instead of wget: the wget stub always
# fails (a broken or absent wget) so fetch_url must fall through to curl.
mkdir -p "$WORK/bin-curl"
cat > "$WORK/bin-curl/curl" <<'EOF'
#!/bin/sh
OUTPUT=
URL=
while [ $# -gt 0 ]; do
	case "$1" in
		-o) OUTPUT=$2; shift 2 ;;
		-f|-L|-k) shift ;;
		*) URL=$1; shift ;;
	esac
done
[ -n "$OUTPUT" ] || exit 2
cp "$TEST_PAYLOAD/${URL##*/}" "$OUTPUT"
EOF
chmod 755 "$WORK/bin-curl/curl"
cat > "$WORK/bin-curl/wget" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 "$WORK/bin-curl/wget"

# Same firmware but without any wget in PATH at all (needs a minimal tool
# dir so the host's real wget cannot leak in).
mkdir -p "$WORK/bin-curl-pure" "$WORK/bin-min"
cp "$WORK/bin-curl/curl" "$WORK/bin-curl-pure/curl"
for tool in mkdir rm chmod grep cat mv ln cp sleep; do
	ln -s "`command -v $tool`" "$WORK/bin-min/$tool"
done

# Mimics BusyBox wget without CA certificates: plain fetches fail the
# certificate check; only --no-check-certificate succeeds.
mkdir -p "$WORK/bin-strict"
cat > "$WORK/bin-strict/wget" <<'EOF'
#!/bin/sh
if [ "$1" != "--no-check-certificate" ]; then
	echo "wget: TLS certificate verification failed" >&2
	exit 1
fi
shift
[ "$1" = "-O" ] || exit 2
OUTPUT=$2
URL=$3
cp "$TEST_PAYLOAD/${URL##*/}" "$OUTPUT"
EOF
chmod 755 "$WORK/bin-strict/wget"

sed \
	-e 's|__DEFAULT_BASE_URL__|http://test.invalid/files|g' \
	-e 's|__INSTALLER_FILE__|install-http.sh|g' \
	"$ROOT/installer/install.sh" > "$WORK/install-http.sh"

run_install() {
	PROFILE=$1
	PACK=$2
	BINARY_BASE=$3
	EXPECTED_PROFILE=${4:-$PROFILE}
	CASE_DIR="$WORK/$PROFILE-$PACK"
	SUFFIX=
	[ "$PACK" = "upx" ] && SUFFIX=-upx
	mkdir -p "$CASE_DIR/runtime" "$CASE_DIR/state" "$CASE_DIR/run"

	PATH="${WGET_BIN:-$WORK/bin}:$PATH" \
	TEST_PAYLOAD="$WORK/payload" \
	TAILSCALE_DIR="$CASE_DIR/runtime" \
	TAILSCALE_STATE_DIR="$CASE_DIR/state" \
	TAILSCALE_RUNTIME_DIR="$CASE_DIR/run" \
	TAILSCALE_BOOT_SCRIPT="$CASE_DIR/start.sh" \
	TAILSCALE_ENABLER_CONF="$CASE_DIR/enabler.conf" \
	TAILSCALE_AUTO_START=0 \
	TAILSCALE_INSTALL_OPENWRT_INIT=0 \
	TAILSCALE_NEED_BUSYBOX="${NEED_BUSYBOX:-0}" \
	sh "$WORK/install-http.sh" "$PROFILE" "$PACK" \
		"${BASE_ARG:-http://test.invalid/files}"

	test -x "$CASE_DIR/runtime/tailscaled"
	test -x "$CASE_DIR/runtime/tailscale"
	test -x "$CASE_DIR/runtime/tailscale-init"
	test -x "$CASE_DIR/start.sh"
	grep -q "TAILSCALE_PROFILE='$EXPECTED_PROFILE'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_PACK='$PACK'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_INSTALLER_FILE='install-http.sh'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_TUN='tailscale0'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_ENABLE_FORWARDING='1'" "$CASE_DIR/enabler.conf"
	cmp "$CASE_DIR/runtime/tailscaled" "$WORK/payload/$BINARY_BASE$SUFFIX"
}

run_install mips plain tailscaled-linux-mips-softfloat
run_install mips-softfloat upx tailscaled-linux-mips-softfloat
run_install mips-hardfloat plain tailscaled-linux-mips-hardfloat
run_install mips-hardfloat upx tailscaled-linux-mips-hardfloat
run_install mipsle plain tailscaled-linux-mipsle-softfloat
run_install mipsle-softfloat upx tailscaled-linux-mipsle-softfloat
run_install mipsle-hardfloat plain tailscaled-linux-mipsle-hardfloat
run_install mipsle-hardfloat upx tailscaled-linux-mipsle-hardfloat
run_install mips64 plain tailscaled-linux-mips64-softfloat
run_install mips64-softfloat plain tailscaled-linux-mips64-softfloat
run_install mips64-hardfloat plain tailscaled-linux-mips64-hardfloat
run_install mips64le plain tailscaled-linux-mips64le-softfloat
run_install mips64le-softfloat plain tailscaled-linux-mips64le-softfloat
run_install mips64le-hardfloat plain tailscaled-linux-mips64le-hardfloat
run_install arm5 plain tailscaled-linux-armv5
run_install armv5 upx tailscaled-linux-armv5 arm5
run_install arm7 upx tailscaled-linux-armv7
run_install armv7 plain tailscaled-linux-armv7 arm7

# wget without CA certificates must fall back to --no-check-certificate
WGET_BIN="$WORK/bin-strict"
run_install mips upx tailscaled-linux-mips-softfloat
WGET_BIN=

# firmware with a broken/failing wget must fall back to curl
WGET_BIN="$WORK/bin-curl"
run_install mips-softfloat plain tailscaled-linux-mips-softfloat
WGET_BIN=

# dead primary mirror: downloads must fall back to the next base URL and
# the configuration must record the mirror that answered first
BASE_ARG="http://dead.invalid/files http://test.invalid/files"
run_install arm5 upx tailscaled-linux-armv5
BASE_ARG=
grep -q "TAILSCALE_BASE_URL='http://test.invalid/files'" \
	"$WORK/arm5-upx/enabler.conf"
grep -q "TAILSCALE_BASE_URLS='http://test.invalid/files http://dead.invalid/files'" \
	"$WORK/arm5-upx/enabler.conf"

# 1.13-era firmware BusyBox: installer must fetch a static BusyBox first
# and expose its applet directory; the wget applet is dropped because the
# firmware has its own wget
NEED_BUSYBOX=1
run_install mipsle upx tailscaled-linux-mipsle-softfloat
NEED_BUSYBOX=
test -x "$WORK/mipsle-upx/runtime/busybox"
test -d "$WORK/mipsle-upx/runtime/bb"
cmp "$WORK/mipsle-upx/runtime/busybox" "$WORK/payload/busybox-mipsel"
test ! -e "$WORK/mipsle-upx/runtime/bb/wget"

# curl-only firmware (no wget anywhere in PATH): the BusyBox wget applet
# must be kept as a fallback downloader
CP="$WORK/curl-pure"
mkdir -p "$CP/runtime" "$CP/state" "$CP/run"
PATH="$WORK/bin-curl-pure:$WORK/bin-min" \
	TEST_PAYLOAD="$WORK/payload" \
	TAILSCALE_DIR="$CP/runtime" \
	TAILSCALE_STATE_DIR="$CP/state" \
	TAILSCALE_RUNTIME_DIR="$CP/run" \
	TAILSCALE_BOOT_SCRIPT="$CP/start.sh" \
	TAILSCALE_ENABLER_CONF="$CP/enabler.conf" \
	TAILSCALE_AUTO_START=0 \
	TAILSCALE_INSTALL_OPENWRT_INIT=0 \
	TAILSCALE_NEED_BUSYBOX=1 \
	TAILSCALE_DOWNLOAD_RETRIES=1 \
	/bin/sh "$WORK/install-http.sh" mipsle upx http://test.invalid/files
test -x "$CP/runtime/tailscaled"
test -e "$CP/runtime/bb/wget"

# no downloader at all: fail fast instead of retrying silently
ND="$WORK/no-downloader"
mkdir -p "$ND/runtime" "$ND/state" "$ND/run"
if PATH="$WORK/bin-min" \
	TAILSCALE_DIR="$ND/runtime" \
	TAILSCALE_STATE_DIR="$ND/state" \
	TAILSCALE_RUNTIME_DIR="$ND/run" \
	TAILSCALE_BOOT_SCRIPT="$ND/start.sh" \
	TAILSCALE_ENABLER_CONF="$ND/enabler.conf" \
	TAILSCALE_AUTO_START=0 \
	TAILSCALE_INSTALL_OPENWRT_INIT=0 \
	/bin/sh "$WORK/install-http.sh" mipsle plain http://test.invalid/files \
		2>"$ND/install.err"; then
	echo "install should fail fast without wget and curl" >&2
	exit 1
fi
grep -q "neither wget nor curl" "$ND/install.err"

if sh "$WORK/install-http.sh" mips64 upx http://test.invalid/files 2>/dev/null; then
	echo "mips64 upx should be rejected" >&2
	exit 1
fi

if sh "$WORK/install-http.sh" mips64le-hardfloat upx http://test.invalid/files 2>/dev/null; then
	echo "mips64le-hardfloat upx should be rejected" >&2
	exit 1
fi

# tailscale-init lifecycle: TUN fallback, status, stop
LC="$WORK/lifecycle"
mkdir -p "$LC/runtime" "$LC/state" "$LC/run"
cp "$ROOT/router/tailscale-init" "$LC/runtime/tailscale-init"
cp "$WORK/fake-tailscaled" "$LC/runtime/tailscaled"
chmod 755 "$LC/runtime/tailscale-init" "$LC/runtime/tailscaled"
cat > "$LC/enabler.conf" <<EOF
TAILSCALE_DIR='$LC/runtime'
TAILSCALE_STATE_DIR='$LC/state'
TAILSCALE_RUNTIME_DIR='$LC/run'
TAILSCALE_TUN='tailscale0'
TAILSCALE_ENABLE_FORWARDING='0'
EOF
: > "$LC/proc-misc"

TAILSCALE_ENABLER_CONF="$LC/enabler.conf" \
	TAILSCALE_PROC_MISC="$LC/proc-misc" \
	sh "$LC/runtime/tailscale-init" start 2>"$LC/start.err"
grep -q "TAILSCALE_TUN='userspace-networking'" "$LC/enabler.conf"
grep -q "falling back to userspace-networking" "$LC/start.err"
test -f "$LC/run/tailscaled.pid"
TAILSCALE_ENABLER_CONF="$LC/enabler.conf" sh "$LC/runtime/tailscale-init" status

TAILSCALE_ENABLER_CONF="$LC/enabler.conf" sh "$LC/runtime/tailscale-init" stop
test ! -f "$LC/run/tailscaled.pid"
test ! -e "$LC/run/tailscaled.sock"
if TAILSCALE_ENABLER_CONF="$LC/enabler.conf" \
	sh "$LC/runtime/tailscale-init" status >/dev/null; then
	echo "status should fail after stop" >&2
	exit 1
fi

# tailscale-init start must fail when the daemon dies right away
FC="$WORK/lifecycle-fail"
mkdir -p "$FC/runtime" "$FC/state" "$FC/run"
cp "$ROOT/router/tailscale-init" "$FC/runtime/tailscale-init"
cp "$WORK/fake-tailscaled-dying" "$FC/runtime/tailscaled"
chmod 755 "$FC/runtime/tailscale-init" "$FC/runtime/tailscaled"
cat > "$FC/enabler.conf" <<EOF
TAILSCALE_DIR='$FC/runtime'
TAILSCALE_STATE_DIR='$FC/state'
TAILSCALE_RUNTIME_DIR='$FC/run'
TAILSCALE_TUN='userspace-networking'
TAILSCALE_ENABLE_FORWARDING='0'
EOF

if TAILSCALE_ENABLER_CONF="$FC/enabler.conf" \
	sh "$FC/runtime/tailscale-init" start 2>"$FC/start.err"; then
	echo "start should fail when tailscaled dies right away" >&2
	exit 1
fi
grep -q "exited right after start" "$FC/start.err"
test ! -f "$FC/run/tailscaled.pid"

echo "installer tests passed"
