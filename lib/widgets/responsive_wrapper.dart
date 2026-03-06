import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Breakpoint definitions for responsive layout
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

/// Device type enum
enum DeviceType { mobile, tablet, desktop }

/// Responsive helper - provides screen info without rebuilding
class Responsive {
  final BuildContext context;

  Responsive(this.context);

  Size get _size => MediaQuery.sizeOf(context);
  double get width => _size.width;
  double get height => _size.height;
  bool get isLandscape => width > height;
  bool get isPortrait => !isLandscape;
  bool get isWeb => kIsWeb;

  DeviceType get deviceType {
    if (width >= Breakpoints.desktop) return DeviceType.desktop;
    if (width >= Breakpoints.tablet) return DeviceType.tablet;
    return DeviceType.mobile;
  }

  bool get isMobile => deviceType == DeviceType.mobile;
  bool get isTablet => deviceType == DeviceType.tablet;
  bool get isDesktop => deviceType == DeviceType.desktop;

  /// True when we should use wide layout (tablet landscape, desktop, or web with enough width)
  bool get isWideLayout => width >= Breakpoints.tablet;

  /// Number of grid columns for shortcuts/actions
  int get shortcutColumns {
    if (width >= Breakpoints.desktop) return 8;
    if (width >= Breakpoints.tablet) return 6;
    if (isLandscape && width >= Breakpoints.mobile) return 6;
    return 4;
  }

  /// Number of columns for list-based grids (cards, items)
  int get cardColumns {
    if (width >= Breakpoints.desktop) return 3;
    if (width >= Breakpoints.tablet) return 2;
    if (isLandscape && width >= Breakpoints.mobile) return 2;
    return 1;
  }

  /// Number of columns for form fields in a row
  int get formColumns {
    if (width >= Breakpoints.desktop) return 3;
    if (width >= Breakpoints.tablet) return 2;
    if (isLandscape) return 2;
    return 1;
  }

  /// Max content width - prevents ultra-wide stretching
  double get maxContentWidth {
    if (width >= Breakpoints.desktop) return 1200;
    if (width >= Breakpoints.tablet) return 900;
    return width;
  }

  /// Horizontal padding that scales with screen size
  double get horizontalPadding {
    if (width >= Breakpoints.desktop) return 32;
    if (width >= Breakpoints.tablet) return 20;
    return 10;
  }

  /// Dialog width that adapts to screen
  double get dialogWidth {
    if (width >= Breakpoints.desktop) return 600;
    if (width >= Breakpoints.tablet) return width * 0.7;
    return width * 0.9;
  }

  /// Dialog height factor
  double get dialogHeightFactor {
    if (isLandscape) return 0.9;
    return 0.8;
  }

  /// Bottom sheet max width
  double get bottomSheetMaxWidth {
    if (width >= Breakpoints.tablet) return 600;
    return width;
  }
}

/// Extension on BuildContext for easy access
extension ResponsiveExtension on BuildContext {
  Responsive get responsive => Responsive(this);
}

/// Wrapper widget that constrains content width and centers for wide screens
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final effectiveMaxWidth = maxWidth ?? r.maxContentWidth;

    if (r.width <= effectiveMaxWidth) {
      return padding != null ? Padding(padding: padding!, child: child) : child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// Scaffold wrapper that handles responsive layout for tab-based screens
/// On wide screens: shows side navigation rail instead of bottom nav
class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final List<BottomNavigationBarItem> navItems;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    required this.navItems,
    required this.currentIndex,
    required this.onIndexChanged,
    this.appBar,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;

    // On wide screens, use NavigationRail
    if (r.isWideLayout && navItems.length >= 2) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onIndexChanged,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Theme.of(context).colorScheme.surface,
              selectedIconTheme: IconThemeData(
                color: Theme.of(context).colorScheme.primary,
              ),
              selectedLabelTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: r.isDesktop ? 13 : 11,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontSize: r.isDesktop ? 12 : 10,
              ),
              destinations: navItems.map((item) {
                return NavigationRailDestination(
                  icon: item.icon,
                  selectedIcon: item.activeIcon,
                  label: Text(item.label ?? ''),
                );
              }).toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    // Mobile: handled by caller (return body as-is for integration with existing bottom nav)
    return body;
  }
}

// ─── Responsive Bottom Sheet ────────────────────────────────────────────

/// Max width for bottom sheets on wide screens (web / tablet landscape)
const double _kBottomSheetMaxWidth = 600.0;

/// Show a bottom sheet that is constrained on wide screens.
/// Drop-in replacement for [showModalBottomSheet] — same API with auto constraints.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
}) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final effectiveConstraints = constraints ??
      (screenWidth > _kBottomSheetMaxWidth
          ? BoxConstraints(maxWidth: _kBottomSheetMaxWidth)
          : null);

  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: effectiveConstraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
  );
}

// ─── Responsive Dialog Width ────────────────────────────────────────────

/// Returns a clamped width for dialogs/popups on wide screens.
/// On mobile, returns [fraction] of screen width. On wide screens, caps at [maxWidth].
double responsiveDialogWidth(BuildContext context, {double fraction = 0.9, double maxWidth = 560}) {
  final w = MediaQuery.sizeOf(context).width;
  return math.min(w * fraction, maxWidth);
}

/// Wraps child in a Center + ConstrainedBox for wide-screen Scaffold bodies.
/// Use when a view doesn't use ResponsiveCenter but needs width capping.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 900,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Responsive grid that adapts columns based on screen width
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final int? maxColumns;
  final double minChildWidth;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.maxColumns,
    this.minChildWidth = 150,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        int columns = (availableWidth / minChildWidth).floor().clamp(1, maxColumns ?? 12);
        final itemWidth = (availableWidth - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((child) {
            return SizedBox(width: itemWidth, child: child);
          }).toList(),
        );
      },
    );
  }
}
