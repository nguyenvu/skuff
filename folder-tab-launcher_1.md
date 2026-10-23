# Folder-tab Launcher cho macOS — Ghi chú ý tưởng & kỹ thuật

> Tên dự kiến: **Skuff** (ngăn kéo) · **Mappe** (bìa hồ sơ) · **Manila** (bản quốc tế)
> Nền tảng: macOS trước, native (SwiftUI + AppKit)
> Mô hình: Free + Pro (mua một lần, 12,99 USD), iCloud Sync trong Pro

---

## 1. Ý tưởng cốt lõi

Một launcher theo ẩn dụ **tủ hồ sơ**: các tab màu dính ở mép màn hình, mỗi tab là một "bìa hồ sơ". Click vào tab thì tập hồ sơ trượt ra, bên trong là app, thư mục hoặc file người dùng đã sắp xếp.

**Vì sao bây giờ:** từ macOS 26 Tahoe, Launchpad đã bị thay bằng Apps trong Spotlight. Nhiều người vẫn muốn duyệt app trực quan. Raycast/Alfred thiên về gõ phím, còn app này thiên về **nhìn lướt và click**.

**Điểm khác biệt:** cảm giác vật lý (tab xiên, chồng lên nhau, trượt ra như rút hồ sơ), tùy biến sâu, và chứa được cả app lẫn file.

---

## 2. Trải nghiệm người dùng

### 2.1 Dãy tab
- Dính mép màn hình (phải/trái/dưới), người dùng chọn; nhớ vị trí riêng cho từng màn hình.
- Chữ xoay dọc, màu pastel mặc định, không lấn át wallpaper.
- **Tab xiên hình thang**: cạnh dính mép dài hơn cạnh ngoài, góc ngoài bo tròn.
- Các tab chồng nhẹ lên nhau; tab đang mở nằm trên cùng.
- Chấm trạng thái ở góc tab: nhóm có app đang chạy.
- Nút **+** (tạo tab) và **✦** (tự sắp xếp app) đặt dưới dãy tab.

### 2.2 Tương tác
| Hành động | Kết quả |
|---|---|
| Hover tab | Tab nhô ra vài pt, bóng đổ; có thể hé 3–4 icon như mép giấy |
| Click tab | Tập hồ sơ trượt ra, dính liền với tab, cùng màu |
| Click lại / click ra ngoài / Esc | Tập trượt vào |
| Phím tắt toàn cục (⌥1, ⌥2…) | Mở tab tương ứng |
| Kéo app/file thả lên tab | Thêm vào nhóm mà không cần mở tab |
| Kéo tab theo chiều dọc | Đổi thứ tự |

### 2.3 Bên trong tập hồ sơ
- Header: tên tab, số mục, nút Edit.
- Ô tìm kiếm trong tab.
- **Tab ứng dụng**: lưới icon, chấm dưới app đang chạy.
- **Tab file**: danh sách có thumbnail, tên, ngày sửa.
- Vùng thả ở cuối: "Drop apps from Finder to add".

---

## 3. Các loại tab

| Loại | Nội dung | Ví dụ |
|---|---|---|
| **Ứng dụng** | Nhóm app do người dùng chọn | Dev, Office, Design |
| **Thư mục** | Nội dung một hoặc nhiều thư mục, tự cập nhật | ~/Projects/Brage, ~/Desktop/Hóa đơn |
| **Bộ lọc thông minh** | Truy vấn đã lưu (kiểu Smart Folder) | PDF sửa trong 7 ngày; ảnh có tag "Khách hàng" |

**Điều kiện lọc:** loại file, đuôi file, tag Finder, ngày sửa, tên chứa từ khóa, vị trí tìm. Có tùy chọn sắp xếp.

**Thao tác với file:** click để mở, Space để Quick Look, kéo file ra app khác, thả file vào tab để chép/di chuyển.

Mỗi loại tab có một ký hiệu nhỏ phân biệt (góc tab hoặc chấm) để nhìn là biết tab chứa app hay file.

---

## 4. Tùy biến (Settings)

### Từng tab
- **Màu**: ColorPicker, lưu hex. Chữ tự đổi sáng/tối theo độ sáng nền.
- **Font**: family, weight, size. Font chung cho cả dãy, từng tab có thể ghi đè.
- **Icon**: emoji, SF Symbol, hoặc ảnh PNG/SVG riêng. Icon đặt ở đầu tab, phía trên chữ dọc.

