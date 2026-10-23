# Skuff — Changelog

Phiên bản trong Xcode: **1.0** · Bundle ID `no.voq.skuff` · Yêu cầu **macOS 27** trở lên.

Bản **What’s New** tiếng Anh và tiếng Na Uy nằm trong [APP_STORE.md](APP_STORE.md). Dán đúng khối đó lên App Store Connect. Phần dưới là changelog đầy đủ cho web và ghi chú phát hành.

---

## 1.0 — First release

### Thêm

- Dãy tab dính mép màn hình: trái, phải, trên hoặc dưới. Mép dưới canh theo chiều rộng Dock.
- Tab hình thang, chồng nhẹ, chữ dọc. Tab đang mở nổi lên trên cùng.
- Click tab để tập hồ sơ trượt ra (hoặc hiện dần). Click lại, click ra ngoài, hoặc Esc để đóng. Cửa sổ không cướp focus.
- Lần đầu mở, Skuff xếp app đã cài vào tab theo danh mục: Dev, Office, Design, và các nhóm còn lại.
- Lưới icon trong tab, ô tìm kiếm, chấm xanh dưới app đang chạy. App chưa cài trên máy hiện mờ.
- Ghim app yêu thích lên đầu tab, icon lớn hơn.
- Rê chuột lên tab để hé vài icon bên trong.
- Kéo tab để đổi thứ tự. Kéo tay nắm để trượt cả dãy. Vị trí được nhớ riêng cho từng màn hình.
- Kéo file `.app` từ Finder thả lên tab để thêm.
- Phím tắt toàn cục Option-1 đến Option-9 mở chín tab đầu. Nếu phím đã bị app khác giữ, Settings báo cảnh.
- Tab tự co và chồng thêm khi không đủ chỗ. Tab đang mở giữ kích thước đầy đủ.
- Tự ẩn khi có app toàn màn hình.
- Menu chuột phải: ghim tab, đổi thứ tự, Settings, xóa tab, thoát Skuff.
- Tùy từng tab: tên, màu, emoji hoặc SF Symbol. Chữ tự đổi sáng hoặc tối theo màu nền.
- Kiểu bề mặt: Flat, Gradient, Liquid (kính hệ thống).
- Theme Pastel. Pro thêm Manila, Mono, Ocean, Forest, Dusk, Ink, Ember, Frost, Berry.
- Pro: không giới hạn số tab, font (family, cỡ, độ đậm, kể cả ghi đè từng tab), icon PNG/SVG, mẫu hình Flat, Folder, Pill, Stacked và thanh chỉnh độ xiên, bo góc, rộng, cao, độ chồng.
- Mua một lần qua StoreKit 2, khôi phục giao dịch, Family Sharing.
- Xuất và nhập cấu hình dạng file, để chuyển máy mà không cần iCloud.
- VoiceOver cho tab và từng app. Tôn trọng Reduce Motion.

### Free và Pro

| | Free | Pro |
|---|---|---|
| Tab ứng dụng | 5 tab dùng được. Tab thứ 6 mở ra thẻ nâng cấp, không chặn thao tác khác | Không giới hạn |
| Màu, emoji, SF Symbol, tìm kiếm, phím tắt | Có | Có |
| Kiểu Flat, Gradient, Liquid | Có | Có |
| Theme | Pastel | Tất cả |
| Hình tab | Standard | Tất cả mẫu và tùy chỉnh |
| Font | Hệ thống | Tùy chọn |
| Icon ảnh PNG/SVG | — | Có |
| Xuất / nhập cấu hình | Có | Có |

### Chưa có trong 1.0

Không đưa các mục này vào mô tả App Store hay trang marketing:

- Tab thư mục và tab bộ lọc thông minh
- Đồng bộ iCloud
- Nhiều mép cùng lúc, tab More, bộ tab theo Focus, thu dãy thành tay nắm

### Trước khi nộp bản build

- Trong `SkuffProduct`, `paywallDisabled` đang là `true` để thử Pro. Đặt lại `false` trước khi phát hành, nếu không mọi người dùng đều được Pro mà không cần mua.
- In-App Purchase `no.voq.skuff.pro` (Non-Consumable) phải được submit cùng bản build đầu tiên.
- Ảnh màn hình cần có cả dãy tab, tập hồ sơ đang mở, và màn hình mua Pro.

---

## 1.0 — English

### Added

- Edge tabs on the left, right, top, or bottom. The bottom strip matches the Dock’s width.
- Trapezoid tabs that overlap slightly, with vertical labels. The open tab sits on top.
- Click a tab and its folder slides out, or fades in. Click again, click outside, or press Esc to close. The panel does not take focus.
- On first launch, installed apps are filed into category tabs such as Dev, Office, and Design.
- An icon grid, in-folder search, and a green dot under apps that are already running. Apps missing on this Mac appear dimmed.
- Pin favorites to the top of a tab, at a larger size.
- Hover a tab to peek at a few of its icons.
- Drag tabs to reorder them. Drag the grip to slide the strip. Position is remembered per display.
- Drop an `.app` from Finder onto a tab to add it.
- Global shortcuts Option-1 through Option-9 open the first nine tabs, with a warning if another app already owns the key.
- Tabs shrink and overlap when the edge runs out of room. The open tab stays full size.
- Hides while another app is full screen.
- Context menu to pin, reorder, open Settings, delete a tab, or quit.
- Per-tab name, color, emoji, or SF Symbol. Label ink follows the background.
- Flat, Gradient, and Liquid finishes.
- Pastel theme. Pro adds Manila, Mono, Ocean, Forest, Dusk, Ink, Ember, Frost, and Berry.
- Pro: unlimited tabs, custom fonts, PNG and SVG icons, shape templates, and sliders for slant, corner radius, size, and overlap.
- One-time unlock with StoreKit 2, Restore Purchases, and Family Sharing.
- Export and import a configuration file.
- VoiceOver labels and actions. Reduce Motion is respected.
