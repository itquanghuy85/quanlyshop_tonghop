import 'package:flutter/material.dart';

/// A beautiful gradient floating action button with press animation effects
class GradientFab extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final Color? iconColor;
  final Color? textColor;
  final double? elevation;
  final bool isExtended;

  const GradientFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.gradientColors,
    this.iconColor,
    this.textColor,
    this.elevation,
    this.isExtended = true,
  });

  /// Factory constructors for common FAB types
  factory GradientFab.primary({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFF667eea), Color(0xFF764ba2)],
    );
  }

  factory GradientFab.success({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFF11998e), Color(0xFF38ef7d)],
    );
  }

  factory GradientFab.warning({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFFf2994a), Color(0xFFf2c94c)],
    );
  }

  factory GradientFab.danger({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFFeb3349), Color(0xFFf45c43)],
    );
  }

  factory GradientFab.info({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFF2196F3), Color(0xFF21CBF3)],
    );
  }

  factory GradientFab.purple({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    );
  }

  factory GradientFab.orange({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFFFF512F), Color(0xFFDD2476)],
    );
  }

  factory GradientFab.teal({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return GradientFab(
      onPressed: onPressed,
      icon: icon,
      label: label,
      gradientColors: const [Color(0xFF00B4DB), Color(0xFF0083B0)],
    );
  }

  @override
  State<GradientFab> createState() => _GradientFabState();
}

class _GradientFabState extends State<GradientFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _elevationAnimation = Tween<double>(begin: 6.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onPressed != null) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: widget.gradientColors.first.withOpacity(
                    isDisabled ? 0.1 : (_isPressed ? 0.2 : 0.4),
                  ),
                  blurRadius: _elevationAnimation.value * 2,
                  spreadRadius: _isPressed ? 0 : 1,
                  offset: Offset(0, _elevationAnimation.value / 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: widget.onPressed,
                onTapDown: _onTapDown,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                borderRadius: BorderRadius.circular(28),
                splashColor: Colors.white.withOpacity(0.3),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDisabled
                          ? [Colors.grey.shade400, Colors.grey.shade500]
                          : widget.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.icon,
                          size: 18,
                          color: widget.iconColor ?? Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: widget.textColor ?? Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
