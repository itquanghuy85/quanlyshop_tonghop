import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';
import '../widgets/custom_app_bar.dart';
import 'financial_report_view.dart';
import 'expense_view.dart';
import 'bank_installment_report_view.dart';
import 'financial_activity_log_view.dart';

/// Unified Financial Hub - Consolidates 4 financial views into one tabbed interface:
/// - Tab 1: Báo cáo giao dịch (FinancialReportView)
/// - Tab 2: Chi phí (ExpenseView)
/// - Tab 3: Trả góp NH (BankInstallmentReportView)
/// - Tab 4: Nhật ký (FinancialActivityLogView)
///
/// This replaces 4 separate navigation entries in the finance tab with one,
/// reducing clutter while keeping all functionality intact.
class FinancialHubView extends StatefulWidget {
  final int initialTab;
  const FinancialHubView({super.key, this.initialTab = 0});

  @override
  State<FinancialHubView> createState() => _FinancialHubViewState();
}

class _FinancialHubViewState extends State<FinancialHubView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: CustomAppBar.buildWithTabs(
        title: loc?.financialManagement ?? 'Quản lý Tài chính',
        tabController: _tabController,
        tabs: [
          CustomTabBar.iconTab(Icons.assessment, loc?.financialReport ?? 'Báo cáo'),
          CustomTabBar.iconTab(Icons.money_off, loc?.expenseManagement ?? 'Chi phí'),
          CustomTabBar.iconTab(Icons.account_balance, loc?.bankInstallmentStats ?? 'Trả góp'),
          CustomTabBar.iconTab(Icons.receipt_long, loc?.financialActivityLog ?? 'Nhật ký'),
        ],
        isScrollable: true,
        accentColor: AppBarAccents.finance,
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FinancialReportView(embedded: true),
          ExpenseView(embedded: true),
          BankInstallmentReportView(embedded: true),
          FinancialActivityLogView(embedded: true),
        ],
      ),
    );
  }
}