### Toàn cục
- Độ xiên (0–12pt), độ bo góc, độ rộng tab, độ chồng giữa các tab.
- Mép hiển thị, phím tắt, tự ẩn khi có app full-screen.
- **Theme preset**: Pastel, Manila (vàng giấy), Mono, nút "áp dụng cho tất cả".
- Preview trực tiếp khi kéo thanh trượt.

---

## 5. Khi có quá nhiều tab

Màn hình 13–14" chứa thoải mái khoảng 7–9 tab cao 80–90pt. Xử lý theo từng mức:

1. **Co lại**: tab tự thu ngắn, tên dài chuyển thành tên rút gọn hoặc **chỉ hiện icon**. Tab đang mở/hover vẫn hiện đầy đủ.
2. **Chồng lên nhau**: mỗi tab chỉ lộ một phần; rê chuột dọc dãy thì tab dưới con trỏ nhô lên, tab xung quanh dạt ra (giống Dock magnification).
3. **Tab "More"**: gom các tab ít dùng; mở ra là danh sách nhóm. Tab **ghim** không bao giờ bị đẩy vào More.

Bổ sung:
- Đặt tab ở nhiều mép để chia tải.
- **Bộ tab theo ngữ cảnh** ("Work", "Personal"), đổi bằng phím tắt hoặc theo Focus mode.
- Thu cả dãy thành tay nắm mỏng, rê chuột mới bung ra.

---

## 6. Kiến trúc kỹ thuật

### 6.1 Cửa sổ
- `NSPanel` borderless, `nonactivatingPanel`, không cướp focus.
- `collectionBehavior`: `.canJoinAllSpaces`, `.stationary`.
- Panel hẹp (~30–36pt) bám mép theo `screen.visibleFrame` (tránh Dock).
- Tập hồ sơ là panel thứ hai, dễ kiểm soát animation hơn so với mở rộng frame.
- Vùng trong suốt cho click đi xuyên xuống; hover bằng `NSTrackingArea`.
- Hỗ trợ nhiều màn hình, tự ẩn khi app full-screen.

### 6.2 Tab xiên
- `Shape` tùy chỉnh hình thang, tham số `slant`, góc bo bằng `addArc`/`addQuadCurve`.
- Chồng tab bằng offset âm + `zIndex` cho tab đang mở.
- Chữ dọc: `rotationEffect(.degrees(90))` chỉ xoay phần hiển thị, khung layout vẫn ngang. Cần `fixedSize()` + tự đảo width/height, hoặc viết custom `Layout`.

### 6.3 App
- Danh sách: `NSMetadataQuery` lọc `com.apple.application-bundle`, tự cập nhật khi cài/gỡ.
- Icon: `NSWorkspace.shared.icon(forFile:)`.
- Mở: `NSWorkspace.shared.openApplication(at:configuration:)`.
- **Tự phân loại lần đầu** bằng `LSApplicationCategoryType` trong Info.plist (`developer-tools`, `productivity`, `utilities`…).
- Lưu theo **bundle ID**, không theo đường dẫn.

### 6.4 File & thư mục
- **Sandbox**: chọn thư mục qua `NSOpenPanel`, lưu **security-scoped bookmark** (`bookmarkData(options: .withSecurityScope)`). Không có thì mất quyền sau khi khởi động lại.
- Theo dõi thay đổi: FSEvents (tab thư mục), `NSMetadataQuery` (bộ lọc thông minh, tag Finder).
- Thumbnail: `QLThumbnailGenerator`.
- Mở file: `NSWorkspace.shared.open(url)`. Kéo ra ngoài: `NSItemProvider` / `NSFilePromiseProvider`.

### 6.5 Icon cho tab
- Emoji: `NSApp.orderFrontCharacterPalette(nil)`.
- SF Symbols: không có API public liệt kê toàn bộ → đóng gói danh sách chọn lọc.
- Ảnh riêng: PNG/SVG nhỏ, lưu trong Application Support.

