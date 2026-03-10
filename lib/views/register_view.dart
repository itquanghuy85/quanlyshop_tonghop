import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/category_service.dart';
import '../models/shop_settings_model.dart';
import '../theme/app_text_styles.dart';
import '../widgets/responsive_wrapper.dart';

class RegisterView extends StatefulWidget {
  final Function(Locale)? setLocale;
  const RegisterView({super.key, this.setLocale});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  // Localization getter
  AppLocalizations get loc => AppLocalizations.of(context)!;
  
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmPassC = TextEditingController();
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _addressC = TextEditingController();
  final _shopNameC = TextEditingController();
  final _inviteCodeC = TextEditingController();

  bool _loading = false;
  String? _error;
  bool _isJoinShop = false; 
  int _currentStep = 0; 
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String _selectedBusinessType = 'electronics'; // Default business type
  String _selectedRole = 'employee'; // Default role for join shop

  @override
  void initState() {
    super.initState();
    _nameC.addListener(_updateEmail);
    _shopNameC.addListener(_updateEmail);
  }

  void _updateEmail() {
    final name = _nameC.text.trim();
    final shopName = _shopNameC.text.trim();
    if (name.isNotEmpty && shopName.isNotEmpty) {
      final normalizedName = _removeDiacritics(name.toLowerCase().replaceAll(' ', ''));
      final normalizedShopName = _removeDiacritics(shopName.toLowerCase().replaceAll(' ', ''));
      _emailC.text = '$normalizedName@$normalizedShopName.com';
    }
  }

  String _removeDiacritics(String str) {
    const vietnamese = 'aAeEoOuUiIdDyY';
    // ĐÃ GỠ BỎ TỪ KHÓA CONST Ở ĐÂY ĐỂ TRÁNH LỖI BUILD
    final vietnameseRegex = [
      RegExp(r'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ'),
      RegExp(r'À|Á|Ạ|Ả|Ã|Â|Ầ|Ấ|Ậ|Ẩ|Ẫ|Ă|Ằ|Ắ|Ặ|Ẳ|Ẵ'),
      RegExp(r'è|é|ẹ|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ'),
      RegExp(r'È|É|Ạ|Ẻ|Ẽ|Ê|Ề|Ế|Ệ|Ể|Ễ'),
      RegExp(r'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ'),
      RegExp(r'Ò|Ó|Ọ|Ỏ|Õ|Ô|Ồ|Ố|Ộ|Ổ|Ỗ|Ơ|Ờ|Ớ|Ợ|Ở|Ỡ'),
      RegExp(r'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ'),
      RegExp(r'Ù|Ú|Ụ|Ủ|Ũ|Ư|Ừ|Ứ|Ự|Ử|Ữ'),
      RegExp(r'ì|í|ị|ỉ|ĩ'),
      RegExp(r'Ì|Í|Ị|Ỉ|Ĩ'),
      RegExp(r'đ'),
      RegExp(r'Đ'),
      RegExp(r'ỳ|ý|ỵ|ỷ|ỹ'),
      RegExp(r'Ỳ|Ý|Ỵ|Ỷ|Ỹ'),
    ];
    for (var i = 0; i < vietnameseRegex.length; i++) {
      str = str.replaceAll(vietnameseRegex[i], vietnamese[i]);
    }
    return str;
  }

  @override
  void dispose() {
    _emailC.dispose(); _passC.dispose(); _confirmPassC.dispose();
    _nameC.dispose(); _phoneC.dispose(); _addressC.dispose();
    _shopNameC.dispose(); _inviteCodeC.dispose();
    super.dispose();
  }

  String _formatError(dynamic e) {
    final String err = e.toString();
    if (err.contains('email-already-in-use')) return loc.emailAlreadyInUse;
    if (err.contains('weak-password')) return loc.weakPassword;
    if (err.contains('invalid-email')) return loc.invalidEmailAddress;
    if (err.contains('network-request-failed')) return loc.networkError;
    if (err.contains('too-many-requests')) return loc.tooManyRequests;
    return err.replaceAll("Exception: ", "").replaceAll("PlatformException(", "").replaceAll(")", "");
  }

