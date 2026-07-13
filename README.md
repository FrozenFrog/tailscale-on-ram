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

Mỗi profile có bản thường `plain`. Với MIPS 32-bit và ARM 32-bit, workflow tạo
thêm bản `upx`. MIPS64/MIPS64LE hiện chỉ có bản `plain` vì UPX 5.2.0 không
nhận dạng ELF MIPS64 ổn định.

Các profile `mips`, `mipsle`, `mips64`, `mips64le` mặc định dùng `softfloat`,
phù hợp hơn với nhiều router cũ. Nếu thiết bị có ABI hard-float, dùng profile
có hậu tố `-hardfloat`.

| Profile installer | GO target | File thường | File UPX |
| --- | --- | --- | --- |
| `mips`, `mips-softfloat` | `linux/mips`, `GOMIPS=softfloat` | `tailscaled-linux-mips-softfloat` | `tailscaled-linux-mips-softfloat-upx` |
| `mips-hardfloat` | `linux/mips`, `GOMIPS=hardfloat` | `tailscaled-linux-mips-hardfloat` | `tailscaled-linux-mips-hardfloat-upx` |
| `mipsle`, `mipsle-softfloat` | `linux/mipsle`, `GOMIPS=softfloat` | `tailscaled-linux-mipsle-softfloat` | `tailscaled-linux-mipsle-softfloat-upx` |
| `mipsle-hardfloat` | `linux/mipsle`, `GOMIPS=hardfloat` | `tailscaled-linux-mipsle-hardfloat` | `tailscaled-linux-mipsle-hardfloat-upx` |
| `mips64`, `mips64-softfloat` | `linux/mips64`, `GOMIPS64=softfloat` | `tailscaled-linux-mips64-softfloat` | chưa hỗ trợ |
| `mips64-hardfloat` | `linux/mips64`, `GOMIPS64=hardfloat` | `tailscaled-linux-mips64-hardfloat` | chưa hỗ trợ |
| `mips64le`, `mips64le-softfloat` | `linux/mips64le`, `GOMIPS64=softfloat` | `tailscaled-linux-mips64le-softfloat` | chưa hỗ trợ |
| `mips64le-hardfloat` | `linux/mips64le`, `GOMIPS64=hardfloat` | `tailscaled-linux-mips64le-hardfloat` | chưa hỗ trợ |
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
TAG=v1.98.8
wget -O /tmp/install-tailscale.sh https://github.com/FrozenFrog/tailscale-on-ram/releases/download/$TAG/install-https.sh
sh /tmp/install-tailscale.sh mipsle plain
```

Ví dụ dùng bản UPX cho thiết bị `arm7`:

```sh
TAG=v1.98.8
wget -O /tmp/install-tailscale.sh https://github.com/FrozenFrog/tailscale-on-ram/releases/download/$TAG/install-https.sh
sh /tmp/install-tailscale.sh arm7 upx
```

Một số BusyBox `wget` bắt tay được TLS nhưng không có sẵn chứng chỉ CA nên
báo lỗi xác minh chứng chỉ. Với lệnh tải tay đầu tiên ở trên, thêm
`--no-check-certificate` ngay sau `wget`; các bước tải về sau (installer và
boot script) tự thử lại với cờ này khi cần — file tải về vẫn được kiểm tra
bằng SHA-256.

`install-https.sh` trong release được khóa vào chính tag đó. Có thể chỉ định
release URL khác bằng tham số thứ ba:

```sh
sh /tmp/install-tailscale.sh mips plain https://github.com/OWNER/REPO/releases/download/TAG
```

## Cách 2: wget chỉ tải được HTTP

Đưa toàn bộ payload release lên cùng một thư mục nginx HTTP. Cách nhanh nhất
là tải file nén `tailscale-release-files.tar.gz` trong release rồi giải nén
thẳng vào thư mục web:

```sh
TAG=v1.98.8
cd /var/www/openwrt-tailscale-enabler
wget https://github.com/FrozenFrog/tailscale-on-ram/releases/download/$TAG/tailscale-release-files.tar.gz
tar -xzf tailscale-release-files.tar.gz
rm tailscale-release-files.tar.gz
```

(Hoặc tải từng asset trong GitHub Release / artifact `tailscale-release-files`
lên cùng thư mục đó.) Router chỉ cần tải một file đầu vào:

```sh
SERVER=http://95.111.195.145/openwrt-tailscale-enabler
wget -O /tmp/install-tailscale.sh $SERVER/install-http.sh
sh /tmp/install-tailscale.sh mipsle plain $SERVER
```

Đổi kiến trúc hoặc pack bằng hai tham số đầu:

```sh
sh /tmp/install-tailscale.sh mips plain $SERVER
sh /tmp/install-tailscale.sh mips-hardfloat plain $SERVER
sh /tmp/install-tailscale.sh mipsle upx $SERVER
sh /tmp/install-tailscale.sh mipsle-hardfloat upx $SERVER
sh /tmp/install-tailscale.sh mips64le plain $SERVER
sh /tmp/install-tailscale.sh mips64le-hardfloat plain $SERVER
sh /tmp/install-tailscale.sh arm5 plain $SERVER
sh /tmp/install-tailscale.sh arm7 upx $SERVER
```

Không bắt buộc dùng IP trên. Có thể dùng IP, hostname và thư mục bất kỳ miễn
là tất cả file release nằm chung một base URL.

### Mirror dự phòng (nhiều base URL)

Tham số base-url (hoặc biến `TAILSCALE_BASE_URLS`) nhận **nhiều URL cách
nhau bằng dấu cách**, thử lần lượt theo thứ tự. URL nào trả lời được sẽ
được ưu tiên cho các lần tải tiếp theo và được ghi lên đầu danh sách trong
file cấu hình — nhờ đó sau reboot, mirror chính chết thì router tự chuyển
sang mirror dự phòng:

```sh
sh /tmp/install-tailscale.sh mipsle upx "http://95.111.195.145/openwrt-tailscale-enabler http://mirror2.example.com/tailscale"
```

Router có wget/curl hỗ trợ TLS có thể thêm URL release GitHub vào cuối
danh sách làm dự phòng sau cùng. Router chỉ tải được HTTP thuần thì mọi
URL trong danh sách phải là mirror HTTP.

### Router chỉ có curl (không có wget)

Một số firmware tùy biến chỉ có `curl` (thường cũng chỉ tải được HTTP thuần).
Installer và boot script tự nhận ra điều này: mỗi lần tải sẽ thử `wget`
trước rồi tự chuyển sang `curl` (`-f -L`, kèm lần thử lại `-k` khi HTTPS
thiếu chứng chỉ). Chỉ khác lệnh tải file đầu vào:

```sh
SERVER=http://95.111.195.145/openwrt-tailscale-enabler
curl -f -o /tmp/install-tailscale.sh $SERVER/install-http.sh
sh /tmp/install-tailscale.sh mipsle plain $SERVER
```

Không cần (và không nên) đặt `alias wget=...` — alias chỉ có tác dụng trong
shell tương tác, không được truyền vào tiến trình `sh` chạy script nên
installer sẽ không thấy nó.

## Firmware có BusyBox quá cũ (thiếu mv, mknod, sha256sum)

BusyBox đời 1.13 trên một số firmware thiếu các applet mà script cần
(`mv`, `mknod`, `dirname`, `sha256sum`). Installer tự phát hiện điều này:
nó tải BusyBox 1.21.1 tĩnh (`busybox-mips`, `busybox-mipsel`,
`busybox-mips64`, `busybox-armv5l`, `busybox-armv7l` — có sẵn trong payload
release và bản mirror) từ chính base URL **trước mọi bước khác**, lưu vào
`$TAILSCALE_DIR/busybox`, cài các applet vào `$TAILSCALE_DIR/bb` và thêm
thư mục đó vào PATH. Nếu firmware có `wget` riêng thì applet wget của
BusyBox bị loại bỏ để wget firmware (có thể hỗ trợ TLS) tiếp tục tải file;
nếu firmware không có wget (ví dụ chỉ có curl) thì applet wget được giữ lại
làm downloader dự phòng — mirror là HTTP thuần nên không cần TLS.

Lưu ý: busybox.net hiện chỉ phục vụ HTTPS nên các thiết bị này không tải
trực tiếp từ đó được — hãy dùng mirror HTTP (Cách 2); wget đời đó thường
cũng không tải được từ GitHub. `$TAILSCALE_DIR` nằm trên RAM nên BusyBox
được tải lại tự động sau mỗi lần reboot, trước khi tailscaled khởi động.
Muốn ép dùng BusyBox tải về dù firmware có đủ applet, đặt
`TAILSCALE_NEED_BUSYBOX=1` khi chạy installer.

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

Mặc định đã hướng tới exit node: cấu hình được ghi với `TAILSCALE_TUN='tailscale0'`
và `TAILSCALE_ENABLE_FORWARDING='1'`, không cần sửa file cấu hình nữa. Khi
khởi động, `tailscale-init` tự nạp module `tun` (modprobe/insmod), tạo
`/dev/net/tun` và kiểm tra driver qua `/proc/misc`.

Nếu thiết bị không có driver TUN, script tự fallback về
`userspace-networking` (Tailscale SSH vẫn chạy, nhưng exit node và subnet
route bị tắt) và ghi lựa chọn đó ngược vào file cấu hình để các lần khởi động
sau không phải dò lại. Trên firmware Padavan, chạy thêm `mtd_storage.sh save`
để giữ file cấu hình trong `/etc/storage` qua reboot. Sau này nếu cài được
driver TUN (OpenWrt: gói `kmod-tun`), sửa lại `TAILSCALE_TUN='tailscale0'`
trong file cấu hình rồi restart.

Quảng bá exit node (chỉ cần chạy một lần, pref được lưu trong state):

```sh
TAILSCALE_ENABLER_CONF=/path/to/tailscale-enabler.conf $TAILSCALE_DIR/tailscale-init restart
$TAILSCALE_DIR/tailscale up --accept-dns=false --ssh --advertise-exit-node --netfilter-mode=on
```

Quản trị viên tailnet vẫn phải duyệt exit node. Exit node định tuyến thật cần
iptables trên thiết bị; nếu thiếu iptables phù hợp, có thể thử
`--netfilter-mode=off` và tự cấu hình firewall.

Nếu `tailscaled` thoát ngay sau khi start, `tailscale-init` sẽ in các dòng
cuối của `$TAILSCALE_DIR/tailscaled.log` để chẩn đoán.

## Build và tạo GitHub Release

Mở **Actions -> Build and release small Tailscale -> Run workflow** rồi nhập:

| Input | Ý nghĩa |
| --- | --- |
| `tailscale_ref` | Tag/branch/commit Tailscale cần build, ví dụ `v1.98.8` |
| `release_tag` | Tag release cần tạo; để trống nếu chỉ cần artifact |

Khi workflow chạy từ tag `v*`, nó tự tạo hoặc cập nhật GitHub Release cho tag
đó. Quy ước tag của dự án bám theo phiên bản Tailscale upstream, ví dụ
`v1.98.8`.

Payload release gồm:

- binary thường cho MIPS softfloat/hardfloat, MIPS64 softfloat/hardfloat,
  `arm5`, `arm7`;
- binary UPX cho MIPS 32-bit softfloat/hardfloat, `arm5`, `arm7`;
- một file checksum tổng `SHA256SUMS`;
- `install-https.sh`, `install-http.sh`;
- wrapper CLI `tailscale` và script init/boot.

Workflow kiểm tra trước khi tạo release:

- đúng ELF MIPS/ARM, đúng endian, static, đúng MIPS float ABI hoặc đúng `GOARM`;
- daemon và embedded CLI chạy được bằng QEMU tương ứng;
- CLI có `--auth-key`, `--ssh`, `--advertise-exit-node`,
  `--advertise-routes`, `--netfilter-mode`;
- các binary UPX vượt qua `upx -t` và QEMU;
- payload đầy đủ có một file `SHA256SUMS`.

Log mặc định nằm tại `$TAILSCALE_DIR/tailscaled.log`.

## 💖 Special Thanks
This project would not have been possible without the contributions and inspiration from::

* **Ovler-Young** ([openwrt-tailscale-enabler-fork](https://github.com/Ovler-Young/openwrt-tailscale-enabler))
* **adyanth** [openwrt-tailscale-enabler-main](https://github.com/adyanth/openwrt-tailscale-enabler)


