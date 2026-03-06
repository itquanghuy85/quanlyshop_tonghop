# Web Print Bridge (POS qua LAN cho bản Web)

Muc tieu
- Trinh duyet web khong the ket noi Bluetooth POS truc tiep.
- Giai phap: web gui lenh in (ESC/POS bytes) qua HTTP toi mot bridge server trong LAN.
- Bridge server se mo TCP `9100` toi may in POS va day bytes in.

## Huong dan nhanh cho truong hop cua ban (IP may in = 192.168.1.199)
0. Don gian nhat: chi can double-click file
`scripts/IN_WEB_1_CLICK.bat`

File nay se tu dong:
- Bat bridge in
- Mo web dung link in

Ban chi can bam IN trong web.

Neu khong dung file 1-click, moi lam thu cong:
1. Tren may tinh noi bo (Windows) da cai Node.js, double-click file:
`scripts/start_web_print_bridge.bat`

2. Sau khi chay, mo web bang link:
`https://quanlyshop.web.app/?bridgeUrl=http://127.0.0.1:19191/print`

3. Bam in trong web nhu binh thuong.

4. Neu may in khong noi cung may tinh bridge, thay `127.0.0.1` bang IP may tinh chay bridge, vi du:
`https://quanlyshop.web.app/?bridgeUrl=http://192.168.1.10:19191/print`

5. Khong tat cua so bridge khi dang su dung in web.

## De nguoi dung khong can ky thuat van dung duoc
- Buoc 1: Tao shortcut file `start_web_print_bridge.bat` ra Desktop va doi ten thanh:
	`BAT IN WEB (POS)`
- Buoc 2: Gui 1 link web co san `bridgeUrl` cho nhan vien.
- Buoc 3: Huong dan 2 buoc duy nhat:
	1) Bam `BAT IN WEB (POS)`
	2) Mo link web da duoc cap

## Gui link qua chat noi bo (moi)
- Vao `Chat noi bo` > menu `...` > `Gửi link in web`
- Nhap IP may tinh chay bridge (co the doi IP chu dong)
- Bam `Gửi link`
- Nhan vien chi can bam vao link trong chat la mo dung trang in web

Checklist cho quan ly:
- Da cai Node.js tren may chay bridge
- May tinh bridge nhin thay may in qua LAN
- May in dung cong 9100
- Cho phep port 19191 trong firewall noi bo

## 1) Chay bridge server
Tu thu muc du an:

```bash
node scripts/web_print_bridge_server.js
```

Tuy chon bien moi truong:

```bash
BRIDGE_PORT=19191
BRIDGE_TOKEN=your_secret_token
DEFAULT_PRINTER_IP=192.168.1.50
DEFAULT_PRINTER_PORT=9100
```

Kiem tra health:

```bash
curl http://127.0.0.1:19191/health
```

## 2) Cau hinh tren web app
Web app doc cac key tu `SharedPreferences`:
- `web_print_bridge_enabled` (bool, mac dinh `true`)
- `web_print_bridge_url` (string, mac dinh `http://127.0.0.1:19191/print`)
- `web_print_bridge_token` (string, neu bridge co token)
- `web_print_bridge_timeout_ms` (int, mac dinh `12000`)

Neu chua set key, app dung mac dinh local bridge.

## 3) Luong in
- Khi chay tren web, `UnifiedPrinterService` uu tien gui lenh qua `WebPrintBridgeService`.
- Neu bridge tra ve `ok=true`, in thanh cong.
- Neu bridge khong chay/cau hinh sai, web se bao in that bai.

## 4) Trien khai LAN
Phuong an de dung thuc te:
1. Dat 1 may tinh trong LAN gan may in POS, chay bridge server.
2. Mo firewall cho cong bridge (vd `19191`) trong LAN.
3. Tren cac may web client, set `web_print_bridge_url` thanh `http://<bridge-ip>:19191/print`.
4. Neu can bao mat, bat `BRIDGE_TOKEN` va set `web_print_bridge_token` tren client.

## 5) Bao mat
- Khuyen nghi chay bridge trong mang noi bo.
- Bat token cho moi request in.
- Khong public cong bridge ra Internet.
