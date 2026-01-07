import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';

class RegisterView extends StatefulWidget {
  final Function(Locale)? setLocale;
  const RegisterView({super.key, this.setLocale});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
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
    if (err.contains('email-already-in-use')) return "Email này đã được đăng ký bởi người khác.";
    if (err.contains('weak-password')) return "Mật khẩu quá yếu, ít nhất 6 ký tự.";
    if (err.contains('invalid-email')) return "Địa chỉ email không đúng định dạng.";
    if (err.contains('network-request-failed')) return "Lỗi kết nối mạng. Vui lòng kiểm tra internet và thử lại.";
    if (err.contains('too-many-requests')) return "Quá nhiều yêu cầu. Vui lòng thử lại sau.";
    return err.replaceAll("Exception: ", "").replaceAll("PlatformException(", "").replaceAll(")", "");
  }

  Future<void> _register() async {
    setState(() { _loading = true; _error = null; });
    try {
      final email = _emailC.text.trim();
      final pass = _passC.text.trim();
      final shopName = _shopNameC.text.trim();
      final name = _nameC.text.trim();

      if (shopName.isEmpty) throw "Vui lòng nhập tên cửa hàng.";
      if (name.isEmpty) throw "Vui lòng nhập họ và tên.";
      if (email.isEmpty || pass.isEmpty) throw "Vui lòng điền các thông tin bắt buộc.";
      if (pass != _confirmPassC.text.trim()) throw "Mật khẩu xác nhận không khớp.";

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      if (cred.user != null) {
        if (_isJoinShop) {
          final success = await UserService.useInviteCode(_inviteCodeC.text.trim(), cred.user!.uid);
          if (!success) throw "Mã mời không chính xác hoặc đã hết hạn.";
        } else {
          await UserService.syncUserInfo(cred.user!.uid, email, extra: {
            'displayName': name.toUpperCase(),
            'phone': _phoneC.text.trim(),
            'address': _addressC.text.trim().toUpperCase(),
            'shopName': shopName.toUpperCase(),
          });
        }
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
        title: const Text("ĐĂNG KÝ TÀI KHOẢN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStepIndicator(),
            const SizedBox(height: 30),
            _currentStep == 0 ? _stepSelectRole() : _stepInputInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _stepNode(0, "Vai trò", _currentStep >= 0),
        Expanded(child: Container(height: 2, color: _currentStep >= 1 ? Colors.blueAccent : Colors.grey.shade300)),
        _stepNode(1, "Thông tin", _currentStep >= 1),
      ],
    );
  }

  Widget _stepNode(int step, String label, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? Colors.blueAccent : Colors.grey.shade300,
          child: Text("${step + 1}", style: TextStyle(color: active ? Colors.white : Colors.grey, fontSize: 12)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.blueAccent : Colors.grey)),
      ],
    );
  }

  Widget _stepSelectRole() {
    return Column(
      children: [
        _roleOption(false, "CHỦ CỬA HÀNG", "Tạo shop mới và quản lý nhân viên", Icons.storefront),
        const SizedBox(height: 16),
        _roleOption(true, "NHÂN VIÊN", "Tham gia shop có sẵn qua mã mời", Icons.badge),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: () => setState(() => _currentStep = 1),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("TIẾP THEO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))])),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? Colors.blueAccent : Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _stepInputInfo() {
    return Column(
      children: [
        _input(_shopNameC, "Tên cửa hàng", Icons.shop),
        _input(_nameC, "Họ và tên", Icons.person),
        _input(_phoneC, "Số điện thoại", Icons.phone, type: TextInputType.phone),
        _input(_emailC, "Email đăng nhập", Icons.email, readOnly: true, helperText: "Email được tạo tự động từ tên và tên shop"),
        _input(_passC, "Mật khẩu", Icons.lock, obscure: _obscurePass, suffix: IconButton(icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePass = !_obscurePass))),
        _input(_confirmPassC, "Xác nhận mật khẩu", Icons.lock_clock, obscure: _obscureConfirm, suffix: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm))),
        _input(_addressC, "Địa chỉ", Icons.map),
        if (_isJoinShop) ...[
          _input(_inviteCodeC, "Mã mời từ Shop", Icons.qr_code),
          Container(
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
                      "HƯỚNG DẪN LẤY MÃ MỜI",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Để tham gia shop, vui lòng yêu cầu chủ shop thực hiện các bước sau:",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInstructionStep(1, "Chủ shop đăng nhập vào ứng dụng"),
                _buildInstructionStep(2, "Chọn tab 'Nhân sự' ở bottom navigation"),
                _buildInstructionStep(3, "Chọn 'Danh sách nhân viên'"),
                _buildInstructionStep(4, "Chọn đăng ký tài khoản thuộc shop  nhân viên"),
                _buildInstructionStep(5, "Chủ shop cung cấp tài khoản và mật khẩu cho bạn"),
                const SizedBox(height: 8),
                Text(
                  "Sau khi có tài khoản và mật khẩu  bạn có thể đăng nhập và tham gia shop.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _currentStep = 0), child: const Text("QUAY LẠI"))),
            const SizedBox(width: 16),
            Expanded(child: ElevatedButton(onPressed: _loading ? null : _register, child: _loading ? const CircularProgressIndicator() : const Text("ĐĂNG KÝ"))),
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
          helperText: helperText, helperStyle: const TextStyle(fontSize: 12, color: Colors.grey),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
