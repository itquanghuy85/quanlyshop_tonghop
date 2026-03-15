import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/social_auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/responsive_wrapper.dart';
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailC.text.trim(),
        password: _passC.text.trim(),
      );
      // syncUserInfo will be called by AuthGate._getRoleAfterSync
      // Do NOT call it here to avoid double-sync race conditions on web
      await _saveAccount();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = _mapLoginError(e));
      }
    } catch (e) {
      // Catch non-Firebase errors (network timeout, etc.)
      if (mounted) {
        setState(() => _error = 'Lỗi kết nối. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _mapLoginError(FirebaseAuthException e) {
    final loc = AppLocalizations.of(context)!;
    switch (e.code) {
      case 'network-request-failed':
        return loc.networkError;
      case 'too-many-requests':
        return loc.tooManyRequests;
      case 'invalid-email':
        return loc.invalidEmailFormat;
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return loc.loginError;
      case 'operation-not-allowed':
        return 'Phương thức Email/Password chưa bật trên Firebase Auth.';
      case 'app-not-authorized':
      case 'invalid-api-key':
      case 'unauthorized-domain':
        return 'Cấu hình Firebase cho nền tảng này chưa đúng. Vui lòng kiểm tra Authorized domains và firebase_options.dart.';
      default:
        return e.message ?? loc.loginError;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await SocialAuthService.signInWithGoogle();
      if (result == null && mounted) {
        setState(() => _loading = false);
      }
      // AuthGate will handle navigation after successful sign-in
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Lỗi đăng nhập Google';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi đăng nhập Google. Vui lòng thử lại.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await SocialAuthService.signInWithApple();
      if (result == null && mounted) {
        setState(() => _loading = false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Lỗi đăng nhập Apple';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi đăng nhập Apple. Vui lòng thử lại.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _emailC.text.trim());
    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_reset, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.forgotPassword),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.forgotPasswordDesc,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.email,
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel.toUpperCase()),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.pleaseEnterValidEmail,
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(
                        context,
                      )!.passwordResetEmailSent(email),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 5),
                  ),
                );
              } on FirebaseAuthException catch (e) {
                String errorMsg = AppLocalizations.of(
                  context,
                )!.errorSendingEmail;
                if (e.code == 'user-not-found') {
                  errorMsg = AppLocalizations.of(context)!.emailNotRegistered;
                } else if (e.code == 'invalid-email') {
                  errorMsg = AppLocalizations.of(context)!.invalidEmailFormat;
                }
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(errorMsg),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(
              AppLocalizations.of(context)!.sendEmail,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    emailController.dispose();
  }

  Locale _selectedLocale = const Locale('vi');
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 80,
                color: AppColors.primary,
              ),
              const SizedBox(height: 10),
              Text(
                localizations.shopManagement,
                style: AppTextStyles.headline4.copyWith(
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              // Language switcher
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.language,
                      color: AppColors.primary,
                      size: 20,
                    ),
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
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.primary,
                      ),
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: const Locale('vi'),
                          child: Row(
                            children: [
                              Text(
                                '🇻🇳 ',
                                style: TextStyle(
                                  fontSize: AppTextStyles.headline3.fontSize,
                                ),
                              ),
                              Text(localizations.vietnamese),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: const Locale('en'),
                          child: Row(
                            children: [
                              Text(
                                '🇺🇸 ',
                                style: TextStyle(
                                  fontSize: AppTextStyles.headline3.fontSize,
                                ),
                              ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  helperText: localizations.emailExample,
                  helperStyle: AppTextStyles.caption.copyWith(
                    color: AppColors.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passC,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: localizations.password,
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                  ),
                  Text(localizations.rememberMe),
                  const Spacer(),
                  TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: Text(
                      AppLocalizations.of(context)!.forgotPassword,
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: AppTextStyles.body2.copyWith(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: AppButtonStyles.elevatedButtonStyle,
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: AppColors.onPrimary,
                        )
                      : Text(
                          localizations.signIn.toUpperCase(),
                          style: AppTextStyles.button,
                        ),
                ),
              ),
              const SizedBox(height: 15),
              // ── OR divider ──
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'HOẶC',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 15),
              // ── Google Sign-In ──
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  icon: Image.network(
                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                    height: 20,
                    width: 20,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.g_mobiledata,
                      size: 24,
                      color: Colors.red,
                    ),
                  ),
                  label: const Text(
                    'Đăng nhập bằng Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // ── Apple Sign-In (only iOS/macOS/web) ──
              if (kIsWeb || (!kIsWeb && Platform.isIOS) || (!kIsWeb && Platform.isMacOS)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _signInWithApple,
                    icon: const Icon(Icons.apple, size: 22),
                    label: const Text(
                      'Đăng nhập bằng Apple',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // ── Link account hint ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade400, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đã có tài khoản Email? Đăng nhập Email trước, liên kết Google/Apple trong Cài đặt',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade700, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterView()),
                  );
                  if (!mounted) return;
                  if (result == true && FirebaseAuth.instance.currentUser == null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(localizations.registerSuccess)),
                    );
                  }
                },

                child: Text(
                  localizations.noAccountRegisterNow,
                  style: AppTextStyles.body2.copyWith(color: AppColors.primary),
                ),
              ),

              const SizedBox(height: 30),
              _buildCalendarCard(),
            ],
          ),
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
    final firstDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    );
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final startWeekday = firstDayOfMonth.weekday; // Monday = 1, Sunday = 7

    final List<Widget> dayCells = [];

    for (int i = 1; i < startWeekday; i++) {
      dayCells.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final bool isToday =
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;

      dayCells.add(
        Container(
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
        ),
      );
    }

    while (dayCells.length % 7 != 0) {
      dayCells.add(const SizedBox());
    }

    final List<Row> weekRows = [];
    for (int i = 0; i < dayCells.length; i += 7) {
      weekRows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: dayCells.sublist(i, i + 7).map((w) {
            return Expanded(child: w);
          }).toList(),
        ),
      );
    }

    final monthYearText =
        '${_currentMonth.month.toString().padLeft(2, '0')}/${_currentMonth.year}';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
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
                        AppLocalizations.of(context)!.perpetualCalendarTitle,
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.todayDateFormat(
                          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}',
                        ),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(
                        Icons.chevron_left,
                        color: AppColors.onPrimary,
                      ),
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
                      icon: const Icon(
                        Icons.chevron_right,
                        color: AppColors.onPrimary,
                      ),
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
                    child: Text(
                      AppLocalizations.of(context)!.monday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.tuesday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.wednesday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.thursday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.friday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.saturday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.sunday,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
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
