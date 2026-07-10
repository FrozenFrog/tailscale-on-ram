# 🏡 Tailscale tối giản cho router Linux MIPS/ARM
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-active-success.svg)
![Backup](https://img.shields.io/badge/backup-automated-blue.svg)
![Tailscale](https://img.shields.io/badge/stack-tailscale-brown.svg)
![Made with Love](https://img.shields.io/badge/made%20with-❤️-ff69b4.svg)

> **Dự án này dùng GitHub Actions để build `tailscaled` dạng static, có sẵn CLI
`tailscale` bên trong cùng các thành phần cần cho Tailscale SSH, subnet route
và exit node. Mục tiêu là các router Linux/OpenWrt dung lượng flash thấp:
binary lớn chạy trong RAM, còn state, cấu hình và boot script nhỏ nằm ở vùng
lưu được sau reboot.**
> Mục đích chính: **Không cần `tar`, `gzip`, `env` hay Go trên router. Router chỉ cần `sh`, `wget`
và đủ RAM để tải binary.**



## 🚀 Hai cách cài đặt

Có hai luồng triển khai, tùy BusyBox `wget` trên router có hỗ trợ HTTPS hay
không.

| Trường hợp | Cách dùng |
| --- | --- |
| Router tải được HTTPS | Tải `install-https.sh` trực tiếp từ GitHub Release |
| Router chỉ tải được HTTP | Đưa toàn bộ release asset lên nginx HTTP, rồi tải `install-http.sh` |

Workflow không chứa IP nginx, SSH key hoặc logic upload server. IP/hostname
nginx chỉ là tham số khi chạy installer và chỉ được ghi trong README hoặc file
cấu hình trên router.

## Kiến trúc được build

Mỗi kiến trúc có bản thường. Bản UPX được tạo cho MIPS 32-bit và ARM 32-bit;
MIPS64 hiện chỉ có bản thường vì UPX 5.2.0 không nhận dạng ELF MIPS64.

| Profile installer | GO target | File thường | File UPX |
| --- | --- | --- | --- |
| `mips` | `linux/mips`, soft-float | `tailscaled-linux-mips-softfloat` | `tailscaled-linux-mips-softfloat-upx` |
| `mipsle` | `linux/mipsle`, soft-float | `tailscaled-linux-mipsle-softfloat` | `tailscaled-linux-mipsle-softfloat-upx` |
| `mips64` | `linux/mips64`, soft-float | `tailscaled-linux-mips64-softfloat` | chưa hỗ trợ |
| `mips64le` | `linux/mips64le`, soft-float | `tailscaled-linux-mips64le-softfloat` | chưa hỗ trợ |
| `arm5` | `linux/arm`, `GOARM=5` | `tailscaled-linux-armv5` | `tailscaled-linux-armv5-upx` |
| `arm7` | `linux/arm`, `GOARM=7` | `tailscaled-linux-armv7` | `tailscaled-linux-armv7-upx` |

`plain` là lựa chọn mặc định và nên dùng trước. UPX giảm dung lượng tải xuống
nhưng một số kernel/CPU MIPS/ARM cũ có thể không chạy binary đã nén; khi gặp
lỗi chạy binary, cài lại bằng `plain`.

Với profile kiến trúc chung, mặc định là:

```sh
TAILSCALE_DIR=/tmp/tailscale
TAILSCALE_STATE_DIR=/etc/tailscale-state
TAILSCALE_ENABLER_CONF=/etc/tailscale-enabler.conf
TAILSCALE_BOOT_SCRIPT=/etc/tailscale-boot.sh
```

Nếu thiết bị không ghi được `/etc`, hãy đặt các biến trên sang phân vùng flash
ghi được trước khi chạy installer.

## Cách 1: wget tải được HTTPS

Tải installer trực tiếp từ GitHub Release. Ví dụ cho thiết bị `mipsle`:

```sh
TAG=v1.98.8-enabler.1
wget -O /tmp/install-tailscale.sh https://github.com/FrozenFrog/openwrt-tailscale-enabler/releases/download/$TAG/install-https.sh
sh /tmp/install-tailscale.sh mipsle plain
```

Ví dụ dùng bản UPX cho thiết bị `arm7`:

```sh
TAG=v1.98.8-enabler.1
wget -O /tmp/install-tailscale.sh https://github.com/FrozenFrog/openwrt-tailscale-enabler/releases/download/$TAG/install-https.sh
sh /tmp/install-tailscale.sh arm7 upx
```

`install-https.sh` trong release được khóa vào chính tag đó. Có thể chỉ định
release URL khác bằng tham số thứ ba:

```sh
sh /tmp/install-tailscale.sh mips plain https://github.com/OWNER/REPO/releases/download/TAG
```

## Cách 2: wget chỉ tải được HTTP

Tải toàn bộ asset trong GitHub Release hoặc artifact `tailscale-release-files`
lên cùng một thư mục nginx HTTP. Router chỉ cần tải một file đầu vào:

```sh
SERVER=http://95.111.195.145/openwrt-tailscale-enabler
wget -O /tmp/install-tailscale.sh $SERVER/install-http.sh
sh /tmp/install-tailscale.sh mipsle plain $SERVER
```

Đổi kiến trúc hoặc pack bằng hai tham số đầu:

```sh
sh /tmp/install-tailscale.sh mips plain $SERVER
sh /tmp/install-tailscale.sh mipsle upx $SERVER
sh /tmp/install-tailscale.sh mips64le plain $SERVER
sh /tmp/install-tailscale.sh arm5 plain $SERVER
sh /tmp/install-tailscale.sh arm7 upx $SERVER
```

Không bắt buộc dùng IP trên. Có thể dùng IP, hostname và thư mục bất kỳ miễn
là tất cả file release nằm chung một base URL.

## Chỉ định vùng lưu cấu hình

Trên router flash nhỏ, không ghi binary lớn vào flash. Chỉ ghi state và script
nhỏ vào phân vùng bền vững; binary luôn được tải lại vào RAM sau reboot.

Ví dụ thiết bị có RAM ở `/var/tmp` và flash ghi được ở `/mnt`:

```sh
export TAILSCALE_DIR=/var/tmp/tailscale
export TAILSCALE_STATE_DIR=/mnt/tailscale-state
export TAILSCALE_ENABLER_CONF=/mnt/tailscale-enabler.conf
export TAILSCALE_BOOT_SCRIPT=/mnt/tailscale-start.sh
sh /var/tmp/install-tailscale.sh mipsle plain http://SERVER/path
```

Ví dụ thiết bị OpenWrt có overlay ghi được:

```sh
export TAILSCALE_DIR=/tmp/tailscale
export TAILSCALE_STATE_DIR=/overlay/tailscale-state
export TAILSCALE_ENABLER_CONF=/etc/tailscale-enabler.conf
export TAILSCALE_BOOT_SCRIPT=/overlay/tailscale-state/tailscale-boot.sh
sh /tmp/install-tailscale.sh arm7 upx http://SERVER/path
```

Muốn đổi server HTTP/HTTPS sau này, chạy lại installer với base URL mới hoặc
sửa `TAILSCALE_BASE_URL` trong file cấu hình:

```sh
TAILSCALE_BASE_URL='http://192.168.1.10/tailscale'
```

## Khởi chạy

Installer tải đúng binary, kiểm tra SHA-256 nếu có `sha256sum`, bắt buộc binary
chạy được với `--version`, rồi khởi động daemon nếu `TAILSCALE_AUTO_START=1`.

CLI nằm trong runtime directory:

```sh
$TAILSCALE_DIR/tailscale status
$TAILSCALE_DIR/tailscale up --auth-key=tskey-auth-REPLACE_ME --accept-dns=false --ssh
```

Không lưu auth key hoặc private key vào repository, workflow, boot script hay
release asset. Nên dùng auth key có thời hạn và thu hồi key sau khi đăng ký
node.

## Tự chạy sau reboot

Installer tạo boot script tại `TAILSCALE_BOOT_SCRIPT`. Script này tải lại
installer, tải lại binary vào RAM và khởi động daemon với state cũ.

Trên OpenWrt có `/etc/rc.common`, installer cũng đặt `/etc/init.d/tailscale`
và gọi `enable` nếu `/etc/init.d` ghi được:

```sh
/etc/init.d/tailscale restart
/etc/init.d/tailscale status
```

Với firmware không dùng OpenWrt init, thêm boot script vào cơ chế startup của
firmware, chạy sau khi mạng đã lên:

```sh
$TAILSCALE_BOOT_SCRIPT
```

Downloader mặc định thử tối đa 20 lần, cách nhau 15 giây. Có thể đổi bằng:

```sh
TAILSCALE_DOWNLOAD_RETRIES='20'
TAILSCALE_DOWNLOAD_RETRY_DELAY='15'
```

Đặt `TAILSCALE_DOWNLOAD_RETRIES='0'` để thử vô hạn.

## Exit node

Tailscale SSH có thể chạy với `userspace-networking`. Exit node định tuyến thật
cần `/dev/net/tun`, iptables và IP forwarding. Sửa file cấu hình:

```sh
TAILSCALE_TUN='tailscale0'
TAILSCALE_ENABLE_FORWARDING='1'
```

Khởi động lại daemon rồi quảng bá exit node:

```sh
TAILSCALE_ENABLER_CONF=/path/to/tailscale-enabler.conf $TAILSCALE_DIR/tailscale-init restart
$TAILSCALE_DIR/tailscale up --accept-dns=false --ssh --advertise-exit-node --netfilter-mode=on
```

Quản trị viên tailnet vẫn phải duyệt exit node. Nếu firmware thiếu TUN hoặc
iptables phù hợp, giữ `TAILSCALE_TUN='userspace-networking'`.

## Build và tạo GitHub Release

Mở **Actions -> Build and release small Tailscale -> Run workflow** rồi nhập:

| Input | Ý nghĩa |
| --- | --- |
| `tailscale_ref` | Tag/branch/commit Tailscale cần build, ví dụ `v1.98.8` |
| `release_tag` | Tag release cần tạo; để trống nếu chỉ cần artifact |

Khi workflow chạy từ tag `v*`, nó tự tạo hoặc cập nhật GitHub Release cho tag
đó. Với tag release tùy chỉnh như `v1.98.8-enabler.1`, dùng workflow dispatch
và đặt `tailscale_ref=v1.98.8`, `release_tag=v1.98.8-enabler.1`.

Payload release gồm:

- binary thường cho `mips`, `mipsle`, `mips64`, `mips64le`, `arm5`, `arm7`;
- binary UPX cho `mips`, `mipsle`, `arm5`, `arm7`;
- một file checksum tổng `SHA256SUMS`;
- `install-https.sh`, `install-http.sh`;
- wrapper CLI `tailscale` và script init/boot.

Workflow kiểm tra trước khi tạo release:

- đúng ELF MIPS/ARM, đúng endian, static, soft-float hoặc đúng `GOARM`;
- daemon và embedded CLI chạy được bằng QEMU tương ứng;
- CLI có `--auth-key`, `--ssh`, `--advertise-exit-node`,
  `--advertise-routes`, `--netfilter-mode`;
- các binary UPX vượt qua `upx -t` và QEMU;
- payload đầy đủ có một file `SHA256SUMS`.

Log mặc định nằm tại `$TAILSCALE_DIR/tailscaled.log`.
