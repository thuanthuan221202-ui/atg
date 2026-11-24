# Antigravity Remote for iOS 16+ (`.ipa` + Windows ACP Bridge)

Ứng dụng **SwiftUI native tối ưu riêng cho iPhone 13 Pro / iOS 16.1** giúp điều khiển trực tiếp **Google Antigravity** trên máy tính Windows của bạn — không phụ thuộc Safari/WebKit cũ, không bị lỗi màn hình đen.

## Tính năng chính
- **App native iOS 16.0+ (SwiftUI):** Chạy mượt 120Hz ProMotion trên iPhone 13 Pro, giao diện tối OLED.
- **Kết nối thẳng vào `agy acp`:** Dùng chung tài khoản Google & toàn bộ cuộc trò chuyện, skills, MCP servers đã có trên Antigravity máy tính.
- **Quét mã QR ghép nối 1 giây:** Mở app → bấm **Quét mã QR** vào cửa sổ terminal Windows là tự điền IP + Token.
- **Chat streaming real-time:** Hiển thị Markdown, khối code có nút **Chép**, phần **Suy luận (Thinking)** gập mở được, thẻ **Tool Call** trực tiếp.
- **Duyệt quyền lệnh từ xa (Allow / Deny):** Khi Antigravity muốn chạy lệnh terminal hoặc sửa file, iPhone rung + hiện nút **Cho phép / Từ chối** (kèm thông báo khi đang khóa màn hình).
- **Chọn thư mục Windows & đổi Model / Thinking / Mode** ngay trên iPhone, hỗ trợ gửi ảnh chụp màn hình từ thư viện ảnh.
- **Kèm sẵn Web UI dự phòng tương thích iOS 16.1** để dùng thử ngay trong lúc build `.ipa`.

---

## Bước 1: Chạy Bridge Server trên máy tính Windows

1. Nhấp đúp file **`server\start-bridge.bat`** (hoặc chạy `node src/index.js` trong thư mục `server`).
2. Nếu Windows Defender Firewall hỏi quyền truy cập mạng (**Private networks**), bấm **Allow access**.
3. Cửa sổ terminal sẽ in ra:
   - **Địa chỉ Wi-Fi LAN** (ví dụ `http://192.168.x.x:8787`) và **Tailscale** (nếu máy bạn có cài Tailscale)
   - **Auth Token** (tự tạo 1 lần và lưu tại `server/bridge-config.json`)
   - **Mã QR ghép nối** để quét từ app iPhone
   - **Link Web UI dự phòng iOS 16.1** (mở trực tiếp trên Safari iPhone là chạy ngay không bị đen!)

> **Điều khiển từ xa qua 4G/5G (không cần cùng Wi-Fi):**
> 1. Cài **Tailscale** trên Windows (hoặc mở biểu tượng Tailscale ở khay hệ thống và **Sign in**) và cài **Tailscale** trên iPhone (hỗ trợ iOS 16.0+), đăng nhập **cùng 1 tài khoản**.
> 2. Chạy [allow-firewall.bat](server/allow-firewall.bat) (mở cổng 8787) và [enable-autostart.bat](server/enable-autostart.bat) (tự chạy ngầm Bridge khi mở máy).
> 3. Chạy [show-qr.bat](server/show-qr.bat) — sẽ hiện sẵn **2 mã QR**: mã **Tailscale 4G/5G (`http://100.x.x.x:8787`)** và mã **Wi-Fi LAN**. Quét mã Tailscale trong app iPhone là điều khiển được ở bất kỳ đâu!

---

## Bước 2: Xuất file `.ipa` tự động (không cần máy Mac)

Vì file `.ipa` bắt buộc biên dịch bằng Xcode trên macOS, dự án đã cấu hình sẵn **GitHub Actions** chạy miễn phí trên máy chủ macOS của GitHub:

1. Tạo một repository mới trên [GitHub](https://github.com/new) (Public hoặc Private đều được).
2. Mở PowerShell trong thư mục `antigravity-ios-remote` và đẩy mã nguồn lên:
   ```powershell
   git init
   git add .
   git commit -m "Initial Antigravity Remote iOS 16 app"
   git branch -M main
   git remote add origin https://github.com/<TEN-CUA-BAN>/<TEN-REPO>.git
   git push -u origin main
   ```
3. Trên GitHub, mở tab **Actions** → chọn workflow **Build AntigravityRemote IPA (iOS 16+)** → chờ khoảng **2–3 phút** chạy xong.
4. Kéo xuống mục **Artifacts** → tải **`AntigravityRemote-iOS16-IPA.zip`** → giải nén lấy file **`AntigravityRemote-iOS16.ipa`**.

---

## Bước 3: Cài `.ipa` lên iPhone 13 Pro (iOS 16.1)

- **Nếu máy có TrollStore (Khuyên dùng cho iOS 16.1):** Gửi file `AntigravityRemote-iOS16.ipa` sang iPhone → mở bằng **TrollStore** → bấm **Install**. Dùng **vĩnh viễn**, không bao giờ hết hạn 7 ngày!
- **Nếu cài bằng Sideloadly / SideStore / AltStore:** Chọn file `AntigravityRemote-iOS16.ipa` và cài bình thường bằng Apple ID.

Khi mở app lần đầu:
1. Bấm **Cho phép (Allow)** khi iOS hỏi quyền **Mạng cục bộ (Local Network)** và **Thông báo**.
2. Bấm **Quét mã QR từ máy tính** và đưa camera vào mã QR đang hiện trên cửa sổ `start-bridge.bat`.
