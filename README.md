# Receiptly — Mini-Project 3: OCR Expense Tracker & Receipt Parser

**Tài liệu hợp nhất từ phiên bản ban đầu đến v10 (Flexible OCR)**  
**Nền tảng:** Flutter / Dart / Android · **Lưu trữ:** SQLite (offline) · **OCR:** Google ML Kit trên thiết bị

> Đây là tài liệu cho **source v10**, không phải xác nhận mọi tình huống OCR đều chính xác hoặc APK release đã được build. Các thay đổi cũ được ghi lại trong phần lịch sử; **hành vi hiện tại của v10** là chuẩn nếu có khác biệt với các bản trước.

## 1. Mục tiêu Mini-Project 3

- Xây dựng ứng dụng quản lý chi tiêu cá nhân bằng Flutter & Dart.
- Đọc văn bản hóa đơn **offline** bằng Google ML Kit Text Recognition.
- Sử dụng Regex và heuristic để trích xuất **tên cửa hàng, tổng tiền, ngày giao dịch**.
- Vẽ **biểu đồ tròn và biểu đồ cột có hiệu ứng** bằng `CustomPainter` và `AnimationController`.

## 2. Chức năng phiên bản v10

### Giao dịch & quản lý dữ liệu

- Xem tổng chi tiêu theo tháng; thêm, sửa, xóa giao dịch và phân loại danh mục.
- Dữ liệu lưu **cục bộ trên thiết bị** trong SQLite (`receiptly.db`, bảng `expenses`); **không yêu cầu đăng ký/đăng nhập** hay backend.
- Hỗ trợ chuyển giao dịch cũ lưu bằng SharedPreferences (khóa `expenses_v1`) sang SQLite; giữ bản dữ liệu cũ để tránh mất nguồn gốc khi chuyển đổi. **Không gỡ ứng dụng trước khi sao lưu**.
- Xuất và nhập dữ liệu **JSON** qua chức năng sao lưu/khôi phục; cần lưu file xuất ra **bên ngoài vùng dữ liệu ứng dụng**. JSON backup không được mã hóa.
- Dữ liệu của từng bản cài đặt độc lập; không tự đồng bộ giữa các thiết bị. Gỡ app/xóa dữ liệu có thể làm mất cơ sở dữ liệu.

### OCR hóa đơn trên thiết bị

1. Chụp ảnh hoặc chọn ảnh hóa đơn trong thư viện.
2. Kiểm tra sơ bộ chất lượng ảnh và nhận diện chữ bằng ML Kit (Latin OCR).
3. Kết hợp văn bản với tọa độ các dòng (`TextBlock.lines`/bounding boxes), ghép thông tin cùng hàng và chạy Regex/heuristic.
4. Đề xuất tên cửa hàng, ngày, tổng thanh toán; ưu tiên nhãn như `Tổng cộng`, `Tổng thanh toán`, tránh nhầm số nhà, hotline và mã hóa đơn.
5. Cho phép người dùng **xem và chỉnh sửa** kết quả trước khi lưu. Thiếu tên/ngày/tổng tiền **không đồng nghĩa tự động từ chối hóa đơn thật**.
6. Với ảnh gần như không đọc được hoặc có dấu hiệu rõ là văn bản không liên quan tới hóa đơn mà không có bằng chứng thanh toán: có thể từ chối/cảnh báo. Ảnh chưa rõ loại vẫn cho người dùng kiểm tra.

Hỗ trợ nhiều cách ghi số/ngày (tùy kết quả OCR), gồm tiền dạng `70 triệu VND` và ngày `16 thg 3, 2022`. OCR và heuristic **không đảm bảo đúng 100%**, kể cả ảnh rõ. Người dùng phải xác nhận trước khi lưu.

### Quy tắc ngày giao dịch

- Chỉ cho phép ghi nhận **ngày hiện tại hoặc quá khứ**, không cho nhập ngày tương lai.
- Giới hạn được tính bằng `DateTime.now()` tại thời điểm thao tác: ngày 12 chưa cho ngày 13; bước sang ngày 13 thì tự được phép.
- Không cho chuyển đến tháng tương lai; khi qua tháng mới, tháng đó được mở.
- Ngày tương lai do OCR nhận diện phải sửa trước khi lưu; nhập file JSON có ngày tương lai bị từ chối. Dữ liệu cũ không tự động xóa chỉ vì từng lưu ngày tương lai.

