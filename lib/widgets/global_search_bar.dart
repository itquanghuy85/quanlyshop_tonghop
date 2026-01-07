import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

class GlobalSearchBar extends StatefulWidget {
  final String hintText;
  final Function(String) onSearch;

  const GlobalSearchBar({
    super.key,
    required this.hintText,
    required this.onSearch,
  });

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 56,
      decoration: BoxDecoration(
        color: _isFocused ? Colors.white : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isFocused 
          ? [BoxShadow(color: Colors.blue.withAlpha(25), blurRadius: 15, offset: const Offset(0, 4))]
          : [],
        border: Border.all(
          color: _isFocused ? Colors.blue.shade300 : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: (val) {
          if (val.length >= 2) {
            // Logic gợi ý realtime có thể thêm ở đây hoặc mở thẳng màn kết quả
          }
        },
        onSubmitted: (val) {
          if (val.isNotEmpty) {
            HapticFeedback.lightImpact();
            widget.onSearch(val);
          }
        },
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
          prefixIcon: Icon(Icons.search_rounded, color: _isFocused ? Colors.blue : Colors.grey),
          suffixIcon: _controller.text.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                },
              )
            : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
