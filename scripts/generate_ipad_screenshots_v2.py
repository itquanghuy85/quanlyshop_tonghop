"""
Generate 3 iPad Pro 13-inch screenshots for App Store Connect.
Resolution: 2048 x 2732 pixels (portrait).
Enhanced version with realistic UI rendering.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import math

# iPad Pro 13" resolution
W, H = 2048, 2732

# Colors (matching app theme)
PRIMARY = (77, 142, 233)
PRIMARY_DARK = (0, 104, 255)
PRIMARY_LIGHT = (66, 165, 245)
SECONDARY = (255, 152, 0)
BG = (248, 250, 255)
SURFACE = (255, 255, 255)
TEXT_PRIMARY = (33, 33, 33)
TEXT_SECONDARY = (117, 117, 117)
TEXT_HINT = (158, 158, 158)
TEXT_WHITE = (255, 255, 255)
GREEN = (76, 175, 80)
GREEN_DARK = (56, 142, 60)
RED = (244, 67, 54)
BLUE_LIGHT = (227, 242, 253)
GREEN_LIGHT = (232, 245, 233)
ORANGE_LIGHT = (255, 243, 224)
RED_LIGHT = (255, 235, 238)
PURPLE = (156, 39, 176)
PURPLE_LIGHT = (243, 229, 245)
TEAL = (0, 150, 136)
TEAL_LIGHT = (224, 242, 241)
INDIGO = (63, 81, 181)
INDIGO_LIGHT = (232, 234, 246)
DIVIDER = (224, 224, 224)
SHADOW_COLOR = (0, 0, 0, 25)

# Output dir
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "screenshots_ipad")
os.makedirs(OUT_DIR, exist_ok=True)

# Logo path
LOGO_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "images", "icon.png")


def font(size, bold=False):
    """Get a font. Try several Windows fonts."""
    paths_bold = [
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
    ]
    paths_regular = [
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]
    candidates = paths_bold if bold else paths_regular
    for p in candidates:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    # Fallback
    for p in paths_regular + paths_bold:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def font_light(size):
    paths = [
        "C:/Windows/Fonts/segoeuil.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
    ]
    for p in paths:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return font(size)


def draw_gradient_rect(img, xy, color_top, color_bottom):
    """Draw a vertical gradient rectangle on the image."""
    x0, y0, x1, y1 = xy
    draw = ImageDraw.Draw(img)
    for yy in range(y0, y1):
        ratio = (yy - y0) / max(1, y1 - y0)
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * ratio)
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * ratio)
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * ratio)
        draw.line([(x0, yy), (x1, yy)], fill=(r, g, b))


def draw_card_shadow(img, draw, x, y, w, h, radius=24):
    """Draw a card with subtle shadow effect."""
    # Shadow (slightly offset, slightly larger)
    shadow_img = Image.new('RGBA', (w+20, h+20), (0,0,0,0))
    sd = ImageDraw.Draw(shadow_img)
    sd.rounded_rectangle([4, 6, w+4, h+6], radius=radius, fill=(0,0,0,30))
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=8))
    img.paste(Image.blend(Image.new('RGBA', shadow_img.size, (0,0,0,0)), shadow_img, 0.5), (x-5, y-3), shadow_img)
    # Card
    draw.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=SURFACE)


def draw_status_bar(draw, y=0):
    """Draw iPad-style status bar."""
    h = 80
    draw.rectangle([0, y, W, y+h], fill=BG)
    f = font(30)
    draw.text((70, y+25), "9:41", fill=TEXT_PRIMARY, font=font(30, bold=True))
    # Right icons
    # Battery
    bx = W - 120
    by = y + 28
    draw.rounded_rectangle([bx, by, bx+55, by+24], radius=4, fill=None, outline=TEXT_SECONDARY, width=2)
    draw.rounded_rectangle([bx+4, by+4, bx+46, by+20], radius=2, fill=GREEN)
    draw.rounded_rectangle([bx+55, by+7, bx+60, by+17], radius=2, fill=TEXT_SECONDARY)
    # WiFi
    wx = bx - 60
    wy = by + 3
    for i in range(4):
        r = 4 + i * 5
        draw.arc([wx-r, wy-r+15, wx+r, wy+r+15], 200, 340, fill=TEXT_SECONDARY, width=2)
    return y + h


def draw_app_header(img, draw, title, subtitle=None, y=80, height=180):
    """Draw a gradient app bar with title."""
    draw_gradient_rect(img, [0, y, W, y+height], PRIMARY, PRIMARY_DARK)

    # Logo
    if os.path.exists(LOGO_PATH):
        try:
            logo = Image.open(LOGO_PATH).convert("RGBA")
            logo = logo.resize((64, 64), Image.LANCZOS)
            img.paste(logo, (55, y + 20), logo)
            tx = 135
        except Exception:
            tx = 60
    else:
        tx = 60

    draw.text((tx, y + 16), title, fill=TEXT_WHITE, font=font(48, bold=True))
    if subtitle:
        draw.text((tx, y + 72), subtitle, fill=(255, 255, 255, 200), font=font(34))

    return y + height


def draw_bottom_nav(draw, active_idx, y=None):
    """Draw bottom navigation bar."""
    if y is None:
        y = H - 140
    h = 140
    draw.rectangle([0, y, W, y+h], fill=SURFACE)
    draw.line([(0, y), (W, y)], fill=DIVIDER, width=2)

    tabs = [
        ("Trang chủ", "🏠"),
        ("Bán hàng", "🛒"),
        ("Sửa chữa", "🔧"),
        ("Kho hàng", "📦"),
        ("Cài đặt", "⚙"),
    ]
    tw = W // len(tabs)
    f_icon = font(36)
    f_label = font(24)

    for i, (label, icon) in enumerate(tabs):
        cx = tw * i + tw // 2
        is_active = i == active_idx
        color = PRIMARY if is_active else TEXT_HINT

        # Active indicator
        if is_active:
            draw.rounded_rectangle([cx-45, y+8, cx+45, y+48], radius=20, fill=(227, 242, 253))

        # Icon dot
        draw.ellipse([cx-16, y+14, cx+16, y+46], fill=color)

        # Label
        bbox = f_label.getbbox(label)
        lw = bbox[2] - bbox[0]
        draw.text((cx - lw//2, y + 58), label, fill=color, font=f_label)

        # Active dot
        if is_active:
            draw.ellipse([cx-4, y+90, cx+4, y+98], fill=PRIMARY)


def lighten(color, amount=160):
    return tuple(min(255, c + amount) for c in color[:3])


def text_width(text, f):
    bbox = f.getbbox(text)
    return bbox[2] - bbox[0]


# ================================================================
# SCREENSHOT 1: Dashboard
# ================================================================
def create_screenshot_1():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)

    status_y = draw_status_bar(draw)
    y = draw_app_header(img, draw, "Quản lý cửa hàng", "Xin chào, Chủ shop! 👋", y=status_y, height=160)
    y += 24

    M = 44  # margin
    CW = W - M * 2  # card width

    # ── Revenue Card ──
    ch = 300
    draw_card_shadow(img, draw, M, y, CW, ch, radius=26)
    draw.text((M+35, y+22), "DOANH THU HÔM NAY", fill=TEXT_SECONDARY, font=font(28, bold=True))
    draw.text((M+35, y+62), "14/03/2026", fill=TEXT_HINT, font=font(24))
    draw.text((M+35, y+100), "12,580,000 đ", fill=GREEN_DARK, font=font(60, bold=True))

    # mini stats
    stats = [
        ("Đơn bán", "18", PRIMARY),
        ("Đơn sửa", "7", SECONDARY),
        ("Khách mới", "5", TEAL),
        ("Nhập kho", "3", INDIGO),
    ]
    scw = CW // 4
    for i, (label, val, color) in enumerate(stats):
        sx = M + scw * i + 20
        sy = y + 195
        draw.ellipse([sx, sy, sx+44, sy+44], fill=lighten(color, 180))
        draw.ellipse([sx+8, sy+8, sx+36, sy+36], fill=color)
        draw.text((sx+56, sy-2), val, fill=TEXT_PRIMARY, font=font(42, bold=True))
        draw.text((sx+56, sy+40), label, fill=TEXT_SECONDARY, font=font(24))
    y += ch + 20

    # ── Quick Actions ──
    draw.text((M+8, y), "TRUY CẬP NHANH", fill=TEXT_SECONDARY, font=font(28, bold=True))
    y += 48

    actions = [
        ("Bán hàng", GREEN, "💰"),
        ("Sửa chữa", PRIMARY, "🔧"),
        ("Nhập kho", SECONDARY, "📦"),
        ("Kiểm kho", INDIGO, "📋"),
        ("Doanh thu", TEAL, "📊"),
        ("Chấm công", PURPLE, "⏱"),
    ]

    aw = (CW - 24) // 2
    ah = 135
    gap = 16
    for i, (label, color, ico) in enumerate(actions):
        col, row = i % 2, i // 2
        ax = M + col * (aw + gap + 8)
        ay = y + row * (ah + gap)
        bg = lighten(color, 185)
        draw.rounded_rectangle([ax, ay, ax+aw, ay+ah], radius=20, fill=bg, outline=lighten(color, 100), width=2)
        draw.ellipse([ax+22, ay+ah//2-26, ax+74, ay+ah//2+26], fill=color)
        draw.text((ax+90, ay+ah//2-22), label, fill=color, font=font(36, bold=True))
    y += 3 * (ah + gap) + 20

    # ── Activity Feed ──
    draw.text((M+8, y), "HOẠT ĐỘNG HÔM NAY", fill=TEXT_SECONDARY, font=font(28, bold=True))
    y += 48
    ch2 = 460
    draw_card_shadow(img, draw, M, y, CW, ch2, radius=26)

    activities = [
        ("Đơn bán #DH001 — Nguyễn Văn A", "1,250,000đ", GREEN, "10:30"),
        ("Sửa iPhone 15 — Trần Thị B", "Đang xử lý", SECONDARY, "09:45"),
        ("Nhập kho: Ốp lưng ×50", "+50 SP", PRIMARY, "09:15"),
        ("Đơn bán #DH002 — Lê Văn C", "3,800,000đ", GREEN, "08:50"),
        ("Đơn sửa #SC003 — Hoàn thành", "500,000đ", TEAL, "08:20"),
        ("Chấm công: 5 nhân viên", "Đã điểm danh", PURPLE, "08:00"),
    ]
    for i, (desc, val, color, time) in enumerate(activities):
        ay = y + 20 + i * 72
        draw.ellipse([M+50, ay+18, M+74, ay+42], fill=color)
        draw.text((M+90, ay+10), desc, fill=TEXT_PRIMARY, font=font(28))
        vw = text_width(val, font(28, bold=True))
        draw.text((M+CW-vw-40, ay+10), val, fill=color, font=font(28, bold=True))
        draw.text((M+90, ay+42), time, fill=TEXT_HINT, font=font(22))
    y += ch2 + 20

    # ── Finance Row ──
    draw.text((M+8, y), "TÀI CHÍNH", fill=TEXT_SECONDARY, font=font(28, bold=True))
    y += 48
    ch3 = 170
    draw_card_shadow(img, draw, M, y, CW, ch3, radius=26)
    fin = [
        ("Doanh thu", "12.5M", GREEN),
        ("Chi phí", "4.2M", RED),
        ("Công nợ", "8.3M", SECONDARY),
        ("Lợi nhuận", "8.3M", TEAL),
    ]
    fw = CW // 4
    for i, (label, val, color) in enumerate(fin):
        fx = M + fw * i + 22
        fy = y + 24
        draw.text((fx, fy), val, fill=color, font=font(42, bold=True))
        draw.text((fx, fy + 52), label, fill=TEXT_SECONDARY, font=font(24))
        if i < 3:
            draw.line([(M + fw*(i+1), y+20), (M + fw*(i+1), y+ch3-20)], fill=DIVIDER, width=1)

    draw_bottom_nav(draw, 0)
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_01.png"), "PNG")
    print("  ✅ Screenshot 1 — Dashboard")


# ================================================================
# SCREENSHOT 2: Sales Management
# ================================================================
def create_screenshot_2():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)

    status_y = draw_status_bar(draw)
    y = draw_app_header(img, draw, "Quản lý đơn hàng", subtitle="18 đơn hôm nay", y=status_y, height=140)
    y += 16

    M = 44
    CW = W - M*2

    # ── Filter chips ──
    chips = [
        ("Tất cả (25)", PRIMARY, True),
        ("Chờ xử lý (3)", SECONDARY, False),
        ("Đang xử lý (5)", PRIMARY_LIGHT, False),
        ("Hoàn thành (15)", GREEN, False),
        ("Đã hủy (2)", RED, False),
    ]
    cx = M
    f_ch = font(26)
    for label, color, active in chips:
        tw2 = text_width(label, f_ch)
        cw = tw2 + 44
        if active:
            draw.rounded_rectangle([cx, y, cx+cw, y+54], radius=27, fill=color)
            draw.text((cx+22, y+12), label, fill=TEXT_WHITE, font=f_ch)
        else:
            draw.rounded_rectangle([cx, y, cx+cw, y+54], radius=27, fill=SURFACE, outline=color, width=2)
            draw.text((cx+22, y+12), label, fill=color, font=f_ch)
        cx += cw + 14
    y += 76

    # ── Order cards ──
    orders = [
        ("#DH140326001", "Nguyễn Văn An", "0912 345 678",
         "iPhone 15 Pro Max 256GB ×1, Ốp lưng ×1", "32,990,000đ",
         "Hoàn thành", GREEN, "14:30", "Đã thanh toán"),
        ("#DH140326002", "Trần Thị Bích", "0987 654 321",
         "Samsung Galaxy S25 Ultra ×1, Sạc nhanh ×1", "28,490,000đ",
         "Đang giao", PRIMARY, "13:15", "Đã thanh toán"),
        ("#DH140326003", "Lê Hoàng Minh", "0909 112 233",
         "AirPods Pro 2 ×2, Apple Watch Ultra 2 ×1", "25,770,000đ",
         "Chờ xử lý", SECONDARY, "12:00", "Chờ thanh toán"),
        ("#DH140326004", "Phạm Quốc Đạt", "0933 445 566",
         "MacBook Air M3 ×1", "27,990,000đ",
         "Hoàn thành", GREEN, "11:30", "Đã thanh toán"),
        ("#DH140326005", "Hoàng Thị Lan", "0977 889 900",
         "iPad Pro M4 13\" ×1, Apple Pencil Pro ×1", "38,480,000đ",
         "Đang xử lý", PRIMARY_LIGHT, "10:45", "Đặt cọc 10,000,000đ"),
        ("#DH140326006", "Võ Minh Tuấn", "0966 778 899",
         "Xiaomi 14 Ultra ×1, Cường lực ×2", "18,290,000đ",
         "Đã hủy", RED, "09:20", "Hoàn tiền"),
        ("#DH140326007", "Đỗ Thanh Hùng", "0944 556 677",
         "OPPO Find X8 Pro ×1", "22,990,000đ",
         "Hoàn thành", GREEN, "08:40", "Đã thanh toán"),
    ]

    for oid, cust, phone, items, total, status, sc, time, pay in orders:
        ch = 260
        if y + ch > H - 180:
            break
        draw_card_shadow(img, draw, M, y, CW, ch, radius=22)

        # header row
        draw.text((M+30, y+18), oid, fill=PRIMARY, font=font(30, bold=True))
        draw.text((M+30+330, y+21), f"• {time} — 14/03/2026", fill=TEXT_HINT, font=font(24))

        # Status badge
        f_st = font(24, bold=True)
        sw = text_width(status, f_st)
        bx = M + CW - sw - 55
        draw.rounded_rectangle([bx, y+14, bx+sw+28, y+50], radius=14, fill=sc)
        draw.text((bx+14, y+18), status, fill=TEXT_WHITE, font=f_st)

        # Customer
        draw.text((M+30, y+60), cust, fill=TEXT_PRIMARY, font=font(32, bold=True))
        draw.text((M+30+380, y+64), phone, fill=TEXT_SECONDARY, font=font(28))

        # Items
        draw.text((M+30, y+104), items[:65], fill=TEXT_SECONDARY, font=font(26))

        # divider
        draw.line([(M+30, y+148), (M+CW-30, y+148)], fill=DIVIDER, width=1)

        # Bottom row
        draw.text((M+30, y+165), total, fill=PRIMARY_DARK, font=font(40, bold=True))

        # Payment badge
        pay_bg = GREEN_LIGHT if "Đã" in pay else ORANGE_LIGHT if "Đặt" in pay else RED_LIGHT
        pay_fg = GREEN_DARK if "Đã" in pay else SECONDARY if "Đặt" in pay else RED
        f_pay = font(24)
        pw = text_width(pay, f_pay)
        px = M + CW - pw - 55
        draw.rounded_rectangle([px-10, y+175, px+pw+10, y+205], radius=10, fill=pay_bg)
        draw.text((px, y+178), pay, fill=pay_fg, font=f_pay)

        y += ch + 14

    # FAB
    fab_x, fab_y = W - 150, H - 240
    draw.ellipse([fab_x, fab_y, fab_x+90, fab_y+90], fill=PRIMARY)
    draw.text((fab_x+28, fab_y+16), "+", fill=TEXT_WHITE, font=font(52, bold=True))

    draw_bottom_nav(draw, 1)
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_02.png"), "PNG")
    print("  ✅ Screenshot 2 — Sales Management")


# ================================================================
# SCREENSHOT 3: Inventory
# ================================================================
def create_screenshot_3():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)

    status_y = draw_status_bar(draw)
    y = draw_app_header(img, draw, "Kho hàng", subtitle="1,247 sản phẩm", y=status_y, height=140)
    y += 16

    M = 44
    CW = W - M*2

    # ── Search bar ──
    draw.rounded_rectangle([M, y, M+CW, y+72], radius=36, fill=SURFACE, outline=DIVIDER, width=2)
    draw.ellipse([M+18, y+18, M+54, y+54], fill=None, outline=TEXT_HINT, width=2)
    draw.text((M+68, y+18), "Tìm kiếm sản phẩm...", fill=TEXT_HINT, font=font(30))
    # scan icon
    draw.rounded_rectangle([M+CW-75, y+14, M+CW-15, y+58], radius=10, fill=PRIMARY)
    draw.text((M+CW-65, y+18), "QR", fill=TEXT_WHITE, font=font(26, bold=True))
    y += 92

    # ── Summary cards ──
    summs = [
        ("Tổng SP", "1,247", PRIMARY, "sản phẩm"),
        ("Tồn kho", "8,563", GREEN, "số lượng"),
        ("Sắp hết", "23", SECONDARY, "cần nhập"),
        ("Hết hàng", "8", RED, "sản phẩm"),
    ]
    sw2 = (CW - 36) // 4
    for i, (label, val, color, sub) in enumerate(summs):
        sx = M + i * (sw2 + 12)
        draw_card_shadow(img, draw, sx, y, sw2, 150, radius=18)
        draw.text((sx+16, y+14), label, fill=TEXT_SECONDARY, font=font(24))
        draw.text((sx+16, y+46), val, fill=color, font=font(44, bold=True))
        draw.text((sx+16, y+102), sub, fill=TEXT_HINT, font=font(20))
        # color accent line
        draw.rounded_rectangle([sx, y, sx+sw2, y+6], radius=3, fill=color)
    y += 175

    # ── Category tabs ──
    cats = ["Tất cả", "Điện thoại", "Phụ kiện", "Linh kiện", "Máy tính"]
    cx = M
    f_cat = font(28)
    for i, cat in enumerate(cats):
        tw2 = text_width(cat, f_cat)
        cw = tw2 + 40
        if i == 0:
            draw.rounded_rectangle([cx, y, cx+cw, y+52], radius=26, fill=PRIMARY)
            draw.text((cx+20, y+10), cat, fill=TEXT_WHITE, font=f_cat)
        else:
            draw.rounded_rectangle([cx, y, cx+cw, y+52], radius=26, fill=SURFACE, outline=DIVIDER, width=2)
            draw.text((cx+20, y+10), cat, fill=TEXT_PRIMARY, font=f_cat)
        cx += cw + 12
    y += 72

    # ── Product list ──
    products = [
        ("iPhone 15 Pro Max 256GB", "IP15PM-256", "29,990,000đ", "Giá vốn 27.5M", "12", GREEN, "Điện thoại", (100,149,237)),
        ("Samsung Galaxy S25 Ultra", "SS-S25U-512", "33,990,000đ", "Giá vốn 30.2M", "8", GREEN, "Điện thoại", (0,150,136)),
        ("AirPods Pro 2 (USB-C)", "AP-PRO2", "5,990,000đ", "Giá vốn 4.8M", "25", GREEN, "Phụ kiện", (156,39,176)),
        ("Ốp lưng MagSafe iPhone 15", "CASE-IP15", "890,000đ", "Giá vốn 320K", "3", SECONDARY, "Phụ kiện", (255,152,0)),
        ("Cường lực 9H Galaxy S25", "GLASS-S25", "150,000đ", "Giá vốn 25K", "2", RED, "Phụ kiện", (244,67,54)),
        ("MacBook Air M3 15\" 256GB", "MBA-M3-15", "32,990,000đ", "Giá vốn 29.8M", "5", GREEN, "Máy tính", (63,81,181)),
        ("Sạc nhanh 67W Xiaomi", "CHG-XI-67W", "490,000đ", "Giá vốn 180K", "0", RED, "Phụ kiện", (244,67,54)),
        ("Apple Watch Ultra 2", "AW-ULTRA2", "21,990,000đ", "Giá vốn 19.5M", "4", GREEN, "Phụ kiện", (0,150,136)),
    ]

    for name, sku, price, cost, stock, stock_c, cat, icon_c in products:
        ch = 175
        if y + ch > H - 180:
            break
        draw_card_shadow(img, draw, M, y, CW, ch, radius=18)

        # Product image placeholder
        draw.rounded_rectangle([M+18, y+16, M+155, y+ch-16], radius=14, fill=lighten(icon_c, 200))
        # icon accent
        draw.rounded_rectangle([M+18, y+16, M+155, y+22], radius=3, fill=icon_c)
        # Placeholder text
        draw.text((M+52, y+60), "📱", fill=icon_c, font=font(48))

        px = M + 175
        draw.text((px, y+16), name, fill=TEXT_PRIMARY, font=font(30, bold=True))
        draw.text((px, y+54), f"SKU: {sku}  •  {cat}", fill=TEXT_SECONDARY, font=font(24))
        draw.text((px, y+92), price, fill=PRIMARY_DARK, font=font(36, bold=True))
        draw.text((px+350, y+98), cost, fill=TEXT_HINT, font=font(24))

        # Stock badge
        if stock == "0":
            stxt = "Hết hàng"
        elif int(stock) <= 3:
            stxt = f"Còn {stock} SP ⚠"
        else:
            stxt = f"Tồn: {stock}"
        f_stk = font(26, bold=True)
        stw = text_width(stxt, f_stk)
        sx = M + CW - stw - 40
        draw.rounded_rectangle([sx-8, y+ch-48, sx+stw+8, y+ch-16], radius=10,
                              fill=lighten(stock_c, 185))
        draw.text((sx, y+ch-46), stxt, fill=stock_c, font=f_stk)

        y += ch + 12

    # FAB
    fab_x, fab_y = W - 150, H - 240
    draw.ellipse([fab_x, fab_y, fab_x+90, fab_y+90], fill=SECONDARY)
    draw.text((fab_x+28, fab_y+16), "+", fill=TEXT_WHITE, font=font(52, bold=True))

    draw_bottom_nav(draw, 3)
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_03.png"), "PNG")
    print("  ✅ Screenshot 3 — Inventory")


if __name__ == "__main__":
    print(f"🖼  Generating iPad Pro 13\" screenshots ({W}×{H} px)…")
    print(f"📂 Output: {OUT_DIR}\n")
    create_screenshot_1()
    create_screenshot_2()
    create_screenshot_3()
    print(f"\n✅ Done! 3 screenshots saved to: {OUT_DIR}")