### 6.6 Dữ liệu
- Mỗi tab là một struct `Codable`:
  ```swift
  struct FolderTab: Codable, Identifiable {
      var id: UUID
      var kind: Kind            // .apps, .folders, .smartFilter
      var title: String
      var icon: TabIcon?        // emoji | sfSymbol | image
      var colorHex: String
      var fontName: String?
      var fontSize: Double?
      var appBundleIDs: [String]
      var folderBookmarks: [Data]   // chỉ local, không đồng bộ
      var folderRelativePaths: [String]   // đồng bộ, dùng để xin lại quyền trên máy khác
      var filter: SmartFilter?
      var isPinned: Bool
      var sortOrder: Int
      var updatedAt: Date
  }
  ```
- Lưu bằng SwiftData (bật CloudKit cho bản Pro, xem mục 8).
- Cửa sổ cài đặt: `Settings` scene của SwiftUI.

### 6.7 Chi tiết dễ quên
- VoiceOver cho tab và từng mục.
- Respect Reduce Motion.
- Phím tắt toàn cục không xung đột với app khác.

---

## 7. Free vs Pro

Mô hình: **tải miễn phí, mở khóa Pro bằng một lần mua** (Non-Consumable In-App Purchase).
Giá đề xuất: **12,99 USD** (khoảng 149 NOK), **6,99 USD** trong tuần ra mắt.

| Tính năng | Free | Pro |
|---|:---:|:---:|
| **Tab** | | |
| Tab ứng dụng | Tối đa 5 | Không giới hạn |
| Tab thư mục | — | ✓ |
| Tab bộ lọc thông minh | — | ✓ |
| Tự phân loại app lần đầu (✦) | ✓ | ✓ |
| Ghim tab | ✓ | ✓ |
| **Giao diện** | | |
| Đổi màu tab | ✓ | ✓ |
| Icon emoji | ✓ | ✓ |
| Icon SF Symbols | ✓ | ✓ |
| Icon ảnh tùy chọn (PNG/SVG) | — | ✓ |
| Font tùy chỉnh (family, weight, size) | — | ✓ |
| Độ xiên, bo góc, độ rộng, độ chồng | Mặc định | Tùy chỉnh |
| Theme preset (Pastel, Manila, Mono…) | Pastel | Tất cả |
| **Bố cục** | | |
| Một mép màn hình | ✓ | ✓ |
| Nhiều mép cùng lúc | — | ✓ |
| Co lại / chồng tab khi quá nhiều | ✓ | ✓ |
| Tab "More" | — | ✓ |
| Thu gọn thành tay nắm | ✓ | ✓ |
| Bộ tab theo ngữ cảnh / Focus mode | — | ✓ |
| **Thao tác** | | |
| Tìm kiếm trong tab | ✓ | ✓ |
| Kéo thả app vào tab | ✓ | ✓ |
| Phím tắt mở tab (⌥1…) | ✓ | ✓ |
| **Đồng bộ** | | |
| iCloud Sync giữa các Mac | — | ✓ |
| Xuất / nhập cấu hình (file JSON) | ✓ | ✓ |

**Nguyên tắc chia:**
- Free phải đủ dùng thật để người dùng cảm nhận được trải nghiệm "rút hồ sơ". Không khóa những thứ cơ bản như màu, emoji, tìm kiếm, phím tắt.
- Pro mở khóa khi người dùng đã gắn bó: cần thêm tab, đưa file vào tab, tùy biến sâu, dùng nhiều máy.
- Tính năng xử lý quá nhiều tab (co lại, chồng tab) nằm trong Free vì nó là chất lượng cơ bản, không phải tính năng cao cấp.
- Xuất/nhập JSON miễn phí để người dùng không cảm thấy bị khóa dữ liệu.

**Khi hết hạn mức Free:** tab thứ 6 hiện trạng thái khóa nhẹ kèm nút "Upgrade". Không popup chặn ngang thao tác.

---

## 8. iCloud Sync (Pro)

### 8.1 Đồng bộ gì
| Dữ liệu | Đồng bộ | Ghi chú |
|---|:---:|---|
| Danh sách tab, thứ tự, ghim | ✓ | |
| Màu, font, icon emoji/SF Symbol | ✓ | |
| Icon ảnh tùy chọn | ✓ | Gửi dạng `CKAsset` |
| App trong tab (bundle ID) | ✓ | App chưa cài trên máy kia hiển thị mờ, kèm link App Store nếu có |
| Bộ lọc thông minh | ✓ | Điều kiện lọc đồng bộ, kết quả tính lại trên từng máy |
| Thư mục trong tab | Một phần | Xem 8.3 |
| Theme, độ xiên, các thiết lập chung | ✓ | |
| Vị trí mép / màn hình | — | Riêng từng máy vì màn hình khác nhau |
| Trạng thái Pro | Tự động | Qua StoreKit, không qua iCloud |

