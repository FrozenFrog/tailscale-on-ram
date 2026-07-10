#!/bin/sh

# These two values are replaced while the release/HTTP payload is assembled.
DEFAULT_BASE_URL="__DEFAULT_BASE_URL__"
DEFAULT_INSTALLER_FILE="__INSTALLER_FILE__"

usage() {
	echo "usage: sh $0 {mips|mipsle|mips64|mips64le|arm5|arm7} [plain|upx] [base-url]" >&2
	exit 2
}

PROFILE_INPUT=${1:-${TAILSCALE_PROFILE:-}}
PACK_INPUT=${2:-${TAILSCALE_PACK:-}}
BASE_INPUT=${3:-}
BASE_ENV=${TAILSCALE_BASE_URL:-}

case "$PROFILE_INPUT" in
	mips|mipsle|mips64|mips64le)
		PROFILE=$PROFILE_INPUT
		ARCH=$PROFILE_INPUT
		BINARY_BASE=tailscaled-linux-$ARCH-softfloat
		DEFAULT_DIR=/tmp/tailscale
		DEFAULT_STATE_DIR=/etc/tailscale-state
		DEFAULT_CONF=/etc/tailscale-enabler.conf
		DEFAULT_BOOT=/etc/tailscale-boot.sh
		;;
	arm5|armv5)
		PROFILE=arm5
		ARCH=armv5
		BINARY_BASE=tailscaled-linux-armv5
		DEFAULT_DIR=/tmp/tailscale
		DEFAULT_STATE_DIR=/etc/tailscale-state
		DEFAULT_CONF=/etc/tailscale-enabler.conf
		DEFAULT_BOOT=/etc/tailscale-boot.sh
		;;
	arm7|armv7)
		PROFILE=arm7
		ARCH=armv7
		BINARY_BASE=tailscaled-linux-armv7
		DEFAULT_DIR=/tmp/tailscale
		DEFAULT_STATE_DIR=/etc/tailscale-state
		DEFAULT_CONF=/etc/tailscale-enabler.conf
		DEFAULT_BOOT=/etc/tailscale-boot.sh
		;;
	*) usage ;;
esac

CONF=${TAILSCALE_ENABLER_CONF:-$DEFAULT_CONF}
[ -f "$CONF" ] && . "$CONF"

# Command-line values override an existing configuration file.
PACK=${PACK_INPUT:-${TAILSCALE_PACK:-plain}}
BASE_URL=${BASE_INPUT:-${BASE_ENV:-$DEFAULT_BASE_URL}}
BASE_URL=${BASE_URL%/}
DIR=${TAILSCALE_DIR:-$DEFAULT_DIR}
STATE_DIR=${TAILSCALE_STATE_DIR:-$DEFAULT_STATE_DIR}
RUNTIME_DIR=${TAILSCALE_RUNTIME_DIR:-/var/run/tailscale}
BOOT_SCRIPT=${TAILSCALE_BOOT_SCRIPT:-$DEFAULT_BOOT}
TUN=${TAILSCALE_TUN:-userspace-networking}
ENABLE_FORWARDING=${TAILSCALE_ENABLE_FORWARDING:-0}
AUTO_START=${TAILSCALE_AUTO_START:-1}
INSTALL_OPENWRT_INIT=${TAILSCALE_INSTALL_OPENWRT_INIT:-1}
DOWNLOAD_RETRIES=${TAILSCALE_DOWNLOAD_RETRIES:-20}
DOWNLOAD_RETRY_DELAY=${TAILSCALE_DOWNLOAD_RETRY_DELAY:-15}
INSTALLER_FILE=$DEFAULT_INSTALLER_FILE

case "$PACK" in
	plain) BINARY=$BINARY_BASE ;;
	upx) BINARY="$BINARY_BASE-upx" ;;
	*) usage ;;
esac

case "$PACK:$ARCH" in
	upx:mips64|upx:mips64le)
		echo "UPX pack is not available for $ARCH with the current UPX toolchain" >&2
		exit 2
		;;
esac

case "$BASE_URL" in
	http://*|https://*) ;;
	*)
		echo "base-url must start with http:// or https://" >&2
		exit 2
		;;
