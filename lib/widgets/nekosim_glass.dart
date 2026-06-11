import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface: blurred backdrop + translucent surface tint +
/// hairline border. Use sparingly (each instance costs a saveLayer) —
/// headers, toolbars, dialogs. For list cards prefer [GlassCard], which
/// fakes the look without a BackdropFilter.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface
                .withValues(alpha: isDark ? 0.55 : 0.6),
            borderRadius: borderRadius,
            border: Border.all(
              width: 1,
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.10 : 0.06),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Cheap glass-look card for scrolling lists: translucent surface and
/// hairline border over the ambient background, no per-item BackdropFilter.
class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface
            .withValues(alpha: isDark ? 0.62 : 0.72),
        borderRadius: borderRadius,
        border: Border.all(
          width: 1,
          color: (isDark ? Colors.white : Colors.black)
              .withValues(alpha: isDark ? 0.10 : 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: onTap != null
            ? InkWell(onTap: onTap, borderRadius: borderRadius, child: child)
            : child,
      ),
    );
  }
}

/// Ambient tech background: soft color blobs derived from the color scheme,
/// placed behind page content so glass surfaces have something to refract.
class GlassAmbientBackground extends StatelessWidget {
  final Widget child;

  const GlassAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? 0.16 : 0.10;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _blob(theme.colorScheme.primary, 320, base),
        ),
        Positioned(
          top: 260,
          left: -140,
          child: _blob(theme.colorScheme.tertiary, 360, base * 0.8),
        ),
        Positioned(
          bottom: -160,
          right: -60,
          child: _blob(theme.colorScheme.secondary, 380, base * 0.7),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  Widget _blob(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section container in the host settings-page style, but glass-skinned:
/// uppercase accent caption above a rounded translucent panel.
class GlassSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const GlassSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
              letterSpacing: 2.0,
            ),
          ),
        ),
        GlassCard(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: theme.dividerColor.withValues(
                      alpha:
                          theme.brightness == Brightness.dark ? 0.10 : 0.05,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
