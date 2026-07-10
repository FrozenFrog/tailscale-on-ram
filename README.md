<<<<<<< HEAD
# Tailscale on OpenWRT

1. Extract the contents of root to your filesystem root:
```
tar x -zvC / -f openwrt-tailscale-enabler-<tag>.tgz
```

2. Install the prerequisites for wget and tailscale:
```
opkg update
opkg install libustream-openssl ca-bundle kmod-tun
```

3. Run tailscale for the first time:
```
/etc/init.d/tailscale start
tailscale up --accept-dns=false --advertise-routes=10.0.0.0/24
```

Both of these commands download the tailscale package to get the binaries to /tmp.
The /etc/init.d/tailscale will start the tailscale daemon. 
The next command uses the tailscale CLI to configure the login and add some settings to prevent dns changes and advertise routes. Use the URL printed to login to tailscale.

4. Enable tailscale at boot:
```
/etc/init.d/tailscale enable
```

Verify by looking for an entry here:
```
ls /etc/rc.d/S*tailscale*
```
This confirms that there is a symlink to start the tailscale service.

At this point, you should have:
* tailscale stubs in `/usr/bin`: `ls /urs/bin/tailscale*`
  * tailscale xxxx bytes
  * tailscaled xxxx bytes
* tailscale service init script in `/etc/init.d/tailscale`: `ls /etc/init.d/tailscale`
* symlink `/etc/rc.d/S*tailscale`: `ls /etc/rc.d/S*tailscale*`

If so, go ahead and...

