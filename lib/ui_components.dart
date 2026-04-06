import 'package:flutter/material.dart';
import 'package:nrf/ui_constants.dart';

class AppSectionTitle extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;

  const AppSectionTitle({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.only(left: 4, bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(title, style: buildSectionTitleStyle()),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: buildCardDecoration(),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