### Thống kê

- Biểu đồ tròn phân bổ số tiền theo danh mục.
- Biểu đồ cột 7 ngày **xếp chồng theo danh mục**, cùng bảng màu với biểu đồ tròn.
- Cập nhật biểu đồ khi thêm/sửa/xóa dữ liệu; cả hai dùng `CustomPainter`.

## 3. Công nghệ và cấu trúc thư mục

| Thành phần | Công nghệ/tệp |
|---|---|
| Giao diện và điều hướng | Flutter Material / `lib/main.dart` |
| OCR trên thiết bị | `google_mlkit_text_recognition` |
| Phân tích văn bản/bố cục | `lib/receipt_parser.dart` |
| Đánh giá ảnh | `lib/receipt_image_quality.dart`, package `image` |
| Lưu SQLite và migration | `lib/expense_store.dart`, `sqflite`, `shared_preferences` |
| Kiểm soát ngày | `lib/transaction_date_rules.dart` |
| Sao lưu/khôi phục | `file_picker`, `share_plus`, `path_provider` |
| Biểu đồ động | `CustomPainter`, `AnimationController` trong `lib/main.dart` |
| Kiểm thử | `test/receipt_parser_test.dart`, `test/transaction_date_rules_test.dart`, `test/widget_test.dart` |
| Cấu hình phụ thuộc | `pubspec.yaml` |
| Build local / CI | `BUILD_APK_WINDOWS.bat`, `build_android.ps1`, `build_android.sh`, `.github/workflows/android-apk.yml` |

### Luồng xử lý

```text
Chụp / chọn ảnh
    ↓
Đánh giá sơ bộ chất lượng ảnh
    ↓
Google ML Kit: văn bản + vị trí các dòng
    ↓
OCR Parser: tên cửa hàng, tổng tiền, ngày + đánh giá dấu hiệu hóa đơn
    ↓
Kiểm tra/chỉnh sửa kết quả
    ↓
Kiểm tra ngày và số tiền hợp lệ
    ↓
SQLite → dashboard / biểu đồ / backup JSON
```

## 4. Yêu cầu môi trường

- Flutter tương thích SDK Dart khai báo trong `pubspec.yaml` (Dart >= 3.8).
- Windows + Android Studio/Android SDK, công cụ Gradle và JDK phù hợp.
- Android Emulator hoặc điện thoại Android để chạy test.
- Cần Internet **trong lúc lấy dependencies và build lần đầu**. App không cần server để ghi chép hoặc xử lý OCR khi thư viện đã được cài đặt.

Kiểm tra môi trường:

```powershell
flutter doctor
flutter doctor --android-licenses
```

## 5. Chạy ứng dụng trên Pixel_7 bằng VS Code

Mở Terminal tại thư mục chứa `pubspec.yaml` (không phải thư mục cha). Nếu dự án không có thư mục `android/`, tạo một lần:

```powershell
flutter create --platforms=android .
```

**Cảnh báo:** Nếu cập nhật dự án đang dùng, hãy **giữ nguyên `android/`, `applicationId` và cấu hình ký** để bảo toàn khả năng cập nhật bản cũ.

Khởi động emulator nếu cần:

```powershell
& "E:\DevTools\Android\Sdk\emulator\emulator.exe" -avd Pixel_7
```

Kiểm tra rồi chạy:

```powershell
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d emulator-5554
```

Thay `emulator-5554` nếu `flutter devices` cho ID khác. `flutter analyze` có thể hiện cảnh báo/info không cản biên dịch; `flutter test` và chạy máy ảo mới xác minh chức năng ở mức tương ứng.

## 6. Kiểm thử chức năng chính

