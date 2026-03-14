"""
Generate 3 iPad Pro 13-inch screenshots for App Store Connect.
Resolution: 2048 x 2732 pixels (portrait).
"""

from PIL import Image, ImageDraw, ImageFont
import os
import sys

# iPad Pro 13" resolution
W, H = 2048, 2732

# Colors (matching app theme)
PRIMARY = (77, 142, 233)        # Blue primary
PRIMARY_DARK = (0, 104, 255)    # Zalo blue
PRIMARY_LIGHT = (66, 165, 245)  
SECONDARY = (255, 152, 0)       # Orange
BG = (248, 250, 255)            # Background
SURFACE = (255, 255, 255)       # White
TEXT_PRIMARY = (33, 33, 33)      # Dark text
TEXT_SECONDARY = (117, 117, 117) # Grey text
TEXT_WHITE = (255, 255, 255)
GREEN = (76, 175, 80)
RED = (244, 67, 54)
BLUE_LIGHT = (227, 242, 253)
GREEN_LIGHT = (232, 245, 233)
ORANGE_LIGHT = (255, 243, 224)
RED_LIGHT = (255, 235, 238)
PURPLE = (156, 39, 176)
TEAL = (0, 150, 136)
INDIGO = (63, 81, 181)
STATUS_BAR_BG = (248, 250, 255)
DIVIDER = (224, 224, 224)

# Output dir
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "screenshots_ipad")
os.makedirs(OUT_DIR, exist_ok=True)

def get_font(size, bold=False):
    """Try to get a good font, fallback to default."""
    font_paths = [
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",  # bold
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/arialbd.ttf",   # bold
    ]
    if bold:
        for fp in [font_paths[1], font_paths[3]]:
            if os.path.exists(fp):
                return ImageFont.truetype(fp, size)
    for fp in font_paths:
        if os.path.exists(fp):
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def draw_status_bar(draw, bg_color=STATUS_BAR_BG, dark_text=True):
    """Draw iPad-style status bar at top."""
    bar_h = 88
    draw.rectangle([0, 0, W, bar_h], fill=bg_color)
    tc = TEXT_PRIMARY if dark_text else TEXT_WHITE
    f = get_font(32)
    draw.text((80, 30), "9:41", fill=tc, font=f)
    # Right side icons (wifi, battery)
    draw.text((W - 300, 30), "Wi-Fi     100%", fill=tc, font=f)


