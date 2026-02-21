import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Shop Manager'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get selectLanguage;

  /// No description provided for @vietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get vietnamese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change language'**
  String get changeLanguage;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @inventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// No description provided for @suppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliers;

  /// No description provided for @parts.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get parts;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @debts.
  ///
  /// In en, this message translates to:
  /// **'Debts'**
  String get debts;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @loginError.
  ///
  /// In en, this message translates to:
  /// **'Invalid username or password'**
  String get loginError;

  /// No description provided for @shopManagement.
  ///
  /// In en, this message translates to:
  /// **'SHOP MANAGEMENT'**
  String get shopManagement;

  /// No description provided for @storeIcon.
  ///
  /// In en, this message translates to:
  /// **'Store icon'**
  String get storeIcon;

  /// No description provided for @manageStaff.
  ///
  /// In en, this message translates to:
  /// **'Manage staff'**
  String get manageStaff;

  /// No description provided for @createInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Create invite code'**
  String get createInviteCode;

  /// No description provided for @shareQR.
  ///
  /// In en, this message translates to:
  /// **'Share QR code'**
  String get shareQR;

  /// No description provided for @staffList.
  ///
  /// In en, this message translates to:
  /// **'Staff list'**
  String get staffList;

  /// No description provided for @addEditDeleteStaff.
  ///
  /// In en, this message translates to:
  /// **'Add/Edit/Delete staff, Create invite code'**
  String get addEditDeleteStaff;

  /// No description provided for @superAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get superAdmin;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get finance;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'DASHBOARD'**
  String get dashboard;

  /// No description provided for @warranty.
  ///
  /// In en, this message translates to:
  /// **'WARRANTY'**
  String get warranty;

  /// No description provided for @auditLog.
  ///
  /// In en, this message translates to:
  /// **'AUDIT LOG'**
  String get auditLog;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'PERFORMANCE'**
  String get performance;

  /// No description provided for @attendance.
  ///
  /// In en, this message translates to:
  /// **'ATTENDANCE'**
  String get attendance;

  /// No description provided for @payroll.
  ///
  /// In en, this message translates to:
  /// **'PAYROLL'**
  String get payroll;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'QUICK ACCESS'**
  String get quickActions;

  /// No description provided for @checkInventory.
  ///
  /// In en, this message translates to:
  /// **'CHECK INVENTORY'**
  String get checkInventory;

  /// No description provided for @manageInventory.
  ///
  /// In en, this message translates to:
  /// **'MANAGE INVENTORY'**
  String get manageInventory;

  /// No description provided for @viewPrintLabels.
  ///
  /// In en, this message translates to:
  /// **'View & Print labels'**
  String get viewPrintLabels;

  /// No description provided for @accountInfo.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT INFO'**
  String get accountInfo;

  /// No description provided for @viewPermissions.
  ///
  /// In en, this message translates to:
  /// **'View permissions and account info'**
  String get viewPermissions;

  /// No description provided for @syncData.
  ///
  /// In en, this message translates to:
  /// **'Sync data'**
  String get syncData;

  /// No description provided for @syncCompleted.
  ///
  /// In en, this message translates to:
  /// **'DATA SYNCED'**
  String get syncCompleted;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'SYNC ERROR'**
  String get syncError;

  /// No description provided for @accountInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT INFORMATION'**
  String get accountInfoTitle;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @viewInventory.
  ///
  /// In en, this message translates to:
  /// **'View inventory'**
  String get viewInventory;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @otherPermissions.
  ///
  /// In en, this message translates to:
  /// **'Other permissions'**
  String get otherPermissions;

  /// No description provided for @viewSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get viewSales;

  /// No description provided for @viewRepairs.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get viewRepairs;

  /// No description provided for @viewPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get viewPrinter;

  /// No description provided for @viewRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get viewRevenue;

  /// No description provided for @viewExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get viewExpenses;

  /// No description provided for @viewDebts.
  ///
  /// In en, this message translates to:
  /// **'Debts'**
  String get viewDebts;

  /// No description provided for @viewSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get viewSettings;

  /// No description provided for @shopLocked.
  ///
  /// In en, this message translates to:
  /// **'Shop locked'**
  String get shopLocked;

  /// No description provided for @shopLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'SHOP IS TEMPORARILY LOCKED BY SUPER ADMIN. All features are restricted until unlocked.'**
  String get shopLockedMessage;

  /// No description provided for @searchCustomerByPhone.
  ///
  /// In en, this message translates to:
  /// **'Quick search by phone'**
  String get searchCustomerByPhone;

  /// No description provided for @arrowForward.
  ///
  /// In en, this message translates to:
  /// **'Arrow forward'**
  String get arrowForward;

  /// No description provided for @perpetualCalendar.
  ///
  /// In en, this message translates to:
  /// **'Perpetual calendar'**
  String get perpetualCalendar;

  /// No description provided for @quickStats.
  ///
  /// In en, this message translates to:
  /// **'Quick stats'**
  String get quickStats;

  /// No description provided for @completedToday.
  ///
  /// In en, this message translates to:
  /// **'Done/Delivered today'**
  String get completedToday;

  /// No description provided for @soldToday.
  ///
  /// In en, this message translates to:
  /// **'Sold today'**
  String get soldToday;

  /// No description provided for @todaySummary.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S WORK'**
  String get todaySummary;

  /// No description provided for @newRepairsToday.
  ///
  /// In en, this message translates to:
  /// **'Devices received today'**
  String get newRepairsToday;

  /// No description provided for @salesToday.
  ///
  /// In en, this message translates to:
  /// **'Sales today'**
  String get salesToday;

  /// No description provided for @expensesToday.
  ///
  /// In en, this message translates to:
  /// **'Expenses today'**
  String get expensesToday;

  /// No description provided for @outstandingDebts.
  ///
  /// In en, this message translates to:
  /// **'Outstanding debts'**
  String get outstandingDebts;

  /// No description provided for @gridMenu.
  ///
  /// In en, this message translates to:
  /// **'Grid menu'**
  String get gridMenu;

  /// No description provided for @sell.
  ///
  /// In en, this message translates to:
  /// **'SELL'**
  String get sell;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'CHAT'**
  String get chat;

  /// No description provided for @profitLoss.
  ///
  /// In en, this message translates to:
  /// **'PROFIT/LOSS'**
  String get profitLoss;

  /// No description provided for @netProfit.
  ///
  /// In en, this message translates to:
  /// **'NET PROFIT'**
  String get netProfit;

  /// No description provided for @inventorySnapshot.
  ///
  /// In en, this message translates to:
  /// **'DAILY INVENTORY'**
  String get inventorySnapshot;

  /// No description provided for @totalItems.
  ///
  /// In en, this message translates to:
  /// **'Total items'**
  String get totalItems;

  /// No description provided for @inventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Stock value'**
  String get inventoryValue;

  /// No description provided for @noItemsInStock.
  ///
  /// In en, this message translates to:
  /// **'No stock items'**
  String get noItemsInStock;

  /// No description provided for @closingCard.
  ///
  /// In en, this message translates to:
  /// **'DAILY CLOSING'**
  String get closingCard;

  /// No description provided for @cashStart.
  ///
  /// In en, this message translates to:
  /// **'Cash start of day'**
  String get cashStart;

  /// No description provided for @bankStart.
  ///
  /// In en, this message translates to:
  /// **'Bank start of day'**
  String get bankStart;

  /// No description provided for @cashEnd.
  ///
  /// In en, this message translates to:
  /// **'Cash end of day'**
  String get cashEnd;

  /// No description provided for @bankEnd.
  ///
  /// In en, this message translates to:
  /// **'Bank end of day'**
  String get bankEnd;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @saveClosing.
  ///
  /// In en, this message translates to:
  /// **'Save closing'**
  String get saveClosing;

  /// No description provided for @revenueDistribution.
  ///
  /// In en, this message translates to:
  /// **'REVENUE DISTRIBUTION'**
  String get revenueDistribution;

  /// No description provided for @salesProfit.
  ///
  /// In en, this message translates to:
  /// **'Sales profit'**
  String get salesProfit;

  /// No description provided for @repairProfit.
  ///
  /// In en, this message translates to:
  /// **'Repair profit'**
  String get repairProfit;

  /// No description provided for @totalExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total expenses'**
  String get totalExpenses;

  /// No description provided for @totalProfit.
  ///
  /// In en, this message translates to:
  /// **'TOTAL PROFIT'**
  String get totalProfit;

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get thisYear;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @quickActionButton.
  ///
  /// In en, this message translates to:
  /// **'Quick action button'**
  String get quickActionButton;

  /// No description provided for @reportCard.
  ///
  /// In en, this message translates to:
  /// **'Report card'**
  String get reportCard;

  /// No description provided for @summaryRow.
  ///
  /// In en, this message translates to:
  /// **'Summary row'**
  String get summaryRow;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM SETTINGS'**
  String get settingsTitle;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language:'**
  String get languageLabel;

  /// No description provided for @brandInfoSection.
  ///
  /// In en, this message translates to:
  /// **'BRAND INFO'**
  String get brandInfoSection;

  /// No description provided for @shopPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get shopPhoneLabel;

  /// No description provided for @shopAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop address'**
  String get shopAddressLabel;

  /// No description provided for @invoiceConfigSection.
  ///
  /// In en, this message translates to:
  /// **'INVOICE CONFIG'**
  String get invoiceConfigSection;

  /// No description provided for @invoiceFooterLabel.
  ///
  /// In en, this message translates to:
  /// **'Footer message'**
  String get invoiceFooterLabel;

  /// No description provided for @createInvoiceTemplate.
  ///
  /// In en, this message translates to:
  /// **'Create invoice template'**
  String get createInvoiceTemplate;

  /// No description provided for @joinShopCode.
  ///
  /// In en, this message translates to:
  /// **'Enter invite code to join shop'**
  String get joinShopCode;

  /// No description provided for @cleanupManagement.
  ///
  /// In en, this message translates to:
  /// **'Cleanup management: Delete old repair history (optional)'**
  String get cleanupManagement;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get aboutSection;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Shop Manager'**
  String get appName;

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Multi-industry shop management solution'**
  String get appDescription;

  /// No description provided for @versionNumber.
  ///
  /// In en, this message translates to:
  /// **'2.6.0'**
  String get versionNumber;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get contactSupport;

  /// No description provided for @developer.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developer;

  /// No description provided for @developerName.
  ///
  /// In en, this message translates to:
  /// **'Quang Huy'**
  String get developerName;

  /// No description provided for @developerRole.
  ///
  /// In en, this message translates to:
  /// **'Mobile app development expert'**
  String get developerRole;

  /// No description provided for @contactPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone/Zalo: 0964 095 979'**
  String get contactPhone;

  /// No description provided for @businessSolutions.
  ///
  /// In en, this message translates to:
  /// **'Business management solutions'**
  String get businessSolutions;

  /// No description provided for @saveAllSettings.
  ///
  /// In en, this message translates to:
  /// **'SAVE ALL SETTINGS'**
  String get saveAllSettings;

  /// No description provided for @enterInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Enter invite code'**
  String get enterInviteCode;

  /// No description provided for @inviteCode8Chars.
  ///
  /// In en, this message translates to:
  /// **'Invite code (8 characters)'**
  String get inviteCode8Chars;

  /// No description provided for @scanQR.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQR;

  /// No description provided for @codeMustBe8Chars.
  ///
  /// In en, this message translates to:
  /// **'Code must be 8 characters'**
  String get codeMustBe8Chars;

  /// No description provided for @joinedShopSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Joined shop successfully!'**
  String get joinedShopSuccessfully;

  /// No description provided for @invalidOrExpiredCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired code'**
  String get invalidOrExpiredCode;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'JOIN'**
  String get join;

  /// No description provided for @cleanupConfigOptIn.
  ///
  /// In en, this message translates to:
  /// **'Cleanup config (opt-in)'**
  String get cleanupConfigOptIn;

  /// No description provided for @enableCleanup.
  ///
  /// In en, this message translates to:
  /// **'Enable cleanup'**
  String get enableCleanup;

  /// No description provided for @daysToDeleteAfter.
  ///
  /// In en, this message translates to:
  /// **'Days (delete after N days)'**
  String get daysToDeleteAfter;

  /// No description provided for @noPermissionToConfigure.
  ///
  /// In en, this message translates to:
  /// **'Account not permitted to configure'**
  String get noPermissionToConfigure;

  /// No description provided for @shopInfoSaved.
  ///
  /// In en, this message translates to:
  /// **'SHOP INFO SAVED!'**
  String get shopInfoSaved;

  /// No description provided for @cleanupConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'Cleanup config saved'**
  String get cleanupConfigSaved;

  /// No description provided for @scanQRCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQRCode;

  /// No description provided for @noPermissionRepair.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to access REPAIR section. Contact shop owner for permissions.'**
  String get noPermissionRepair;

  /// No description provided for @allowed.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get allowed;

  /// No description provided for @notAllowed.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get notAllowed;

  /// No description provided for @repairPermission.
  ///
  /// In en, this message translates to:
  /// **'Repair permission'**
  String get repairPermission;

  /// No description provided for @salesPermission.
  ///
  /// In en, this message translates to:
  /// **'Sales permission'**
  String get salesPermission;

  /// No description provided for @inventoryPermission.
  ///
  /// In en, this message translates to:
  /// **'Inventory permission'**
  String get inventoryPermission;

  /// No description provided for @suppliersPermission.
  ///
  /// In en, this message translates to:
  /// **'Suppliers permission'**
  String get suppliersPermission;

  /// No description provided for @customersPermission.
  ///
  /// In en, this message translates to:
  /// **'Customers permission'**
  String get customersPermission;

  /// No description provided for @warrantyPermission.
  ///
  /// In en, this message translates to:
  /// **'Warranty permission'**
  String get warrantyPermission;

  /// No description provided for @chatPermission.
  ///
  /// In en, this message translates to:
  /// **'Chat permission'**
  String get chatPermission;

  /// No description provided for @printerPermission.
  ///
  /// In en, this message translates to:
  /// **'Printer permission'**
  String get printerPermission;

  /// No description provided for @revenuePermission.
  ///
  /// In en, this message translates to:
  /// **'Revenue permission'**
  String get revenuePermission;

  /// No description provided for @expensesPermission.
  ///
  /// In en, this message translates to:
  /// **'Expenses permission'**
  String get expensesPermission;

  /// No description provided for @debtsPermission.
  ///
  /// In en, this message translates to:
  /// **'Debts permission'**
  String get debtsPermission;

  /// No description provided for @noPermissionRevenue.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to view REVENUE screen. Contact shop owner for permissions.'**
  String get noPermissionRevenue;

  /// No description provided for @noPermissionRevenueReport.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to view REVENUE REPORT screen. Contact shop owner for permissions.'**
  String get noPermissionRevenueReport;

  /// No description provided for @noPermissionSales.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to access SALES section. Contact shop owner for permissions.'**
  String get noPermissionSales;

  /// No description provided for @noPermissionInventory.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to access INVENTORY section. Contact shop owner for permissions.'**
  String get noPermissionInventory;

  /// No description provided for @noPermissionCustomers.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to view CUSTOMER SYSTEM. Contact shop owner for permissions.'**
  String get noPermissionCustomers;

  /// No description provided for @noPermissionWarranty.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to access WARRANTY section. Contact shop owner for permissions.'**
  String get noPermissionWarranty;

  /// No description provided for @noPermissionChat.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to use INTERNAL CHAT. Contact shop owner for permissions.'**
  String get noPermissionChat;

  /// No description provided for @noPermissionPrinter.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to configure PRINTER. Contact shop owner for permissions.'**
  String get noPermissionPrinter;

  /// No description provided for @noPermissionCreateRepair.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to create repair orders. Contact shop owner for permissions.'**
  String get noPermissionCreateRepair;

  /// No description provided for @viewInventoryPermission.
  ///
  /// In en, this message translates to:
  /// **'View inventory permission'**
  String get viewInventoryPermission;

  /// No description provided for @inventoryCheck.
  ///
  /// In en, this message translates to:
  /// **'INVENTORY CHECK'**
  String get inventoryCheck;

  /// No description provided for @checkInventoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Check phone & accessory stock'**
  String get checkInventoryDesc;

  /// No description provided for @receiptPrinter.
  ///
  /// In en, this message translates to:
  /// **'RECEIPT PRINTER'**
  String get receiptPrinter;

  /// No description provided for @printReceiptsDesc.
  ///
  /// In en, this message translates to:
  /// **'Print invoices, receipts'**
  String get printReceiptsDesc;

  /// No description provided for @repairReceipt.
  ///
  /// In en, this message translates to:
  /// **'REPAIR RECEIPT'**
  String get repairReceipt;

  /// No description provided for @createRepairReceiptDesc.
  ///
  /// In en, this message translates to:
  /// **'Create repair intake form'**
  String get createRepairReceiptDesc;

  /// No description provided for @thermalPrinter.
  ///
  /// In en, this message translates to:
  /// **'THERMAL PRINTER'**
  String get thermalPrinter;

  /// No description provided for @printLabelsDesc.
  ///
  /// In en, this message translates to:
  /// **'Print device labels'**
  String get printLabelsDesc;

  /// No description provided for @quickMenu.
  ///
  /// In en, this message translates to:
  /// **'Quick menu'**
  String get quickMenu;

  /// No description provided for @customerAddress.
  ///
  /// In en, this message translates to:
  /// **'CUSTOMER ADDRESS'**
  String get customerAddress;

  /// No description provided for @addToContacts.
  ///
  /// In en, this message translates to:
  /// **'ADD TO CONTACTS'**
  String get addToContacts;

  /// No description provided for @viewCustomerHistory.
  ///
  /// In en, this message translates to:
  /// **'VIEW CUSTOMER HISTORY'**
  String get viewCustomerHistory;

  /// No description provided for @appearanceCondition.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE CONDITION'**
  String get appearanceCondition;

  /// No description provided for @appearanceHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: SCRATCHED, CRACKED, BENT...'**
  String get appearanceHint;

  /// No description provided for @accessoriesIncluded.
  ///
  /// In en, this message translates to:
  /// **'ACCESSORIES INCLUDED'**
  String get accessoriesIncluded;

  /// No description provided for @accessoriesHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: CHARGER, EARPHONES...'**
  String get accessoriesHint;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHOD'**
  String get paymentMethod;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'CREDIT'**
  String get credit;

  /// No description provided for @installment.
  ///
  /// In en, this message translates to:
  /// **'INSTALLMENT (BANK)'**
  String get installment;

  /// No description provided for @t86.
  ///
  /// In en, this message translates to:
  /// **'T86'**
  String get t86;

  /// No description provided for @bankT86.
  ///
  /// In en, this message translates to:
  /// **'BANK T86'**
  String get bankT86;

  /// No description provided for @enterPhoneFirst.
  ///
  /// In en, this message translates to:
  /// **'PLEASE ENTER PHONE NUMBER FIRST'**
  String get enterPhoneFirst;

  /// No description provided for @priceMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'PRICE MUST BE GREATER THAN OR EQUAL TO 0!'**
  String get priceMustBePositive;

  /// No description provided for @customerAddedToContacts.
  ///
  /// In en, this message translates to:
  /// **'CUSTOMER ADDED TO CONTACTS'**
  String get customerAddedToContacts;

  /// No description provided for @newOrder.
  ///
  /// In en, this message translates to:
  /// **'NEW ORDER'**
  String get newOrder;

  /// No description provided for @receivedDevice.
  ///
  /// In en, this message translates to:
  /// **'RECEIVE'**
  String get receivedDevice;

  /// No description provided for @addProductToInventory.
  ///
  /// In en, this message translates to:
  /// **'ADD PRODUCT TO INVENTORY'**
  String get addProductToInventory;

  /// No description provided for @productType.
  ///
  /// In en, this message translates to:
  /// **'Product type'**
  String get productType;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get phone;

  /// No description provided for @accessory.
  ///
  /// In en, this message translates to:
  /// **'ACCESSORY'**
  String get accessory;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product/Part name'**
  String get productName;

  /// No description provided for @imeiNumber.
  ///
  /// In en, this message translates to:
  /// **'IMEI number (if any)'**
  String get imeiNumber;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity (e.g.: 64GB, 128GB)'**
  String get capacity;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @supplierRequired.
  ///
  /// In en, this message translates to:
  /// **'Supplier (required)'**
  String get supplierRequired;

  /// No description provided for @addSupplierQuick.
  ///
  /// In en, this message translates to:
  /// **'Add supplier quick'**
  String get addSupplierQuick;

  /// No description provided for @addSupplier.
  ///
  /// In en, this message translates to:
  /// **'ADD SUPPLIER'**
  String get addSupplier;

  /// No description provided for @enterProductNameAndSupplier.
  ///
  /// In en, this message translates to:
  /// **'PLEASE ENTER PRODUCT NAME AND SELECT SUPPLIER'**
  String get enterProductNameAndSupplier;

  /// No description provided for @productAddedToInventory.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT ADDED TO INVENTORY'**
  String get productAddedToInventory;

  /// No description provided for @deleteMultipleProducts.
  ///
  /// In en, this message translates to:
  /// **'DELETE MULTIPLE PRODUCTS'**
  String get deleteMultipleProducts;

  /// No description provided for @confirmDeleteSelectedProducts.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} selected products from inventory?'**
  String confirmDeleteSelectedProducts(int count);

  /// No description provided for @productsDeleted.
  ///
  /// In en, this message translates to:
  /// **'SELECTED PRODUCTS DELETED'**
  String get productsDeleted;

  /// No description provided for @productDeleted.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT DELETED FROM INVENTORY'**
  String get productDeleted;

  /// No description provided for @onlyAdminCanDelete.
  ///
  /// In en, this message translates to:
  /// **'Only MANAGER accounts can delete products from inventory'**
  String get onlyAdminCanDelete;

  /// No description provided for @selectPrinter.
  ///
  /// In en, this message translates to:
  /// **'SELECT PRINTER'**
  String get selectPrinter;

  /// No description provided for @noPrintersFound.
  ///
  /// In en, this message translates to:
  /// **'No printers found. Please connect a printer first.'**
  String get noPrintersFound;

  /// No description provided for @labelPrintedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'LABEL PRINTED SUCCESSFULLY'**
  String get labelPrintedSuccessfully;

  /// No description provided for @labelPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'LABEL PRINT FAILED - CHECK PRINTER'**
  String get labelPrintFailed;

  /// No description provided for @errorPrintingLabel.
  ///
  /// In en, this message translates to:
  /// **'ERROR PRINTING LABEL'**
  String get errorPrintingLabel;

  /// No description provided for @financeCenter.
  ///
  /// In en, this message translates to:
  /// **'FINANCE CENTER'**
  String get financeCenter;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'STAFF'**
  String get staff;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordHint;

  /// No description provided for @priceHint.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceHint;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @saveRepairOrder.
  ///
  /// In en, this message translates to:
  /// **'Save repair order'**
  String get saveRepairOrder;

  /// No description provided for @noPermissionSuppliers.
  ///
  /// In en, this message translates to:
  /// **'This account is not permitted to view SUPPLIERS. Contact shop owner for permissions.'**
  String get noPermissionSuppliers;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @supplierShort.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get supplierShort;

  /// No description provided for @imei.
  ///
  /// In en, this message translates to:
  /// **'IMEI'**
  String get imei;

  /// No description provided for @quantityShort.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get quantityShort;

  /// No description provided for @printPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Print phone label'**
  String get printPhoneLabel;

  /// No description provided for @deleteFromInventory.
  ///
  /// In en, this message translates to:
  /// **'Delete from inventory'**
  String get deleteFromInventory;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get deleteSelected;

  /// No description provided for @addNewProduct.
  ///
  /// In en, this message translates to:
  /// **'Add new product'**
  String get addNewProduct;

  /// No description provided for @modelRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter device model'**
  String get modelRequired;

  /// No description provided for @issueRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter device issue'**
  String get issueRequired;

  /// No description provided for @orderCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Repair order created successfully!'**
  String get orderCreatedSuccessfully;

  /// No description provided for @createNewOrderQuestion.
  ///
  /// In en, this message translates to:
  /// **'Do you want to create a new repair order?'**
  String get createNewOrderQuestion;

  /// No description provided for @saveOrderError.
  ///
  /// In en, this message translates to:
  /// **'Error saving order: {error}'**
  String saveOrderError(String error);

  /// No description provided for @confirmPrintLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm print label'**
  String get confirmPrintLabel;

  /// No description provided for @printLabel.
  ///
  /// In en, this message translates to:
  /// **'Print label'**
  String get printLabel;

  /// No description provided for @confirmDeleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete product \'{name}\' from inventory?'**
  String confirmDeleteProduct(String name);

  /// No description provided for @deleteProductFromInventory.
  ///
  /// In en, this message translates to:
  /// **'Delete product from inventory'**
  String get deleteProductFromInventory;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @productDeletedFromInventory.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT DELETED FROM INVENTORY'**
  String get productDeletedFromInventory;

  /// No description provided for @confirmDeleteMultipleProducts.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} selected products from inventory?'**
  String confirmDeleteMultipleProducts(int count);

  /// No description provided for @multipleProductsDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count} PRODUCTS DELETED'**
  String multipleProductsDeleted(int count);

  /// No description provided for @imeiOptional.
  ///
  /// In en, this message translates to:
  /// **'IMEI (Optional)'**
  String get imeiOptional;

  /// No description provided for @capacityExample.
  ///
  /// In en, this message translates to:
  /// **'Capacity (e.g.: 64GB, 128GB)'**
  String get capacityExample;

  /// No description provided for @addSupplierQuickly.
  ///
  /// In en, this message translates to:
  /// **'Add supplier quick'**
  String get addSupplierQuickly;

  /// No description provided for @supplierName.
  ///
  /// In en, this message translates to:
  /// **'Supplier name'**
  String get supplierName;

  /// No description provided for @contactPerson.
  ///
  /// In en, this message translates to:
  /// **'Contact person'**
  String get contactPerson;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @condition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get condition;

  /// No description provided for @accessories.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get accessories;

  /// No description provided for @labelPrintError.
  ///
  /// In en, this message translates to:
  /// **'Label print error: {error}'**
  String labelPrintError(String error);

  /// No description provided for @cashClosingSaved.
  ///
  /// In en, this message translates to:
  /// **'DAILY CLOSING SAVED'**
  String get cashClosingSaved;

  /// No description provided for @netProfitAfterExpenses.
  ///
  /// In en, this message translates to:
  /// **'NET PROFIT AFTER EXPENSES'**
  String get netProfitAfterExpenses;

  /// No description provided for @timePeriod.
  ///
  /// In en, this message translates to:
  /// **'Time period'**
  String get timePeriod;

  /// No description provided for @todayCashFlow.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S CASH FLOW'**
  String get todayCashFlow;

  /// No description provided for @saveCashClosing.
  ///
  /// In en, this message translates to:
  /// **'Save closing'**
  String get saveCashClosing;

  /// No description provided for @syncHealthCheck.
  ///
  /// In en, this message translates to:
  /// **'SYNC HEALTH CHECK'**
  String get syncHealthCheck;

  /// No description provided for @syncHealthy.
  ///
  /// In en, this message translates to:
  /// **'SYNC COMPLETE'**
  String get syncHealthy;

  /// No description provided for @syncIssues.
  ///
  /// In en, this message translates to:
  /// **'SYNC ISSUES FOUND'**
  String get syncIssues;

  /// No description provided for @checkingSyncStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking sync status...'**
  String get checkingSyncStatus;

  /// No description provided for @localData.
  ///
  /// In en, this message translates to:
  /// **'Local data'**
  String get localData;

  /// No description provided for @cloudData.
  ///
  /// In en, this message translates to:
  /// **'Cloud data'**
  String get cloudData;

  /// No description provided for @notSynced.
  ///
  /// In en, this message translates to:
  /// **'Not synced'**
  String get notSynced;

  /// No description provided for @autoFix.
  ///
  /// In en, this message translates to:
  /// **'AUTO FIX'**
  String get autoFix;

  /// No description provided for @downloadShopData.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD SHOP DATA'**
  String get downloadShopData;

  /// No description provided for @uploadToCloud.
  ///
  /// In en, this message translates to:
  /// **'SYNC DATA TO CLOUD'**
  String get uploadToCloud;

  /// No description provided for @resetShopData.
  ///
  /// In en, this message translates to:
  /// **'RESET SHOP DATA'**
  String get resetShopData;

  /// No description provided for @logoutAccount.
  ///
  /// In en, this message translates to:
  /// **'LOGOUT ACCOUNT'**
  String get logoutAccount;

  /// No description provided for @shopInfo.
  ///
  /// In en, this message translates to:
  /// **'SHOP INFORMATION'**
  String get shopInfo;

  /// No description provided for @staffPermissions.
  ///
  /// In en, this message translates to:
  /// **'STAFF PERMISSION MANAGEMENT'**
  String get staffPermissions;

  /// No description provided for @debtDebug.
  ///
  /// In en, this message translates to:
  /// **'DEBT DEBUG'**
  String get debtDebug;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM SETTINGS'**
  String get systemSettings;

  /// No description provided for @languageApp.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageApp;

  /// No description provided for @yourRole.
  ///
  /// In en, this message translates to:
  /// **'Your role'**
  String get yourRole;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Shop owner'**
  String get owner;

  /// No description provided for @manager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get manager;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get user;

  /// No description provided for @debugTools.
  ///
  /// In en, this message translates to:
  /// **'DEBUG TOOLS'**
  String get debugTools;

  /// No description provided for @syncManagement.
  ///
  /// In en, this message translates to:
  /// **'DATA SYNC'**
  String get syncManagement;

  /// No description provided for @shopAdmin.
  ///
  /// In en, this message translates to:
  /// **'SHOP ADMIN'**
  String get shopAdmin;

  /// No description provided for @advancedAdmin.
  ///
  /// In en, this message translates to:
  /// **'ADVANCED ADMIN'**
  String get advancedAdmin;

  /// No description provided for @confirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get confirmLogout;

  /// No description provided for @warningNewDevice.
  ///
  /// In en, this message translates to:
  /// **'This device has very little data'**
  String get warningNewDevice;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'products'**
  String get products;

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE ANYWAY'**
  String get continueAnyway;

  /// No description provided for @newStaffWarning.
  ///
  /// In en, this message translates to:
  /// **'Please DOWNLOAD DATA first, DO NOT sync to cloud without data.'**
  String get newStaffWarning;

  /// No description provided for @dataToUpload.
  ///
  /// In en, this message translates to:
  /// **'Data to upload'**
  String get dataToUpload;

  /// No description provided for @newRepairOrders.
  ///
  /// In en, this message translates to:
  /// **'new repair orders'**
  String get newRepairOrders;

  /// No description provided for @newSaleOrders.
  ///
  /// In en, this message translates to:
  /// **'new sale orders'**
  String get newSaleOrders;

  /// No description provided for @existingCloudData.
  ///
  /// In en, this message translates to:
  /// **'Existing cloud data will NOT be deleted.'**
  String get existingCloudData;

  /// No description provided for @downloadAllData.
  ///
  /// In en, this message translates to:
  /// **'Download all shop data from cloud.'**
  String get downloadAllData;

  /// No description provided for @downloadingData.
  ///
  /// In en, this message translates to:
  /// **'Downloading data...'**
  String get downloadingData;

  /// No description provided for @uploadingData.
  ///
  /// In en, this message translates to:
  /// **'Syncing data...'**
  String get uploadingData;

  /// No description provided for @uploadSuccess.
  ///
  /// In en, this message translates to:
  /// **'Data synced to cloud!'**
  String get uploadSuccess;

  /// No description provided for @confirmResetShop.
  ///
  /// In en, this message translates to:
  /// **'Type \'XOA HET\' to confirm'**
  String get confirmResetShop;

  /// No description provided for @confirmResetButton.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM RESET'**
  String get confirmResetButton;

  /// No description provided for @resetSuccess.
  ///
  /// In en, this message translates to:
  /// **'SHOP DATA RESET!'**
  String get resetSuccess;

  /// No description provided for @onlySuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'ONLY SUPER ADMIN CAN RESET SHOP DATA!'**
  String get onlySuperAdmin;

  /// No description provided for @repairListTitle.
  ///
  /// In en, this message translates to:
  /// **'REPAIR LIST'**
  String get repairListTitle;

  /// No description provided for @machinesCount.
  ///
  /// In en, this message translates to:
  /// **'devices'**
  String get machinesCount;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get processing;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @searchFullApp.
  ///
  /// In en, this message translates to:
  /// **'Search entire app'**
  String get searchFullApp;

  /// No description provided for @saleListTitle.
  ///
  /// In en, this message translates to:
  /// **'SALES MANAGEMENT'**
  String get saleListTitle;

  /// No description provided for @todaySales.
  ///
  /// In en, this message translates to:
  /// **'TODAY\'S SALES'**
  String get todaySales;

  /// No description provided for @ordersCount.
  ///
  /// In en, this message translates to:
  /// **'orders'**
  String get ordersCount;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @searchByNameImei.
  ///
  /// In en, this message translates to:
  /// **'Search by customer, device or IMEI...'**
  String get searchByNameImei;

  /// No description provided for @financeManagement.
  ///
  /// In en, this message translates to:
  /// **'FINANCE MANAGEMENT'**
  String get financeManagement;

  /// No description provided for @revenueExpenseOverview.
  ///
  /// In en, this message translates to:
  /// **'Revenue, expense overview'**
  String get revenueExpenseOverview;

  /// No description provided for @filterByTime.
  ///
  /// In en, this message translates to:
  /// **'Filter by time'**
  String get filterByTime;

  /// No description provided for @partnerManagement.
  ///
  /// In en, this message translates to:
  /// **'PARTNER MANAGEMENT'**
  String get partnerManagement;

  /// No description provided for @suppliersCount.
  ///
  /// In en, this message translates to:
  /// **'suppliers'**
  String get suppliersCount;

  /// No description provided for @partnersCount.
  ///
  /// In en, this message translates to:
  /// **'partners'**
  String get partnersCount;

  /// No description provided for @supplierTab.
  ///
  /// In en, this message translates to:
  /// **'SUPPLIERS'**
  String get supplierTab;

  /// No description provided for @repairPartnerTab.
  ///
  /// In en, this message translates to:
  /// **'REPAIR PARTNERS'**
  String get repairPartnerTab;

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleLabel;

  /// No description provided for @generateQRInvite.
  ///
  /// In en, this message translates to:
  /// **'Generate QR invite'**
  String get generateQRInvite;

  /// No description provided for @saleDetail.
  ///
  /// In en, this message translates to:
  /// **'SALE DETAILS'**
  String get saleDetail;

  /// No description provided for @repairDetail.
  ///
  /// In en, this message translates to:
  /// **'REPAIR DETAILS'**
  String get repairDetail;

  /// No description provided for @attendanceManagement.
  ///
  /// In en, this message translates to:
  /// **'Manage work hours'**
  String get attendanceManagement;

  /// No description provided for @deleteSupplier.
  ///
  /// In en, this message translates to:
  /// **'DELETE SUPPLIER'**
  String get deleteSupplier;

  /// No description provided for @confirmDeleteSupplier.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this supplier?'**
  String get confirmDeleteSupplier;

  /// No description provided for @deleteSaleOrder.
  ///
  /// In en, this message translates to:
  /// **'DELETE SALE ORDER'**
  String get deleteSaleOrder;

  /// No description provided for @confirmDeleteSaleOrder.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this sale order?'**
  String get confirmDeleteSaleOrder;

  /// No description provided for @permissionManagement.
  ///
  /// In en, this message translates to:
  /// **'PERMISSION MANAGEMENT'**
  String get permissionManagement;

  /// No description provided for @ownerFullAccess.
  ///
  /// In en, this message translates to:
  /// **'SHOP OWNER has full access to all features in the system'**
  String get ownerFullAccess;

  /// No description provided for @managerFullAccess.
  ///
  /// In en, this message translates to:
  /// **'MANAGER has full access to all features in the system'**
  String get managerFullAccess;

  /// No description provided for @bluetoothPrinterTest.
  ///
  /// In en, this message translates to:
  /// **'BLUETOOTH PRINTER TEST'**
  String get bluetoothPrinterTest;

  /// No description provided for @checkBluetoothPermission.
  ///
  /// In en, this message translates to:
  /// **'Check detailed Bluetooth permissions...'**
  String get checkBluetoothPermission;

  /// No description provided for @checkBluetoothOn.
  ///
  /// In en, this message translates to:
  /// **'Check if Bluetooth is on...'**
  String get checkBluetoothOn;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version 2.6.0+100'**
  String get appVersion;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'SAVE SETTINGS'**
  String get saveSettings;

  /// No description provided for @deleteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Delete template?'**
  String get deleteTemplate;

  /// No description provided for @saveTemplate.
  ///
  /// In en, this message translates to:
  /// **'SAVE TEMPLATE'**
  String get saveTemplate;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get saveChanges;

  /// No description provided for @addCode.
  ///
  /// In en, this message translates to:
  /// **'ADD CODE'**
  String get addCode;

  /// No description provided for @deletePartner.
  ///
  /// In en, this message translates to:
  /// **'Delete partner'**
  String get deletePartner;

  /// No description provided for @scanSettings.
  ///
  /// In en, this message translates to:
  /// **'Scan settings'**
  String get scanSettings;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm action'**
  String get confirmAction;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @pleaseEnter.
  ///
  /// In en, this message translates to:
  /// **'Please enter'**
  String get pleaseEnter;

  /// No description provided for @pleaseSelect.
  ///
  /// In en, this message translates to:
  /// **'Please select'**
  String get pleaseSelect;

  /// No description provided for @invalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid input'**
  String get invalidInput;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionError;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get print;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createNew.
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get createNew;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @viewMore.
  ///
  /// In en, this message translates to:
  /// **'View more'**
  String get viewMore;

  /// No description provided for @viewLess.
  ///
  /// In en, this message translates to:
  /// **'View less'**
  String get viewLess;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @hideAll.
  ///
  /// In en, this message translates to:
  /// **'Hide all'**
  String get hideAll;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @by.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get by;

  /// No description provided for @at.
  ///
  /// In en, this message translates to:
  /// **'At'**
  String get at;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'And'**
  String get and;

  /// No description provided for @withLabel.
  ///
  /// In en, this message translates to:
  /// **'With'**
  String get withLabel;

  /// No description provided for @without.
  ///
  /// In en, this message translates to:
  /// **'Without'**
  String get without;

  /// No description provided for @old.
  ///
  /// In en, this message translates to:
  /// **'Old'**
  String get old;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @less.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get less;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @close2.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close2;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @attach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modified;

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get created;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter your registered email, we will send a password reset link.'**
  String get forgotPasswordDesc;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get pleaseEnterValidEmail;

  /// No description provided for @passwordResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent to {email}'**
  String passwordResetEmailSent(String email);

  /// No description provided for @errorSendingEmail.
  ///
  /// In en, this message translates to:
  /// **'Error sending email'**
  String get errorSendingEmail;

  /// No description provided for @emailNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Email not registered'**
  String get emailNotRegistered;

  /// No description provided for @invalidEmailFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get invalidEmailFormat;

  /// No description provided for @sendEmail.
  ///
  /// In en, this message translates to:
  /// **'SEND EMAIL'**
  String get sendEmail;

  /// No description provided for @noAccountRegisterNow.
  ///
  /// In en, this message translates to:
  /// **'No account? Register now'**
  String get noAccountRegisterNow;

  /// No description provided for @registerSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful! Please login.'**
  String get registerSuccess;

  /// No description provided for @emailExample.
  ///
  /// In en, this message translates to:
  /// **'E.g.: name@domain.com or name@gmail.com'**
  String get emailExample;

  /// No description provided for @perpetualCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Perpetual Calendar'**
  String get perpetualCalendarTitle;

  /// No description provided for @todayDateFormat.
  ///
  /// In en, this message translates to:
  /// **'Today: {date}'**
  String todayDateFormat(String date);

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get monday;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tuesday;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wednesday;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thursday;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get friday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get saturday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sunday;

  /// No description provided for @languageAndInterface.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE & INTERFACE'**
  String get languageAndInterface;

  /// No description provided for @accountAndSecurity.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT & SECURITY'**
  String get accountAndSecurity;

  /// No description provided for @selectOtherShop.
  ///
  /// In en, this message translates to:
  /// **'SELECT OTHER SHOP'**
  String get selectOtherShop;

  /// No description provided for @logoutFromApp.
  ///
  /// In en, this message translates to:
  /// **'Logout from app'**
  String get logoutFromApp;

  /// No description provided for @logoutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Logout?'**
  String get logoutQuestion;

  /// No description provided for @logoutError.
  ///
  /// In en, this message translates to:
  /// **'Logout error: {error}'**
  String logoutError(String error);

  /// No description provided for @syncCenter.
  ///
  /// In en, this message translates to:
  /// **'SYNC CENTER'**
  String get syncCenter;

  /// No description provided for @syncCenterDesc.
  ///
  /// In en, this message translates to:
  /// **'Download, upload, check and restore data'**
  String get syncCenterDesc;

  /// No description provided for @viewShopAsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin can select shop to view data'**
  String get viewShopAsAdmin;

  /// No description provided for @noShops.
  ///
  /// In en, this message translates to:
  /// **'No shops available'**
  String get noShops;

  /// No description provided for @selectShopLabel.
  ///
  /// In en, this message translates to:
  /// **'Select shop'**
  String get selectShopLabel;

  /// No description provided for @selectShopPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'-- Select shop to view --'**
  String get selectShopPlaceholder;

  /// No description provided for @currentlyViewing.
  ///
  /// In en, this message translates to:
  /// **'Viewing: {shopName}'**
  String currentlyViewing(String shopName);

  /// No description provided for @ownerRole.
  ///
  /// In en, this message translates to:
  /// **'SHOP OWNER'**
  String get ownerRole;

  /// No description provided for @managerRole.
  ///
  /// In en, this message translates to:
  /// **'MANAGER'**
  String get managerRole;

  /// No description provided for @employeeRole.
  ///
  /// In en, this message translates to:
  /// **'EMPLOYEE'**
  String get employeeRole;

  /// No description provided for @technicianRole.
  ///
  /// In en, this message translates to:
  /// **'TECHNICIAN'**
  String get technicianRole;

  /// No description provided for @adminRole.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get adminRole;

  /// No description provided for @userRole.
  ///
  /// In en, this message translates to:
  /// **'USER'**
  String get userRole;

  /// No description provided for @dangerWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'⚠️ DANGER WARNING'**
  String get dangerWarningTitle;

  /// No description provided for @resetShopWarning.
  ///
  /// In en, this message translates to:
  /// **'This action will permanently delete 100% of Orders, Inventory, Debts and Logs from both Cloud and this Device. CANNOT BE UNDONE!'**
  String get resetShopWarning;

  /// No description provided for @resetCloudError.
  ///
  /// In en, this message translates to:
  /// **'ERROR DELETING CLOUD DATA: {error}'**
  String resetCloudError(String error);

  /// No description provided for @viewAndEditStaffPermissions.
  ///
  /// In en, this message translates to:
  /// **'View and edit staff access permissions'**
  String get viewAndEditStaffPermissions;

  /// No description provided for @resetShopAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Use to reset all shop data (SUPER ADMIN ONLY)'**
  String get resetShopAdminOnly;

  /// No description provided for @syncErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncErrorTitle;

  /// No description provided for @noTransactionHistory.
  ///
  /// In en, this message translates to:
  /// **'No transaction history'**
  String get noTransactionHistory;

  /// No description provided for @noActivityLogs.
  ///
  /// In en, this message translates to:
  /// **'No activity logs yet'**
  String get noActivityLogs;

  /// No description provided for @noRepairOrders.
  ///
  /// In en, this message translates to:
  /// **'No repair orders'**
  String get noRepairOrders;

  /// No description provided for @noSaleOrders.
  ///
  /// In en, this message translates to:
  /// **'No sale orders'**
  String get noSaleOrders;

  /// No description provided for @noPaymentData.
  ///
  /// In en, this message translates to:
  /// **'No payment data'**
  String get noPaymentData;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotifications;

  /// No description provided for @notSyncedCount.
  ///
  /// In en, this message translates to:
  /// **'Not synced ({count})'**
  String notSyncedCount(int count);

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get notSelected;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get confirmDelete;

  /// No description provided for @confirmActionWithName.
  ///
  /// In en, this message translates to:
  /// **'Confirm {action}'**
  String confirmActionWithName(String action);

  /// No description provided for @confirmDeleteOrder.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM DELETE ORDER'**
  String get confirmDeleteOrder;

  /// No description provided for @enterPasswordToDelete.
  ///
  /// In en, this message translates to:
  /// **'Enter account password to delete:'**
  String get enterPasswordToDelete;

  /// No description provided for @deletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'DELETED SUCCESSFULLY'**
  String get deletedSuccessfully;

  /// No description provided for @addToStock.
  ///
  /// In en, this message translates to:
  /// **'ADD TO STOCK'**
  String get addToStock;

  /// No description provided for @continueAdding.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE ADDING'**
  String get continueAdding;

  /// No description provided for @manualEntry.
  ///
  /// In en, this message translates to:
  /// **'Manual entry'**
  String get manualEntry;

  /// No description provided for @confirmStagingStock.
  ///
  /// In en, this message translates to:
  /// **'Confirm add to staging stock'**
  String get confirmStagingStock;

  /// No description provided for @addToStagingStock.
  ///
  /// In en, this message translates to:
  /// **'Add to Staging Stock'**
  String get addToStagingStock;

  /// No description provided for @purchaseOrderCreated.
  ///
  /// In en, this message translates to:
  /// **'Purchase order created'**
  String get purchaseOrderCreated;

  /// No description provided for @addMore.
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get addMore;

  /// No description provided for @confirmStockIn.
  ///
  /// In en, this message translates to:
  /// **'Confirm stock in?'**
  String get confirmStockIn;

  /// No description provided for @pleaseEnterPartnerName.
  ///
  /// In en, this message translates to:
  /// **'Please enter partner name'**
  String get pleaseEnterPartnerName;

  /// No description provided for @pleaseEnterSupplierName.
  ///
  /// In en, this message translates to:
  /// **'Please enter supplier name'**
  String get pleaseEnterSupplierName;

  /// No description provided for @supplierAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Supplier added successfully'**
  String get supplierAddedSuccess;

  /// No description provided for @supplierAddError.
  ///
  /// In en, this message translates to:
  /// **'Error: Cannot add supplier'**
  String get supplierAddError;

  /// No description provided for @partnerDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Partner deleted successfully'**
  String get partnerDeletedSuccess;

  /// No description provided for @partnerDeleteError.
  ///
  /// In en, this message translates to:
  /// **'Error: Cannot delete partner'**
  String get partnerDeleteError;

  /// No description provided for @supplierDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Supplier deleted successfully'**
  String get supplierDeletedSuccess;

  /// No description provided for @supplierDeleteError.
  ///
  /// In en, this message translates to:
  /// **'Error: Cannot delete supplier'**
  String get supplierDeleteError;

  /// No description provided for @partnerAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Partner added successfully'**
  String get partnerAddedSuccess;

  /// No description provided for @partnerUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Partner updated'**
  String get partnerUpdatedSuccess;

  /// No description provided for @partnerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Partner not found!'**
  String get partnerNotFound;

  /// No description provided for @partnerInfoNotFound.
  ///
  /// In en, this message translates to:
  /// **'Partner info not found!'**
  String get partnerInfoNotFound;

  /// No description provided for @loadingList.
  ///
  /// In en, this message translates to:
  /// **'Loading list...'**
  String get loadingList;

  /// No description provided for @searchError.
  ///
  /// In en, this message translates to:
  /// **'Search error: {error}'**
  String searchError(String error);

  /// No description provided for @qrProcessError.
  ///
  /// In en, this message translates to:
  /// **'QR processing error: {error}'**
  String qrProcessError(String error);

  /// No description provided for @errorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithMessage(String error);

  /// No description provided for @loadCustomerListError.
  ///
  /// In en, this message translates to:
  /// **'Error loading customer list: {error}'**
  String loadCustomerListError(String error);

  /// No description provided for @deleteError.
  ///
  /// In en, this message translates to:
  /// **'Delete error: {error}'**
  String deleteError(String error);

  /// No description provided for @shopTab.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopTab;

  /// No description provided for @templateTab.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templateTab;

  /// No description provided for @versionFormat.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionFormat(String version);

  /// No description provided for @displayInfoOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Info displayed on label'**
  String get displayInfoOnLabel;

  /// No description provided for @shopNameField.
  ///
  /// In en, this message translates to:
  /// **'Shop Name'**
  String get shopNameField;

  /// No description provided for @shopNameHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: HULUCA MOBILE'**
  String get shopNameHint;

  /// No description provided for @hotlineHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: 0909 123 456'**
  String get hotlineHint;

  /// No description provided for @zalo.
  ///
  /// In en, this message translates to:
  /// **'Zalo'**
  String get zalo;

  /// No description provided for @slogan.
  ///
  /// In en, this message translates to:
  /// **'Slogan'**
  String get slogan;

  /// No description provided for @sloganHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: Best prices guaranteed'**
  String get sloganHint;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'E.g.: 123 ABC, District 1, HCM'**
  String get addressHint;

  /// No description provided for @invoiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice template saved'**
  String get invoiceSaved;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'PROFILE SAVED'**
  String get profileSaved;

  /// No description provided for @partDeleted.
  ///
  /// In en, this message translates to:
  /// **'Part deleted'**
  String get partDeleted;

  /// No description provided for @partsDeletedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} parts deleted'**
  String partsDeletedCount(int count);

  /// No description provided for @csvCopied.
  ///
  /// In en, this message translates to:
  /// **'CSV copied to clipboard'**
  String get csvCopied;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get statusDone;

  /// No description provided for @receiptSavedAndPrinted.
  ///
  /// In en, this message translates to:
  /// **'Receipt saved and printed successfully!'**
  String get receiptSavedAndPrinted;

  /// No description provided for @partnerDeleted.
  ///
  /// In en, this message translates to:
  /// **'PARTNER DELETED'**
  String get partnerDeleted;

  /// No description provided for @refreshingFcmToken.
  ///
  /// In en, this message translates to:
  /// **'Refreshing FCM token...'**
  String get refreshingFcmToken;

  /// No description provided for @isActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get isActive;

  /// No description provided for @confirmButton.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM'**
  String get confirmButton;

  /// No description provided for @shopField.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopField;

  /// No description provided for @selectShopToViewData.
  ///
  /// In en, this message translates to:
  /// **'SELECT SHOP TO VIEW'**
  String get selectShopToViewData;

  /// No description provided for @homeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// No description provided for @salesTab.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesTab;

  /// No description provided for @repairsTab.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get repairsTab;

  /// No description provided for @inventoryTab.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventoryTab;

  /// No description provided for @financeTab.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get financeTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @exitAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit app?'**
  String get exitAppTitle;

  /// No description provided for @groupChat.
  ///
  /// In en, this message translates to:
  /// **'GROUP CHAT'**
  String get groupChat;

  /// No description provided for @newMessagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} new messages'**
  String newMessagesCount(int count);

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessages;

  /// No description provided for @financialOverview.
  ///
  /// In en, this message translates to:
  /// **'FINANCIAL OVERVIEW'**
  String get financialOverview;

  /// No description provided for @todayOverview.
  ///
  /// In en, this message translates to:
  /// **'TODAY OVERVIEW'**
  String get todayOverview;

  /// No description provided for @todayExpenseLabel.
  ///
  /// In en, this message translates to:
  /// **'TODAY EXPENSE'**
  String get todayExpenseLabel;

  /// No description provided for @todayActivities.
  ///
  /// In en, this message translates to:
  /// **'TODAY ACTIVITIES'**
  String get todayActivities;

  /// No description provided for @profitFormula.
  ///
  /// In en, this message translates to:
  /// **'= Income - Expense - Cost'**
  String get profitFormula;

  /// No description provided for @featureLockedByAdmin.
  ///
  /// In en, this message translates to:
  /// **'This feature has been locked by Administrator.\nPlease contact developer for support.'**
  String get featureLockedByAdmin;

  /// No description provided for @featureLockedByOwner.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to access this feature.\nPlease contact Shop Owner for access.'**
  String get featureLockedByOwner;

  /// No description provided for @technicalSupport.
  ///
  /// In en, this message translates to:
  /// **'TECHNICAL SUPPORT'**
  String get technicalSupport;

  /// No description provided for @contactShopOwner.
  ///
  /// In en, this message translates to:
  /// **'CONTACT SHOP OWNER'**
  String get contactShopOwner;

  /// No description provided for @hulucaTech.
  ///
  /// In en, this message translates to:
  /// **'Huluca Tech'**
  String get hulucaTech;

  /// No description provided for @shopOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop Owner'**
  String get shopOwnerLabel;

  /// No description provided for @adminLocked.
  ///
  /// In en, this message translates to:
  /// **'ADMIN LOCKED'**
  String get adminLocked;

  /// No description provided for @ownerPermissionLocked.
  ///
  /// In en, this message translates to:
  /// **'OWNER PERMISSION LOCKED'**
  String get ownerPermissionLocked;

  /// No description provided for @featureLocked.
  ///
  /// In en, this message translates to:
  /// **'Feature locked'**
  String get featureLocked;

  /// No description provided for @supportAvailability.
  ///
  /// In en, this message translates to:
  /// **'24/7 Support • Response within 30 minutes'**
  String get supportAvailability;

  /// No description provided for @requestPermission.
  ///
  /// In en, this message translates to:
  /// **'Request permission'**
  String get requestPermission;

  /// No description provided for @contactShopOwnerOrManager.
  ///
  /// In en, this message translates to:
  /// **'Contact Shop Owner or Manager'**
  String get contactShopOwnerOrManager;

  /// No description provided for @requestFeatureAccess.
  ///
  /// In en, this message translates to:
  /// **'Request access to this feature'**
  String get requestFeatureAccess;

  /// No description provided for @loginAgainAfterPermission.
  ///
  /// In en, this message translates to:
  /// **'After permission granted, login again to apply'**
  String get loginAgainAfterPermission;

  /// No description provided for @cannotMakeCall.
  ///
  /// In en, this message translates to:
  /// **'Cannot make call: {phoneNumber}'**
  String cannotMakeCall(String phoneNumber);

  /// No description provided for @cannotOpenZalo.
  ///
  /// In en, this message translates to:
  /// **'Cannot open Zalo. Please contact: {phoneNumber}'**
  String cannotOpenZalo(String phoneNumber);

  /// No description provided for @notificationActive.
  ///
  /// In en, this message translates to:
  /// **'Notifications (active)'**
  String get notificationActive;

  /// No description provided for @notificationInactive.
  ///
  /// In en, this message translates to:
  /// **'Notifications (inactive)'**
  String get notificationInactive;

  /// No description provided for @searchWholeApp.
  ///
  /// In en, this message translates to:
  /// **'Search whole app'**
  String get searchWholeApp;

  /// No description provided for @contactAdminToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Contact Admin to unlock'**
  String get contactAdminToUnlock;

  /// No description provided for @systemAdminLabel.
  ///
  /// In en, this message translates to:
  /// **'System Administrator'**
  String get systemAdminLabel;

  /// No description provided for @shopOwnerLabelFull.
  ///
  /// In en, this message translates to:
  /// **'Shop Owner'**
  String get shopOwnerLabelFull;

  /// No description provided for @managerLabel.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get managerLabel;

  /// No description provided for @staffLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffLabel;

  /// No description provided for @userLabel.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userLabel;

  /// No description provided for @welcomeNewStaff.
  ///
  /// In en, this message translates to:
  /// **'Welcome new staff!'**
  String get welcomeNewStaff;

  /// No description provided for @newStaffSyncGuide.
  ///
  /// In en, this message translates to:
  /// **'Go to Shop Settings → Download shop data to sync'**
  String get newStaffSyncGuide;

  /// No description provided for @downloadShopDataToStart.
  ///
  /// In en, this message translates to:
  /// **'Download shop data to start working'**
  String get downloadShopDataToStart;

  /// No description provided for @downloadShopDataTitle.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD SHOP DATA'**
  String get downloadShopDataTitle;

  /// No description provided for @fromCloudToDevice.
  ///
  /// In en, this message translates to:
  /// **'from cloud to this device.'**
  String get fromCloudToDevice;

  /// No description provided for @debtsAndExpenses.
  ///
  /// In en, this message translates to:
  /// **'Debts & Expenses'**
  String get debtsAndExpenses;

  /// No description provided for @customersAndSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Customers & Suppliers'**
  String get customersAndSuppliers;

  /// No description provided for @downloadOnlyThisShop.
  ///
  /// In en, this message translates to:
  /// **'Only download this shop\'s data, won\'t affect other shops.'**
  String get downloadOnlyThisShop;

  /// No description provided for @downloadMayTakeFewMinutes.
  ///
  /// In en, this message translates to:
  /// **'Process may take a few minutes depending on data size.'**
  String get downloadMayTakeFewMinutes;

  /// No description provided for @startDownload.
  ///
  /// In en, this message translates to:
  /// **'START DOWNLOAD'**
  String get startDownload;

  /// No description provided for @downloadingShopData.
  ///
  /// In en, this message translates to:
  /// **'Downloading shop data...'**
  String get downloadingShopData;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait'**
  String get pleaseWait;

  /// No description provided for @shopDataDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Shop data downloaded!'**
  String get shopDataDownloaded;

  /// No description provided for @quickAccess.
  ///
  /// In en, this message translates to:
  /// **'QUICK ACCESS'**
  String get quickAccess;

  /// No description provided for @salesOrder.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesOrder;

  /// No description provided for @salesOrderList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get salesOrderList;

  /// No description provided for @repairOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Repairs'**
  String get repairOrderTitle;

  /// No description provided for @pendingStockShort.
  ///
  /// In en, this message translates to:
  /// **'Pending Stock'**
  String get pendingStockShort;

  /// No description provided for @temporaryImport.
  ///
  /// In en, this message translates to:
  /// **'Temp Import'**
  String get temporaryImport;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @incomeExpense.
  ///
  /// In en, this message translates to:
  /// **'Income/Expense'**
  String get incomeExpense;

  /// No description provided for @createSaleOrder.
  ///
  /// In en, this message translates to:
  /// **'CREATE SALE ORDER'**
  String get createSaleOrder;

  /// No description provided for @sellProductsQuickly.
  ///
  /// In en, this message translates to:
  /// **'Sell products quickly'**
  String get sellProductsQuickly;

  /// No description provided for @receiveDeviceForRepair.
  ///
  /// In en, this message translates to:
  /// **'Receive device for repair'**
  String get receiveDeviceForRepair;

  /// No description provided for @addStock.
  ///
  /// In en, this message translates to:
  /// **'+ ADD STOCK'**
  String get addStock;

  /// No description provided for @newStockIn.
  ///
  /// In en, this message translates to:
  /// **'New stock in'**
  String get newStockIn;

  /// No description provided for @scanToCheck.
  ///
  /// In en, this message translates to:
  /// **'Scan to check'**
  String get scanToCheck;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'REPORT'**
  String get report;

  /// No description provided for @checkInOut.
  ///
  /// In en, this message translates to:
  /// **'Check in/out'**
  String get checkInOut;

  /// No description provided for @quickWarrantyLookup.
  ///
  /// In en, this message translates to:
  /// **'Quick warranty lookup'**
  String get quickWarrantyLookup;

  /// No description provided for @createSale.
  ///
  /// In en, this message translates to:
  /// **'Create sale'**
  String get createSale;

  /// No description provided for @createRepair.
  ///
  /// In en, this message translates to:
  /// **'Create repair'**
  String get createRepair;

  /// No description provided for @stockIn.
  ///
  /// In en, this message translates to:
  /// **'Stock in'**
  String get stockIn;

  /// No description provided for @revenueReport.
  ///
  /// In en, this message translates to:
  /// **'Revenue report'**
  String get revenueReport;

  /// No description provided for @createNewSaleOrder.
  ///
  /// In en, this message translates to:
  /// **'CREATE NEW SALE ORDER'**
  String get createNewSaleOrder;

  /// No description provided for @createSaleOrderQuickly.
  ///
  /// In en, this message translates to:
  /// **'Create sale order quickly'**
  String get createSaleOrderQuickly;

  /// No description provided for @management.
  ///
  /// In en, this message translates to:
  /// **'MANAGEMENT'**
  String get management;

  /// No description provided for @saleOrderList.
  ///
  /// In en, this message translates to:
  /// **'Sale order list'**
  String get saleOrderList;

  /// No description provided for @viewSearchTrackSales.
  ///
  /// In en, this message translates to:
  /// **'View, search and track all sale orders.'**
  String get viewSearchTrackSales;

  /// No description provided for @addEditViewCustomers.
  ///
  /// In en, this message translates to:
  /// **'Add, edit and view customer information.'**
  String get addEditViewCustomers;

  /// No description provided for @viewProcessWarrantyRequests.
  ///
  /// In en, this message translates to:
  /// **'View and process warranty requests.'**
  String get viewProcessWarrantyRequests;

  /// No description provided for @repairs.
  ///
  /// In en, this message translates to:
  /// **'REPAIRS'**
  String get repairs;

  /// No description provided for @createNewRepairOrder.
  ///
  /// In en, this message translates to:
  /// **'CREATE NEW REPAIR ORDER'**
  String get createNewRepairOrder;

  /// No description provided for @repairOrderList.
  ///
  /// In en, this message translates to:
  /// **'Repair order list'**
  String get repairOrderList;

  /// No description provided for @viewSearchTrackRepairs.
  ///
  /// In en, this message translates to:
  /// **'View, search and track all repair orders.'**
  String get viewSearchTrackRepairs;

  /// No description provided for @holdForDetailedGuide.
  ///
  /// In en, this message translates to:
  /// **'Hold for detailed guide'**
  String get holdForDetailedGuide;

  /// No description provided for @stockInNew.
  ///
  /// In en, this message translates to:
  /// **'STOCK IN NEW'**
  String get stockInNew;

  /// No description provided for @stockInNewGuide.
  ///
  /// In en, this message translates to:
  /// **'Stock in with full information:\n\n✅ Support: Phones, Accessories, Parts\n✅ Save temp: Input when info is incomplete\n✅ Confirm: Stock officially enters inventory\n\n📌 Use when: Inputting new stock from supplier, need full IMEI/SKU, cost price, supplier...'**
  String get stockInNewGuide;

  /// No description provided for @fullInformation.
  ///
  /// In en, this message translates to:
  /// **'Full information'**
  String get fullInformation;

  /// No description provided for @quickStockIn.
  ///
  /// In en, this message translates to:
  /// **'QUICK STOCK IN'**
  String get quickStockIn;

  /// No description provided for @quickStockInGuide.
  ///
  /// In en, this message translates to:
  /// **'Super fast stock in - just scan:\n\n⚡ Scan barcode/QR continuously\n⚡ Auto-fill info from library\n⚡ Suitable for large quantities\n\n📌 Use when: Quick input of accessories, parts already in system.'**
  String get quickStockInGuide;

  /// No description provided for @continuousScan.
  ///
  /// In en, this message translates to:
  /// **'Continuous scan'**
  String get continuousScan;

  /// No description provided for @checkInventoryGuide.
  ///
  /// In en, this message translates to:
  /// **'Check inventory by scanning:\n\n🔍 Scan QR/Barcode to check stock\n🔍 Compare actual vs system quantity\n🔍 Record discrepancies\n\n📌 Use when: Periodic inventory check, stock reconciliation.'**
  String get checkInventoryGuide;

  /// No description provided for @contactOwnerForAccess.
  ///
  /// In en, this message translates to:
  /// **'Contact shop owner for access'**
  String get contactOwnerForAccess;

  /// No description provided for @compareInventory.
  ///
  /// In en, this message translates to:
  /// **'Compare inventory'**
  String get compareInventory;

  /// No description provided for @pendingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Pending confirmation'**
  String get pendingConfirmation;

  /// No description provided for @viewPendingStockList.
  ///
  /// In en, this message translates to:
  /// **'View pending stock confirmation list.'**
  String get viewPendingStockList;

  /// No description provided for @productList.
  ///
  /// In en, this message translates to:
  /// **'Product list'**
  String get productList;

  /// No description provided for @viewManageProducts.
  ///
  /// In en, this message translates to:
  /// **'View and manage products in stock.'**
  String get viewManageProducts;

  /// No description provided for @suppliersPartners.
  ///
  /// In en, this message translates to:
  /// **'Suppliers - Partners'**
  String get suppliersPartners;

  /// No description provided for @manageSupplierPartnerDebt.
  ///
  /// In en, this message translates to:
  /// **'Manage suppliers, repair partners and debts.'**
  String get manageSupplierPartnerDebt;

  /// No description provided for @quickInputCodeList.
  ///
  /// In en, this message translates to:
  /// **'Quick input code list'**
  String get quickInputCodeList;

  /// No description provided for @viewManageQuickInputCodes.
  ///
  /// In en, this message translates to:
  /// **'View and manage quick input codes.'**
  String get viewManageQuickInputCodes;

  /// No description provided for @contactOwnerForPermission.
  ///
  /// In en, this message translates to:
  /// **'Contact shop owner for permission'**
  String get contactOwnerForPermission;

  /// No description provided for @staffManagement.
  ///
  /// In en, this message translates to:
  /// **'STAFF MANAGEMENT'**
  String get staffManagement;

  /// No description provided for @recordWorkingHours.
  ///
  /// In en, this message translates to:
  /// **'Record working hours'**
  String get recordWorkingHours;

  /// No description provided for @employeeManagement.
  ///
  /// In en, this message translates to:
  /// **'EMPLOYEE MANAGEMENT'**
  String get employeeManagement;

  /// No description provided for @salaryCalculation.
  ///
  /// In en, this message translates to:
  /// **'SALARY\nCalculation'**
  String get salaryCalculation;

  /// No description provided for @workSchedule.
  ///
  /// In en, this message translates to:
  /// **'Work\nSchedule'**
  String get workSchedule;

  /// No description provided for @salaryCommissionSettings.
  ///
  /// In en, this message translates to:
  /// **'Salary &\nCommission Settings'**
  String get salaryCommissionSettings;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get reports;

  /// No description provided for @viewAllStaffAttendance.
  ///
  /// In en, this message translates to:
  /// **'View all staff attendance by day/month.'**
  String get viewAllStaffAttendance;

  /// No description provided for @personalAttendance.
  ///
  /// In en, this message translates to:
  /// **'Personal attendance'**
  String get personalAttendance;

  /// No description provided for @checkInOutAndHistory.
  ///
  /// In en, this message translates to:
  /// **'Check-in/out and view personal attendance history.'**
  String get checkInOutAndHistory;

  /// No description provided for @salaryGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'SALARY CALCULATION GUIDE'**
  String get salaryGuideTitle;

  /// No description provided for @goToPayroll.
  ///
  /// In en, this message translates to:
  /// **'GO TO PAYROLL'**
  String get goToPayroll;

  /// No description provided for @financialManagement.
  ///
  /// In en, this message translates to:
  /// **'FINANCIAL MANAGEMENT'**
  String get financialManagement;

  /// No description provided for @closeCashToday.
  ///
  /// In en, this message translates to:
  /// **'CLOSE CASH TODAY'**
  String get closeCashToday;

  /// No description provided for @reconcileCashAndBank.
  ///
  /// In en, this message translates to:
  /// **'Reconcile cash & bank'**
  String get reconcileCashAndBank;

  /// No description provided for @reportsAndAnalysis.
  ///
  /// In en, this message translates to:
  /// **'REPORTS & ANALYSIS'**
  String get reportsAndAnalysis;

  /// No description provided for @revenueOverview.
  ///
  /// In en, this message translates to:
  /// **'Revenue\nOverview'**
  String get revenueOverview;

  /// No description provided for @financialReport.
  ///
  /// In en, this message translates to:
  /// **'Financial\nReport'**
  String get financialReport;

  /// No description provided for @debtManagement.
  ///
  /// In en, this message translates to:
  /// **'Debt\nManagement'**
  String get debtManagement;

  /// No description provided for @bankInstallmentStats.
  ///
  /// In en, this message translates to:
  /// **'Bank\nInstallment Stats'**
  String get bankInstallmentStats;

  /// No description provided for @warrantyTracking.
  ///
  /// In en, this message translates to:
  /// **'Warranty\nTracking'**
  String get warrantyTracking;

  /// No description provided for @debtManagementIncomeExpense.
  ///
  /// In en, this message translates to:
  /// **'Debt Management (Income/Expense)'**
  String get debtManagementIncomeExpense;

  /// No description provided for @summaryAllTransactions.
  ///
  /// In en, this message translates to:
  /// **'Summary of all income/expense transactions.'**
  String get summaryAllTransactions;

  /// No description provided for @financialLog.
  ///
  /// In en, this message translates to:
  /// **'Financial Log'**
  String get financialLog;

  /// No description provided for @trackAllFinancialActivities.
  ///
  /// In en, this message translates to:
  /// **'Track all financial activities.'**
  String get trackAllFinancialActivities;

  /// No description provided for @shopInfoLogoLocationMembers.
  ///
  /// In en, this message translates to:
  /// **'Shop info, logo, location and member management.'**
  String get shopInfoLogoLocationMembers;

  /// No description provided for @configureNotificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Configure notification and alert settings.'**
  String get configureNotificationSettings;

  /// No description provided for @designPrintTemplates.
  ///
  /// In en, this message translates to:
  /// **'Design print templates for thermal printer.'**
  String get designPrintTemplates;

  /// No description provided for @manageSystemForSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'Manage entire system for super admin.'**
  String get manageSystemForSuperAdmin;

  /// No description provided for @developerAndAppInfo.
  ///
  /// In en, this message translates to:
  /// **'Developer and app information.'**
  String get developerAndAppInfo;

  /// No description provided for @dataSyncComplete.
  ///
  /// In en, this message translates to:
  /// **'Data sync complete'**
  String get dataSyncComplete;

  /// No description provided for @localCloudMatch100.
  ///
  /// In en, this message translates to:
  /// **'Local and Cloud match 100%'**
  String get localCloudMatch100;

  /// No description provided for @needsDataSync.
  ///
  /// In en, this message translates to:
  /// **'Needs data sync'**
  String get needsDataSync;

  /// No description provided for @salesAndRepairOrders.
  ///
  /// In en, this message translates to:
  /// **'sales + repair orders'**
  String get salesAndRepairOrders;

  /// No description provided for @expiringWarrantiesMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} devices expiring warranty. View now!'**
  String expiringWarrantiesMessage(int count);

  /// No description provided for @productsInStock.
  ///
  /// In en, this message translates to:
  /// **'Products in stock'**
  String get productsInStock;

  /// No description provided for @repairOrdersDataItem.
  ///
  /// In en, this message translates to:
  /// **'Repair orders'**
  String get repairOrdersDataItem;

  /// No description provided for @saleOrdersDataItem.
  ///
  /// In en, this message translates to:
  /// **'Sale orders'**
  String get saleOrdersDataItem;

  /// No description provided for @debtsAndExpensesDataItem.
  ///
  /// In en, this message translates to:
  /// **'Debts & Expenses'**
  String get debtsAndExpensesDataItem;

  /// No description provided for @customersAndSuppliersDataItem.
  ///
  /// In en, this message translates to:
  /// **'Customers & Suppliers'**
  String get customersAndSuppliersDataItem;

  /// No description provided for @downloadDataOf.
  ///
  /// In en, this message translates to:
  /// **'Download data of'**
  String get downloadDataOf;

  /// No description provided for @fromCloudToThisDevice.
  ///
  /// In en, this message translates to:
  /// **'from cloud to this device.'**
  String get fromCloudToThisDevice;

  /// No description provided for @onlyDownloadThisShopData.
  ///
  /// In en, this message translates to:
  /// **'Only download this shop\'s data, won\'t affect others.'**
  String get onlyDownloadThisShopData;

  /// No description provided for @processMayTakeFewMinutes.
  ///
  /// In en, this message translates to:
  /// **'Process may take a few minutes depending on data size.'**
  String get processMayTakeFewMinutes;

  /// No description provided for @downloadSuccess.
  ///
  /// In en, this message translates to:
  /// **'Shop data downloaded successfully!'**
  String get downloadSuccess;

  /// No description provided for @downloadError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String downloadError(String error);

  /// No description provided for @dataFullySynced.
  ///
  /// In en, this message translates to:
  /// **'Data fully synced'**
  String get dataFullySynced;

  /// No description provided for @localAndCloudMatched.
  ///
  /// In en, this message translates to:
  /// **'Local and cloud data matched'**
  String get localAndCloudMatched;

  /// No description provided for @syncNeeded.
  ///
  /// In en, this message translates to:
  /// **'Sync needed'**
  String get syncNeeded;

  /// No description provided for @comparingLocalVsCloud.
  ///
  /// In en, this message translates to:
  /// **'Comparing local and cloud data...'**
  String get comparingLocalVsCloud;

  /// No description provided for @saleAndRepairCount.
  ///
  /// In en, this message translates to:
  /// **'{saleCount} sales + {repairCount} repairs'**
  String saleAndRepairCount(int saleCount, int repairCount);

  /// No description provided for @saleAndRepairOrders.
  ///
  /// In en, this message translates to:
  /// **'{saleCount} sales + {repairCount} repairs'**
  String saleAndRepairOrders(int saleCount, int repairCount);

  /// No description provided for @expenseItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} expense items'**
  String expenseItemsCount(int count);

  /// No description provided for @expiringWarrantiesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} devices expiring warranty. View now!'**
  String expiringWarrantiesCount(int count);

  /// No description provided for @registerAccount.
  ///
  /// In en, this message translates to:
  /// **'Account Registration'**
  String get registerAccount;

  /// No description provided for @step.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get step;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @storeOwner.
  ///
  /// In en, this message translates to:
  /// **'Store Owner'**
  String get storeOwner;

  /// No description provided for @createNewShop.
  ///
  /// In en, this message translates to:
  /// **'Create a new shop and manage employees'**
  String get createNewShop;

  /// No description provided for @employee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get employee;

  /// No description provided for @joinExistingShop.
  ///
  /// In en, this message translates to:
  /// **'Join an existing shop via invitation code'**
  String get joinExistingShop;

  /// No description provided for @shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop Name'**
  String get shopName;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @loginEmail.
  ///
  /// In en, this message translates to:
  /// **'Login Email'**
  String get loginEmail;

  /// No description provided for @emailAutoGenerated.
  ///
  /// In en, this message translates to:
  /// **'Email is automatically generated from name and shop name'**
  String get emailAutoGenerated;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @shopInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Shop Invitation Code'**
  String get shopInviteCode;

  /// No description provided for @howToGetInviteCode.
  ///
  /// In en, this message translates to:
  /// **'HOW TO GET INVITATION CODE'**
  String get howToGetInviteCode;

  /// No description provided for @joinShopInstructions.
  ///
  /// In en, this message translates to:
  /// **'To join a shop, please ask the store owner to follow these steps:'**
  String get joinShopInstructions;

  /// No description provided for @storeOwnerLogin.
  ///
  /// In en, this message translates to:
  /// **'Store owner logs into the app'**
  String get storeOwnerLogin;

  /// No description provided for @selectStaffTab.
  ///
  /// In en, this message translates to:
  /// **'Select the \'Staff\' tab in bottom navigation'**
  String get selectStaffTab;

  /// No description provided for @selectEmployeeList.
  ///
  /// In en, this message translates to:
  /// **'Select \'Employee List\''**
  String get selectEmployeeList;

  /// No description provided for @selectRegisterEmployee.
  ///
  /// In en, this message translates to:
  /// **'Select register account for shop employee'**
  String get selectRegisterEmployee;

  /// No description provided for @ownerProvidesCredentials.
  ///
  /// In en, this message translates to:
  /// **'Store owner provides account and password to you'**
  String get ownerProvidesCredentials;

  /// No description provided for @loginWithCredentials.
  ///
  /// In en, this message translates to:
  /// **'After having account and password, you can log in and join the shop.'**
  String get loginWithCredentials;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'REGISTER'**
  String get register;

  /// No description provided for @step1of2.
  ///
  /// In en, this message translates to:
  /// **'Step 1/2'**
  String get step1of2;

  /// No description provided for @step2of2.
  ///
  /// In en, this message translates to:
  /// **'Step 2/2'**
  String get step2of2;

  /// No description provided for @printerSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Printer settings saved'**
  String get printerSettingsSaved;

  /// No description provided for @bluetoothPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission required'**
  String get bluetoothPermissionRequired;

  /// No description provided for @enableBluetoothToScan.
  ///
  /// In en, this message translates to:
  /// **'Enable Bluetooth to scan printers'**
  String get enableBluetoothToScan;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found. Pair first in Bluetooth settings.'**
  String get noDevicesFound;

  /// No description provided for @bluetoothScanError.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth scan error: {error}'**
  String bluetoothScanError(String error);

  /// No description provided for @selectBluetoothPrinter.
  ///
  /// In en, this message translates to:
  /// **'Select Bluetooth Printer'**
  String get selectBluetoothPrinter;

  /// No description provided for @enterIpFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter IP address first'**
  String get enterIpFirst;

  /// No description provided for @testingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get testingConnection;

  /// No description provided for @connectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get connectionSuccessful;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect: {error}'**
  String connectionFailed(String error);

  /// No description provided for @selectBluetoothPrinterFirst.
  ///
  /// In en, this message translates to:
  /// **'Select Bluetooth printer first'**
  String get selectBluetoothPrinterFirst;

  /// No description provided for @bluetoothConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connection successful!'**
  String get bluetoothConnectionSuccessful;

  /// No description provided for @bluetoothConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect Bluetooth'**
  String get bluetoothConnectionFailed;

  /// No description provided for @printerSettings.
  ///
  /// In en, this message translates to:
  /// **'PRINTER SETTINGS'**
  String get printerSettings;

  /// No description provided for @labelDesign.
  ///
  /// In en, this message translates to:
  /// **'LABEL DESIGN'**
  String get labelDesign;

  /// No description provided for @wifiPrinterConnection.
  ///
  /// In en, this message translates to:
  /// **'WIFI PRINTER CONNECTION'**
  String get wifiPrinterConnection;

  /// No description provided for @bluetoothPrinterConnection.
  ///
  /// In en, this message translates to:
  /// **'BLUETOOTH PRINTER CONNECTION'**
  String get bluetoothPrinterConnection;

  /// No description provided for @receiptSettings.
  ///
  /// In en, this message translates to:
  /// **'RECEIPT SETTINGS'**
  String get receiptSettings;

  /// No description provided for @productLabelDesign.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT LABEL DESIGN'**
  String get productLabelDesign;

  /// No description provided for @customizeContentAndFontSize.
  ///
  /// In en, this message translates to:
  /// **'Customize content and font size'**
  String get customizeContentAndFontSize;

  /// No description provided for @layoutShopInfoFormula.
  ///
  /// In en, this message translates to:
  /// **'Layout, shop info, CPK formula'**
  String get layoutShopInfoFormula;

  /// No description provided for @hot.
  ///
  /// In en, this message translates to:
  /// **'HOT'**
  String get hot;

  /// No description provided for @wifiPrinter.
  ///
  /// In en, this message translates to:
  /// **'WIFI PRINTER'**
  String get wifiPrinter;

  /// No description provided for @printerIpAddress.
  ///
  /// In en, this message translates to:
  /// **'Printer IP address'**
  String get printerIpAddress;

  /// No description provided for @backupIpOptional.
  ///
  /// In en, this message translates to:
  /// **'Backup IP (optional)'**
  String get backupIpOptional;

  /// No description provided for @testWifiConnection.
  ///
  /// In en, this message translates to:
  /// **'TEST WIFI CONNECTION'**
  String get testWifiConnection;

  /// No description provided for @bluetoothPrinter.
  ///
  /// In en, this message translates to:
  /// **'BLUETOOTH PRINTER'**
  String get bluetoothPrinter;

  /// No description provided for @noBluetoothPrinterSelected.
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth printer selected'**
  String get noBluetoothPrinterSelected;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'SCANNING...'**
  String get scanning;

  /// No description provided for @scanBluetooth.
  ///
  /// In en, this message translates to:
  /// **'SCAN BLUETOOTH'**
  String get scanBluetooth;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'TEST'**
  String get test;

  /// No description provided for @receiptSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'RECEIPT SETTINGS'**
  String get receiptSettingsTitle;

  /// No description provided for @showShopLogo.
  ///
  /// In en, this message translates to:
  /// **'Show shop logo'**
  String get showShopLogo;

  /// No description provided for @showPhoneAndAddress.
  ///
  /// In en, this message translates to:
  /// **'Show phone & address'**
  String get showPhoneAndAddress;

  /// No description provided for @showQrCodeLookup.
  ///
  /// In en, this message translates to:
  /// **'Show QR code lookup'**
  String get showQrCodeLookup;

  /// No description provided for @receiptClosingMessage.
  ///
  /// In en, this message translates to:
  /// **'Receipt closing message'**
  String get receiptClosingMessage;

  /// No description provided for @thankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get thankYou;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {deviceName}'**
  String selected(String deviceName);

  /// No description provided for @learnHowToUseApp.
  ///
  /// In en, this message translates to:
  /// **'Learn how to use the Shopmanager app'**
  String get learnHowToUseApp;

  /// No description provided for @searchGuides.
  ///
  /// In en, this message translates to:
  /// **'Search guides...'**
  String get searchGuides;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get newLabel;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @easy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get easy;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @tryDifferentKeywords.
  ///
  /// In en, this message translates to:
  /// **'Try searching with different keywords'**
  String get tryDifferentKeywords;

  /// No description provided for @foundResults.
  ///
  /// In en, this message translates to:
  /// **'Found {count} results'**
  String foundResults(int count);

  /// No description provided for @needMoreHelp.
  ///
  /// In en, this message translates to:
  /// **'Need more help?'**
  String get needMoreHelp;

  /// No description provided for @supportTeamReady.
  ///
  /// In en, this message translates to:
  /// **'If you can\'t find the answer, our support team is ready to help.'**
  String get supportTeamReady;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'support@huluca.com'**
  String get supportEmail;

  /// No description provided for @hotline.
  ///
  /// In en, this message translates to:
  /// **'Hotline: 1900 xxxx'**
  String get hotline;

  /// No description provided for @supportHotline.
  ///
  /// In en, this message translates to:
  /// **'Support hotline: 1900 xxxx'**
  String get supportHotline;

  /// No description provided for @stepsToPerform.
  ///
  /// In en, this message translates to:
  /// **'Steps to perform'**
  String get stepsToPerform;

  /// No description provided for @usefulTips.
  ///
  /// In en, this message translates to:
  /// **'💡 Useful tips'**
  String get usefulTips;

  /// No description provided for @importantNotes.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Important notes'**
  String get importantNotes;

  /// No description provided for @relatedArticles.
  ///
  /// In en, this message translates to:
  /// **'📚 Related articles'**
  String get relatedArticles;

  /// No description provided for @wasArticleHelpful.
  ///
  /// In en, this message translates to:
  /// **'Was this article helpful?'**
  String get wasArticleHelpful;

  /// No description provided for @thankYouForFeedback.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback! 🎉'**
  String get thankYouForFeedback;

  /// No description provided for @weWillImprove.
  ///
  /// In en, this message translates to:
  /// **'We will improve this content!'**
  String get weWillImprove;

  /// No description provided for @notYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get notYet;

  /// No description provided for @stepsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String stepsCount(int count);

  /// No description provided for @information.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get information;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get skip;

  /// No description provided for @welcomeToShopManager.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Shop Manager'**
  String get welcomeToShopManager;

  /// No description provided for @welcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'Multi-industry shop management: Electronics, Food, Fashion & more. Easy to use, powerful and efficient for all business needs.'**
  String get welcomeDesc;

  /// No description provided for @professionalSalesManagement.
  ///
  /// In en, this message translates to:
  /// **'Professional Sales Management'**
  String get professionalSalesManagement;

  /// No description provided for @salesDesc.
  ///
  /// In en, this message translates to:
  /// **'Create sales orders quickly, track revenue, manage customers and product warranties easily.'**
  String get salesDesc;

  /// No description provided for @repairAndWarranty.
  ///
  /// In en, this message translates to:
  /// **'Repair & Warranty'**
  String get repairAndWarranty;

  /// No description provided for @repairDesc.
  ///
  /// In en, this message translates to:
  /// **'Track repair progress, manage parts, update order status and handle warranties efficiently.'**
  String get repairDesc;

  /// No description provided for @smartInventoryManagement.
  ///
  /// In en, this message translates to:
  /// **'Smart Inventory Management'**
  String get smartInventoryManagement;

  /// No description provided for @inventoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Ultra-fast inventory input with QR code and IMEI. 100% accurate inventory control with automatic inventory system.'**
  String get inventoryDesc;

  /// No description provided for @staffAndAttendance.
  ///
  /// In en, this message translates to:
  /// **'Staff & Attendance'**
  String get staffAndAttendance;

  /// No description provided for @staffDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage employees, track attendance with selfie, calculate salary and evaluate work performance.'**
  String get staffDesc;

  /// No description provided for @financeAndReports.
  ///
  /// In en, this message translates to:
  /// **'Finance & Reports'**
  String get financeAndReports;

  /// No description provided for @financeDesc.
  ///
  /// In en, this message translates to:
  /// **'View detailed revenue reports, manage expenses, track debts and comprehensive financial analysis.'**
  String get financeDesc;

  /// No description provided for @internalChatAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Internal Chat & Notifications'**
  String get internalChatAndNotifications;

  /// No description provided for @chatDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time communication with staff, instant notifications and management of general shop information.'**
  String get chatDesc;

  /// No description provided for @printReceiptsAndDeviceConnection.
  ///
  /// In en, this message translates to:
  /// **'Print Receipts & Device Connection'**
  String get printReceiptsAndDeviceConnection;

  /// No description provided for @printDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect Bluetooth/WiFi thermal printers. Print professional labels and receipts with one touch.'**
  String get printDesc;

  /// No description provided for @cloudSync247.
  ///
  /// In en, this message translates to:
  /// **'24/7 Cloud Sync'**
  String get cloudSync247;

  /// No description provided for @cloudDesc.
  ///
  /// In en, this message translates to:
  /// **'Data always safe and synchronized instantly between all devices. Manage shop remotely anytime, anywhere.'**
  String get cloudDesc;

  /// No description provided for @startJourney.
  ///
  /// In en, this message translates to:
  /// **'Start Your Journey'**
  String get startJourney;

  /// No description provided for @startDesc.
  ///
  /// In en, this message translates to:
  /// **'Explore all features and manage your shop efficiently. Wish you success!'**
  String get startDesc;

  /// No description provided for @hulucaShop.
  ///
  /// In en, this message translates to:
  /// **'HULUCA SHOP'**
  String get hulucaShop;

  /// No description provided for @phoneRepairShopManagement.
  ///
  /// In en, this message translates to:
  /// **'Multi-Industry Shop Management'**
  String get phoneRepairShopManagement;

  /// No description provided for @repairManagement.
  ///
  /// In en, this message translates to:
  /// **'Repair Management'**
  String get repairManagement;

  /// No description provided for @repairManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Track repair orders from receiving to delivery'**
  String get repairManagementDesc;

  /// No description provided for @inventoryManagement.
  ///
  /// In en, this message translates to:
  /// **'Inventory Management'**
  String get inventoryManagement;

  /// No description provided for @inventoryManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Import goods, export inventory, check parts'**
  String get inventoryManagementDesc;

  /// No description provided for @salesAndDebt.
  ///
  /// In en, this message translates to:
  /// **'Sales & Debt'**
  String get salesAndDebt;

  /// No description provided for @salesAndDebtDesc.
  ///
  /// In en, this message translates to:
  /// **'Fast sales, track customer debt'**
  String get salesAndDebtDesc;

  /// No description provided for @supplierAndPartnerManagement.
  ///
  /// In en, this message translates to:
  /// **'Supplier & Partner Management'**
  String get supplierAndPartnerManagement;

  /// No description provided for @supplierAndPartnerManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Track supplier and partner debt'**
  String get supplierAndPartnerManagementDesc;

  /// No description provided for @reportsAndStatistics.
  ///
  /// In en, this message translates to:
  /// **'Reports & Statistics'**
  String get reportsAndStatistics;

  /// No description provided for @reportsAndStatisticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Revenue, profit, inventory over time'**
  String get reportsAndStatisticsDesc;

  /// No description provided for @cloudSync.
  ///
  /// In en, this message translates to:
  /// **'Cloud Sync'**
  String get cloudSync;

  /// No description provided for @cloudSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Safe data, access anytime, anywhere'**
  String get cloudSyncDesc;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version 10.0.9'**
  String get version;

  /// No description provided for @salaryCalculationGuide.
  ///
  /// In en, this message translates to:
  /// **'SALARY CALCULATION GUIDE'**
  String get salaryCalculationGuide;

  /// No description provided for @accessSalaryTable.
  ///
  /// In en, this message translates to:
  /// **'Access salary table'**
  String get accessSalaryTable;

  /// No description provided for @accessSalaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Go to Staff tab → Press \"SALARY Calculate salary\" to view all employees\' salary table.'**
  String get accessSalaryDesc;

  /// No description provided for @salarySettings.
  ///
  /// In en, this message translates to:
  /// **'Salary settings'**
  String get salarySettings;

  /// No description provided for @salarySettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'• Default settings: ⚙️ icon → \"DEFAULT\" tab\n• Individual settings: \"EMPLOYEES\" tab → Select employee → \"Individual settings\"'**
  String get salarySettingsDesc;

  /// No description provided for @salaryComponents.
  ///
  /// In en, this message translates to:
  /// **'Salary components'**
  String get salaryComponents;

  /// No description provided for @salaryComponentsDesc.
  ///
  /// In en, this message translates to:
  /// **'• Basic salary (monthly/daily/hourly)\n• Sales commission (% or fixed)\n• Repair commission\n• Allowances (travel, lunch, phone...)\n• Overtime OT (150%, 200% rates...)'**
  String get salaryComponentsDesc;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @viewDetailsDesc.
  ///
  /// In en, this message translates to:
  /// **'Click on employee name to view:\n• INCOME: Salary + Commission + Allowances + Bonus + OT\n• DEDUCTIONS: PIT + SI + HI + UI\n• NET PAY: Total income - Total deductions'**
  String get viewDetailsDesc;

  /// No description provided for @printSalarySlip.
  ///
  /// In en, this message translates to:
  /// **'Print salary slip'**
  String get printSalarySlip;

  /// No description provided for @printSalaryDesc.
  ///
  /// In en, this message translates to:
  /// **'• Print summary: 🖨️ icon → \"Print consolidated salary table\"\n• Print individual: Open employee details → \"Print salary slip\"'**
  String get printSalaryDesc;

  /// No description provided for @taxAndInsurance.
  ///
  /// In en, this message translates to:
  /// **'Tax & Insurance'**
  String get taxAndInsurance;

  /// No description provided for @taxAndInsuranceDesc.
  ///
  /// In en, this message translates to:
  /// **'💳 \"Deduction/Tax Settings\" icon:\n• Personal deduction: 11 million\n• SI 8%, HI 1.5%, UI 1%'**
  String get taxAndInsuranceDesc;

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'UNDERSTOOD'**
  String get understood;

  /// No description provided for @goToSalaryTable.
  ///
  /// In en, this message translates to:
  /// **'GO TO SALARY TABLE'**
  String get goToSalaryTable;

  /// No description provided for @staffListLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff\nList'**
  String get staffListLabel;

  /// No description provided for @viewAttendanceAllStaff.
  ///
  /// In en, this message translates to:
  /// **'View attendance of all staff by day/month.'**
  String get viewAttendanceAllStaff;

  /// No description provided for @personalAttendanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Check-in/out and view personal attendance history.'**
  String get personalAttendanceDescription;

  /// No description provided for @usageGuide.
  ///
  /// In en, this message translates to:
  /// **'Usage guide'**
  String get usageGuide;

  /// No description provided for @cashClosingToday.
  ///
  /// In en, this message translates to:
  /// **'CASH CLOSING TODAY'**
  String get cashClosingToday;

  /// No description provided for @reportAndAnalysis.
  ///
  /// In en, this message translates to:
  /// **'REPORTS & ANALYSIS'**
  String get reportAndAnalysis;

  /// No description provided for @manageAllTransactions.
  ///
  /// In en, this message translates to:
  /// **'Manage all income/expense transactions.'**
  String get manageAllTransactions;

  /// No description provided for @expenseManagement.
  ///
  /// In en, this message translates to:
  /// **'Expense Management'**
  String get expenseManagement;

  /// No description provided for @addTrackShopExpenses.
  ///
  /// In en, this message translates to:
  /// **'Add and track shop expenses.'**
  String get addTrackShopExpenses;

  /// No description provided for @debtManagementInOut.
  ///
  /// In en, this message translates to:
  /// **'Debt Management (In/Out)'**
  String get debtManagementInOut;

  /// No description provided for @recordPayDebts.
  ///
  /// In en, this message translates to:
  /// **'Record and pay debts.'**
  String get recordPayDebts;

  /// No description provided for @financialReportLabel.
  ///
  /// In en, this message translates to:
  /// **'Financial Report'**
  String get financialReportLabel;

  /// No description provided for @summarizeAllTransactions.
  ///
  /// In en, this message translates to:
  /// **'Summarize all income/expense transactions.'**
  String get summarizeAllTransactions;

  /// No description provided for @financialActivityLog.
  ///
  /// In en, this message translates to:
  /// **'Financial Activity Log'**
  String get financialActivityLog;

  /// No description provided for @trackAllIncomeExpenseActivities.
  ///
  /// In en, this message translates to:
  /// **'Track all income/expense activities.'**
  String get trackAllIncomeExpenseActivities;

  /// No description provided for @todayIncome.
  ///
  /// In en, this message translates to:
  /// **'TODAY INCOME'**
  String get todayIncome;

  /// No description provided for @todayExpense.
  ///
  /// In en, this message translates to:
  /// **'TODAY EXPENSE'**
  String get todayExpense;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'sales'**
  String get sales;

  /// No description provided for @repair.
  ///
  /// In en, this message translates to:
  /// **'repair'**
  String get repair;

  /// No description provided for @expenseItems.
  ///
  /// In en, this message translates to:
  /// **'expense items'**
  String get expenseItems;

  /// No description provided for @todayNetProfit.
  ///
  /// In en, this message translates to:
  /// **'TODAY NET PROFIT'**
  String get todayNetProfit;

  /// No description provided for @totalDebt.
  ///
  /// In en, this message translates to:
  /// **'TOTAL DEBT'**
  String get totalDebt;

  /// No description provided for @shopSettings.
  ///
  /// In en, this message translates to:
  /// **'Shop Settings'**
  String get shopSettings;

  /// No description provided for @shopSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Information, logo, location and shop member management.'**
  String get shopSettingsDescription;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @notificationSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure notification and alert settings.'**
  String get notificationSettingsDescription;

  /// No description provided for @printer.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get printer;

  /// No description provided for @printerSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Setup connection and print template design.'**
  String get printerSettingsDescription;

  /// No description provided for @adminCenter.
  ///
  /// In en, this message translates to:
  /// **'Admin Center'**
  String get adminCenter;

  /// No description provided for @adminCenterDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage entire system for super admin.'**
  String get adminCenterDescription;

  /// No description provided for @aboutDeveloperDescription.
  ///
  /// In en, this message translates to:
  /// **'Information about developer and application.'**
  String get aboutDeveloperDescription;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'LOGOUT'**
  String get logout;

  /// No description provided for @logoutFromAccount.
  ///
  /// In en, this message translates to:
  /// **'Logout from account'**
  String get logoutFromAccount;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout from this account?'**
  String get logoutConfirmMessage;

  /// No description provided for @needSyncData.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Need data sync'**
  String get needSyncData;

  /// No description provided for @recordsNotSynced.
  ///
  /// In en, this message translates to:
  /// **'records not synced. Tap to open Sync Center.'**
  String recordsNotSynced(int count);

  /// No description provided for @todayFinancialReport.
  ///
  /// In en, this message translates to:
  /// **'TODAY FINANCIAL REPORT'**
  String get todayFinancialReport;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @saleOrders.
  ///
  /// In en, this message translates to:
  /// **'sale orders'**
  String get saleOrders;

  /// No description provided for @repairOrders.
  ///
  /// In en, this message translates to:
  /// **'repair orders'**
  String get repairOrders;

  /// No description provided for @todayActivity.
  ///
  /// In en, this message translates to:
  /// **'TODAY ACTIVITY'**
  String get todayActivity;

  /// No description provided for @pendingRepairs.
  ///
  /// In en, this message translates to:
  /// **'Pending repairs'**
  String get pendingRepairs;

  /// No description provided for @netProfitFormula.
  ///
  /// In en, this message translates to:
  /// **'= Income - Expense - Cost'**
  String get netProfitFormula;

  /// No description provided for @userGuide.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get userGuide;

  /// No description provided for @viewDetailedGuideForEachFeature.
  ///
  /// In en, this message translates to:
  /// **'View detailed guide for each feature in app'**
  String get viewDetailedGuideForEachFeature;

  /// No description provided for @warrantyReminder.
  ///
  /// In en, this message translates to:
  /// **'WARRANTY REMINDER'**
  String get warrantyReminder;

  /// No description provided for @devicesExpiringWarranty.
  ///
  /// In en, this message translates to:
  /// **'devices expiring warranty soon. View now!'**
  String get devicesExpiringWarranty;

  /// No description provided for @checkingSync.
  ///
  /// In en, this message translates to:
  /// **'Checking sync...'**
  String get checkingSync;

  /// No description provided for @checkingLocalVsCloud.
  ///
  /// In en, this message translates to:
  /// **'Checking local vs cloud data'**
  String get checkingLocalVsCloud;

  /// No description provided for @dataSyncedFully.
  ///
  /// In en, this message translates to:
  /// **'✅ Data synced fully'**
  String get dataSyncedFully;

  /// No description provided for @localCloudMatched.
  ///
  /// In en, this message translates to:
  /// **'Local and Cloud matched 100%'**
  String get localCloudMatched;

  /// No description provided for @recheckingSync.
  ///
  /// In en, this message translates to:
  /// **'🔄 Rechecking...'**
  String get recheckingSync;

  /// No description provided for @exitApp.
  ///
  /// In en, this message translates to:
  /// **'Exit app?'**
  String get exitApp;

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'EXIT'**
  String get exit;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered by someone else.'**
  String get emailAlreadyInUse;

  /// No description provided for @weakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password too weak, at least 6 characters required.'**
  String get weakPassword;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address format.'**
  String get invalidEmailAddress;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network connection error. Please check your internet and try again.'**
  String get networkError;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get tooManyRequests;

  /// No description provided for @pleaseEnterShopName.
  ///
  /// In en, this message translates to:
  /// **'Please enter shop name.'**
  String get pleaseEnterShopName;

  /// No description provided for @pleaseEnterFullName.
  ///
  /// In en, this message translates to:
  /// **'Please enter full name.'**
  String get pleaseEnterFullName;

  /// No description provided for @pleaseEnterRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in required fields.'**
  String get pleaseEnterRequiredFields;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Password confirmation does not match.'**
  String get passwordMismatch;

  /// No description provided for @invalidOrExpiredInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code is incorrect or expired.'**
  String get invalidOrExpiredInviteCode;

  /// No description provided for @loadingShopData.
  ///
  /// In en, this message translates to:
  /// **'Loading shop data...'**
  String get loadingShopData;

  /// No description provided for @switchedToShop.
  ///
  /// In en, this message translates to:
  /// **'Switched to shop: {shopName}'**
  String switchedToShop(String shopName);

  /// No description provided for @errorSwitchingShop.
  ///
  /// In en, this message translates to:
  /// **'Error switching shop: {error}'**
  String errorSwitchingShop(String error);

  /// No description provided for @onlySuperAdminCanDelete.
  ///
  /// In en, this message translates to:
  /// **'ONLY SUPER ADMIN CAN DELETE SHOP DATA!'**
  String get onlySuperAdminCanDelete;

  /// No description provided for @dangerWarning.
  ///
  /// In en, this message translates to:
  /// **'⚠️ DANGER WARNING'**
  String get dangerWarning;

  /// No description provided for @deleteAllDataWarning.
  ///
  /// In en, this message translates to:
  /// **'This action will delete 100% of Orders, Inventory, Debts and Logs of the Shop on both Cloud and this Device. CANNOT BE RECOVERED!'**
  String get deleteAllDataWarning;

  /// No description provided for @typeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type \'DELETE ALL\' to confirm:'**
  String get typeToConfirm;

  /// No description provided for @deleteAllPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'DELETE ALL'**
  String get deleteAllPlaceholder;

  /// No description provided for @confirmDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM DELETE ALL'**
  String get confirmDeleteAll;

  /// No description provided for @shopDataDeleted.
  ///
  /// In en, this message translates to:
  /// **'SHOP DATA DELETED!'**
  String get shopDataDeleted;

  /// No description provided for @errorDeletingCloudData.
  ///
  /// In en, this message translates to:
  /// **'ERROR DELETING CLOUD DATA: {error}'**
  String errorDeletingCloudData(String error);

  /// No description provided for @userGuideSection.
  ///
  /// In en, this message translates to:
  /// **'📚 User Guide'**
  String get userGuideSection;

  /// No description provided for @userGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get userGuideTitle;

  /// No description provided for @userGuideDesc.
  ///
  /// In en, this message translates to:
  /// **'Detailed step-by-step guide for every feature in the app.'**
  String get userGuideDesc;

  /// No description provided for @inventoryFeature.
  ///
  /// In en, this message translates to:
  /// **'📦 Inventory'**
  String get inventoryFeature;

  /// No description provided for @salesFeature.
  ///
  /// In en, this message translates to:
  /// **'🛒 Sales'**
  String get salesFeature;

  /// No description provided for @repairFeature.
  ///
  /// In en, this message translates to:
  /// **'🔧 Repair'**
  String get repairFeature;

  /// No description provided for @reportFeature.
  ///
  /// In en, this message translates to:
  /// **'📊 Reports'**
  String get reportFeature;

  /// No description provided for @reviewUserGuide.
  ///
  /// In en, this message translates to:
  /// **'Review User Guide'**
  String get reviewUserGuide;

  /// No description provided for @resetGuidesDesc.
  ///
  /// In en, this message translates to:
  /// **'Reset to show first-time guides again'**
  String get resetGuidesDesc;

  /// No description provided for @guidesReset.
  ///
  /// In en, this message translates to:
  /// **'Done! Guides will show again when entering screens.'**
  String get guidesReset;

  /// No description provided for @changedToVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Changed to Vietnamese'**
  String get changedToVietnamese;

  /// No description provided for @changedToEnglish.
  ///
  /// In en, this message translates to:
  /// **'Changed to English'**
  String get changedToEnglish;

  /// No description provided for @replacePin.
  ///
  /// In en, this message translates to:
  /// **'REPLACE PIN'**
  String get replacePin;

  /// No description provided for @pressGlass.
  ///
  /// In en, this message translates to:
  /// **'PRESS GLASS'**
  String get pressGlass;

  /// No description provided for @replaceScreen.
  ///
  /// In en, this message translates to:
  /// **'REPLACE SCREEN'**
  String get replaceScreen;

  /// No description provided for @noPower.
  ///
  /// In en, this message translates to:
  /// **'NO POWER'**
  String get noPower;

  /// No description provided for @speakerMic.
  ///
  /// In en, this message translates to:
  /// **'SPEAKER/MIC'**
  String get speakerMic;

  /// No description provided for @charging.
  ///
  /// In en, this message translates to:
  /// **'CHARGING'**
  String get charging;

  /// No description provided for @software.
  ///
  /// In en, this message translates to:
  /// **'SOFTWARE'**
  String get software;

  /// No description provided for @sim.
  ///
  /// In en, this message translates to:
  /// **'SIM'**
  String get sim;

  /// No description provided for @backCover.
  ///
  /// In en, this message translates to:
  /// **'BACK COVER'**
  String get backCover;

  /// No description provided for @walkInCustomerNoSave.
  ///
  /// In en, this message translates to:
  /// **'Walk-in customer - not saved to contacts'**
  String get walkInCustomerNoSave;

  /// No description provided for @pleaseEnterNameAndPhone.
  ///
  /// In en, this message translates to:
  /// **'Please enter both name and phone number'**
  String get pleaseEnterNameAndPhone;

  /// No description provided for @customerWithPhoneExists.
  ///
  /// In en, this message translates to:
  /// **'Customer with this phone already exists: {name}'**
  String customerWithPhoneExists(String name);

  /// No description provided for @customerAdded.
  ///
  /// In en, this message translates to:
  /// **'Customer added: {name}'**
  String customerAdded(String name);

  /// No description provided for @errorAddingCustomer.
  ///
  /// In en, this message translates to:
  /// **'Error adding customer: {error}'**
  String errorAddingCustomer(String error);

  /// No description provided for @pleaseEnterModel.
  ///
  /// In en, this message translates to:
  /// **'Please enter device Model'**
  String get pleaseEnterModel;

  /// No description provided for @pleaseEnterPhoneAndModel.
  ///
  /// In en, this message translates to:
  /// **'Please enter Phone and device Model'**
  String get pleaseEnterPhoneAndModel;

  /// No description provided for @syncingDataToServer.
  ///
  /// In en, this message translates to:
  /// **'Syncing data to server...'**
  String get syncingDataToServer;

  /// No description provided for @createRepairOrder.
  ///
  /// In en, this message translates to:
  /// **'CREATE REPAIR'**
  String get createRepairOrder;

  /// No description provided for @repairOrderCreated.
  ///
  /// In en, this message translates to:
  /// **'Created repair order {model} for customer {customer}'**
  String repairOrderCreated(String model, String customer);

  /// No description provided for @orderSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'ORDER SAVED SUCCESSFULLY'**
  String get orderSavedSuccess;

  /// No description provided for @sendingPrintCommand.
  ///
  /// In en, this message translates to:
  /// **'Sending print command...'**
  String get sendingPrintCommand;

  /// No description provided for @partnerCost.
  ///
  /// In en, this message translates to:
  /// **'Partner: {partner} - Cost: {cost}'**
  String partnerCost(String partner, String cost);

  /// No description provided for @costOnly.
  ///
  /// In en, this message translates to:
  /// **'Cost: {cost}'**
  String costOnly(String cost);

  /// No description provided for @totalCost.
  ///
  /// In en, this message translates to:
  /// **'Total cost: {amount}'**
  String totalCost(String amount);

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'ADD SERVICE'**
  String get addService;

  /// No description provided for @serviceName.
  ///
  /// In en, this message translates to:
  /// **'Service name *'**
  String get serviceName;

  /// No description provided for @costVND.
  ///
  /// In en, this message translates to:
  /// **'Cost (VND)'**
  String get costVND;

  /// No description provided for @partnerOptional.
  ///
  /// In en, this message translates to:
  /// **'Partner (optional)'**
  String get partnerOptional;

  /// No description provided for @noPartner.
  ///
  /// In en, this message translates to:
  /// **'No partner'**
  String get noPartner;

  /// No description provided for @partnerPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Partner payment method *'**
  String get partnerPaymentMethod;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @saveOrder.
  ///
  /// In en, this message translates to:
  /// **'SAVE ORDER'**
  String get saveOrder;

  /// No description provided for @customerAndDevice.
  ///
  /// In en, this message translates to:
  /// **'CUSTOMER & DEVICE'**
  String get customerAndDevice;

  /// No description provided for @phoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get phoneOptional;

  /// No description provided for @phoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone *'**
  String get phoneRequired;

  /// No description provided for @customerNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Customer name (optional)'**
  String get customerNameOptional;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerName;

  /// No description provided for @deviceModel.
  ///
  /// In en, this message translates to:
  /// **'DEVICE MODEL *'**
  String get deviceModel;

  /// No description provided for @deviceIssue.
  ///
  /// In en, this message translates to:
  /// **'DEVICE ISSUE *'**
  String get deviceIssue;

  /// No description provided for @estimatedPrice.
  ///
  /// In en, this message translates to:
  /// **'ESTIMATED PRICE'**
  String get estimatedPrice;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'SERVICES'**
  String get services;

  /// No description provided for @securityAccessories.
  ///
  /// In en, this message translates to:
  /// **'SECURITY & ACCESSORIES'**
  String get securityAccessories;

  /// No description provided for @screenPassword.
  ///
  /// In en, this message translates to:
  /// **'Screen password'**
  String get screenPassword;

  /// No description provided for @otherAccessories.
  ///
  /// In en, this message translates to:
  /// **'Other accessories'**
  String get otherAccessories;

  /// No description provided for @notesAndImages.
  ///
  /// In en, this message translates to:
  /// **'NOTES & IMAGES'**
  String get notesAndImages;

  /// No description provided for @notesPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Notes...'**
  String get notesPlaceholder;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in customer (not saved to contacts)'**
  String get walkInCustomer;

  /// No description provided for @walkInCustomerDesc.
  ///
  /// In en, this message translates to:
  /// **'Name/Phone only saved on receipt, phone not required'**
  String get walkInCustomerDesc;

  /// No description provided for @saveToContactsDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter phone to save customer to contacts'**
  String get saveToContactsDesc;

  /// No description provided for @walkInCustomerDefault.
  ///
  /// In en, this message translates to:
  /// **'WALK-IN CUSTOMER'**
  String get walkInCustomerDefault;

  /// No description provided for @createRepairOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATE REPAIR ORDER'**
  String get createRepairOrderTitle;

  /// No description provided for @fillCustomerAndDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Fill customer and device info'**
  String get fillCustomerAndDeviceInfo;

  /// No description provided for @selectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Select customer'**
  String get selectCustomer;

  /// No description provided for @todayClosedNoRepair.
  ///
  /// In en, this message translates to:
  /// **'❌ Today is closed! Cannot create new repair order.'**
  String get todayClosedNoRepair;

  /// No description provided for @selectCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'SELECT CUSTOMER'**
  String get selectCustomerTitle;

  /// No description provided for @searchByNameOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone...'**
  String get searchByNameOrPhone;

  /// No description provided for @noCustomerFound.
  ///
  /// In en, this message translates to:
  /// **'No customer found'**
  String get noCustomerFound;

  /// No description provided for @repairInputAction.
  ///
  /// In en, this message translates to:
  /// **'CREATE REPAIR ORDER'**
  String get repairInputAction;

  /// No description provided for @repairInputDesc.
  ///
  /// In en, this message translates to:
  /// **'Created repair order {model} for customer {customer}'**
  String repairInputDesc(String model, String customer);

  /// No description provided for @repairPartner.
  ///
  /// In en, this message translates to:
  /// **'Repair partner'**
  String get repairPartner;

  /// No description provided for @resetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset all'**
  String get resetAll;

  /// No description provided for @repairing.
  ///
  /// In en, this message translates to:
  /// **'Repairing'**
  String get repairing;

  /// No description provided for @repairDone.
  ///
  /// In en, this message translates to:
  /// **'Repair done'**
  String get repairDone;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @selectedStatuses.
  ///
  /// In en, this message translates to:
  /// **'Selected: {count} statuses'**
  String selectedStatuses(int count);

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get apply;

  /// No description provided for @orderHasAccounting.
  ///
  /// In en, this message translates to:
  /// **'Order has accounting data:\n• Price: {price}\n• Cost: {cost}'**
  String orderHasAccounting(String price, String cost);

  /// No description provided for @orderHasParts.
  ///
  /// In en, this message translates to:
  /// **'Order has parts:'**
  String get orderHasParts;

  /// No description provided for @statusRepairing.
  ///
  /// In en, this message translates to:
  /// **'REPAIRING'**
  String get statusRepairing;

  /// No description provided for @statusRepairDone.
  ///
  /// In en, this message translates to:
  /// **'REPAIR DONE'**
  String get statusRepairDone;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'DELIVERED'**
  String get statusDelivered;

  /// No description provided for @deletedRepairDesc.
  ///
  /// In en, this message translates to:
  /// **'Deleted repair {model} - {customer} - {phone}{partsInfo}'**
  String deletedRepairDesc(String model, String customer, String phone, String partsInfo);

  /// No description provided for @returnedParts.
  ///
  /// In en, this message translates to:
  /// **' (returned parts: {parts})'**
  String returnedParts(String parts);

  /// No description provided for @displayedRepairs.
  ///
  /// In en, this message translates to:
  /// **'Displayed {count} repair orders'**
  String displayedRepairs(int count);

  /// No description provided for @statusReceivedUpper.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED'**
  String get statusReceivedUpper;

  /// No description provided for @statusRepairingUpper.
  ///
  /// In en, this message translates to:
  /// **'REPAIRING'**
  String get statusRepairingUpper;

  /// No description provided for @statusRepairDoneUpper.
  ///
  /// In en, this message translates to:
  /// **'REPAIR DONE'**
  String get statusRepairDoneUpper;

  /// No description provided for @statusDeliveredUpper.
  ///
  /// In en, this message translates to:
  /// **'DELIVERED'**
  String get statusDeliveredUpper;

  /// No description provided for @statusPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'PENDING APPROVAL'**
  String get statusPendingApproval;

  /// No description provided for @statusOther.
  ///
  /// In en, this message translates to:
  /// **'OTHER'**
  String get statusOther;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @statusSelectMultiple.
  ///
  /// In en, this message translates to:
  /// **'STATUS (select multiple)'**
  String get statusSelectMultiple;

  /// No description provided for @timeFilter.
  ///
  /// In en, this message translates to:
  /// **'TIME'**
  String get timeFilter;

  /// No description provided for @partsWillReturn.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Parts will be returned to inventory!'**
  String get partsWillReturn;

  /// No description provided for @deleteRepairAction.
  ///
  /// In en, this message translates to:
  /// **'DELETE REPAIR'**
  String get deleteRepairAction;

  /// No description provided for @orderPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Order is pending approval from manager/owner'**
  String get orderPendingApproval;

  /// No description provided for @deliveredDevice.
  ///
  /// In en, this message translates to:
  /// **'Delivered device {model} to customer {customer}. Warranty: {warranty}'**
  String deliveredDevice(String model, String customer, String warranty);

  /// No description provided for @repairOrderShare.
  ///
  /// In en, this message translates to:
  /// **'REPAIR ORDER - {customer} - {phone} - {model} - {price}'**
  String repairOrderShare(String customer, String phone, String model, String price);

  /// No description provided for @statusUpdated.
  ///
  /// In en, this message translates to:
  /// **'UPDATED: {status}'**
  String statusUpdated(String status);

  /// No description provided for @orderWillBeSentForApproval.
  ///
  /// In en, this message translates to:
  /// **'Order will be sent to manager for approval before delivery'**
  String get orderWillBeSentForApproval;

  /// No description provided for @sentDeliveryApprovalRequest.
  ///
  /// In en, this message translates to:
  /// **'Sent delivery approval request'**
  String get sentDeliveryApprovalRequest;

  /// No description provided for @approvedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Approved delivery of {model} to customer {customer}. Warranty: {warranty}'**
  String approvedDelivery(String model, String customer, String warranty);

  /// No description provided for @approvedAndCompletedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Approved and completed delivery'**
  String get approvedAndCompletedDelivery;

  /// No description provided for @rejectedBackToRepairDone.
  ///
  /// In en, this message translates to:
  /// **'Rejected - order returned to Repair Done status'**
  String get rejectedBackToRepairDone;

  /// No description provided for @editRepairAction.
  ///
  /// In en, this message translates to:
  /// **'EDIT REPAIR'**
  String get editRepairAction;

  /// No description provided for @savedOrderChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVED ORDER CHANGES'**
  String get savedOrderChanges;

  /// No description provided for @orderHasParts2.
  ///
  /// In en, this message translates to:
  /// **'This order already has parts:'**
  String get orderHasParts2;

  /// No description provided for @addedPartsFromInventory.
  ///
  /// In en, this message translates to:
  /// **'Added parts from inventory: {parts}\n(Cost already recorded when imported)'**
  String addedPartsFromInventory(String parts);

  /// No description provided for @partsSupplier.
  ///
  /// In en, this message translates to:
  /// **'Parts supplier'**
  String get partsSupplier;

  /// No description provided for @addedPartsWithPayment.
  ///
  /// In en, this message translates to:
  /// **'Added parts ({method}): {parts}'**
  String addedPartsWithPayment(String method, String parts);

  /// No description provided for @savedTechnicianNotes.
  ///
  /// In en, this message translates to:
  /// **'Saved technician notes'**
  String get savedTechnicianNotes;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// No description provided for @phoneRequired2.
  ///
  /// In en, this message translates to:
  /// **'Phone cannot be empty'**
  String get phoneRequired2;

  /// No description provided for @addressLabel2.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel2;

  /// No description provided for @editButton.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// No description provided for @partnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Partner: {name}'**
  String partnerLabel(String name);

  /// No description provided for @orderPendingYourApproval.
  ///
  /// In en, this message translates to:
  /// **'Order is pending your approval for delivery'**
  String get orderPendingYourApproval;

  /// No description provided for @waitingManagerApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for manager approval for delivery'**
  String get waitingManagerApproval;

  /// No description provided for @repairDoneReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Repair done - ready for delivery'**
  String get repairDoneReadyForDelivery;

  /// No description provided for @repairingButton.
  ///
  /// In en, this message translates to:
  /// **'REPAIRING'**
  String get repairingButton;

  /// No description provided for @repairDoneButton.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get repairDoneButton;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @orderAlreadyHasParts.
  ///
  /// In en, this message translates to:
  /// **'This order already has parts:'**
  String get orderAlreadyHasParts;

  /// No description provided for @partsWillBeAddedAndDeducted.
  ///
  /// In en, this message translates to:
  /// **'If you continue, new parts will be ADDED and DEDUCTED FROM INVENTORY immediately.\n\nDo you want to continue?'**
  String get partsWillBeAddedAndDeducted;

  /// No description provided for @continueAddMore.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE ADDING'**
  String get continueAddMore;

  /// No description provided for @editPrice.
  ///
  /// In en, this message translates to:
  /// **'Edit price'**
  String get editPrice;

  /// No description provided for @editService.
  ///
  /// In en, this message translates to:
  /// **'Edit service'**
  String get editService;

  /// No description provided for @addServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get addServiceTitle;

  /// No description provided for @partnerOptional2.
  ///
  /// In en, this message translates to:
  /// **'Partner (optional)'**
  String get partnerOptional2;

  /// No description provided for @serviceUpdated.
  ///
  /// In en, this message translates to:
  /// **'SERVICE UPDATED'**
  String get serviceUpdated;

  /// No description provided for @serviceAdded.
  ///
  /// In en, this message translates to:
  /// **'SERVICE ADDED'**
  String get serviceAdded;

  /// No description provided for @serviceDeleted.
  ///
  /// In en, this message translates to:
  /// **'SERVICE DELETED'**
  String get serviceDeleted;

  /// No description provided for @preparingPrint.
  ///
  /// In en, this message translates to:
  /// **'Preparing print command...'**
  String get preparingPrint;

  /// No description provided for @printSuccess.
  ///
  /// In en, this message translates to:
  /// **'Printed successfully!'**
  String get printSuccess;

  /// No description provided for @smartphoneSpecialist.
  ///
  /// In en, this message translates to:
  /// **'Smartphone Specialist'**
  String get smartphoneSpecialist;

  /// No description provided for @editOrderInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit order information'**
  String get editOrderInfoTitle;

  /// No description provided for @customerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerNameLabel;

  /// No description provided for @deviceModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Device model'**
  String get deviceModelLabel;

  /// No description provided for @deviceIssueLabel.
  ///
  /// In en, this message translates to:
  /// **'Device issue'**
  String get deviceIssueLabel;

  /// No description provided for @accessoriesIncludedLabel.
  ///
  /// In en, this message translates to:
  /// **'Accessories included'**
  String get accessoriesIncludedLabel;

  /// No description provided for @warrantyLabel2.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get warrantyLabel2;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get saveButton;

  /// No description provided for @cancelButtonLower.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButtonLower;

  /// No description provided for @enterModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter device model'**
  String get enterModelRequired;

  /// No description provided for @enterIssueRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter issue description'**
  String get enterIssueRequired;

  /// No description provided for @editInfoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit information'**
  String get editInfoTooltip;

  /// No description provided for @noPartnerOption.
  ///
  /// In en, this message translates to:
  /// **'No partner'**
  String get noPartnerOption;

  /// No description provided for @enterServiceName.
  ///
  /// In en, this message translates to:
  /// **'Please enter service name'**
  String get enterServiceName;

  /// No description provided for @chargeCustomerVnd.
  ///
  /// In en, this message translates to:
  /// **'Charge customer (VND)'**
  String get chargeCustomerVnd;

  /// No description provided for @partsCostVnd.
  ///
  /// In en, this message translates to:
  /// **'Parts cost (VND)'**
  String get partsCostVnd;

  /// No description provided for @repairOrderFinance.
  ///
  /// In en, this message translates to:
  /// **'REPAIR ORDER FINANCE'**
  String get repairOrderFinance;

  /// No description provided for @customerCharge.
  ///
  /// In en, this message translates to:
  /// **'Customer charge'**
  String get customerCharge;

  /// No description provided for @partsCost.
  ///
  /// In en, this message translates to:
  /// **'Parts cost'**
  String get partsCost;

  /// No description provided for @editInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'EDIT INFO'**
  String get editInfoTitle;

  /// No description provided for @partsInventoryShort.
  ///
  /// In en, this message translates to:
  /// **'Parts Inv'**
  String get partsInventoryShort;

  /// No description provided for @techShort.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get techShort;

  /// No description provided for @printFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed! Please check printer settings.'**
  String get printFailed;

  /// No description provided for @printError.
  ///
  /// In en, this message translates to:
  /// **'Print error: {error}'**
  String printError(String error);

  /// No description provided for @noAccessPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to access this feature'**
  String get noAccessPermission;

  /// No description provided for @repairDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'REPAIR ORDER DETAIL'**
  String get repairDetailTitle;

  /// No description provided for @sendApprovalRequest.
  ///
  /// In en, this message translates to:
  /// **'SEND APPROVAL REQUEST'**
  String get sendApprovalRequest;

  /// No description provided for @selectWarrantyPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select warranty period:'**
  String get selectWarrantyPeriod;

  /// No description provided for @selectPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Select payment method:'**
  String get selectPaymentMethod;

  /// No description provided for @confirmDeliveryAndPayment.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM DELIVERY & PAYMENT'**
  String get confirmDeliveryAndPayment;

  /// No description provided for @completeDelivery.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE DELIVERY'**
  String get completeDelivery;

  /// No description provided for @noWarranty.
  ///
  /// In en, this message translates to:
  /// **'NO WARRANTY'**
  String get noWarranty;

  /// No description provided for @oneMonth.
  ///
  /// In en, this message translates to:
  /// **'1 MONTH'**
  String get oneMonth;

  /// No description provided for @threeMonths.
  ///
  /// In en, this message translates to:
  /// **'3 MONTHS'**
  String get threeMonths;

  /// No description provided for @sixMonths.
  ///
  /// In en, this message translates to:
  /// **'6 MONTHS'**
  String get sixMonths;

  /// No description provided for @twelveMonths.
  ///
  /// In en, this message translates to:
  /// **'12 MONTHS'**
  String get twelveMonths;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'CASH'**
  String get cash;

  /// No description provided for @bankTransfer.
  ///
  /// In en, this message translates to:
  /// **'BANK TRANSFER'**
  String get bankTransfer;

  /// No description provided for @debt.
  ///
  /// In en, this message translates to:
  /// **'DEBT'**
  String get debt;

  /// No description provided for @financeTitleUpper.
  ///
  /// In en, this message translates to:
  /// **'FINANCE'**
  String get financeTitleUpper;

  /// No description provided for @luuYTitle.
  ///
  /// In en, this message translates to:
  /// **'WARNING'**
  String get luuYTitle;

  /// No description provided for @partsInventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Parts inventory empty. '**
  String get partsInventoryEmpty;

  /// No description provided for @noProductsInInventory.
  ///
  /// In en, this message translates to:
  /// **'No products in inventory yet.'**
  String get noProductsInInventory;

  /// No description provided for @totalProductsLinhKien.
  ///
  /// In en, this message translates to:
  /// **'Total: {total}, PARTS: {parts}. '**
  String totalProductsLinhKien(int total, int parts);

  /// No description provided for @goToInventoryAddParts.
  ///
  /// In en, this message translates to:
  /// **'Go to Inventory → Add Product → Select type \'PARTS\''**
  String get goToInventoryAddParts;

  /// No description provided for @addedPartsFromInventoryMsg.
  ///
  /// In en, this message translates to:
  /// **'Added parts from inventory: {parts}\n(Cost already recorded when imported)'**
  String addedPartsFromInventoryMsg(String parts);

  /// No description provided for @priceLabel.
  ///
  /// In en, this message translates to:
  /// **'PRICE'**
  String get priceLabel;

  /// No description provided for @costLabel.
  ///
  /// In en, this message translates to:
  /// **'COST'**
  String get costLabel;

  /// No description provided for @chargeCustomerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer charge'**
  String get chargeCustomerLabel;

  /// No description provided for @partsLabel.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get partsLabel;

  /// No description provided for @profitLabel.
  ///
  /// In en, this message translates to:
  /// **'PROFIT'**
  String get profitLabel;

  /// No description provided for @expectedProfit.
  ///
  /// In en, this message translates to:
  /// **'Expected profit'**
  String get expectedProfit;

  /// No description provided for @partsUsedLabel.
  ///
  /// In en, this message translates to:
  /// **'Parts: {parts}'**
  String partsUsedLabel(String parts);

  /// No description provided for @servicesCount.
  ///
  /// In en, this message translates to:
  /// **'SERVICES ({count})'**
  String servicesCount(int count);

  /// No description provided for @repairServices.
  ///
  /// In en, this message translates to:
  /// **'REPAIR SERVICES'**
  String get repairServices;

  /// No description provided for @imagesCount.
  ///
  /// In en, this message translates to:
  /// **'IMAGES ({count})'**
  String imagesCount(int count);

  /// No description provided for @receivedImages.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED DEVICE IMAGES'**
  String get receivedImages;

  /// No description provided for @noImages.
  ///
  /// In en, this message translates to:
  /// **'No images'**
  String get noImages;

  /// No description provided for @statusReceivedMsg.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED DEVICE'**
  String get statusReceivedMsg;

  /// No description provided for @statusStartRepairMsg.
  ///
  /// In en, this message translates to:
  /// **'START REPAIR'**
  String get statusStartRepairMsg;

  /// No description provided for @debtNoteRepair.
  ///
  /// In en, this message translates to:
  /// **'Debt for repair: {model}'**
  String debtNoteRepair(String model);

  /// No description provided for @pendingDeliveryApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending delivery approval - {customer}'**
  String pendingDeliveryApproval(String customer);

  /// No description provided for @requestDeliveryApprovalDesc.
  ///
  /// In en, this message translates to:
  /// **'Request delivery approval for {model} - customer {customer}'**
  String requestDeliveryApprovalDesc(String model, String customer);

  /// No description provided for @notifRequestDeliveryApproval.
  ///
  /// In en, this message translates to:
  /// **'📋 DELIVERY APPROVAL REQUEST'**
  String get notifRequestDeliveryApproval;

  /// No description provided for @chatRequestDeliveryApproval.
  ///
  /// In en, this message translates to:
  /// **'📋 DELIVERY REQUEST: {model} - {customer} - {price}đ'**
  String chatRequestDeliveryApproval(String model, String customer, String price);

  /// No description provided for @defaultShopName.
  ///
  /// In en, this message translates to:
  /// **'SHOP NEW'**
  String get defaultShopName;

  /// No description provided for @defaultShopDesc.
  ///
  /// In en, this message translates to:
  /// **'Smartphone Specialist'**
  String get defaultShopDesc;

  /// No description provided for @defaultShopPhone.
  ///
  /// In en, this message translates to:
  /// **'0123.456.789'**
  String get defaultShopPhone;

  /// No description provided for @techNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'TECHNICIAN NOTES'**
  String get techNotesTitle;

  /// No description provided for @repairProcessNotes.
  ///
  /// In en, this message translates to:
  /// **'Repair process notes:'**
  String get repairProcessNotes;

  /// No description provided for @techNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Replace power IC, check mainboard, replace charging cable...'**
  String get techNotesHint;

  /// No description provided for @trackRepairProgress.
  ///
  /// In en, this message translates to:
  /// **'Track repair progress and update status.'**
  String get trackRepairProgress;

  /// No description provided for @repairOrderDetail.
  ///
  /// In en, this message translates to:
  /// **'REPAIR ORDER DETAIL'**
  String get repairOrderDetail;

  /// No description provided for @partsShort.
  ///
  /// In en, this message translates to:
  /// **'PT: {parts}'**
  String partsShort(String parts);

  /// No description provided for @noServicesYet.
  ///
  /// In en, this message translates to:
  /// **'No services yet'**
  String get noServicesYet;

  /// No description provided for @totalServices.
  ///
  /// In en, this message translates to:
  /// **'Total SVC:'**
  String get totalServices;

  /// No description provided for @deliveryLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get deliveryLabel;

  /// No description provided for @approveDelivery.
  ///
  /// In en, this message translates to:
  /// **'APPROVE DELIVERY'**
  String get approveDelivery;

  /// No description provided for @deliverDevice.
  ///
  /// In en, this message translates to:
  /// **'DELIVER'**
  String get deliverDevice;

  /// No description provided for @sendDeliveryRequest.
  ///
  /// In en, this message translates to:
  /// **'SEND DELIVERY REQUEST'**
  String get sendDeliveryRequest;

  /// No description provided for @addServiceButton.
  ///
  /// In en, this message translates to:
  /// **'ADD SERVICE'**
  String get addServiceButton;

  /// No description provided for @noServicesMessage.
  ///
  /// In en, this message translates to:
  /// **'No services added'**
  String get noServicesMessage;

  /// No description provided for @totalServiceCost.
  ///
  /// In en, this message translates to:
  /// **'Total service cost'**
  String get totalServiceCost;

  /// No description provided for @customerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerLabel;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @issueLabel.
  ///
  /// In en, this message translates to:
  /// **'Device issue'**
  String issueLabel(String issue);

  /// No description provided for @accessoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get accessoriesLabel;

  /// No description provided for @noAccessories.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noAccessories;

  /// No description provided for @errorSaving.
  ///
  /// In en, this message translates to:
  /// **'Error saving: {error}'**
  String errorSaving(String error);

  /// No description provided for @rejectDeliveryDesc.
  ///
  /// In en, this message translates to:
  /// **'Reject delivery approval for {model}'**
  String rejectDeliveryDesc(String model);

  /// No description provided for @customerInfo.
  ///
  /// In en, this message translates to:
  /// **'Customer: {name}'**
  String customerInfo(String name);

  /// No description provided for @deviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Device: {model}'**
  String deviceInfo(String model);

  /// No description provided for @priceInfo.
  ///
  /// In en, this message translates to:
  /// **'Price: {price}đ'**
  String priceInfo(String price);

  /// No description provided for @paymentInfo.
  ///
  /// In en, this message translates to:
  /// **'Payment: {method}'**
  String paymentInfo(String method);

  /// No description provided for @selectWarrantyNote.
  ///
  /// In en, this message translates to:
  /// **'Select warranty (can change before approval):'**
  String get selectWarrantyNote;

  /// No description provided for @confirmApproveDelivery.
  ///
  /// In en, this message translates to:
  /// **'Confirm approve delivery and complete transaction?'**
  String get confirmApproveDelivery;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'REJECT'**
  String get reject;

  /// No description provided for @chatApprovedDelivery.
  ///
  /// In en, this message translates to:
  /// **'✅ APPROVED DELIVERY: {summary}'**
  String chatApprovedDelivery(String summary);

  /// No description provided for @noneYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get noneYet;

  /// No description provided for @deliveryDate.
  ///
  /// In en, this message translates to:
  /// **'Delivery date'**
  String get deliveryDate;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'APPROVE'**
  String get approve;

  /// No description provided for @shareRepairReceipt.
  ///
  /// In en, this message translates to:
  /// **'🌟 REPAIR/WARRANTY RECEIPT 🌟\n----------------------------\nShop: {shopName}\nModel: {model}\nCustomer: {customerName} - {phone}\nIssue: {issue}\nWarranty: {warranty}\nTotal: {total}\n----------------------------\nThank you for your trust!'**
  String shareRepairReceipt(String shopName, String model, String customerName, String phone, String issue, String warranty, String total);

  /// No description provided for @actionDeliverDevice.
  ///
  /// In en, this message translates to:
  /// **'DELIVER DEVICE'**
  String get actionDeliverDevice;

  /// No description provided for @actionRequestDeliveryApproval.
  ///
  /// In en, this message translates to:
  /// **'REQUEST DELIVERY APPROVAL'**
  String get actionRequestDeliveryApproval;

  /// No description provided for @debtNoteForRepair.
  ///
  /// In en, this message translates to:
  /// **'Debt for repair: {model}'**
  String debtNoteForRepair(String model);

  /// No description provided for @repairOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'REPAIR ORDER - {customerName} - {phone} - {model} - {total}'**
  String repairOrderSummary(String customerName, String phone, String model, String total);

  /// No description provided for @chatDeviceDelivered.
  ///
  /// In en, this message translates to:
  /// **'✅ DEVICE DELIVERED: {summary}'**
  String chatDeviceDelivered(String summary);

  /// No description provided for @partsPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'PARTS PAYMENT'**
  String get partsPaymentTitle;

  /// No description provided for @totalPartsAmount.
  ///
  /// In en, this message translates to:
  /// **'TOTAL PARTS AMOUNT'**
  String get totalPartsAmount;

  /// No description provided for @partsDesc.
  ///
  /// In en, this message translates to:
  /// **'Parts: {parts}'**
  String partsDesc(String parts);

  /// No description provided for @supplierOptional.
  ///
  /// In en, this message translates to:
  /// **'Supplier (optional)'**
  String get supplierOptional;

  /// No description provided for @supplierHint.
  ///
  /// In en, this message translates to:
  /// **'e.g.: Parts ABC'**
  String get supplierHint;

  /// No description provided for @paymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHOD:'**
  String get paymentMethodLabel;

  /// No description provided for @debtWarning.
  ///
  /// In en, this message translates to:
  /// **'Debt will be recorded in Debt Management'**
  String get debtWarning;

  /// No description provided for @defaultPartsSupplier.
  ///
  /// In en, this message translates to:
  /// **'Parts supplier'**
  String get defaultPartsSupplier;

  /// No description provided for @recordDebt.
  ///
  /// In en, this message translates to:
  /// **'RECORD DEBT'**
  String get recordDebt;

  /// No description provided for @viewRepairPartners.
  ///
  /// In en, this message translates to:
  /// **'View repair partners'**
  String get viewRepairPartners;

  /// No description provided for @serviceNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Service name *'**
  String get serviceNameRequired;

  /// No description provided for @pleaseEnterServiceName.
  ///
  /// In en, this message translates to:
  /// **'Please enter service name'**
  String get pleaseEnterServiceName;

  /// No description provided for @costVnd.
  ///
  /// In en, this message translates to:
  /// **'Cost (VND)'**
  String get costVnd;

  /// No description provided for @costField.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get costField;

  /// No description provided for @partnerPaymentMethodRequired.
  ///
  /// In en, this message translates to:
  /// **'Partner payment method *'**
  String get partnerPaymentMethodRequired;

  /// No description provided for @pleaseSelectPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Please select payment method'**
  String get pleaseSelectPaymentMethod;

  /// No description provided for @selectPartsTitle.
  ///
  /// In en, this message translates to:
  /// **'SELECT PARTS / COMPONENTS'**
  String get selectPartsTitle;

  /// No description provided for @searchPartOrSupplier.
  ///
  /// In en, this message translates to:
  /// **'Search by name or supplier'**
  String get searchPartOrSupplier;

  /// No description provided for @noPartsFound.
  ///
  /// In en, this message translates to:
  /// **'No matching parts found'**
  String get noPartsFound;

  /// No description provided for @mainWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Main warehouse'**
  String get mainWarehouse;

  /// No description provided for @oldWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Old stock'**
  String get oldWarehouse;

  /// No description provided for @stockQty.
  ///
  /// In en, this message translates to:
  /// **'Stock: {qty}'**
  String stockQty(int qty);

  /// No description provided for @costPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost: {price}'**
  String costPrice(String price);

  /// No description provided for @sellPrice.
  ///
  /// In en, this message translates to:
  /// **'Sell: {price}'**
  String sellPrice(String price);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'OUT OF STOCK'**
  String get outOfStock;

  /// No description provided for @confirmQty.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM ({qty})'**
  String confirmQty(int qty);

  /// No description provided for @confirmBtn.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM'**
  String get confirmBtn;

  /// No description provided for @invoiceTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATE INVOICE TEMPLATE'**
  String get invoiceTemplateTitle;

  /// No description provided for @invoiceTemplateSaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice template saved'**
  String get invoiceTemplateSaved;

  /// No description provided for @headerLabel.
  ///
  /// In en, this message translates to:
  /// **'Header:'**
  String get headerLabel;

  /// No description provided for @invoiceHeaderHint.
  ///
  /// In en, this message translates to:
  /// **'INVOICE HEADER'**
  String get invoiceHeaderHint;

  /// No description provided for @bodyLabelWithPlaceholders.
  ///
  /// In en, this message translates to:
  /// **'Body (use placeholders like customerName, total):'**
  String get bodyLabelWithPlaceholders;

  /// No description provided for @invoiceBodyHint.
  ///
  /// In en, this message translates to:
  /// **'MAIN CONTENT'**
  String get invoiceBodyHint;

  /// No description provided for @footerLabel.
  ///
  /// In en, this message translates to:
  /// **'Footer:'**
  String get footerLabel;

  /// No description provided for @invoiceFooterHint.
  ///
  /// In en, this message translates to:
  /// **'INVOICE FOOTER'**
  String get invoiceFooterHint;

  /// No description provided for @previewLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview:'**
  String get previewLabel;

  /// No description provided for @generateQrSampleOrder.
  ///
  /// In en, this message translates to:
  /// **'CREATE QR FOR SAMPLE ORDER'**
  String get generateQrSampleOrder;

  /// No description provided for @qrCodeScanInfo.
  ///
  /// In en, this message translates to:
  /// **'QR Code (scan to view order info):'**
  String get qrCodeScanInfo;

  /// No description provided for @workScheduleSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'WORK SCHEDULE SETTINGS'**
  String get workScheduleSettingsTitle;

  /// No description provided for @generalSettingsTab.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSettingsTab;

  /// No description provided for @staffTab.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffTab;

  /// No description provided for @workScheduleSaved.
  ///
  /// In en, this message translates to:
  /// **'Work schedule settings saved'**
  String get workScheduleSaved;

  /// No description provided for @staffSalarySaved.
  ///
  /// In en, this message translates to:
  /// **'Staff salary saved'**
  String get staffSalarySaved;

  /// No description provided for @saveErrorMsg.
  ///
  /// In en, this message translates to:
  /// **'Error saving: {error}'**
  String saveErrorMsg(String error);

  /// No description provided for @staffScheduleSavedFor.
  ///
  /// In en, this message translates to:
  /// **'Saved work schedule for {name}'**
  String staffScheduleSavedFor(String name);

  /// No description provided for @loadingStaffList.
  ///
  /// In en, this message translates to:
  /// **'Loading staff list...'**
  String get loadingStaffList;

  /// No description provided for @noStaffData.
  ///
  /// In en, this message translates to:
  /// **'No staff data'**
  String get noStaffData;

  /// No description provided for @tapToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Tap reload to refresh'**
  String get tapToRefresh;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @staffCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff count: {count}'**
  String staffCountLabel(int count);

  /// No description provided for @staffWorkSchedule.
  ///
  /// In en, this message translates to:
  /// **'Individual staff schedules'**
  String get staffWorkSchedule;

  /// No description provided for @scheduleNotSet.
  ///
  /// In en, this message translates to:
  /// **'Schedule not set'**
  String get scheduleNotSet;

  /// No description provided for @workHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Work Hours'**
  String get workHoursLabel;

  /// No description provided for @startTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startTimeLabel;

  /// No description provided for @endTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endTimeLabel;

  /// No description provided for @lunchBreakLabel.
  ///
  /// In en, this message translates to:
  /// **'Lunch break'**
  String get lunchBreakLabel;

  /// No description provided for @maxOvertimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Max OT'**
  String get maxOvertimeLabel;

  /// No description provided for @workDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Work Days'**
  String get workDaysLabel;

  /// No description provided for @holidaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Holidays:'**
  String get holidaysLabel;

  /// No description provided for @addBtn.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addBtn;

  /// No description provided for @overtimeRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Overtime Rate'**
  String get overtimeRateLabel;

  /// No description provided for @weekdayLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekday'**
  String get weekdayLabel;

  /// No description provided for @weekendLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get weekendLabel;

  /// No description provided for @holidayLabel.
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get holidayLabel;

  /// No description provided for @saveSettingsBtn.
  ///
  /// In en, this message translates to:
  /// **'SAVE SETTINGS'**
  String get saveSettingsBtn;

  /// No description provided for @noStaffFoundMsg.
  ///
  /// In en, this message translates to:
  /// **'No staff found'**
  String get noStaffFoundMsg;

  /// No description provided for @addStaffFirstHint.
  ///
  /// In en, this message translates to:
  /// **'Please add staff in \"Staff Management\" first'**
  String get addStaffFirstHint;

  /// No description provided for @salarySettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Salary Settings'**
  String get salarySettingsLabel;

  /// No description provided for @selectStaffHint.
  ///
  /// In en, this message translates to:
  /// **'Select staff'**
  String get selectStaffHint;

  /// No description provided for @baseSalaryVnd.
  ///
  /// In en, this message translates to:
  /// **'Base salary (VND)'**
  String get baseSalaryVnd;

  /// No description provided for @attendanceLookupLabel.
  ///
  /// In en, this message translates to:
  /// **'Attendance Lookup'**
  String get attendanceLookupLabel;

  /// No description provided for @noAttendanceDataFor.
  ///
  /// In en, this message translates to:
  /// **'No attendance data for {date}'**
  String noAttendanceDataFor(String date);

  /// No description provided for @checkInLabel.
  ///
  /// In en, this message translates to:
  /// **'In:'**
  String get checkInLabel;

  /// No description provided for @checkOutLabel.
  ///
  /// In en, this message translates to:
  /// **'Out:'**
  String get checkOutLabel;

  /// No description provided for @approvedStatus.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvedStatus;

  /// No description provided for @rejectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedStatus;

  /// No description provided for @pendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingStatus;

  /// No description provided for @selectStaffToViewAttendance.
  ///
  /// In en, this message translates to:
  /// **'Select staff to view attendance'**
  String get selectStaffToViewAttendance;

  /// No description provided for @displayError.
  ///
  /// In en, this message translates to:
  /// **'Display Error'**
  String get displayError;

  /// No description provided for @errorMsg.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorMsg(String error);

  /// No description provided for @noStaffHint.
  ///
  /// In en, this message translates to:
  /// **'No staff yet. Tap \"Reload\" below or add staff in Staff Management.'**
  String get noStaffHint;

  /// No description provided for @staffScheduleFor.
  ///
  /// In en, this message translates to:
  /// **'Work schedule: {name}'**
  String staffScheduleFor(String name);

  /// No description provided for @workTimeSettings.
  ///
  /// In en, this message translates to:
  /// **'Work Time Settings'**
  String get workTimeSettings;

  /// No description provided for @startTimeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get startTimeFieldLabel;

  /// No description provided for @endTimeFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get endTimeFieldLabel;

  /// No description provided for @lunchBreakHours.
  ///
  /// In en, this message translates to:
  /// **'Lunch break (hours)'**
  String get lunchBreakHours;

  /// No description provided for @maxOvertimePerDay.
  ///
  /// In en, this message translates to:
  /// **'Max overtime per day'**
  String get maxOvertimePerDay;

  /// No description provided for @selectTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get selectTimeLabel;

  /// No description provided for @workDaysSettings.
  ///
  /// In en, this message translates to:
  /// **'Work Days Settings'**
  String get workDaysSettings;

  /// No description provided for @workDaysInWeek.
  ///
  /// In en, this message translates to:
  /// **'Work days in week:'**
  String get workDaysInWeek;

  /// No description provided for @addHolidayBtn.
  ///
  /// In en, this message translates to:
  /// **'Add holiday'**
  String get addHolidayBtn;

  /// No description provided for @holidayListLabel.
  ///
  /// In en, this message translates to:
  /// **'Holiday list:'**
  String get holidayListLabel;

  /// No description provided for @overtimeSettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Overtime Settings'**
  String get overtimeSettingsLabel;

  /// No description provided for @weekdayOvertimeRate.
  ///
  /// In en, this message translates to:
  /// **'Weekday overtime (% of salary/hour)'**
  String get weekdayOvertimeRate;

  /// No description provided for @weekendOvertimeRate.
  ///
  /// In en, this message translates to:
  /// **'Weekend overtime (% of salary/hour)'**
  String get weekendOvertimeRate;

  /// No description provided for @holidayOvertimeRate.
  ///
  /// In en, this message translates to:
  /// **'Holiday overtime (% of salary/hour)'**
  String get holidayOvertimeRate;

  /// No description provided for @staffSalarySettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff Salary Settings'**
  String get staffSalarySettingsLabel;

  /// No description provided for @addUpdateSalary.
  ///
  /// In en, this message translates to:
  /// **'Add/Update Salary'**
  String get addUpdateSalary;

  /// No description provided for @saveSalary.
  ///
  /// In en, this message translates to:
  /// **'Save salary'**
  String get saveSalary;

  /// No description provided for @currentSalaryList.
  ///
  /// In en, this message translates to:
  /// **'Current salary list:'**
  String get currentSalaryList;

  /// No description provided for @manageStaffAttendance.
  ///
  /// In en, this message translates to:
  /// **'Manage Staff Attendance'**
  String get manageStaffAttendance;

  /// No description provided for @selectDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDateLabel;

  /// No description provided for @attendanceInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Attendance Info'**
  String get attendanceInfoLabel;

  /// No description provided for @staffNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Staff:'**
  String get staffNameLabel;

  /// No description provided for @checkInTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Check-in:'**
  String get checkInTimeLabel;

  /// No description provided for @checkOutTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Check-out:'**
  String get checkOutTimeLabel;

  /// No description provided for @selectStaffForAttendance.
  ///
  /// In en, this message translates to:
  /// **'Please select staff to view attendance info'**
  String get selectStaffForAttendance;

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'About Developer'**
  String get aboutDeveloper;

  /// No description provided for @hulucaStoreDongNai.
  ///
  /// In en, this message translates to:
  /// **'HULUCA STORE DONG NAI'**
  String get hulucaStoreDongNai;

  /// No description provided for @professionalStoreManagementApp.
  ///
  /// In en, this message translates to:
  /// **'Professional store management application'**
  String get professionalStoreManagementApp;

  /// No description provided for @developerAndDesigner.
  ///
  /// In en, this message translates to:
  /// **'Developer & Designer'**
  String get developerAndDesigner;

  /// No description provided for @hulucaStore.
  ///
  /// In en, this message translates to:
  /// **'HULUCA STORE'**
  String get hulucaStore;

  /// No description provided for @dongNai.
  ///
  /// In en, this message translates to:
  /// **'DONG NAI'**
  String get dongNai;

  /// No description provided for @professionalPhoneRepairShop.
  ///
  /// In en, this message translates to:
  /// **'Professional shop management solution'**
  String get professionalPhoneRepairShop;

  /// No description provided for @hotlineAndZalo.
  ///
  /// In en, this message translates to:
  /// **'Hotline & Zalo'**
  String get hotlineAndZalo;

  /// No description provided for @shopManagerApp.
  ///
  /// In en, this message translates to:
  /// **'Shop Manager App'**
  String get shopManagerApp;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @appFullDescription.
  ///
  /// In en, this message translates to:
  /// **'Comprehensive multi-industry shop management: Electronics (IMEI, warranty), Food (expiry), Fashion (size/color variants) with real-time sync.'**
  String get appFullDescription;

  /// No description provided for @attendanceTracking.
  ///
  /// In en, this message translates to:
  /// **'ATTENDANCE TRACKING'**
  String get attendanceTracking;

  /// No description provided for @viewByMonth.
  ///
  /// In en, this message translates to:
  /// **'View by month'**
  String get viewByMonth;

  /// No description provided for @viewByDay.
  ///
  /// In en, this message translates to:
  /// **'View by day'**
  String get viewByDay;

  /// No description provided for @attendanceForDate.
  ///
  /// In en, this message translates to:
  /// **'ATTENDANCE {date}'**
  String attendanceForDate(String date);

  /// No description provided for @monthLabel.
  ///
  /// In en, this message translates to:
  /// **'MONTH {month}'**
  String monthLabel(String month);

  /// No description provided for @present.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get present;

  /// No description provided for @lateArrival.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get lateArrival;

  /// No description provided for @absent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get absent;

  /// No description provided for @totalStaff.
  ///
  /// In en, this message translates to:
  /// **'Total Staff'**
  String get totalStaff;

  /// No description provided for @checkedInStatus.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get checkedInStatus;

  /// No description provided for @todayLabel.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get todayLabel;

  /// No description provided for @noStaffYet.
  ///
  /// In en, this message translates to:
  /// **'No staff yet'**
  String get noStaffYet;

  /// No description provided for @notCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Not checked in'**
  String get notCheckedIn;

  /// No description provided for @completedStatus.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedStatus;

  /// No description provided for @workingStatus.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get workingStatus;

  /// No description provided for @workDaysCount.
  ///
  /// In en, this message translates to:
  /// **'Work days'**
  String get workDaysCount;

  /// No description provided for @workHoursCount.
  ///
  /// In en, this message translates to:
  /// **'Work hours'**
  String get workHoursCount;

  /// No description provided for @roleOwnerShort.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwnerShort;

  /// No description provided for @roleManagerShort.
  ///
  /// In en, this message translates to:
  /// **'Mgr'**
  String get roleManagerShort;

  /// No description provided for @roleTechnicianShort.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get roleTechnicianShort;

  /// No description provided for @roleEmployeeShort.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get roleEmployeeShort;

  /// No description provided for @noAttendanceData.
  ///
  /// In en, this message translates to:
  /// **'No attendance data'**
  String get noAttendanceData;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @checkInTimeShort.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get checkInTimeShort;

  /// No description provided for @checkOutTimeShort.
  ///
  /// In en, this message translates to:
  /// **'Check-out'**
  String get checkOutTimeShort;

  /// No description provided for @earlyLeave.
  ///
  /// In en, this message translates to:
  /// **'Early leave'**
  String get earlyLeave;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @attendancePhotos.
  ///
  /// In en, this message translates to:
  /// **'Attendance photos:'**
  String get attendancePhotos;

  /// No description provided for @checkInPhoto.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get checkInPhoto;

  /// No description provided for @checkOutPhoto.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get checkOutPhoto;

  /// No description provided for @hasPhoto.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get hasPhoto;

  /// No description provided for @noPhoto.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get noPhoto;

  /// No description provided for @monthYearFormat.
  ///
  /// In en, this message translates to:
  /// **'Month {monthYear}'**
  String monthYearFormat(String monthYear);

  /// No description provided for @errorLoadingCustomers.
  ///
  /// In en, this message translates to:
  /// **'Error loading customers: {error}'**
  String errorLoadingCustomers(String error);

  /// No description provided for @editCustomerAction.
  ///
  /// In en, this message translates to:
  /// **'edit customer'**
  String get editCustomerAction;

  /// No description provided for @deleteCustomerAction.
  ///
  /// In en, this message translates to:
  /// **'delete customer'**
  String get deleteCustomerAction;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteCustomer.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete customer \"{name}\"?'**
  String confirmDeleteCustomer(String name);

  /// No description provided for @confirmActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm {action}'**
  String confirmActionTitle(String action);

  /// No description provided for @ownerPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Only shop owner can perform this action.\nEnter account password to confirm:'**
  String get ownerPasswordRequired;

  /// No description provided for @pleaseLoginAgain.
  ///
  /// In en, this message translates to:
  /// **'Please login again'**
  String get pleaseLoginAgain;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password!'**
  String get incorrectPassword;

  /// No description provided for @customerManagement.
  ///
  /// In en, this message translates to:
  /// **'Customer Management'**
  String get customerManagement;

  /// No description provided for @addCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get addCustomer;

  /// No description provided for @searchCustomers.
  ///
  /// In en, this message translates to:
  /// **'Search customers...'**
  String get searchCustomers;

  /// No description provided for @noCustomersYet.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get noCustomersYet;

  /// No description provided for @customerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Customer not found'**
  String get customerNotFound;

  /// No description provided for @notePrefix.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String notePrefix(String note);

  /// No description provided for @totalPurchasedAmount.
  ///
  /// In en, this message translates to:
  /// **'Purchased: {amount}'**
  String totalPurchasedAmount(String amount);

  /// No description provided for @repairCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Repairs: {count} times'**
  String repairCountLabel(int count);

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @addCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get addCustomerTitle;

  /// No description provided for @editCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get editCustomerTitle;

  /// No description provided for @customerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Customer name *'**
  String get customerNameRequired;

  /// No description provided for @enterCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Enter customer name'**
  String get enterCustomerName;

  /// No description provided for @pleaseEnterCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Please enter customer name'**
  String get pleaseEnterCustomerName;

  /// No description provided for @phoneNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number *'**
  String get phoneNumberRequired;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter phone number'**
  String get enterPhoneNumber;

  /// No description provided for @pleaseEnterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter phone number'**
  String get pleaseEnterPhoneNumber;

  /// No description provided for @enterEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter email (optional)'**
  String get enterEmailOptional;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String addressLabel(String address);

  /// No description provided for @enterAddressOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter address (optional)'**
  String get enterAddressOptional;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String notesLabel(String notes);

  /// No description provided for @enterNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Enter notes (optional)'**
  String get enterNotesOptional;

  /// No description provided for @totalPurchasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Total purchases'**
  String get totalPurchasesLabel;

  /// No description provided for @totalRepairsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total repairs'**
  String get totalRepairsLabel;

  /// No description provided for @noHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get noHistoryYet;

  /// No description provided for @fastInventoryCheck.
  ///
  /// In en, this message translates to:
  /// **'Fast Inventory Check'**
  String get fastInventoryCheck;

  /// No description provided for @checklistTitle.
  ///
  /// In en, this message translates to:
  /// **'📋 Checklist'**
  String get checklistTitle;

  /// No description provided for @checklistDescription.
  ///
  /// In en, this message translates to:
  /// **'System displays all products in stock. Scan QR code of each product to mark as checked.'**
  String get checklistDescription;

  /// No description provided for @scanImeiBarcode.
  ///
  /// In en, this message translates to:
  /// **'📷 Scan IMEI/Barcode'**
  String get scanImeiBarcode;

  /// No description provided for @scanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Press \"Start scan\" and point camera to QR/barcode to begin checking.'**
  String get scanInstructions;

  /// No description provided for @checkedVsMissing.
  ///
  /// In en, this message translates to:
  /// **'✅ Checked vs ❌ Missing'**
  String get checkedVsMissing;

  /// No description provided for @checkStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Green = scanned and found. Red = not yet scanned. Report shows checked vs missing.'**
  String get checkStatusDescription;

  /// No description provided for @inventoryReport.
  ///
  /// In en, this message translates to:
  /// **'📊 Inventory Report'**
  String get inventoryReport;

  /// No description provided for @reportDescription.
  ///
  /// In en, this message translates to:
  /// **'After scanning, view summary report to know missing and excess items.'**
  String get reportDescription;

  /// No description provided for @errorLoadingInventory.
  ///
  /// In en, this message translates to:
  /// **'Error loading inventory: {error}'**
  String errorLoadingInventory(String error);

  /// No description provided for @phonesCategory.
  ///
  /// In en, this message translates to:
  /// **'Phones'**
  String get phonesCategory;

  /// No description provided for @checkAllPhones.
  ///
  /// In en, this message translates to:
  /// **'Check all phones in stock'**
  String get checkAllPhones;

  /// No description provided for @accessoriesCategory.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get accessoriesCategory;

  /// No description provided for @checkAllAccessories.
  ///
  /// In en, this message translates to:
  /// **'Check all accessories'**
  String get checkAllAccessories;

  /// No description provided for @specialCategory.
  ///
  /// In en, this message translates to:
  /// **'Special'**
  String get specialCategory;

  /// No description provided for @specialProductsCheck.
  ///
  /// In en, this message translates to:
  /// **'Special products need separate check'**
  String get specialProductsCheck;

  /// No description provided for @duplicateScanWarning.
  ///
  /// In en, this message translates to:
  /// **'Scanned this code recently! Wait 3 seconds before scanning again'**
  String get duplicateScanWarning;

  /// No description provided for @phoneMissingImei.
  ///
  /// In en, this message translates to:
  /// **'Phone QR missing IMEI'**
  String get phoneMissingImei;

  /// No description provided for @notInStockError.
  ///
  /// In en, this message translates to:
  /// **'Not in stock'**
  String get notInStockError;

  /// No description provided for @accessoryMissingCode.
  ///
  /// In en, this message translates to:
  /// **'Accessory QR missing code'**
  String get accessoryMissingCode;

  /// No description provided for @unknownAccessory.
  ///
  /// In en, this message translates to:
  /// **'Unknown accessory'**
  String get unknownAccessory;

  /// No description provided for @invalidQrForInventory.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR for inventory check: {error}'**
  String invalidQrForInventory(String error);

  /// No description provided for @productNotFoundById.
  ///
  /// In en, this message translates to:
  /// **'Product not found with ID: {id}'**
  String productNotFoundById(String id);

  /// No description provided for @productNotSupportedForInventory.
  ///
  /// In en, this message translates to:
  /// **'Product not supported for inventory: {type}'**
  String productNotSupportedForInventory(String type);

  /// No description provided for @errorCheckingProduct.
  ///
  /// In en, this message translates to:
  /// **'Error checking product: {error}'**
  String errorCheckingProduct(String error);

  /// No description provided for @qrScanSettings.
  ///
  /// In en, this message translates to:
  /// **'QR SCAN SETTINGS'**
  String get qrScanSettings;

  /// No description provided for @soundFeedback.
  ///
  /// In en, this message translates to:
  /// **'Sound feedback'**
  String get soundFeedback;

  /// No description provided for @playSoundOnScan.
  ///
  /// In en, this message translates to:
  /// **'Play sound when scan'**
  String get playSoundOnScan;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// No description provided for @vibrateOnScan.
  ///
  /// In en, this message translates to:
  /// **'Vibrate device when scan'**
  String get vibrateOnScan;

  /// No description provided for @scanTips.
  ///
  /// In en, this message translates to:
  /// **'Tip: Keep 20-30cm distance from QR code for best results'**
  String get scanTips;

  /// No description provided for @closeButton.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get closeButton;

  /// No description provided for @fastInventoryCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'FAST INVENTORY CHECK'**
  String get fastInventoryCheckTitle;

  /// No description provided for @selectZone.
  ///
  /// In en, this message translates to:
  /// **'Select Zone'**
  String get selectZone;

  /// No description provided for @hideChecklist.
  ///
  /// In en, this message translates to:
  /// **'Hide checklist'**
  String get hideChecklist;

  /// No description provided for @showChecklist.
  ///
  /// In en, this message translates to:
  /// **'Show checklist'**
  String get showChecklist;

  /// No description provided for @scanSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Scan settings'**
  String get scanSettingsButton;

  /// No description provided for @stopScan.
  ///
  /// In en, this message translates to:
  /// **'Stop scan'**
  String get stopScan;

  /// No description provided for @startScan.
  ///
  /// In en, this message translates to:
  /// **'Start scan'**
  String get startScan;

  /// No description provided for @toggleFlash.
  ///
  /// In en, this message translates to:
  /// **'Toggle flash'**
  String get toggleFlash;

  /// No description provided for @phonesChecked.
  ///
  /// In en, this message translates to:
  /// **'📱 Checked'**
  String get phonesChecked;

  /// No description provided for @phonesMissing.
  ///
  /// In en, this message translates to:
  /// **'📱 Missing'**
  String get phonesMissing;

  /// No description provided for @phonesExtra.
  ///
  /// In en, this message translates to:
  /// **'📱 Extra'**
  String get phonesExtra;

  /// No description provided for @accessoriesChecked.
  ///
  /// In en, this message translates to:
  /// **'🔧 Checked'**
  String get accessoriesChecked;

  /// No description provided for @accessoriesMissing.
  ///
  /// In en, this message translates to:
  /// **'🔧 Missing'**
  String get accessoriesMissing;

  /// No description provided for @accessoriesExtra.
  ///
  /// In en, this message translates to:
  /// **'🔧 Extra'**
  String get accessoriesExtra;

  /// No description provided for @pressToStartScan.
  ///
  /// In en, this message translates to:
  /// **'Press scan button to start inventory check'**
  String get pressToStartScan;

  /// No description provided for @scanInstructionsShort.
  ///
  /// In en, this message translates to:
  /// **'Phones: scan IMEI\nAccessories: scan each item'**
  String get scanInstructionsShort;

  /// No description provided for @processingLabel.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processingLabel;

  /// No description provided for @pendingCheckCount.
  ///
  /// In en, this message translates to:
  /// **'Pending ({count})'**
  String pendingCheckCount(int count);

  /// No description provided for @scannedCount.
  ///
  /// In en, this message translates to:
  /// **'Scanned ({count})'**
  String scannedCount(int count);

  /// No description provided for @noProductsInStockMsg.
  ///
  /// In en, this message translates to:
  /// **'No products in stock'**
  String get noProductsInStockMsg;

  /// No description provided for @scannedLabel.
  ///
  /// In en, this message translates to:
  /// **'Scanned: {count}'**
  String scannedLabel(int count);

  /// No description provided for @holdQrSteady.
  ///
  /// In en, this message translates to:
  /// **'Hold QR steady in front of camera'**
  String get holdQrSteady;

  /// No description provided for @selectCheckArea.
  ///
  /// In en, this message translates to:
  /// **'Select check area'**
  String get selectCheckArea;

  /// No description provided for @completedExclamation.
  ///
  /// In en, this message translates to:
  /// **'Completed!'**
  String get completedExclamation;

  /// No description provided for @switchedToZone.
  ///
  /// In en, this message translates to:
  /// **'Switched to zone: {zone}'**
  String switchedToZone(String zone);

  /// No description provided for @labelSettings.
  ///
  /// In en, this message translates to:
  /// **'Product Label Settings'**
  String get labelSettings;

  /// No description provided for @labelTemplates.
  ///
  /// In en, this message translates to:
  /// **'Label Templates'**
  String get labelTemplates;

  /// No description provided for @labelDisplayInfo.
  ///
  /// In en, this message translates to:
  /// **'Information displayed on label'**
  String get labelDisplayInfo;

  /// No description provided for @shopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop Name'**
  String get shopNameLabel;

  /// No description provided for @shopNameExample.
  ///
  /// In en, this message translates to:
  /// **'Ex: HULUCA MOBILE'**
  String get shopNameExample;

  /// No description provided for @hotlineLabel.
  ///
  /// In en, this message translates to:
  /// **'Hotline'**
  String get hotlineLabel;

  /// No description provided for @hotlineExample.
  ///
  /// In en, this message translates to:
  /// **'Ex: 0909 123 456'**
  String get hotlineExample;

  /// No description provided for @sloganLabel.
  ///
  /// In en, this message translates to:
  /// **'Slogan'**
  String get sloganLabel;

  /// No description provided for @sloganExample.
  ///
  /// In en, this message translates to:
  /// **'Ex: Best price guaranteed'**
  String get sloganExample;

  /// No description provided for @addressOptional.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get addressOptional;

  /// No description provided for @addressExample.
  ///
  /// In en, this message translates to:
  /// **'Ex: 123 ABC Street, District 1, HCM'**
  String get addressExample;

  /// No description provided for @cpkPriceSettings.
  ///
  /// In en, this message translates to:
  /// **'CPK Price Settings'**
  String get cpkPriceSettings;

  /// No description provided for @cpkFormulaTitle.
  ///
  /// In en, this message translates to:
  /// **'📌 CPK Price Formula (With Accessories):'**
  String get cpkFormulaTitle;

  /// No description provided for @formulaLabel.
  ///
  /// In en, this message translates to:
  /// **'Formula'**
  String get formulaLabel;

  /// No description provided for @formulaExample.
  ///
  /// In en, this message translates to:
  /// **'price + 500000 or price * 1.05'**
  String get formulaExample;

  /// No description provided for @formulaHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: \"price + 500000\" = Selling price + 500k for with-accessories price'**
  String get formulaHint;

  /// No description provided for @fixedLabelContent.
  ///
  /// In en, this message translates to:
  /// **'Fixed content on label'**
  String get fixedLabelContent;

  /// No description provided for @fixedLabelContentHint.
  ///
  /// In en, this message translates to:
  /// **'These text lines will display by default on all labels'**
  String get fixedLabelContentHint;

  /// No description provided for @line1Label.
  ///
  /// In en, this message translates to:
  /// **'Line 1'**
  String get line1Label;

  /// No description provided for @line2Label.
  ///
  /// In en, this message translates to:
  /// **'Line 2'**
  String get line2Label;

  /// No description provided for @line3Label.
  ///
  /// In en, this message translates to:
  /// **'Line 3'**
  String get line3Label;

  /// No description provided for @line1Example.
  ///
  /// In en, this message translates to:
  /// **'Ex: 100% Authentic guaranteed'**
  String get line1Example;

  /// No description provided for @line2Example.
  ///
  /// In en, this message translates to:
  /// **'Ex: 7-day return policy'**
  String get line2Example;

  /// No description provided for @line3Example.
  ///
  /// In en, this message translates to:
  /// **'Ex: 0% installment support'**
  String get line3Example;

  /// No description provided for @savingLabel.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get savingLabel;

  /// No description provided for @saveSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE SETTINGS'**
  String get saveSettingsButton;

  /// No description provided for @labelSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ Label settings saved!'**
  String get labelSettingsSaved;

  /// No description provided for @errorPrefixLabel.
  ///
  /// In en, this message translates to:
  /// **'❌ Error: {error}'**
  String errorPrefixLabel(String error);

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @deleteTemplateQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete template?'**
  String get deleteTemplateQuestion;

  /// No description provided for @confirmDeleteTemplate.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete template \"{name}\"?'**
  String confirmDeleteTemplate(String name);

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cancelButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get deleteButton;

  /// No description provided for @editTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit label template'**
  String get editTemplateTitle;

  /// No description provided for @templateNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get templateNameLabel;

  /// No description provided for @labelSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Label size'**
  String get labelSizeLabel;

  /// No description provided for @cpkPriceFormulaLabel.
  ///
  /// In en, this message translates to:
  /// **'CPK price formula'**
  String get cpkPriceFormulaLabel;

  /// No description provided for @productInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Product Info'**
  String get productInfoLabel;

  /// No description provided for @productNameField.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productNameField;

  /// No description provided for @productCodeField.
  ///
  /// In en, this message translates to:
  /// **'Product code'**
  String get productCodeField;

  /// No description provided for @qrCodeField.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCodeField;

  /// No description provided for @imeiSerialField.
  ///
  /// In en, this message translates to:
  /// **'IMEI/Serial'**
  String get imeiSerialField;

  /// No description provided for @capacityField.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacityField;

  /// No description provided for @colorField.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorField;

  /// No description provided for @conditionField.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get conditionField;

  /// No description provided for @priceInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Price Info'**
  String get priceInfoLabel;

  /// No description provided for @priceKpkField.
  ///
  /// In en, this message translates to:
  /// **'KPK Price (no accessories)'**
  String get priceKpkField;

  /// No description provided for @priceCpkField.
  ///
  /// In en, this message translates to:
  /// **'CPK Price (with accessories)'**
  String get priceCpkField;

  /// No description provided for @originalPriceField.
  ///
  /// In en, this message translates to:
  /// **'Original price (strikethrough)'**
  String get originalPriceField;

  /// No description provided for @discountPercentField.
  ///
  /// In en, this message translates to:
  /// **'Discount %'**
  String get discountPercentField;

  /// No description provided for @shopInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop Info'**
  String get shopInfoLabel;

  /// No description provided for @otherInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherInfoLabel;

  /// No description provided for @warrantyField.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get warrantyField;

  /// No description provided for @supplierField.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get supplierField;

  /// No description provided for @importDateField.
  ///
  /// In en, this message translates to:
  /// **'Import date'**
  String get importDateField;

  /// No description provided for @pleaseEnterTemplateName.
  ///
  /// In en, this message translates to:
  /// **'Please enter template name'**
  String get pleaseEnterTemplateName;

  /// No description provided for @saveTemplateButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE TEMPLATE'**
  String get saveTemplateButton;

  /// No description provided for @templateUpdated.
  ///
  /// In en, this message translates to:
  /// **'✅ Updated template \"{name}\"'**
  String templateUpdated(String name);

  /// No description provided for @productNameLabelShort.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productNameLabelShort;

  /// No description provided for @detailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsLabel;

  /// No description provided for @labelInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Label Info'**
  String get labelInfoTitle;

  /// No description provided for @priceKpkLabel.
  ///
  /// In en, this message translates to:
  /// **'KPK Price'**
  String get priceKpkLabel;

  /// No description provided for @priceCpkLabel.
  ///
  /// In en, this message translates to:
  /// **'CPK Price'**
  String get priceCpkLabel;

  /// No description provided for @imeiLabel.
  ///
  /// In en, this message translates to:
  /// **'IMEI'**
  String get imeiLabel;

  /// No description provided for @qrLabel.
  ///
  /// In en, this message translates to:
  /// **'QR'**
  String get qrLabel;

  /// No description provided for @shopLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shopLabel;

  /// No description provided for @labelDesignSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ Label design saved!'**
  String get labelDesignSaved;

  /// No description provided for @resetToDefaultQuestion.
  ///
  /// In en, this message translates to:
  /// **'Reset to default?'**
  String get resetToDefaultQuestion;

  /// No description provided for @layoutWillReset.
  ///
  /// In en, this message translates to:
  /// **'Label layout will be reset to original settings.'**
  String get layoutWillReset;

  /// No description provided for @resetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetButton;

  /// No description provided for @labelDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'LABEL DESIGN'**
  String get labelDesignTitle;

  /// No description provided for @layoutTab.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutTab;

  /// No description provided for @ptyDesignerTab.
  ///
  /// In en, this message translates to:
  /// **'PTY 1:1 Designer'**
  String get ptyDesignerTab;

  /// No description provided for @paperTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Paper type:'**
  String get paperTypeLabel;

  /// No description provided for @rollMmLabel.
  ///
  /// In en, this message translates to:
  /// **'Roll (mm)'**
  String get rollMmLabel;

  /// No description provided for @stickerCmLabel.
  ///
  /// In en, this message translates to:
  /// **'Sticker (cm)'**
  String get stickerCmLabel;

  /// No description provided for @rollPaperSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Roll paper size (mm):'**
  String get rollPaperSizeLabel;

  /// No description provided for @customPaperSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom paper size (mm)'**
  String get customPaperSizeLabel;

  /// No description provided for @stickerSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Sticker size (cm):'**
  String get stickerSizeLabel;

  /// No description provided for @widthCmLabel.
  ///
  /// In en, this message translates to:
  /// **'Width (cm)'**
  String get widthCmLabel;

  /// No description provided for @heightCmLabel.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get heightCmLabel;

  /// No description provided for @codeTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code type:'**
  String get codeTypeLabel;

  /// No description provided for @offOption.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offOption;

  /// No description provided for @qrOption.
  ///
  /// In en, this message translates to:
  /// **'QR'**
  String get qrOption;

  /// No description provided for @barcodeOption.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcodeOption;

  /// No description provided for @designInstructions.
  ///
  /// In en, this message translates to:
  /// **'👆 Tap element on template to edit...'**
  String get designInstructions;

  /// No description provided for @zoomPreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Zoom preview:'**
  String get zoomPreviewLabel;

  /// No description provided for @labelPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'LABEL PREVIEW'**
  String get labelPreviewTitle;

  /// No description provided for @tapToSelect.
  ///
  /// In en, this message translates to:
  /// **'Tap to select'**
  String get tapToSelect;

  /// No description provided for @displayOption.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displayOption;

  /// No description provided for @spacingLabel.
  ///
  /// In en, this message translates to:
  /// **'Spacing:'**
  String get spacingLabel;

  /// No description provided for @boldOption.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get boldOption;

  /// No description provided for @fontStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Font style:'**
  String get fontStyleLabel;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Shop Owner'**
  String get roleOwner;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleTechnician.
  ///
  /// In en, this message translates to:
  /// **'Technician'**
  String get roleTechnician;

  /// No description provided for @roleCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get roleCashier;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @helpCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenterTitle;

  /// No description provided for @searchByKeyword.
  ///
  /// In en, this message translates to:
  /// **'Search by keyword, feature...'**
  String get searchByKeyword;

  /// No description provided for @suggestionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestionsLabel;

  /// No description provided for @feedbackContact.
  ///
  /// In en, this message translates to:
  /// **'Have feature suggestions? Contact support@huluca.com'**
  String get feedbackContact;

  /// No description provided for @feedbackSupport.
  ///
  /// In en, this message translates to:
  /// **'Feedback / Support'**
  String get feedbackSupport;

  /// No description provided for @noGuideFound.
  ///
  /// In en, this message translates to:
  /// **'No guide found matching keyword.'**
  String get noGuideFound;

  /// No description provided for @otherTopics.
  ///
  /// In en, this message translates to:
  /// **'Other topics'**
  String get otherTopics;

  /// No description provided for @stepsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} steps'**
  String stepsCountLabel(int count);

  /// No description provided for @tipsCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} tips'**
  String tipsCountLabel(int count);

  /// No description provided for @quickGuide.
  ///
  /// In en, this message translates to:
  /// **'Quick Guide'**
  String get quickGuide;

  /// No description provided for @quickGuideDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a topic or enter keyword...'**
  String get quickGuideDescription;

  /// No description provided for @contentStandard.
  ///
  /// In en, this message translates to:
  /// **'All content is prepared according to Shopmanager standards.'**
  String get contentStandard;

  /// No description provided for @forRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'For {role}'**
  String forRoleLabel(String role);

  /// No description provided for @estimatedTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated time: {time}'**
  String estimatedTimeLabel(String time);

  /// No description provided for @difficultyLabel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty: {level}'**
  String difficultyLabel(String level);

  /// No description provided for @prerequisitesLabel.
  ///
  /// In en, this message translates to:
  /// **'Prerequisites'**
  String get prerequisitesLabel;

  /// No description provided for @stepsLabel.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get stepsLabel;

  /// No description provided for @tipsAndNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Tips & Notes'**
  String get tipsAndNotesLabel;

  /// No description provided for @watchVideoLabel.
  ///
  /// In en, this message translates to:
  /// **'Watch video tutorial'**
  String get watchVideoLabel;

  /// No description provided for @attachmentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsLabel;

  /// No description provided for @relatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get relatedLabel;

  /// No description provided for @needHelpLabel.
  ///
  /// In en, this message translates to:
  /// **'Need help? Contact support team: support@huluca.com'**
  String get needHelpLabel;

  /// No description provided for @understoodGuide.
  ///
  /// In en, this message translates to:
  /// **'I understood this guide'**
  String get understoodGuide;

  /// No description provided for @markedAsViewed.
  ///
  /// In en, this message translates to:
  /// **'Marked this guide as viewed.'**
  String get markedAsViewed;

  /// No description provided for @videoGuideLabel.
  ///
  /// In en, this message translates to:
  /// **'Video Guide'**
  String get videoGuideLabel;

  /// No description provided for @videosBeingUpdated.
  ///
  /// In en, this message translates to:
  /// **'Video tutorials are being updated.'**
  String get videosBeingUpdated;

  /// No description provided for @contactSupportLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get contactSupportLabel;

  /// No description provided for @sendEmailForHelp.
  ///
  /// In en, this message translates to:
  /// **'Send email to support@huluca.com for quick assistance.'**
  String get sendEmailForHelp;

  /// No description provided for @suggestImprovementLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggest Improvement'**
  String get suggestImprovementLabel;

  /// No description provided for @feedbackHelps.
  ///
  /// In en, this message translates to:
  /// **'Your feedback helps make documentation better!'**
  String get feedbackHelps;

  /// No description provided for @filteredByRole.
  ///
  /// In en, this message translates to:
  /// **'Filtered guides matching your role.'**
  String get filteredByRole;

  /// No description provided for @featuredLabel.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get featuredLabel;

  /// No description provided for @quickLabel.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get quickLabel;

  /// No description provided for @needMoreHelpLabel.
  ///
  /// In en, this message translates to:
  /// **'Need more help?'**
  String get needMoreHelpLabel;

  /// No description provided for @hulucaTeamSupport.
  ///
  /// In en, this message translates to:
  /// **'Huluca team is ready to support via email, Zalo or direct training.'**
  String get hulucaTeamSupport;

  /// No description provided for @emailSupportLabel.
  ///
  /// In en, this message translates to:
  /// **'Email support@huluca.com'**
  String get emailSupportLabel;

  /// No description provided for @emailCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied email support@huluca.com'**
  String get emailCopied;

  /// No description provided for @zaloSupportLabel.
  ///
  /// In en, this message translates to:
  /// **'Zalo Support'**
  String get zaloSupportLabel;

  /// No description provided for @contactZaloLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact Zalo Support: 0901 234 567'**
  String get contactZaloLabel;

  /// No description provided for @scheduleTrainingLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule Training'**
  String get scheduleTrainingLabel;

  /// No description provided for @scheduleTrainingThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Schedule online training this week.'**
  String get scheduleTrainingThisWeek;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @defaultSettings.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultSettings;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @switchShop.
  ///
  /// In en, this message translates to:
  /// **'Switch shop'**
  String get switchShop;

  /// No description provided for @currentShop.
  ///
  /// In en, this message translates to:
  /// **'Current Shop'**
  String get currentShop;

  /// No description provided for @shopSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to: {shopName}'**
  String shopSwitched(Object shopName);

  /// No description provided for @cannotSwitchShop.
  ///
  /// In en, this message translates to:
  /// **'Cannot switch shop'**
  String get cannotSwitchShop;

  /// No description provided for @createNewBranch.
  ///
  /// In en, this message translates to:
  /// **'Create new branch'**
  String get createNewBranch;

  /// No description provided for @branchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get branchName;

  /// No description provided for @branchCreated.
  ///
  /// In en, this message translates to:
  /// **'Branch created: {name}'**
  String branchCreated(Object name);

  /// No description provided for @errorCreatingBranch.
  ///
  /// In en, this message translates to:
  /// **'Error creating branch'**
  String get errorCreatingBranch;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @phoneLengthInvalid.
  ///
  /// In en, this message translates to:
  /// **'Phone number must be 9-12 digits'**
  String get phoneLengthInvalid;

  /// No description provided for @imeiMinLength.
  ///
  /// In en, this message translates to:
  /// **'IMEI must be at least 6 characters'**
  String get imeiMinLength;

  /// No description provided for @imeiLengthInvalid.
  ///
  /// In en, this message translates to:
  /// **'IMEI must be 6-20 characters'**
  String get imeiLengthInvalid;

  /// No description provided for @imeiDigitsOnly.
  ///
  /// In en, this message translates to:
  /// **'IMEI must contain only digits'**
  String get imeiDigitsOnly;

  /// No description provided for @modelMinLength.
  ///
  /// In en, this message translates to:
  /// **'Model must be at least 2 characters'**
  String get modelMinLength;

  /// No description provided for @modelMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Model must not exceed 50 characters'**
  String get modelMaxLength;

  /// No description provided for @printLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Print Label'**
  String get printLabelTitle;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailable;

  /// No description provided for @productInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Product Information'**
  String get productInfoTitle;

  /// No description provided for @productNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Product Name:'**
  String get productNameLabel;

  /// No description provided for @productDetailLabel.
  ///
  /// In en, this message translates to:
  /// **'Detail:'**
  String get productDetailLabel;

  /// No description provided for @imeiLabelWithColon.
  ///
  /// In en, this message translates to:
  /// **'IMEI:'**
  String get imeiLabelWithColon;

  /// No description provided for @originalPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Original Price:'**
  String get originalPriceLabel;

  /// No description provided for @labelModeAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto Mode'**
  String get labelModeAutoTitle;

  /// No description provided for @labelModeAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use label design settings'**
  String get labelModeAutoSubtitle;

  /// No description provided for @labelModeCustomTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Mode'**
  String get labelModeCustomTitle;

  /// No description provided for @labelModeCustomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter custom prices and text'**
  String get labelModeCustomSubtitle;

  /// No description provided for @labelCustomContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Content'**
  String get labelCustomContentTitle;

  /// No description provided for @labelKpkExplain.
  ///
  /// In en, this message translates to:
  /// **'KPK: \"Không phải không\" price'**
  String get labelKpkExplain;

  /// No description provided for @labelCpkExplain.
  ///
  /// In en, this message translates to:
  /// **'CPK: \"Có phải không\" price'**
  String get labelCpkExplain;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'₫'**
  String get currencySymbol;

  /// No description provided for @deviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device Name'**
  String get deviceNameLabel;

  /// No description provided for @productDetailLabelPlain.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get productDetailLabelPlain;

  /// No description provided for @qrCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCodeLabel;

  /// No description provided for @addCustomLinesLabel.
  ///
  /// In en, this message translates to:
  /// **'Add Custom Lines'**
  String get addCustomLinesLabel;

  /// No description provided for @customLine1Hint.
  ///
  /// In en, this message translates to:
  /// **'Custom line 1...'**
  String get customLine1Hint;

  /// No description provided for @customLine2Hint.
  ///
  /// In en, this message translates to:
  /// **'Custom line 2...'**
  String get customLine2Hint;

  /// No description provided for @customLine3Hint.
  ///
  /// In en, this message translates to:
  /// **'Custom line 3...'**
  String get customLine3Hint;

  /// No description provided for @printQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Print Quantity'**
  String get printQuantityLabel;

  /// No description provided for @priceKpkPrefix.
  ///
  /// In en, this message translates to:
  /// **'KPK: '**
  String get priceKpkPrefix;

  /// No description provided for @priceCpkPrefix.
  ///
  /// In en, this message translates to:
  /// **'CPK: '**
  String get priceCpkPrefix;

  /// No description provided for @imeiPrefix.
  ///
  /// In en, this message translates to:
  /// **'IMEI: '**
  String get imeiPrefix;

  /// No description provided for @printingLabel.
  ///
  /// In en, this message translates to:
  /// **'Printing...'**
  String get printingLabel;

  /// No description provided for @printLabelQuantity.
  ///
  /// In en, this message translates to:
  /// **'Print {count} labels'**
  String printLabelQuantity(int count);

  /// No description provided for @printLabelSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully printed {count} labels'**
  String printLabelSuccess(int count);

  /// No description provided for @printLabelPartial.
  ///
  /// In en, this message translates to:
  /// **'Printed {success}/{total} labels'**
  String printLabelPartial(int success, int total);

  /// No description provided for @printLabelError.
  ///
  /// In en, this message translates to:
  /// **'Print error: {error}'**
  String printLabelError(String error);

  /// No description provided for @imeiWithValue.
  ///
  /// In en, this message translates to:
  /// **'IMEI: {imei}'**
  String imeiWithValue(String imei);

  /// No description provided for @labelNoteFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Label Note'**
  String get labelNoteFieldLabel;

  /// No description provided for @labelNoteFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Additional note for label...'**
  String get labelNoteFieldHint;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{fieldName} is required'**
  String fieldRequired(String fieldName);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'vi': return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