| ID | Bài test | Kết quả mong đợi |
|---|---|---|
| DB01 | Nâng từ bản SharedPreferences cũ lên v10 | Giao dịch cũ có trong SQLite, không nhân đôi |
| DB02 | Thêm, sửa, xóa; đóng app rồi mở lại | Giao dịch và tổng tiền nhất quán |
| BK01 | Xuất JSON ra Drive/Files | Có file sao lưu thực sự, đọc được |
| BK02 | Nhập lại JSON | Khôi phục đúng; không nhân đôi ID |
| BK03 | Nhập JSON lỗi hoặc ngày tương lai | Thông báo lỗi, không làm hỏng dữ liệu cũ |
| OCR01 | Hóa đơn cà phê có địa chỉ/số nhà | Không coi số nhà là tổng tiền |
| OCR02 | Hóa đơn nhiều dòng giá | Ưu tiên tổng phải thanh toán |
| OCR03 | Tên cửa hàng giống tên món (`CAFE`) | Không nhầm dòng món hàng có giá là cửa hàng |
| OCR04 | Ngày `16 thg 3, 2022` hoặc ISO | Đề xuất ngày chính xác nếu OCR đọc đúng |
| OCR05 | Hóa đơn thiếu một trường | Mở form chỉnh sửa; cảnh báo phù hợp |
| OCR06 | Ảnh sách/ảnh không liên quan | Cảnh báo hoặc từ chối khi dấu hiệu không phải hóa đơn rõ ràng |
| OCR07 | Ảnh quá mờ/không đọc được | Yêu cầu chụp hoặc chọn lại |
| OCR08 | Tắt Internet rồi quét | OCR vẫn xử lý trên thiết bị |
| CH01 | Nhiều danh mục cùng ngày | Cột chồng có các màu danh mục đúng |
| CH02 | Sửa/xóa giao dịch | Hai biểu đồ cập nhật |
| DT01 | Hôm nay ngày 12, thử lưu ngày 13 | Không cho phép |
| DT02 | Đến ngày 13, lưu ngày 13 | Cho phép |
| DT03 | Tháng 10 chưa sang tháng 11 | Chặn điều hướng tháng 11; mở khi đến tháng 11 |
| APK01 | Cài APK release và chạy không dùng VS Code | CRUD, OCR, backup hoạt động độc lập |

**Bộ hóa đơn tham chiếu đã dùng trong quá trình phát triển:** ĐẸP COFFEE, AN NAM, THE NOODLE HOUSE. Chúng là **test samples**, không phải danh sách cửa hàng viết cố định trong ứng dụng. Unit test parser dựa trên nội dung chữ; phải test OCR thực tế bằng ảnh trên emulator. Hóa đơn AN NAM có ngày tương lai thì đúng quy tắc là đọc ngày nhưng **không cho lưu** trước khi chỉnh sửa.

## 7. Build, cài và chia sẻ APK Release

Chạy từ thư mục project:

```powershell
flutter build apk --release
```

APK mặc định ở:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Nếu dùng script đi kèm dự án, xem `BUILD_APK_WINDOWS.bat` và `build_android.ps1` để biết vị trí bản APK được copy vào `dist/`.

Cài thử trên máy ảo:

```powershell
& "E:\DevTools\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 install -r "build\app\outputs\flutter-apk\app-release.apk"
```

**Quan trọng về dữ liệu và chữ ký:** Debug APK và Release APK có thể ký bằng khóa khác nhau nên không thể cài đè. Sao lưu JSON trước khi đổi loại APK; không xóa ứng dụng nếu chưa có bản sao lưu. Trước khi phát hành chính thức, cấu hình **keystore release cố định** (không commit khóa/mật khẩu lên GitHub) để có thể cập nhật sau này. Không khẳng định APK đã kiểm thử release nếu chưa tự chạy lệnh build/cài và test.

Push source lên GitHub sau khi kiểm thử; sử dụng GitHub Releases hoặc Google Drive để phân phối APK. Không push dữ liệu SQLite của người dùng, backup riêng tư, file `.env` có bí mật hoặc khóa ký.

## 8. Xem dữ liệu SQLite trên Emulator

