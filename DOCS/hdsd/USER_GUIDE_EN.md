# 📱 QUANLYSHOP USER GUIDE (ENGLISH)

> **Phone Repair & Sales Shop Management Software**  
> Complete user documentation

---

## 📋 TABLE OF CONTENTS

1. [Introduction](#1-introduction)
2. [Registration & Login](#2-registration--login)
3. [Home Dashboard](#3-home-dashboard)
4. [Sales Module](#4-sales-module)
5. [Repair Module](#5-repair-module)
6. [Inventory Module](#6-inventory-module)
7. [Finance Module](#7-finance-module)
8. [HR Module](#8-hr-module)
9. [Settings](#9-settings)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. INTRODUCTION

### 1.1 What is QuanLyShop?

**QuanLyShop (Huluca)** is a comprehensive management software for phone repair and sales shops. The app helps you:

- 📱 **Sales Management**: Create invoices, track revenue, manage installments
- 🔧 **Repair Management**: Receive devices, track progress, manage warranties
- 📦 **Inventory Management**: Stock in/out, inventory check, track stock levels
- 💰 **Finance Management**: Revenue, expenses, debts, reports
- 👥 **HR Management**: Staff, attendance, payroll
- 🖨️ **Invoice Printing**: Bluetooth/WiFi thermal printer support

### 1.2 System Requirements

| Platform | Minimum Requirement |
|----------|---------------------|
| Android | Android 6.0 or higher |
| iOS | iOS 12.0 or higher |
| Web | Latest Chrome, Firefox, Safari |

### 1.3 Installation

**On Android:**
1. Download APK from provided link
2. Enable "Install from unknown sources" in Settings
3. Open APK file and tap "Install"

**On iOS:**
1. Contact admin for TestFlight access
2. Open TestFlight and install the app

---

## 2. REGISTRATION & LOGIN

### 2.1 Create New Account

> **Note:** Only shop owners need to register. Staff accounts are created by the owner.

**Steps:**
1. Open app, tap **"REGISTER"**
2. Fill in information:
   - **Email**: Valid email address (used for login)
   - **Password**: Minimum 6 characters
   - **Confirm Password**: Re-enter password
   - **Shop Name**: Your shop name
   - **Phone Number**: Contact number
3. Tap **"REGISTER"**
4. Check email and verify (if required)
5. Login with created credentials

### 2.2 Login

1. Open app
2. Enter **Email** and **Password**
3. Tap **"LOGIN"**

**Forgot Password?**
1. Tap **"Forgot Password?"** on login screen
2. Enter registered email
3. Check email and follow reset instructions

---

## 3. HOME DASHBOARD

### 3.1 Interface Overview

```
┌─────────────────────────────────────┐
│  🔔 Notifications   🔍 Search       │  ← Header
├─────────────────────────────────────┤
│                                     │
│     📊 QUICK STATS                  │  ← Dashboard
│     • Today's Revenue               │
│     • Pending Repairs               │
│     • Today's Sales                 │
│     • Expiring Warranties           │
│                                     │
├─────────────────────────────────────┤
│                                     │
│     📱 SHORTCUTS                    │  ← Quick Actions
│     • Create Repair Order           │
│     • Quick Sale                    │
│     • Scan QR                       │
│                                     │
├─────────────────────────────────────┤
│  🏠   🛒   🔧   📦   👥   💰   ⚙️  │  ← Navigation
│ Home Sale Repair Stock HR Finance Set│
└─────────────────────────────────────┘
```

### 3.2 Bottom Navigation

| Icon | Tab | Function |
|------|-----|----------|
| 🏠 | **Home** | Dashboard, overview statistics |
| 🛒 | **Sales** | Sales management, orders |
| 🔧 | **Repair** | Repair order management |
| 📦 | **Inventory** | Stock management, products |
| 👥 | **HR** | Staff management, attendance |
| 💰 | **Finance** | Revenue, expenses, debts |
| ⚙️ | **Settings** | Shop and system settings |

### 3.3 Dashboard Stats

**Displayed metrics:**
- **Today's Revenue**: Total from sales + repairs
- **Pending Repairs**: Unfinished repair tickets
- **Devices Sold Today**: Number sold today
- **Today's Expenses**: Total expenses
- **Outstanding Debts**: Uncollected debts
- **Expiring Warranties**: Warranties < 30 days

---

## 4. SALES MODULE

### 4.1 Create Sales Order

1. Go to **Sales** > tap **"+ NEW ORDER"**
2. **Select Customer:**
   - Search existing customer
   - Or tap **"+ Add New"** to create new
3. **Add Products:**
   - Scan barcode/QR or search manually
   - Adjust quantity
4. **Payment:**
   - Select payment method (Cash/Transfer/Card)
   - Full payment or partial (creates debt)
   - Add warranty period
5. **Complete:**
   - Tap **"CONFIRM SALE"**
   - Print invoice (optional)

### 4.2 Warranty Management

| Warranty Type | Description |
|---------------|-------------|
| **1 đổi 1** | 1-to-1 exchange within period |
| **Bảo hành** | Standard repair warranty |
| **Không BH** | No warranty |

### 4.3 Installment Sales

1. Create order as normal
2. In payment section, select **"Installment"**
3. Enter down payment amount
4. System automatically calculates remaining debt
5. Track payments in **Finance > Debts**

---

## 5. REPAIR MODULE

### 5.1 Receive Device for Repair

1. Go to **Repair** > tap **"+ NEW REPAIR"**
2. **Customer Info:**
   - Phone number (auto-search existing)
   - Customer name
3. **Device Info:**
   - Device type (Phone/Tablet/Laptop)
   - Brand and model
   - IMEI (optional but recommended)
   - Device condition
4. **Issue Description:**
   - Reported problem
   - Diagnostic notes
   - Take photos (before repair)
5. **Pricing:**
   - Estimated cost
   - Deposit amount (optional)
6. **Confirm:**
   - Tap **"CREATE REPAIR ORDER"**
   - Print receipt for customer

### 5.2 Repair Status

| Status | Description | Color |
|--------|-------------|-------|
| **Chờ xử lý** | Waiting/Queued | 🟡 Yellow |
| **Đang sửa** | In Progress | 🔵 Blue |
| **Đã xong** | Completed | 🟢 Green |
| **Đã giao** | Delivered | ⚪ Gray |
| **Hủy** | Cancelled | 🔴 Red |

### 5.3 Complete Repair

1. Open repair order
2. Update status to **"Completed"**
3. Add:
   - Parts used (auto deducts from inventory)
   - Labor cost
   - Final total
4. Take photos (after repair)
5. Notify customer (auto SMS/notification)
6. When customer picks up:
   - Collect payment
   - Update status to **"Delivered"**
   - Print warranty card

---

## 6. INVENTORY MODULE

### 6.1 Stock Categories

| Category | Examples |
|----------|----------|
| **Phones** | iPhone, Samsung, etc. |
| **Accessories** | Cases, chargers, cables |
| **Parts** | Screens, batteries, ICs |

### 6.2 Add New Product

1. Go to **Inventory** > tap **"+ STOCK IN"**
2. Select product type
3. Fill information:
   - Product name
   - IMEI (for phones)
   - Purchase price
   - Selling price
   - Quantity
   - Supplier
   - Warranty period
4. Take product photos (optional)
5. Tap **"SAVE"**

### 6.3 Pending Stock (Staging)

Products imported without price are held in **Pending Stock**:
- Displayed with orange "PENDING" badge
- Cannot be sold until priced
- Go to **Inventory > Pending** to set prices

### 6.4 Stock Adjustment

For inventory discrepancies:
1. Go to **Inventory > Adjustments**
2. Select product
3. Enter actual quantity
4. Provide reason
5. System logs the change

---

## 7. FINANCE MODULE

### 7.1 Revenue Tracking

View all income sources:
- **Sales**: Product sales
- **Repairs**: Repair services
- **Debt Collections**: Collected debts

### 7.2 Expense Management

1. Go to **Finance > Expenses**
2. Tap **"+ ADD EXPENSE"**
3. Fill:
   - Amount
   - Category (Rent, Utilities, Supplies, etc.)
   - Description
   - Payment method
   - Receipt photo (optional)
4. Tap **"SAVE"**

### 7.3 Debt Management

**Customer Debts (Receivable):**
- Track money owed by customers
- Record partial payments
- Send payment reminders

**Supplier Debts (Payable):**
- Track money owed to suppliers
- Schedule payments
- View payment history

### 7.4 Daily Cash Closing

End-of-day reconciliation:
1. Go to **Finance > Cash Close**
2. Enter physical cash count
3. System compares with recorded transactions
4. Note any discrepancies
5. Confirm closing

### 7.5 Reports

Available reports:
- **Daily Revenue**: Income by day
- **Monthly Summary**: Monthly totals
- **Product Performance**: Best sellers
- **Staff Performance**: Sales by employee
- **Debt Aging**: Overdue debts

---

## 8. HR MODULE

### 8.1 Staff Management

**Add New Staff:**
1. Go to **HR > Staff List**
2. Tap **"+ ADD STAFF"**
3. Enter:
   - Email (used for login)
   - Name
   - Phone
   - Role (Manager/Employee)
   - Permissions
4. Staff receives login email

### 8.2 Role Permissions

| Permission | Owner | Manager | Employee |
|------------|-------|---------|----------|
| View Dashboard | ✅ | ✅ | ✅ |
| Create Sales | ✅ | ✅ | ✅ |
| Create Repairs | ✅ | ✅ | ✅ |
| Manage Inventory | ✅ | ✅ | ⚙️ |
| View Reports | ✅ | ✅ | ❌ |
| Manage Staff | ✅ | ⚙️ | ❌ |
| System Settings | ✅ | ❌ | ❌ |

⚙️ = Configurable per user

### 8.3 Attendance (Chấm công)

**For Employees:**
1. Go to **HR > Attendance**
2. Tap **"CHECK-IN"** when arriving
3. Take selfie photo
4. Location recorded (if enabled)
5. Tap **"CHECK-OUT"** when leaving

**For Managers:**
- View all staff attendance
- Edit incorrect records
- Generate attendance reports
- Configure work schedules

### 8.4 Salary Settings (Cài đặt lương)

**Salary Types:**
- **Monthly**: Fixed monthly salary
- **Daily**: Per-day rate
- **Hourly**: Per-hour rate

**Commission Settings:**
- Sales commission (% or fixed)
- Repair commission (% or fixed)
- Bonus targets

**Allowances:**
- Transport
- Meals
- Phone

### 8.5 Payroll

1. Go to **HR > Payroll**
2. Select pay period
3. System auto-calculates:
   - Base salary
   - Commissions
   - Allowances
   - Deductions (late/absent)
4. Review and approve
5. Generate pay slips

---

## 9. SETTINGS

### 9.1 Shop Profile

- Shop name and address
- Contact information
- Logo upload
- Business hours

### 9.2 Printer Setup

**Bluetooth Thermal Printer:**
1. Go to **Settings > Printer**
2. Turn on Bluetooth
3. Tap **"Scan Devices"**
4. Select your printer
5. Print test page

**Supported printers:**
- 58mm thermal printers
- 80mm thermal printers
- Most Bluetooth POS printers

### 9.3 Notification Settings

Configure notifications for:
- New repair orders
- Order completion
- Payment reminders
- Low stock alerts
- Staff check-in/out

### 9.4 Data Sync

**Sync Status Indicators:**
- 🟢 Green: Fully synced
- 🟡 Yellow: Syncing in progress
- 🔴 Red: Sync error

**Manual Sync:**
- Pull down to refresh on any list
- Or tap sync icon in header

---

## 10. TROUBLESHOOTING

### 10.1 Common Issues

**Cannot Login:**
- Check email/password spelling
- Reset password if forgotten
- Check internet connection

**Data Not Syncing:**
- Check internet connection
- Pull down to refresh
- Restart app if needed

**Printer Not Working:**
- Ensure Bluetooth is ON
- Check printer battery
- Re-pair the printer
- Check paper roll

**App Running Slow:**
- Close other apps
- Clear app cache
- Update to latest version

### 10.2 Error Messages

| Error | Solution |
|-------|----------|
| "Network Error" | Check internet, try again |
| "Permission Denied" | Contact admin for access |
| "Sync Failed" | Check connection, retry |
| "Invalid Data" | Check required fields |

### 10.3 Support Contact

- **Email**: admin@huluca.com
- **In-app**: Settings > Help & Support

---

## 📝 QUICK REFERENCE

### Keyboard Shortcuts (Web)

| Shortcut | Action |
|----------|--------|
| `Ctrl + N` | New order |
| `Ctrl + S` | Save |
| `Ctrl + P` | Print |
| `Ctrl + F` | Search |
| `Esc` | Close dialog |

### Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 Green | Success, Paid, Completed |
| 🟡 Yellow | Pending, Warning |
| 🔵 Blue | In Progress, Info |
| 🟠 Orange | Partial, Staging |
| 🔴 Red | Error, Cancelled, Overdue |

---

**Version:** 1.0  
**Last Updated:** February 2026  
**© Huluca - QuanLyShop**
