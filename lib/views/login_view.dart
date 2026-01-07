import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'register_view.dart';

class LoginView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const LoginView({super.key, this.setLocale});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  bool _loading = false;
  bool _rememberMe = false;
  String? _error;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailC.text = prefs.getString('saved_email') ?? '';
      _passC.text = prefs.getString('saved_pass') ?? '';
      _rememberMe = prefs.getBool('remember_me') ?? false;
    });
  }

  Future<void> _saveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailC.text.trim());
      await prefs.setString('saved_pass', _passC.text.trim());
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('saved_email');
      await prefs.remove('saved_pass');
      await prefs.setBool('remember_me', false);
    }
  }

  Future<void> _login() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailC.text.trim(),
        password: _passC.text.trim(),
      );
      final u = cred.user;
      if (u != null && u.email != null) {
        await UserService.syncUserInfo(u.uid, u.email!);
      }
      await _saveAccount();
    } on FirebaseAuthException {
      if (mounted) setState(() => _error = AppLocalizations.of(context)!.loginError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Locale _selectedLocale = const Locale('vi');
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront_rounded, size: 80, color: AppColors.primary),
              const SizedBox(height: 10),
              Text(localizations.shopManagement, style: AppTextStyles.headline4.copyWith(color: AppColors.primary)),
              const SizedBox(height: 20),
              // Language switcher
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      localizations.selectLanguage,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 24,
                      width: 1,
                      color: AppColors.primary.withOpacity(0.5),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<Locale>(
                      value: _selectedLocale,
                      underline: const SizedBox(),
                      icon: Icon(Icons.arrow_drop_down, color: AppColors.primary),
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: const Locale('vi'),
                          child: Row(
                            children: [
                              const Text('🇻🇳 ', style: TextStyle(fontSize: 16)),
                              Text(localizations.vietnamese),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: const Locale('en'),
                          child: Row(
                            children: [
                              const Text('🇺🇸 ', style: TextStyle(fontSize: 16)),
                              Text(localizations.english),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (locale) {
                        if (locale != null) {
                          setState(() => _selectedLocale = locale);
                          widget.setLocale?.call(locale);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailC,
                decoration: InputDecoration(
                  labelText: localizations.email,
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'Ví dụ: ten@domain.com hoặc ten@gmail.com',
                  helperStyle: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passC,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: localizations.password,
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                  ),
                  Text(localizations.rememberMe),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: AppTextStyles.body2.copyWith(color: AppColors.error)),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: AppButtonStyles.elevatedButtonStyle,
                  child: _loading
                      ? const CircularProgressIndicator(color: AppColors.onPrimary)
                      : Text(localizations.signIn.toUpperCase(), style: AppTextStyles.button),
                ),
              ),              const SizedBox(height: 15),
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterView()));
                  if (result == true) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Đăng ký thành công! Vui lòng đăng nhập.')),
                    );
                  }
                },


                child: Text('Chưa có tài khoản? Đăng ký ngay', style: AppTextStyles.body2.copyWith(color: AppColors.primary)),
              ),              const SizedBox(height: 30),
              _buildCalendarCard(),
            ],
          ),
        ),
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta);
    });
  }

  Widget _buildCalendarCard() {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // Monday = 1, Sunday = 7

    final List<Widget> dayCells = [];

    for (int i = 1; i < startWeekday; i++) {
      dayCells.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final bool isToday =
          date.year == now.year && date.month == now.month && date.day == now.day;

      dayCells.add(Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '$day',
            style: AppTextStyles.caption.copyWith(
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              color: isToday ? AppColors.onPrimary : AppColors.onSurface,
            ),
          ),
        ),
      ));
    }

    while (dayCells.length % 7 != 0) {
      dayCells.add(const SizedBox());
    }

    final List<Row> weekRows = [];
    for (int i = 0; i < dayCells.length; i += 7) {
      weekRows.add(Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: dayCells.sublist(i, i + 7).map((w) {
          return Expanded(child: w);
        }).toList(),
      ));
    }

    final monthYearText = '${_currentMonth.month.toString().padLeft(2, '0')}/${_currentMonth.year}';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lịch vạn niên',
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hôm nay: ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.onPrimary.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left, color: AppColors.onPrimary),
                    ),
                    Text(
                      monthYearText,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right, color: AppColors.onPrimary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: Text('T2', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('T3', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('T4', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('T5', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('T6', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('T7', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text('CN', style: AppTextStyles.overline.copyWith(color: AppColors.onPrimary)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...weekRows,
          ],
        ),
      ),
    );
  }
}