5. Reboot the router and verify that it shows up online on the [Tailscale Admin portal](https://login.tailscale.com/admin/machines).

If you log back into your router, the first time you run a command like `tailscale status` the stub will download the `tailscale` binary.  The `tailscaled` daemon should have already been downloaded by the service start.

6. To update the version of tailscale, grab the latest version [here](https://pkgs.tailscale.com/stable/#static) of the form `1.2.10_mips` and replace the same in `/usr/bin/tailscale` and `/usr/bin/tailscaled`: `version="1.2.10_mips"`.

Note: You need to have atleast 11+16 = ~27 MB of free space in `/tmp` (which is usually in RAM) to be able to use this.



=======
# Tailscale tối giản cho router TOTOLINK MIPS

[![Build and release](https://github.com/FrozenFrog/openwrt-tailscale-enabler/actions/workflows/build_small_tailscale.yml/badge.svg)](https://github.com/FrozenFrog/openwrt-tailscale-enabler/actions/workflows/build_small_tailscale.yml)

Dự án build một binary `tailscaled` tĩnh có sẵn CLI, Tailscale SSH,
Tailnet Lock, quảng bá subnet route và exit node. Binary được tải vào RAM khi
router khởi động; chỉ state, cấu hình và boot script nhỏ được giữ trên flash.

Không cần `tar`, `gzip`, `env` hay Go trên router. Có thể cài từ GitHub Release
qua HTTPS hoặc từ một nginx server qua HTTP thuần.

## Thiết bị hỗ trợ

| Thiết bị | Profile cài đặt | ABI | Runtime trong RAM | State trên flash |
| --- | --- | --- | --- | --- |
| TOTOLINK T10 firmware gốc | `t10` | `linux/mipsle`, soft-float | `/var/tmp/tailscale` | `/mnt/tailscale-state` |
| TOTOLINK W300RT, OpenWrt 12.09 | `w300rt` | `linux/mips`, soft-float | `/tmp/tailscale` | `/overlay/tailscale-state` |

Workflow phát hành bốn binary:

| File | Mục đích |
| --- | --- |
| `tailscaled-linux-mipsle-softfloat` | T10, bản thường ổn định |
| `tailscaled-linux-mipsle-softfloat-upx` | T10, bản nén UPX |
| `tailscaled-linux-mips-softfloat` | W300RT, bản thường ổn định |
| `tailscaled-linux-mips-softfloat-upx` | W300RT, bản nén UPX |

`plain` là lựa chọn mặc định. UPX giảm mạnh dung lượng tải xuống nhưng có thể
gặp `Trace/breakpoint trap` trên CPU hoặc kernel MIPS cũ dù đã chạy qua QEMU.
Khi chưa kiểm thử trực tiếp trên đúng model router, hãy dùng `plain`.

## Cách 1: router tải được HTTPS

Luồng này tải toàn bộ file trực tiếp từ một GitHub Release đã gắn tag.

Ví dụ cài bản thường cho T10:

```sh
TAG=v1.98.8-enabler.1
wget -O /var/tmp/install-tailscale.sh https://github.com/FrozenFrog/openwrt-tailscale-enabler/releases/download/$TAG/install-https.sh
sh /var/tmp/install-tailscale.sh t10 plain
```

Ví dụ cài bản UPX cho W300RT:

```sh
TAG=v1.98.8-enabler.1
wget -O /tmp/install-tailscale.sh https://github.com/FrozenFrog/openwrt-tailscale-enabler/releases/download/$TAG/install-https.sh
sh /tmp/install-tailscale.sh w300rt upx
```

`install-https.sh` trong mỗi release được khóa vào chính tag đó. Có thể chỉ
định một release URL khác bằng tham số thứ ba:

```sh
sh /tmp/install-tailscale.sh w300rt plain https://github.com/OWNER/REPO/releases/download/TAG
```

## Cách 2: router chỉ tải được HTTP

Đây là luồng dành cho BusyBox `wget` cũ không hỗ trợ HTTPS. Đặt toàn bộ payload
từ artifact `tailscale-release-files` vào cùng một thư mục nginx. Router chỉ
cần tải một file đầu vào; file này tự lấy đúng binary và các script còn lại.

T10:

```sh
SERVER=http://95.111.195.145/openwrt-tailscale-enabler
wget -O /var/tmp/install-tailscale.sh $SERVER/install-http.sh
sh /var/tmp/install-tailscale.sh t10 plain $SERVER
```

W300RT:

```sh
SERVER=http://95.111.195.145/openwrt-tailscale-enabler
wget -O /tmp/install-tailscale.sh $SERVER/install-http.sh
sh /tmp/install-tailscale.sh w300rt plain $SERVER
```

Không bắt buộc dùng IP trên. Có thể dùng IP, hostname và thư mục bất kỳ miễn
là tất cả file release nằm chung một base URL.

### Đổi địa chỉ nginx

Cách an toàn nhất là chạy lại installer với URL mới ở tham số thứ ba. Installer
sẽ cập nhật cấu hình và boot script:

```sh
NEW_SERVER=http://192.168.1.10/tailscale
wget -O /var/tmp/install-tailscale.sh $NEW_SERVER/install-http.sh
sh /var/tmp/install-tailscale.sh t10 plain $NEW_SERVER
```

Cũng có thể sửa trực tiếp `TAILSCALE_BASE_URL` trong:

- T10: `/mnt/tailscale-enabler.conf`
- W300RT: `/etc/tailscale-enabler.conf`

Ví dụ:

```sh
TAILSCALE_BASE_URL='http://192.168.1.10/tailscale'
```

## Khởi chạy và xác thực

Installer kiểm tra SHA-256 nếu firmware có `sha256sum`, bắt buộc binary chạy
được với `--version`, sau đó khởi động `tailscaled`.

T10:

```sh
/var/tmp/tailscale/tailscale status
/var/tmp/tailscale/tailscale up --auth-key=tskey-auth-REPLACE_ME --accept-dns=false --ssh
```

W300RT:

```sh
/tmp/tailscale/tailscale status
/tmp/tailscale/tailscale up --auth-key=tskey-auth-REPLACE_ME --accept-dns=false --ssh
```

Không lưu auth key hoặc private key vào repository, workflow, boot script hay
file release. Nên dùng auth key có thời hạn và thu hồi key sau khi đăng ký node.

## Tự chạy sau khi reboot

Trên W300RT, installer đặt `/etc/init.d/tailscale`, gọi `enable` và tải lại
binary vào `/tmp` sau khi mạng sẵn sàng. Kiểm tra bằng:

```sh
/etc/init.d/tailscale restart
/etc/init.d/tailscale status
```

Trên T10, boot script nhỏ nằm ở `/mnt/tailscale-start.sh`. Thêm lệnh sau vào
cơ chế startup hiện có của firmware để chạy sau khi WAN/LAN đã lên:

```sh
/mnt/tailscale-start.sh
```

Binary lớn không được ghi vào `/mnt`; nó luôn được tải lại vào `/var/tmp`.
State của node vẫn tồn tại sau reboot nên không cần xác thực lại nếu state còn
nguyên vẹn. Downloader mặc định thử tối đa 20 lần, cách nhau 15 giây; có thể
đổi bằng `TAILSCALE_DOWNLOAD_RETRIES` và `TAILSCALE_DOWNLOAD_RETRY_DELAY` trong
file cấu hình. Đặt số lần thử là `0` để thử vô hạn.

## Exit node

Tailscale SSH hoạt động với `userspace-networking`, nhưng exit node định tuyến
thật cần `/dev/net/tun`, iptables và IP forwarding. Sửa file cấu hình của thiết
bị:

```sh
TAILSCALE_TUN='tailscale0'
TAILSCALE_ENABLE_FORWARDING='1'
```

Khởi động lại daemon rồi quảng bá exit node:

```sh
# T10
TAILSCALE_ENABLER_CONF=/mnt/tailscale-enabler.conf /var/tmp/tailscale/tailscale-init restart
/var/tmp/tailscale/tailscale up --accept-dns=false --ssh --advertise-exit-node --netfilter-mode=on

# W300RT
/etc/init.d/tailscale restart
/tmp/tailscale/tailscale up --accept-dns=false --ssh --advertise-exit-node --netfilter-mode=on
```

Quản trị viên tailnet vẫn phải duyệt exit node. Nếu firmware không có TUN hoặc
iptables phù hợp, giữ `TAILSCALE_TUN='userspace-networking'`; Tailscale SSH vẫn
có thể hoạt động nhưng router không thể làm routed exit node.

## Build, tạo release và upload nginx

Mở **Actions → Build and release small Tailscale → Run workflow** rồi nhập:

| Input | Ý nghĩa |
| --- | --- |
| `tailscale_ref` | Tag/branch/commit Tailscale cần build, ví dụ `v1.98.8` |
| `release_tag` | Tag release cần tạo; để trống nếu chỉ cần artifact |
| `http_base_url` | URL HTTP công khai tương ứng với thư mục nginx |
| `deploy_nginx` | Bật để workflow tự upload payload lên VPS |
| `nginx_path` | Đường dẫn đích trên VPS, ví dụ `/var/www/html/openwrt-tailscale-enabler` |

Nếu bật `deploy_nginx`, cấu hình các GitHub Actions Secrets sau:

| Secret | Bắt buộc | Nội dung |
| --- | --- | --- |
| `NGINX_HOST` | Có | IP hoặc hostname SSH của VPS |
| `NGINX_SSH_PRIVATE_KEY` | Có | Private key chỉ dùng cho deploy |
| `NGINX_USER` | Không | Mặc định `root` |
| `NGINX_PORT` | Không | Mặc định `22` |
| `NGINX_KNOWN_HOSTS` | Khuyến nghị | Dòng host key đã xác minh; nếu trống workflow dùng `ssh-keyscan` |

Workflow thực hiện các kiểm tra sau trước khi tạo release hoặc upload nginx:

- đúng ELF MIPS big-endian hoặc MIPS little-endian, static, soft-float;
- daemon và embedded CLI chạy được bằng `qemu-mips-static` hoặc
  `qemu-mipsel-static`;
- cả bản thường và UPX có `--auth-key`, `--ssh`, `--advertise-exit-node`,
  `--advertise-routes`, `--netfilter-mode` và lệnh Tailnet Lock;
- UPX vượt qua kiểm tra nội bộ `upx -t` và QEMU;
- mọi binary có checksum riêng, payload đầy đủ có `SHA256SUMS`.

Có thể tạo release bằng cách dispatch workflow với `release_tag`, hoặc push một
tag trùng tag Tailscale upstream, ví dụ `v1.98.8`. Khi cần tag release tùy chỉnh
như `v1.98.8-enabler.1`, hãy dùng workflow dispatch và đặt `tailscale_ref` riêng.

## Xử lý lỗi nhanh

`Trace/breakpoint trap`: chọn nhầm endian hoặc bản UPX không tương thích. T10
dùng `t10 plain`; W300RT dùng `w300rt plain`.

`Access denied`: kiểm tra daemon đang chạy, CLI đang dùng đúng socket và auth
key chưa hết hạn/thu hồi.

`tailnet lock is not supported by this binary`: không dùng binary cũ; tải lại
artifact/release mới vì workflow hiện giữ `tailnetlock`, `ipnbus` và
`unixsocketidentity`.

Log mặc định nằm tại `/var/tmp/tailscale/tailscaled.log` trên T10 và
`/tmp/tailscale/tailscaled.log` trên W300RT.
>>>>>>> 2538642 (testing new commit)
