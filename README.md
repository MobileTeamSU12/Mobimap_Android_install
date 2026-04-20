# Deploy

Repo này đã được cấu hình `Git LFS` cho file `*.apk` để có thể đẩy các bản build lớn lên GitHub mà không bị chặn bởi giới hạn blob thường.

## Chuẩn bị một lần trên máy

1. Cài `Git LFS` nếu máy chưa có.
2. Chạy lệnh:

```bash
git lfs install
```

## Cách đẩy file APK lớn

1. Đảm bảo file `.apk` được thêm sau khi repo đã có `.gitattributes`.
2. Dùng quy trình Git bình thường:

```bash
git add .gitattributes path/to/your.apk
git commit -m "Cập nhật APK"
git push
```

`Git LFS` sẽ tự chuyển file APK thành pointer trong Git và upload nội dung thật lên LFS storage.

## Quy trình bằng `deploy.exe`

1. Download và mở file `deploy.exe`.
2. Nhập token của GitHub. Nếu cần tạo mới, vào: `https://github.com/settings/tokens`
3. Nhập tên repo Git, ví dụ: `MobileTeamSU12/Mobimap_Android_install`
4. Nhập đường dẫn tới thư mục build ra file `.apk`

## Lưu ý

- Nếu commit một file APK lớn trước khi cấu hình `Git LFS`, GitHub vẫn có thể từ chối push.
- Với các file đã từng commit kiểu Git thường và chưa push lên remote, cần đưa lại file đó vào commit mới dưới dạng `Git LFS` hoặc viết lại lịch sử commit tương ứng.

## Dọn lịch sử để giảm dung lượng repo

Script [scripts/Optimize-RepoHistory.ps1](D:/trash/Mobimap_Android_install/scripts/Optimize-RepoHistory.ps1) sẽ:

- hiển thị dung lượng repo trước và sau khi tối ưu
- hiển thị tiến trình từng bước sau khi chọn option
- `pull --ff-only` branch hiện tại từ remote trước khi bắt đầu, trừ khi dùng `-SkipPull`
- tạo mirror backup ngoài repo
- xóa lịch sử của các file khớp pattern, mặc định là `*.apk`
- khôi phục lại đúng bộ file đang có ở `HEAD`
- commit lại các file đó dưới `Git LFS`
- tùy chọn `push --force` branch hiện tại

Ví dụ:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Optimize-RepoHistory.ps1
```

Khi chạy không truyền tham số, script sẽ hiện menu để chọn:

- tối ưu có pull
- tối ưu có pull và push force
- tối ưu bỏ qua pull
- tối ưu bỏ qua pull và push force
- hoặc chế độ tùy chỉnh

Sau khi chọn option, script sẽ in:

- cấu hình đã chọn
- bước đang chạy theo dạng `[n/tổng]`
- dung lượng repo trước và sau khi tối ưu
- và giữ cửa sổ chờ `Enter` khi chạy ở chế độ tương tác

Có thể ép hiện menu ngay cả khi truyền tham số khác:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Optimize-RepoHistory.ps1 -Interactive
```

Có thể push luôn sau khi dọn:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Optimize-RepoHistory.ps1 -PushCurrentBranch
```

Nếu không muốn `pull` trước khi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Optimize-RepoHistory.ps1 -SkipPull
```