Database tên `receiptly.db`, bảng `expenses`, nằm trong sandbox app (thường là `/data/user/0/<applicationId>/databases/`). Dùng Android Studio **App Inspection → Database Inspector** khi chạy bản debug, hoặc ADB `run-as` nếu package cho phép. Không nhập nguyên `<applicationId>` như cú pháp PowerShell: phải thay bằng package thật.

## 9. Lịch sử phát triển — từ bản đầu đến v10

| Phiên bản | Thay đổi đáng chú ý |
|---|---|
| v1 / bản đầu | Flutter Material UI, ML Kit offline, Regex merchant/total/date, SharedPreferences JSON, biểu đồ CustomPainter |
| v2 / Fixed v2 | Chỉnh lỗi cú pháp trong `main.dart`, biểu đồ và form |
| v3 / Fixed v3 | Thêm `flutter_test`, `flutter_lints`, sửa test mẫu `MyApp` |
| v4 | SQLite + migration dữ liệu cũ, JSON Backup/Restore, kiểm tra dấu hiệu hóa đơn, stacked bar chart |
| v5 | Giới hạn ngày/tháng tương lai theo thời gian thực; kiểm tra OCR, lưu SQLite và JSON nhập |
| v6 | Parser ưu tiên nhãn tổng, hạn chế nhầm địa chỉ/số điện thoại/mã đơn |
| v7 | Phân tích OCR dựa vào tọa độ dòng chữ và ghép dòng theo bố cục |
| v8 | Nới lỏng cảnh báo “không phải hóa đơn” để giảm từ chối nhầm hóa đơn thật |
| v9 | Phân tích thêm tiền bằng chữ, ngày tiếng Việt rút gọn, đánh giá sơ bộ chất lượng ảnh; bản quá chặt có thể từ chối hóa đơn thật |
| v9 Merchant Fix | Sửa heuristic lấy tên cửa hàng để không chọn dòng món kèm giá (ví dụ `CAFE SỮA 38,000`) |
| **v10 (hiện tại)** | **Flexible OCR**: trả kết quả có thể chỉnh sửa khi thiếu trường; từ chối/cảnh báo chủ yếu với ảnh không đọc được hoặc không liên quan rõ ràng; giữ SQLite, backup, biểu đồ, date guard |

> Bản v10 kế thừa **chức năng**, không nhất thiết mọi thay đổi trung gian đã được nhập tuần tự trên máy của người dùng. Đối chiếu các file `lib/` và `pubspec.yaml` khi nâng cấp.

## 10. Hạn chế và lưu ý bảo mật

- Google ML Kit trích chữ, còn parser chọn thông tin bằng quy tắc; **không có độ chính xác tuyệt đối** đối với mọi bố cục.
- Phát hiện “không phải hóa đơn” chỉ là heuristic; có thể cảnh báo sai hoặc bỏ sót. Thiếu trường không phải căn cứ duy nhất để kết luận ảnh không hợp lệ.
- Chất lượng ảnh thấp, chữ bị cắt, thiếu sáng, font lạ, tổng tiền ở nhiều cột hoặc cách ghi ngày không phổ biến có thể làm sai OCR.
- SharedPreferences cũ chỉ phục vụ migration; dữ liệu giao dịch hiện tại dùng SQLite. Không có đăng nhập/đồng bộ cloud.
- Backup JSON là dữ liệu chi tiêu **không mã hóa**. Không upload công khai hay commit lên Git.
- Dữ liệu bị xóa khi gỡ app thường không tự phục hồi; nên sao lưu trước khi nâng cấp/cài lại.
- APK release chưa được build trong môi trường tạo tài liệu này. Chỉ phát hành sau khi `flutter analyze`, `flutter test`, kiểm thử thực tế và APK release đạt yêu cầu.

## 11. Gợi ý nộp báo cáo lab

Minh chứng nên gồm: ảnh dashboard, ảnh chọn hóa đơn, màn hình kiểm tra OCR, ví dụ nhận diện merchant/total/date, ảnh biểu đồ tròn/cột, bằng chứng SQLite/backup JSON, log `flutter test`, log build APK, và kết quả thử offline trên Pixel_7. Phân biệt rõ **test parser từ text** với **test OCR thực tế từ ảnh**.
