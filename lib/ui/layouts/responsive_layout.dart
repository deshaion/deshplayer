import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobileLayout;
  final Widget desktopLayout;

  const ResponsiveLayout({
    super.key,
    required this.mobileLayout,
    required this.desktopLayout,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use 800px as the breakpoint for Desktop vs Mobile layout
        if (constraints.maxWidth >= 800) {
          return desktopLayout;
        } else {
          return mobileLayout;
        }
      },
    );
  }
}