### 8.2 Kỹ thuật
- **SwiftData + CloudKit** (private database). Lưu ý: mọi thuộc tính phải optional hoặc có giá trị mặc định, không dùng `@Attribute(.unique)`, quan hệ phải optional.
- Thiết lập chung có thể dùng `NSUbiquitousKeyValueStore` (giới hạn 1 MB, đủ cho settings).
- Bật capability **iCloud → CloudKit** và **Background Modes → Remote notifications** để nhận thay đổi.
- Xung đột: last-write-wins theo từng tab là đủ cho dạng dữ liệu này.
- Chỉ bật sync khi có quyền Pro. Khi tắt Pro (ví dụ hoàn tiền), dữ liệu local vẫn giữ nguyên.
- Có công tắc bật/tắt sync trong Settings và hiển thị trạng thái "Đã đồng bộ lúc…".

### 8.3 Thư mục trên máy khác
Security-scoped bookmark **gắn với từng máy**, không dùng được trên Mac khác. Cách xử lý:
- Lưu thêm đường dẫn tương đối so với thư mục home (ví dụ `~/Projects/Brage`).
- Trên máy mới, nếu thư mục tồn tại: hiện nút "Cấp quyền truy cập", mở `NSOpenPanel` trỏ sẵn vào đúng thư mục.
- Nếu không tồn tại: tab hiện trạng thái "Thư mục không có trên máy này", không xóa cấu hình.

---

## 9. Phân phối & App Store

### 9.1 Thiết lập trong App Store Connect
- **Giá app:** Free.
- **In-App Purchase:** loại **Non-Consumable**, Reference Name "Pro Unlock", Product ID ví dụ `no.voq.skuff.pro` (không đổi được sau khi tạo).
- Ký **Paid Apps Agreement** và điền thông tin ngân hàng, thuế trước.
- Localization tiếng Anh và tiếng Na Uy cho tên và mô tả In-App Purchase.
- Bật **Family Sharing**.
- Ảnh chụp màn hình mua Pro cho reviewer; In-App Purchase đầu tiên submit cùng một bản build.
- Đăng ký **Small Business Program** để phí còn 15% (doanh thu dưới 1 triệu USD/năm).

### 9.2 StoreKit 2
- `Product.products(for:)` để lấy sản phẩm, `product.purchase()` để mua.
- Kiểm tra quyền qua `Transaction.currentEntitlements` khi mở app, lắng nghe `Transaction.updates`.
- **Bắt buộc có nút "Restore Purchases"** gọi `AppStore.sync()`.
- Thử nghiệm bằng StoreKit Configuration file trong Xcode, sau đó Sandbox tester.

### 9.3 Khác
- Mac App Store khả thi: app sandbox vẫn mở app qua NSWorkspace và đọc metadata trong `/Applications`.
- Dựng prototype trong sandbox sớm để kiểm tra `~/Applications` và quyền thư mục.
- Cân nhắc Setapp làm kênh phụ.
- Kiểm tra tên trên App Store, nhãn hiệu, và trang con kiểu voq.no/<tên>.

---

## 10. Lộ trình gợi ý

### MVP (1.0)
- Free: tab ứng dụng (tối đa 5), một mép, tự phân loại lần đầu, màu, emoji, SF Symbols.
- Tab xiên, mở/đóng tập hồ sơ, tìm kiếm, kéo thả app, phím tắt.
- Xử lý quá nhiều tab mức 1 (co lại) và mức 2 (chồng lên nhau).
- Pro: không giới hạn tab, font tùy chỉnh, icon ảnh, tùy chỉnh hình dáng, theme preset.
- StoreKit 2, nút Restore Purchases, xuất/nhập JSON.

### 1.1
- Pro: tab thư mục và bộ lọc thông minh.
- Pro: iCloud Sync.

### Phiên bản sau
- Pro: tab "More", nhiều mép, bộ tab theo ngữ cảnh / Focus mode.
- Tay nắm thu gọn.
