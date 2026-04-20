# Huong dan cuc don gian de gui log iPhone

Muc tieu: ban chi can chay 1 script, test app nhu binh thuong, roi gui 1 file zip cho Copilot.

## Ban can chuan bi

- May Mac da cai Flutter va Xcode
- iPhone da cam cap vao Mac
- Da mo khoa iPhone va bam Trust neu duoc hoi

## Cac buoc thuc hien

1. Mo Terminal tren Mac
2. Di den thu muc du an
3. Chay lenh sau:

   sh scripts/collect_ios_uat_logs.sh

4. Script se hien danh sach thiet bi, ban copy va dan DEVICE ID cua iPhone
5. De cua so Terminal do mo nguyen
6. Mo app tren iPhone va test dung 14 buoc UAT
7. Test xong, quay lai Terminal va bam Ctrl+C
8. Script tu dong tao file zip log

## File can gui cho Copilot

Gui file zip theo duong dan dang:

UAT_LOGS/YYYYMMDD_HHMMSS/ios_uat_logs.zip

Chi can gui file zip nay la du.

## Neu gap loi nhanh

- Khong thay iPhone trong danh sach: rut cap cam lai, mo khoa iPhone, bam Trust, chay lai script
- Bao khong tim thay flutter: mo dung Terminal o may Mac da cai Flutter
- Co log it hoac rong: chay lai script, de Terminal mo trong suot qua trinh test UAT
