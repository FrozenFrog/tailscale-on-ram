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
exit 0
EOF
chmod 755 "$WORK/fake-tailscaled"

for binary in \
	tailscaled-linux-mipsle-softfloat \
	tailscaled-linux-mipsle-softfloat-upx \
	tailscaled-linux-mips-softfloat \
	tailscaled-linux-mips-softfloat-upx; do
	cp "$WORK/fake-tailscaled" "$WORK/payload/$binary"
	(
		cd "$WORK/payload"
		sha256sum "$binary" > "$binary.sha256"
	)
done

cat > "$WORK/bin/wget" <<'EOF'
#!/bin/sh
[ "$1" = "-O" ] || exit 2
OUTPUT=$2
URL=$3
cp "$TEST_PAYLOAD/${URL##*/}" "$OUTPUT"
EOF
chmod 755 "$WORK/bin/wget"

sed \
	-e 's|__DEFAULT_BASE_URL__|http://test.invalid/files|g' \
	-e 's|__INSTALLER_FILE__|install-http.sh|g' \
	"$ROOT/installer/install.sh" > "$WORK/install-http.sh"

run_install() {
	PROFILE=$1
	PACK=$2
	ARCH=$3
	CASE_DIR="$WORK/$PROFILE-$PACK"
	mkdir -p "$CASE_DIR/runtime" "$CASE_DIR/state" "$CASE_DIR/run"

	PATH="$WORK/bin:$PATH" \
	TEST_PAYLOAD="$WORK/payload" \
	TAILSCALE_DIR="$CASE_DIR/runtime" \
	TAILSCALE_STATE_DIR="$CASE_DIR/state" \
	TAILSCALE_RUNTIME_DIR="$CASE_DIR/run" \
	TAILSCALE_BOOT_SCRIPT="$CASE_DIR/start.sh" \
	TAILSCALE_ENABLER_CONF="$CASE_DIR/enabler.conf" \
	TAILSCALE_AUTO_START=0 \
	TAILSCALE_INSTALL_OPENWRT_INIT=0 \
	sh "$WORK/install-http.sh" "$PROFILE" "$PACK" http://test.invalid/files

	test -x "$CASE_DIR/runtime/tailscaled"
	test -x "$CASE_DIR/runtime/tailscale"
	test -x "$CASE_DIR/runtime/tailscale-init"
	test -x "$CASE_DIR/start.sh"
	grep -q "TAILSCALE_PROFILE='$PROFILE'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_PACK='$PACK'" "$CASE_DIR/enabler.conf"
	grep -q "TAILSCALE_INSTALLER_FILE='install-http.sh'" "$CASE_DIR/enabler.conf"
	cmp "$CASE_DIR/runtime/tailscaled" "$WORK/payload/tailscaled-linux-$ARCH-softfloat${PACK#plain}"
}

run_install t10 plain mipsle

# The UPX suffix is handled separately because ${PACK#plain} is empty only for
# the plain case.
PROFILE=w300rt
PACK=upx
CASE_DIR="$WORK/$PROFILE-$PACK"
mkdir -p "$CASE_DIR/runtime" "$CASE_DIR/state" "$CASE_DIR/run"
PATH="$WORK/bin:$PATH" \
TEST_PAYLOAD="$WORK/payload" \
TAILSCALE_DIR="$CASE_DIR/runtime" \
TAILSCALE_STATE_DIR="$CASE_DIR/state" \
TAILSCALE_RUNTIME_DIR="$CASE_DIR/run" \
TAILSCALE_BOOT_SCRIPT="$CASE_DIR/start.sh" \
TAILSCALE_ENABLER_CONF="$CASE_DIR/enabler.conf" \
TAILSCALE_AUTO_START=0 \
TAILSCALE_INSTALL_OPENWRT_INIT=0 \
sh "$WORK/install-http.sh" w300rt upx http://test.invalid/files

test -x "$CASE_DIR/runtime/tailscaled"
grep -q "TAILSCALE_PROFILE='w300rt'" "$CASE_DIR/enabler.conf"
grep -q "TAILSCALE_PACK='upx'" "$CASE_DIR/enabler.conf"
cmp "$CASE_DIR/runtime/tailscaled" "$WORK/payload/tailscaled-linux-mips-softfloat-upx"

echo "installer tests passed"