esac

case "$BASE_URL$DIR$STATE_DIR$RUNTIME_DIR$BOOT_SCRIPT$CONF" in
	*"'"*)
		echo "single quotes are not supported in paths or base-url" >&2
		exit 2
		;;
esac

mkdir -p "$DIR" "$STATE_DIR" "$RUNTIME_DIR" || exit 1

download() {
	REMOTE=$1
	LOCAL=$2
	TMP="$LOCAL.download.$$"
	ATTEMPT=1
	while :; do
		rm -f "$TMP"
		echo "downloading $BASE_URL/$REMOTE (attempt $ATTEMPT)"
		if wget -O "$TMP" "$BASE_URL/$REMOTE"; then
			mv "$TMP" "$LOCAL"
			return 0
		fi

		rm -f "$TMP"
		if [ "$DOWNLOAD_RETRIES" -gt 0 ] && [ "$ATTEMPT" -ge "$DOWNLOAD_RETRIES" ]; then
			return 1
		fi
		ATTEMPT=$((ATTEMPT + 1))
		sleep "$DOWNLOAD_RETRY_DELAY"
	done
}

download "$BINARY" "$DIR/$BINARY" || exit 1

if command -v sha256sum >/dev/null 2>&1; then
	download "$BINARY.sha256" "$DIR/$BINARY.sha256" || exit 1
	if ! (cd "$DIR" && sha256sum -c "$BINARY.sha256"); then
		echo "SHA-256 verification failed" >&2
		rm -f "$DIR/$BINARY"
		exit 1
	fi
else
	echo "sha256sum is unavailable; using the executable test only"
fi

chmod 755 "$DIR/$BINARY"
if ! "$DIR/$BINARY" --version >/dev/null 2>&1; then
	echo "binary test failed; check target ABI and avoid UPX on incompatible routers" >&2
	rm -f "$DIR/$BINARY"
	exit 1
fi

download tailscale "$DIR/tailscale" || exit 1
download tailscale-init "$DIR/tailscale-init" || exit 1
download tailscale-boot "$BOOT_SCRIPT" || exit 1
chmod 755 "$DIR/tailscale" "$DIR/tailscale-init" "$BOOT_SCRIPT"
mv "$DIR/$BINARY" "$DIR/tailscaled"

mkdir -p `dirname "$CONF"`
cat > "$CONF" <<EOF
TAILSCALE_PROFILE='$PROFILE'
TAILSCALE_PACK='$PACK'
TAILSCALE_BASE_URL='$BASE_URL'
TAILSCALE_INSTALLER_FILE='$INSTALLER_FILE'
TAILSCALE_DIR='$DIR'
TAILSCALE_STATE_DIR='$STATE_DIR'
TAILSCALE_RUNTIME_DIR='$RUNTIME_DIR'
TAILSCALE_BOOT_SCRIPT='$BOOT_SCRIPT'
TAILSCALE_TUN='$TUN'
TAILSCALE_ENABLE_FORWARDING='$ENABLE_FORWARDING'
TAILSCALE_DOWNLOAD_RETRIES='$DOWNLOAD_RETRIES'
TAILSCALE_DOWNLOAD_RETRY_DELAY='$DOWNLOAD_RETRY_DELAY'
EOF
chmod 600 "$CONF" 2>/dev/null || true

if [ "$INSTALL_OPENWRT_INIT" = "1" ] && [ -x /etc/rc.common ] && \
	[ -d /etc/init.d ] && [ -w /etc/init.d ]; then
	download tailscale-openwrt-init /etc/init.d/tailscale || exit 1
	chmod 755 /etc/init.d/tailscale
	/etc/init.d/tailscale enable 2>/dev/null || true
fi

if [ "$AUTO_START" = "1" ]; then
	TAILSCALE_ENABLER_CONF="$CONF" "$DIR/tailscale-init" restart || exit 1
fi

echo "Tailscale runtime: $DIR"
echo "Tailscale state:   $STATE_DIR"
echo "Configuration:     $CONF"
echo "Boot script:       $BOOT_SCRIPT"
echo "CLI:               $DIR/tailscale"