  Future<void> _register() async {
    setState(() { _loading = true; _error = null; });
    try {
      final email = _emailC.text.trim();
      final pass = _passC.text.trim();
      final shopName = _shopNameC.text.trim();
      final name = _nameC.text.trim();

      if (shopName.isEmpty) throw loc.pleaseEnterShopName;
      if (name.isEmpty) throw loc.pleaseEnterFullName;
      if (email.isEmpty || pass.isEmpty) throw loc.pleaseEnterRequiredFields;
      if (pass != _confirmPassC.text.trim()) throw loc.passwordMismatch;

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      if (cred.user != null) {
        try {
          if (_isJoinShop) {
            final success = await UserService.useInviteCode(_inviteCodeC.text.trim(), cred.user!.uid);
            if (!success) throw loc.invalidOrExpiredInviteCode;
            // Save employee displayName + info to Firestore (useInviteCode only sets shopId)
            await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
              'displayName': name.toUpperCase(),
              'email': email,
              'phone': _phoneC.text.trim(),
              'address': _addressC.text.trim().toUpperCase(),
              'role': _selectedRole,
            }, SetOptions(merge: true));
            // Also set Firebase Auth displayName for fast lookup
            await cred.user!.updateDisplayName(name.toUpperCase());
          } else {
            // Create user info with business type
            await UserService.syncUserInfo(cred.user!.uid, email, extra: {
              'displayName': name.toUpperCase(),
              'phone': _phoneC.text.trim(),
              'address': _addressC.text.trim().toUpperCase(),
              'shopName': shopName.toUpperCase(),
            });
            // Also set Firebase Auth displayName for fast lookup
            await cred.user!.updateDisplayName(name.toUpperCase());
            
            // Save shop settings with business type
            final shopId = await UserService.getCurrentShopId();
            if (shopId != null) {
              final settings = ShopSettings.fromBusinessType(_selectedBusinessType, shopId);
              await CategoryService().saveShopSettings(settings);
            }
          }
        } catch (e) {
          // Sign out on setup error to avoid stuck auth state
          await FirebaseAuth.instance.signOut();
          rethrow;
        }
        // Sign out to avoid race condition with AuthGate's syncUserInfo
        // User will log in manually with the new account
        await FirebaseAuth.instance.signOut();
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      final errorMsg = _formatError(e);
      setState(() { _error = errorMsg; _loading = false; });
      NotificationService.showSnackBar(errorMsg, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(AppLocalizations.of(context)!.registerAccount, style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: true,
      ),
      body: ResponsiveCenter(
        maxWidth: 480,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildStepIndicator(),
            const SizedBox(height: 30),
            _currentStep == 0 ? _stepSelectRole() : _stepInputInfo(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepNode(0, AppLocalizations.of(context)!.storeOwner, _currentStep >= 0),
        Expanded(child: Container(height: 2, color: _currentStep >= 1 ? Colors.blueAccent : Colors.grey.shade300)),
        _stepNode(1, AppLocalizations.of(context)!.information, _currentStep >= 1),
      ],
    );
  }

  Widget _stepNode(int step, String label, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? Colors.blueAccent : Colors.grey.shade300,
          child: Text("${step + 1}", style: TextStyle(color: active ? Colors.white : Colors.grey, fontSize: AppTextStyles.subtitle1.fontSize)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: active ? Colors.blueAccent : Colors.grey)),
      ],
    );
  }

  Widget _stepSelectRole() {
    return Column(
      children: [
        _roleOption(false, AppLocalizations.of(context)!.storeOwner, AppLocalizations.of(context)!.createNewShop, Icons.storefront),
        const SizedBox(height: 16),
        _roleOption(true, AppLocalizations.of(context)!.employee, AppLocalizations.of(context)!.joinExistingShop, Icons.badge),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () => setState(() => _currentStep = 1),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(AppLocalizations.of(context)!.next, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _roleOption(bool value, String title, String desc, IconData icon) {
    final selected = _isJoinShop == value;
    return GestureDetector(
      onTap: () => setState(() => _isJoinShop = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: selected ? Colors.blueAccent : Colors.grey.shade200, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.blueAccent : Colors.grey, size: 30),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(desc, style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade600))])),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? Colors.blueAccent : Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _stepInputInfo() {
    return Column(
      children: [
        _input(_shopNameC, AppLocalizations.of(context)!.shopName, Icons.shop),
        _input(_nameC, AppLocalizations.of(context)!.fullName, Icons.person),
        _input(_phoneC, AppLocalizations.of(context)!.phoneNumber, Icons.phone, type: TextInputType.phone),
        _input(_emailC, AppLocalizations.of(context)!.loginEmail, Icons.email, readOnly: true, helperText: AppLocalizations.of(context)!.emailAutoGenerated),
        _input(_passC, AppLocalizations.of(context)!.password, Icons.lock, obscure: _obscurePass, suffix: IconButton(icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePass = !_obscurePass))),
        _input(_confirmPassC, AppLocalizations.of(context)!.confirmPassword, Icons.lock_clock, obscure: _obscureConfirm, suffix: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm))),
        _input(_addressC, AppLocalizations.of(context)!.address, Icons.map),
        // Business type selection for store owners
        if (!_isJoinShop) ...[
          const SizedBox(height: 8),
          _buildBusinessTypeSelector(),
          const SizedBox(height: 8),
        ],
        if (_isJoinShop) ...[
          _input(_inviteCodeC, AppLocalizations.of(context)!.shopInviteCode, Icons.qr_code),          // Role selection for join shop
          _buildRoleSelector(),
          const SizedBox(height: 8),          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.howToGetInviteCode,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: AppTextStyles.headline4.fontSize,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.joinShopInstructions,
                  style: TextStyle(
                    fontSize: AppTextStyles.headline5.fontSize,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInstructionStep(1, AppLocalizations.of(context)!.storeOwnerLogin),
                _buildInstructionStep(2, AppLocalizations.of(context)!.selectStaffTab),
                _buildInstructionStep(3, AppLocalizations.of(context)!.selectEmployeeList),
                _buildInstructionStep(4, AppLocalizations.of(context)!.selectRegisterEmployee),
                _buildInstructionStep(5, AppLocalizations.of(context)!.ownerProvidesCredentials),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.loginWithCredentials,
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        
        if (_error != null) Text(_error!, style: TextStyle(color: Colors.red, fontSize: AppTextStyles.headline5.fontSize)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _currentStep = 0), child: Text(AppLocalizations.of(context)!.back))),
            const SizedBox(width: 16),
            Expanded(child: ElevatedButton(onPressed: _loading ? null : _register, child: _loading ? const CircularProgressIndicator() : Text(AppLocalizations.of(context)!.register))),
          ],
        ),
      ],
    );
  }

  Widget _input(TextEditingController c, String l, IconData i, {bool obscure = false, TextInputType type = TextInputType.text, bool readOnly = false, Widget? suffix, String? helperText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: c, obscureText: obscure, keyboardType: type, readOnly: readOnly,
        decoration: InputDecoration(
          labelText: l, prefixIcon: Icon(i, size: 20), suffixIcon: suffix,
          helperText: helperText, helperStyle: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true, fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int step, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              instruction,
              style: TextStyle(
                fontSize: AppTextStyles.headline5.fontSize,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    final roles = [
      {'value': 'manager', 'label': '👔 Quản lý', 'desc': 'Toàn quyền quản lý cửa hàng'},
      {'value': 'employee', 'label': '🧑‍💼 Nhân viên', 'desc': 'Bán hàng, nhận đơn sửa'},
      {'value': 'technician', 'label': '🔧 Kỹ thuật', 'desc': 'Sửa chữa thiết bị'},
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vai trò trong cửa hàng',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...roles.map((r) {
            final selected = _selectedRole == r['value'];
            return GestureDetector(
              onTap: () => setState(() => _selectedRole = r['value'] as String),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.blue.withOpacity(0.1) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? Colors.blue : Colors.grey.shade200,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(r['label'] as String, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r['desc'] as String,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_off,
                      color: selected ? Colors.blue : Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBusinessTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Loại hình kinh doanh',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _businessTypeOption('electronics', '📱 Điện tử', 'Điện thoại, laptop, phụ kiện', Colors.blue),
          // Food và General tạm ẩn - chỉ hỗ trợ Electronics và Fashion
          // _businessTypeOption('food', '🍎 Thực phẩm', 'Rau củ, thịt cá, đồ khô', Colors.green),
          _businessTypeOption('fashion', '👕 Thời trang', 'Quần áo, giày dép, túi xách', Colors.blue),
          // _businessTypeOption('general', '📦 Tổng hợp', 'Các loại khác, tự thiết lập', Colors.orange),
        ],
      ),
    );
  }

  Widget _businessTypeOption(String type, String title, String desc, Color color) {
    final selected = _selectedBusinessType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedBusinessType = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                desc,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_off,
              color: selected ? color : Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
