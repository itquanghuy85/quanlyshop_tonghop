import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_text_styles.dart';

/// Widget AppBar và TabBar - Thiết kế Compact & Modern với Gradient
class CustomAppBar {
  CustomAppBar._();

  // ========== CONSTANTS - ULTRA COMPACT ==========
  static const double kAppBarHeight = 44.0;
  static const double kAppBarElevation = 0.0;
  static const double kTabBarHeight = 36.0;
  static const double kTitleFontSize = 14.0;
  static const double kSubtitleFontSize = 10.0;

  // ========== COLOR SCHEME ==========
  static const Color kPrimaryColor = Color(0xFF1976D2); // Blue 700
  static const Color kPrimaryLight = Color(0xFF42A5F5);
  static const Color kPrimaryDark = Color(0xFF1565C0);

  // ========== GRADIENT COLORS ==========
  static const Color kGradientStart = Color(0xFF0068FF); // Zalo Blue
  static const Color kGradientEnd = Color(0xFF0084FF); // Zalo Blue Light

  /// Default gradient for AppBar
  static const LinearGradient kDefaultGradient = LinearGradient(
    colors: [kGradientStart, kGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color kAccentGreen = Color(0xFF43A047);
  static const Color kAccentOrange = Color(0xFFFB8C00);
  static const Color kAccentRed = Color(0xFFE53935);
  static const Color kAccentPurple = Color(0xFF8E24AA);

  static const Color kSurfaceWhite = Colors.white;
  static const Color kSurfaceLight = Color(0xFFF5F5F5);
  static const Color kTextPrimary = Color(0xFF212121);
  static const Color kTextSecondary = Color(0xFF616161);
  static const Color kDivider = Color(0xFFEEEEEE);

  /// AppBar với Gradient - Modern style
  static PreferredSizeWidget build({
    required String title,
    String? subtitle,
    Color? accentColor, // Màu accent cho border/indicator
    Color? backgroundColor,
    List<Widget>? actions,
    Widget? leading,
    bool showBackButton = true,
    bool centerTitle = true,
    PreferredSizeWidget? bottom,
    double? elevation,
    VoidCallback? onBackPressed,
    SystemUiOverlayStyle? systemOverlayStyle,
    bool useGradient = true, // Mặc định dùng gradient
  }) {
    final accent = accentColor ?? kPrimaryColor;

    // Nếu dùng gradient
    if (useGradient) {
      return AppBar(
        toolbarHeight: kAppBarHeight,
        elevation: elevation ?? kAppBarElevation,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: centerTitle,
        automaticallyImplyLeading: showBackButton,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: kDefaultGradient),
        ),
        leading:
            leading ??
            (showBackButton && onBackPressed != null
                ? IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    onPressed: onBackPressed,
                  )
                : null),
        title: _buildTitleWhite(title, subtitle),
        actions: actions != null
            ? [
                ...actions.map(
                  (a) => Theme(
                    data: ThemeData(
                      iconTheme: const IconThemeData(color: Colors.white),
                    ),
                    child: a,
                  ),
                ),
                const SizedBox(width: 4),
              ]
            : null,
        bottom: bottom,
      );
    }

    // Nền sáng - chữ tối (legacy style)
    final bgColor = backgroundColor ?? kSurfaceWhite;
    final isLight = bgColor.computeLuminance() > 0.5;
    final fgColor = isLight ? kTextPrimary : Colors.white;