def draw_rounded_rect(draw, xy, radius, fill, outline=None, width=0):
    """Draw a rounded rectangle."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_app_bar(draw, title, y=88, bg=PRIMARY, height=120):
    """Draw Material-style app bar."""
    draw.rectangle([0, y, W, y + height], fill=bg)
    f_title = get_font(48, bold=True)
    draw.text((60, y + 36), title, fill=TEXT_WHITE, font=f_title)
    return y + height


def draw_card(draw, x, y, w, h, fill=SURFACE, radius=24, shadow=True):
    """Draw a Material card with optional shadow."""
    if shadow:
        draw.rounded_rectangle([x+4, y+6, x+w+4, y+h+6], radius=radius, fill=(0,0,0,20))
    draw.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=fill)


def draw_icon_circle(draw, cx, cy, r, color):
    """Draw a colored circle (icon placeholder)."""
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=color)


def draw_tab_bar(draw, tabs, active_index, y):
    """Draw bottom navigation tab bar."""
    bar_h = 130
    draw.rectangle([0, y, W, y + bar_h], fill=SURFACE)
    draw.line([(0, y), (W, y)], fill=DIVIDER, width=2)
    tab_w = W // len(tabs)
    f = get_font(28)
    for i, (icon_text, label) in enumerate(tabs):
        cx = tab_w * i + tab_w // 2
        color = PRIMARY if i == active_index else TEXT_SECONDARY
        # Icon circle
        draw.ellipse([cx-22, y+20, cx+22, y+64], fill=color if i == active_index else (200,200,200))
        # Label
        bbox = f.getbbox(label)
        tw = bbox[2] - bbox[0]
        draw.text((cx - tw//2, y + 75), label, fill=color, font=f)
    return y + bar_h

# ================================================================
# SCREENSHOT 1: Dashboard / Home Screen
# ================================================================
def create_screenshot_1():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    
    draw_status_bar(draw)
    
    # App bar with gradient-like blue
    draw.rectangle([0, 88, W, 88+180], fill=PRIMARY)
    f_shop = get_font(36)
    f_title = get_font(52, bold=True)
    f_sub = get_font(32)
    draw.text((60, 108), "HULUCA Shop Manager", fill=(255,255,255,180), font=f_shop)
    draw.text((60, 158), "Xin chào, Chủ shop!", fill=TEXT_WHITE, font=f_title)
    
    y = 88 + 180 + 30
    
    # === Revenue summary card ===
    card_margin = 40
    card_w = W - card_margin * 2
    draw_card(draw, card_margin, y, card_w, 320, fill=SURFACE, radius=28)
    
    f_h = get_font(38, bold=True)
    f_v = get_font(56, bold=True)
    f_s = get_font(30)
    
    draw.text((card_margin + 40, y + 25), "DOANH THU HÔM NAY", fill=TEXT_SECONDARY, font=f_s)
    draw.text((card_margin + 40, y + 70), "12,580,000 đ", fill=GREEN, font=f_v)
    
    # Sub-stats row
    col_w = card_w // 3
    stats = [
        ("Đơn bán", "18", PRIMARY),
        ("Đơn sửa", "7", SECONDARY),
        ("Khách mới", "5", TEAL),
    ]
    for i, (label, val, color) in enumerate(stats):
        sx = card_margin + col_w * i + 40
        sy = y + 175
        draw_icon_circle(draw, sx + 25, sy + 25, 25, color)
        draw.text((sx + 65, sy + 5), val, fill=TEXT_PRIMARY, font=get_font(44, bold=True))
        draw.text((sx + 65, sy + 52), label, fill=TEXT_SECONDARY, font=get_font(28))
    
    y += 350
    
    # === Quick Actions section ===
    draw.text((card_margin + 10, y), "TRUY CẬP NHANH", fill=TEXT_SECONDARY, font=get_font(32, bold=True))
    y += 55
    
    # Quick action cards - 2 columns
    actions = [
        ("Bán hàng", GREEN, "🛒"),
        ("Sửa chữa", PRIMARY, "🔧"),
        ("Nhập kho", SECONDARY, "📦"),
        ("Kiểm kho", INDIGO, "📋"),
        ("Doanh thu", TEAL, "📊"),
        ("Chấm công", PURPLE, "⏰"),
    ]
    
    action_w = (card_w - 20) // 2
    action_h = 160
    for i, (label, color, emoji) in enumerate(actions):
        col = i % 2
        row = i // 2
        ax = card_margin + col * (action_w + 20)
        ay = y + row * (action_h + 16)
        
        # Card with light color background
        light = tuple(min(255, c + 180) for c in color)
        draw_card(draw, ax, ay, action_w, action_h, fill=light, radius=20, shadow=False)
        draw.rounded_rectangle([ax, ay, ax+action_w, ay+action_h], radius=20, outline=color+(80,), width=2)
        
        # Icon circle
        draw_icon_circle(draw, ax + 65, ay + action_h//2, 35, color)
        
        # Label
        draw.text((ax + 120, ay + action_h//2 - 22), label, fill=color, font=get_font(38, bold=True))
    
    y += 3 * (action_h + 16) + 30
    
    # === Today Activity Card ===
    draw_card(draw, card_margin, y, card_w, 420, fill=SURFACE, radius=28)
    draw.text((card_margin + 40, y + 25), "HOẠT ĐỘNG HÔM NAY", fill=TEXT_SECONDARY, font=get_font(32, bold=True))
    
    activities = [
        ("Đơn bán #DH2603001 - Nguyễn Văn A", "1,250,000đ", GREEN, "10:30"),
        ("Sửa iPhone 15 - Trần Thị B", "Đang xử lý", SECONDARY, "09:45"),
        ("Nhập kho: Ốp lưng x50", "+50 SP", PRIMARY, "09:15"),
        ("Đơn bán #DH2603002 - Lê Văn C", "3,800,000đ", GREEN, "08:50"),
        ("Chấm công: 5 nhân viên", "Đã điểm danh", TEAL, "08:00"),
    ]
    
    for i, (desc, val, color, time) in enumerate(activities):
        ay = y + 80 + i * 68
        draw_icon_circle(draw, card_margin + 70, ay + 18, 12, color)
        draw.text((card_margin + 100, ay), desc, fill=TEXT_PRIMARY, font=get_font(28))
        draw.text((card_w - 60, ay), val, fill=color, font=get_font(28, bold=True))
        draw.text((card_margin + 100, ay + 32), time, fill=TEXT_SECONDARY, font=get_font(24))
    
    y += 450
    
    # === Finance shortcuts row ===
    draw_card(draw, card_margin, y, card_w, 200, fill=SURFACE, radius=28)
    draw.text((card_margin + 40, y + 20), "TÀI CHÍNH", fill=TEXT_SECONDARY, font=get_font(32, bold=True))
    
    fin_items = [
        ("Doanh thu", "12.5M", GREEN),
        ("Chi phí", "4.2M", RED),
        ("Công nợ", "8.3M", SECONDARY),
        ("Lợi nhuận", "8.3M", TEAL),
    ]
    fi_w = card_w // 4
    for i, (label, val, color) in enumerate(fin_items):
        fx = card_margin + fi_w * i + 20
        fy = y + 80
        draw.text((fx + 20, fy), val, fill=color, font=get_font(40, bold=True))
        draw.text((fx + 20, fy + 50), label, fill=TEXT_SECONDARY, font=get_font(26))

    y += 230
    
    # Draw bottom tab bar
    tabs = [
        ("🏠", "Trang chủ"),
        ("🛒", "Bán hàng"),
        ("🔧", "Sửa chữa"),
        ("📦", "Kho hàng"),
        ("⚙️", "Cài đặt"),
    ]
    tab_y = H - 130
    draw_tab_bar(draw, tabs, 0, tab_y)
    
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_01.png"), "PNG")
    print("Screenshot 1 saved: Dashboard")


# ================================================================
# SCREENSHOT 2: Sales Management / Order List
# ================================================================
def create_screenshot_2():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    
    draw_status_bar(draw)
    y = draw_app_bar(draw, "Quản lý đơn hàng", bg=PRIMARY)
    
    # Filter chips
    y += 20
    chips = ["Tất cả (25)", "Chờ xử lý (3)", "Đang xử lý (5)", "Hoàn thành (15)", "Đã hủy (2)"]
    cx = 40
    f_chip = get_font(28)
    chip_colors = [PRIMARY, SECONDARY, PRIMARY_LIGHT, GREEN, RED]
    for i, chip in enumerate(chips):
        bbox = f_chip.getbbox(chip)
        tw = bbox[2] - bbox[0]
        chip_w = tw + 40
        color = chip_colors[i]
        if i == 0:
            draw.rounded_rectangle([cx, y, cx + chip_w, y + 60], radius=30, fill=color)
            draw.text((cx + 20, y + 13), chip, fill=TEXT_WHITE, font=f_chip)
        else:
            draw.rounded_rectangle([cx, y, cx + chip_w, y + 60], radius=30, fill=SURFACE, outline=color, width=2)
            draw.text((cx + 20, y + 13), chip, fill=color, font=f_chip)
        cx += chip_w + 16
    
    y += 90
    
    # Order cards
    orders = [
        {
            "id": "#DH140326001",
            "customer": "Nguyễn Văn An",
            "phone": "0912 345 678",
            "items": "iPhone 15 Pro Max 256GB x1, Ốp lưng x1",
            "total": "32,990,000đ",
            "status": "Hoàn thành",
            "status_color": GREEN,
            "time": "14:30 - 14/03/2026",
            "payment": "Đã thanh toán",
        },
        {
            "id": "#DH140326002",
            "customer": "Trần Thị Bích",
            "phone": "0987 654 321",
            "items": "Samsung Galaxy S25 Ultra x1, Sạc nhanh x1",
            "total": "28,490,000đ",
            "status": "Đang giao",
            "status_color": PRIMARY,
            "time": "13:15 - 14/03/2026",
            "payment": "Đã thanh toán",
        },
        {
            "id": "#DH140326003",
            "customer": "Lê Hoàng Minh",
            "phone": "0909 112 233",
            "items": "AirPods Pro 2 x2, Apple Watch Ultra 2 x1",
            "total": "25,770,000đ",
            "status": "Chờ xử lý",
            "status_color": SECONDARY,
            "time": "12:00 - 14/03/2026",
            "payment": "Chờ thanh toán",
        },
        {
            "id": "#DH140326004",
            "customer": "Phạm Quốc Đạt",
            "phone": "0933 445 566",
            "items": "MacBook Air M3 x1",
            "total": "27,990,000đ",
            "status": "Hoàn thành",
            "status_color": GREEN,
            "time": "11:30 - 14/03/2026",
            "payment": "Đã thanh toán",
        },
        {
            "id": "#DH140326005",
            "customer": "Hoàng Thị Lan",
            "phone": "0977 889 900",
            "items": "iPad Pro M4 13\" x1, Apple Pencil Pro x1",
            "total": "38,480,000đ",
            "status": "Đang xử lý",
            "status_color": PRIMARY_LIGHT,
            "time": "10:45 - 14/03/2026",
            "payment": "Đặt cọc 10,000,000đ",
        },
        {
            "id": "#DH140326006",
            "customer": "Võ Minh Tuấn",
            "phone": "0966 778 899",
            "items": "Xiaomi 14 Ultra x1, Cường lực x2",
            "total": "18,290,000đ",
            "status": "Đã hủy",
            "status_color": RED,
            "time": "09:20 - 14/03/2026",
            "payment": "Hoàn tiền",
        },
    ]
    
    card_margin = 40
    card_w = W - card_margin * 2
    
    for order in orders:
        card_h = 280
        draw_card(draw, card_margin, y, card_w, card_h, radius=20)
        
        f_id = get_font(34, bold=True)
        f_name = get_font(32, bold=True)
        f_detail = get_font(28)
        f_total = get_font(40, bold=True)
        f_status = get_font(26, bold=True)
        
        # Order ID & Status
        draw.text((card_margin + 30, y + 20), order["id"], fill=PRIMARY, font=f_id)
        
        # Status badge
        status_text = order["status"]
        bbox = f_status.getbbox(status_text)
        sw = bbox[2] - bbox[0]
        badge_x = card_margin + card_w - sw - 60
        draw.rounded_rectangle([badge_x, y + 15, badge_x + sw + 30, y + 55], 
                              radius=15, fill=order["status_color"])
        draw.text((badge_x + 15, y + 20), status_text, fill=TEXT_WHITE, font=f_status)
        
        # Customer
        draw.text((card_margin + 30, y + 65), order["customer"], fill=TEXT_PRIMARY, font=f_name)
        draw.text((card_margin + 30 + 400, y + 68), order["phone"], fill=TEXT_SECONDARY, font=f_detail)
        
        # Items  
        draw.text((card_margin + 30, y + 110), order["items"][:60], fill=TEXT_SECONDARY, font=f_detail)
        
        # Divider
        draw.line([(card_margin + 30, y + 160), (card_margin + card_w - 30, y + 160)], fill=DIVIDER, width=2)
        
        # Total & Payment
        draw.text((card_margin + 30, y + 180), order["total"], fill=PRIMARY_DARK, font=f_total)
        draw.text((card_margin + 30 + 500, y + 195), order["payment"], fill=TEXT_SECONDARY, font=f_detail)
        draw.text((card_w - 100, y + 240), order["time"], fill=TEXT_SECONDARY, font=get_font(24))
        
        y += card_h + 16
        if y > H - 200:
            break
    
    # Bottom tab bar
    tabs = [
        ("🏠", "Trang chủ"),
        ("🛒", "Bán hàng"),
        ("🔧", "Sửa chữa"),
        ("📦", "Kho hàng"),
        ("⚙️", "Cài đặt"),
    ]
    draw_tab_bar(draw, tabs, 1, H - 130)
    
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_02.png"), "PNG")
    print("Screenshot 2 saved: Sales Management")


# ================================================================
# SCREENSHOT 3: Inventory Management
# ================================================================
def create_screenshot_3():
    img = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(img)
    
    draw_status_bar(draw)
    y = draw_app_bar(draw, "Kho hàng", bg=PRIMARY)
    
    # Search bar
    y += 20
    card_margin = 40
    card_w = W - card_margin * 2
    draw.rounded_rectangle([card_margin, y, card_margin + card_w, y + 80], radius=40, fill=SURFACE, outline=DIVIDER, width=2)
    draw.text((card_margin + 55, y + 20), "🔍  Tìm kiếm sản phẩm...", fill=TEXT_SECONDARY, font=get_font(30))
    
    y += 110
    
    # Summary cards row
    summary = [
        ("Tổng SP", "1,247", PRIMARY, "sản phẩm"),
        ("Tồn kho", "8,563", GREEN, "số lượng"),
        ("Sắp hết", "23", SECONDARY, "cần nhập"),
        ("Hết hàng", "8", RED, "sản phẩm"),
    ]
    
    sum_w = (card_w - 48) // 4
    for i, (label, val, color, sub) in enumerate(summary):
        sx = card_margin + i * (sum_w + 16)
        draw_card(draw, sx, y, sum_w, 165, radius=20)
        draw.text((sx + 20, y + 18), label, fill=TEXT_SECONDARY, font=get_font(26))
        draw.text((sx + 20, y + 55), val, fill=color, font=get_font(46, bold=True))
        draw.text((sx + 20, y + 115), sub, fill=TEXT_SECONDARY, font=get_font(22))
    
    y += 195
    
    # Category tabs
    categories = ["Tất cả", "Điện thoại", "Phụ kiện", "Linh kiện", "Máy tính"]
    cx = card_margin
    f_cat = get_font(30)
    for i, cat in enumerate(categories):
        bbox = f_cat.getbbox(cat)
        tw = bbox[2] - bbox[0]
        cw = tw + 40
        if i == 0:
            draw.rounded_rectangle([cx, y, cx+cw, y+56], radius=28, fill=PRIMARY)
            draw.text((cx+20, y+12), cat, fill=TEXT_WHITE, font=f_cat)
        else:
            draw.rounded_rectangle([cx, y, cx+cw, y+56], radius=28, fill=SURFACE, outline=DIVIDER, width=2)
            draw.text((cx+20, y+12), cat, fill=TEXT_PRIMARY, font=f_cat)
        cx += cw + 12
    
    y += 80
    
    # Product list
    products = [
        {
            "name": "iPhone 15 Pro Max 256GB",
            "sku": "IP15PM-256-BLK",
            "price": "29,990,000đ",
            "cost": "27,500,000đ",
            "stock": "12",
            "stock_color": GREEN,
            "category": "Điện thoại",
        },
        {
            "name": "Samsung Galaxy S25 Ultra 512GB",
            "sku": "SS-S25U-512-TIT",
            "price": "33,990,000đ",
            "cost": "30,200,000đ",
            "stock": "8",
            "stock_color": GREEN,
            "category": "Điện thoại",
        },
        {
            "name": "AirPods Pro 2 (USB-C)",
            "sku": "AP-PRO2-USBC",
            "price": "5,990,000đ",
            "cost": "4,800,000đ",
            "stock": "25",
            "stock_color": GREEN,
            "category": "Phụ kiện",
        },
        {
            "name": "Ốp lưng MagSafe iPhone 15",
            "sku": "CASE-IP15-MAG",
            "price": "890,000đ",
            "cost": "320,000đ",
            "stock": "3",
            "stock_color": SECONDARY,
            "category": "Phụ kiện",
        },
        {
            "name": "Cường lực 9H Samsung S25",
            "sku": "GLASS-SS25-9H",
            "price": "150,000đ",
            "cost": "25,000đ",
            "stock": "2",
            "stock_color": RED,
            "category": "Phụ kiện",
        },
        {
            "name": "MacBook Air M3 15\" 256GB",
            "sku": "MBA-M3-15-256",
            "price": "32,990,000đ",
            "cost": "29,800,000đ",
            "stock": "5",
            "stock_color": GREEN,
            "category": "Máy tính",
        },
        {
            "name": "Sạc nhanh 67W Xiaomi",
            "sku": "CHG-XI-67W",
            "price": "490,000đ",
            "cost": "180,000đ",
            "stock": "0",
            "stock_color": RED,
            "category": "Phụ kiện",
        },
        {
            "name": "Apple Watch Ultra 2",
            "sku": "AW-ULTRA2-49",
            "price": "21,990,000đ",
            "cost": "19,500,000đ",
            "stock": "4",
            "stock_color": GREEN,
            "category": "Phụ kiện",
        },
    ]
    
    for product in products:
        card_h = 200
        draw_card(draw, card_margin, y, card_w, card_h, radius=18)
        
        f_name = get_font(32, bold=True)
        f_detail = get_font(26)
        f_price = get_font(36, bold=True)
        f_stock = get_font(30, bold=True)
        
        # Product image placeholder
        draw.rounded_rectangle([card_margin + 20, y + 20, card_margin + 180, y + card_h - 20], 
                              radius=14, fill=BLUE_LIGHT)
        draw.text((card_margin + 55, y + 70), "📱", fill=TEXT_PRIMARY, font=get_font(50))
        
        # Product info
        px = card_margin + 200
        draw.text((px, y + 20), product["name"], fill=TEXT_PRIMARY, font=f_name)
        draw.text((px, y + 60), f'SKU: {product["sku"]}', fill=TEXT_SECONDARY, font=f_detail)
        draw.text((px, y + 100), product["price"], fill=PRIMARY_DARK, font=f_price)
        draw.text((px + 380, y + 105), f'Giá vốn: {product["cost"]}', fill=TEXT_SECONDARY, font=f_detail)
        
        # Stock badge
        stock_text = f'Tồn: {product["stock"]}'
        if product["stock"] == "0":
            stock_text = "Hết hàng"
        bbox = f_stock.getbbox(stock_text)
        sw = bbox[2] - bbox[0]
        sx = card_margin + card_w - sw - 50
        sc = product["stock_color"]
        light_sc = tuple(min(255, c + 180) for c in sc)
        draw.rounded_rectangle([sx - 15, y + 145, sx + sw + 15, y + 185], radius=12, fill=light_sc)
        draw.text((sx, y + 148), stock_text, fill=sc, font=f_stock)
        
        # Category
        draw.text((px, y + 150), product["category"], fill=TEXT_SECONDARY, font=f_detail)
        
        y += card_h + 12
        if y > H - 200:
            break
    
    # Bottom tab bar
    tabs = [
        ("🏠", "Trang chủ"),
        ("🛒", "Bán hàng"),
        ("🔧", "Sửa chữa"),
        ("📦", "Kho hàng"),
        ("⚙️", "Cài đặt"),
    ]
    draw_tab_bar(draw, tabs, 3, H - 130)
    
    img.save(os.path.join(OUT_DIR, "iPad_Pro_13_screenshot_03.png"), "PNG")
    print("Screenshot 3 saved: Inventory Management")


if __name__ == "__main__":
    print(f"Generating iPad Pro 13\" screenshots ({W}x{H})...")
    print(f"Output directory: {OUT_DIR}")
    create_screenshot_1()
    create_screenshot_2()
    create_screenshot_3()
    print(f"\nDone! 3 screenshots saved to: {OUT_DIR}")
