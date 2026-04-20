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