    return AppBar(
      toolbarHeight: kAppBarHeight,
      elevation: elevation ?? kAppBarElevation,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      centerTitle: centerTitle,
      automaticallyImplyLeading: showBackButton,
      leading:
          leading ??
          (showBackButton && onBackPressed != null
              ? IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 20,
                    color: accent,
                  ),
                  onPressed: onBackPressed,
                )
              : null),
      title: _buildTitle(title, subtitle, fgColor, accent),
      actions: actions != null
          ? [
              ...actions.map(
                (a) => Theme(
                  data: ThemeData(iconTheme: IconThemeData(color: accent)),
                  child: a,
                ),
              ),
              const SizedBox(width: 4),
            ]
          : null,
      bottom: bottom != null
          ? PreferredSize(
              preferredSize: bottom.preferredSize,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: kDivider, width: 1)),
                ),
                child: bottom,
              ),
            )
          : PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: kDivider, height: 1),
            ),
    );
  }

  /// AppBar với Search - Clean style
  static PreferredSizeWidget buildWithSearch({
    required String title,
    required bool isSearching,
    required TextEditingController searchController,
    required VoidCallback onSearchToggle,
    required ValueChanged<String> onSearchChanged,
    String searchHint = 'Tìm kiếm...',
    Color? accentColor,
    List<Widget>? actions,
    bool showBackButton = true,
    PreferredSizeWidget? bottom,
  }) {
    final accent = accentColor ?? kPrimaryColor;

    return AppBar(
      toolbarHeight: kAppBarHeight,
      elevation: kAppBarElevation,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      backgroundColor: kSurfaceWhite,
      foregroundColor: kTextPrimary,
      automaticallyImplyLeading: showBackButton,
      title: isSearching
          ? _buildSearchFieldClean(
              searchController,
              onSearchChanged,
              searchHint,
              accent,
            )
          : Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: kTitleFontSize,
                color: kTextPrimary,
              ),
            ),
      actions: [
        IconButton(
          icon: Icon(
            isSearching ? Icons.close_rounded : Icons.search_rounded,
            color: accent,
          ),
          onPressed: () {
            if (isSearching) searchController.clear();
            onSearchToggle();
          },
          tooltip: isSearching ? 'Đóng' : 'Tìm kiếm',
        ),
        if (!isSearching && actions != null) ...actions,
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(bottom?.preferredSize.height ?? 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bottom != null) bottom,
            Container(color: kDivider, height: 1),
          ],
        ),
      ),
    );
  }

  /// AppBar với Tabs - Gradient style
  static PreferredSizeWidget buildWithTabs({
    required String title,
    String? subtitle,
    required TabController tabController,
    required List<Tab> tabs,
    Color? accentColor,
    List<Widget>? actions,
    bool showBackButton = true,
    bool isScrollable = false,
    VoidCallback? onBackPressed,
    bool useGradient = true,
  }) {
    final accent = accentColor ?? kPrimaryColor;

    // Khi title rỗng và không có back button → ẩn toolbar để không tạo khoảng trống thừa
    final double resolvedToolbarHeight =
        (title.isEmpty && !showBackButton && (actions == null || actions.isEmpty))
            ? 0.0
            : kAppBarHeight;

    // Gradient style
    if (useGradient) {
      return AppBar(
        toolbarHeight: resolvedToolbarHeight,
        elevation: kAppBarElevation,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: showBackButton,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: kDefaultGradient),
        ),
        leading: showBackButton && onBackPressed != null
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                onPressed: onBackPressed,
              )
            : null,
        title: _buildTitleWhite(title, subtitle),
        actions: actions != null
            ? [
                ...actions.map(
                  (a) => Theme(
                    data: ThemeData(
                      iconTheme: const IconThemeData(color: Colors.white),
                    ),
                    child: a,
                  ),
                ),
                const SizedBox(width: 8),
              ]
            : null,
        bottom: CustomTabBar.buildGradient(
          controller: tabController,
          tabs: tabs,
          isScrollable: isScrollable,
        ),
      );
    }

    // Legacy white style
    return AppBar(
      toolbarHeight: kAppBarHeight,
      elevation: kAppBarElevation,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      backgroundColor: kSurfaceWhite,
      foregroundColor: kTextPrimary,
      automaticallyImplyLeading: showBackButton,
      leading: showBackButton && onBackPressed != null
          ? IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, size: 20, color: accent),
              onPressed: onBackPressed,
            )
          : null,
      title: _buildTitle(title, subtitle, kTextPrimary, accent),
      actions: actions != null ? [...actions, const SizedBox(width: 8)] : null,
      bottom: CustomTabBar.build(
        controller: tabController,
        tabs: tabs,
        isScrollable: isScrollable,
        accentColor: accent,
      ),
    );
  }

  /// SliverAppBar cho scrollable content - Clean style
  static Widget buildSliver({
    required String title,
    String? subtitle,
    Color? accentColor,
    List<Widget>? actions,
    bool pinned = true,
    bool floating = false,
    double expandedHeight = 120.0,
    Widget? flexibleContent,
    PreferredSizeWidget? bottom,
  }) {
    final accent = accentColor ?? kPrimaryColor;

    return SliverAppBar(
      pinned: pinned,
      floating: floating,
      expandedHeight: expandedHeight,
      elevation: kAppBarElevation,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: kSurfaceWhite,
          child: flexibleContent != null
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: kAppBarHeight),
                    child: flexibleContent,
                  ),
                )
              : null,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTextStyles.headline3.fontSize,
            color: kTextPrimary,
          ),
        ),
        centerTitle: false,
        titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 16),
      ),
      backgroundColor: kSurfaceWhite,
      foregroundColor: accent,
      actions: actions,
      bottom: bottom,
    );
  }

  // ========== PRIVATE HELPERS ==========

  /// Build title for gradient (white text)
  static Widget _buildTitleWhite(String title, String? subtitle) {
    if (subtitle == null) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: kTitleFontSize,
          color: Colors.white,
          letterSpacing: -0.3,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: kTitleFontSize,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: kSubtitleFontSize,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  static Widget _buildTitle(
    String title,
    String? subtitle,
    Color titleColor,
    Color accentColor,
  ) {
    if (subtitle == null) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: kTitleFontSize,
          color: titleColor,
          letterSpacing: -0.3,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: kTitleFontSize,
            color: titleColor,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: kSubtitleFontSize,
            fontWeight: FontWeight.w400,
            color: kTextSecondary,
          ),
        ),
      ],
    );
  }

  static Widget _buildSearchFieldClean(
    TextEditingController controller,
    ValueChanged<String> onChanged,
    String hint,
    Color accentColor,
  ) {
    return Container(
      height: 32, // Compact
      decoration: BoxDecoration(
        color: kSurfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        style: TextStyle(
          color: kTextPrimary,
          fontSize: AppTextStyles.headline5.fontSize,
        ),
        cursorColor: accentColor,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: kTextSecondary,
            fontSize: AppTextStyles.headline5.fontSize,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: kTextSecondary,
            size: 18,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}

/// Custom TabBar - Compact
class CustomTabBar {
  CustomTabBar._();

  /// TabBar Compact style
  static PreferredSizeWidget build({
    required TabController controller,
    required List<Tab> tabs,
    bool isScrollable = false,
    Color? accentColor,
    EdgeInsetsGeometry? padding,
  }) {
    final accent = accentColor ?? CustomAppBar.kPrimaryColor;

    return PreferredSize(
      preferredSize: const Size.fromHeight(CustomAppBar.kTabBarHeight),
      child: Container(
        color: CustomAppBar.kSurfaceWhite,
        child: TabBar(
          controller: controller,
          isScrollable: isScrollable,
          labelColor: accent,
          unselectedLabelColor: CustomAppBar.kTextSecondary,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTextStyles.subtitle1.fontSize,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: AppTextStyles.subtitle1.fontSize,
          ),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 2,
          indicatorColor: accent,
          dividerColor: Colors.transparent,
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: tabs,
        ),
      ),
    );
  }

  /// TabBar cho Gradient AppBar (text trắng)
  static PreferredSizeWidget buildGradient({
    required TabController controller,
    required List<Tab> tabs,
    bool isScrollable = false,
    EdgeInsetsGeometry? padding,
  }) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(CustomAppBar.kTabBarHeight),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        labelColor: const Color(0xFF143E82),
        unselectedLabelColor: Colors.white.withValues(alpha: 0.82),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        dividerColor: Colors.transparent,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: tabs,
      ),
    );
  }

  /// TabBar cho nền xám nhạt
  static Widget buildLight({
    required TabController controller,
    required List<Tab> tabs,
    bool isScrollable = false,
    Color? accentColor,
  }) {
    final accent = accentColor ?? CustomAppBar.kPrimaryColor;

    return Container(
      decoration: const BoxDecoration(
        color: CustomAppBar.kSurfaceWhite,
        border: Border(
          bottom: BorderSide(color: CustomAppBar.kDivider, width: 1),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        labelColor: accent,
        unselectedLabelColor: CustomAppBar.kTextSecondary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: AppTextStyles.subtitle1.fontSize,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2,
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        tabs: tabs,
      ),
    );
  }

  /// Tạo Tab item với icon và label
  static Tab iconTab(IconData icon, String label) {
    return Tab(
      height: CustomAppBar.kTabBarHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  /// Tạo Tab item chỉ có label
  static Tab textTab(String label) {
    return Tab(height: CustomAppBar.kTabBarHeight, text: label);
  }

  /// Tạo Tab item với badge count
  static Tab badgeTab(
    String label,
    int count, {
    IconData? icon,
    Color? badgeColor,
  }) {
    return Tab(
      height: CustomAppBar.kTabBarHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 4)],
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor ?? CustomAppBar.kAccentRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTextStyles.caption.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Extension để tạo AppBar action buttons đẹp
class AppBarActions {
  AppBarActions._();

  /// Icon button
  static Widget icon({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color? color,
    double size = 22,
  }) {
    return IconButton(
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      tooltip: tooltip,
      color: color ?? CustomAppBar.kPrimaryColor,
      splashRadius: 20,
    );
  }

  /// Badge icon button
  static Widget badge({
    required IconData icon,
    required VoidCallback onPressed,
    required int badgeCount,
    String? tooltip,
    Color? iconColor,
    Color? badgeColor,
  }) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon, size: 22),
          onPressed: onPressed,
          tooltip: tooltip,
          color: iconColor ?? CustomAppBar.kPrimaryColor,
          splashRadius: 20,
        ),
        if (badgeCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: badgeColor ?? CustomAppBar.kAccentRed,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTextStyles.caption.fontSize,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  /// Text button
  static Widget text({
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? CustomAppBar.kPrimaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  /// Popup menu
  static Widget menu<T>({
    required List<PopupMenuEntry<T>> items,
    required void Function(T) onSelected,
    IconData icon = Icons.more_vert_rounded,
    String? tooltip,
  }) {
    return PopupMenuButton<T>(
      icon: Icon(icon, color: CustomAppBar.kPrimaryColor),
      tooltip: tooltip ?? 'Menu',
      onSelected: onSelected,
      itemBuilder: (_) => items,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    );
  }
}

/// Accent colors theo context - Sử dụng khi cần phân biệt chức năng
class AppBarAccents {
  AppBarAccents._();

  /// Default - Xanh dương
  static const Color primary = CustomAppBar.kPrimaryColor;

  /// Sales - Xanh lá
  static const Color sales = Color(0xFF2E7D32);

  /// Repairs - Cam
  static const Color repairs = CustomAppBar.kAccentOrange;

  /// Inventory - Xanh lá
  static const Color inventory = CustomAppBar.kAccentGreen;

  /// Finance - Tím
  static const Color finance = CustomAppBar.kAccentPurple;

  /// Staff - Đỏ
  static const Color staff = CustomAppBar.kAccentRed;

  /// Settings - Xám đậm
  static const Color settings = Color(0xFF455A64);

  /// Chat - Teal
  static const Color chat = Color(0xFF00796B);

  /// Customer/Debt - Primary
  static const Color customer = CustomAppBar.kPrimaryColor;
}
