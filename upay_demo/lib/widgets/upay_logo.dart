import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Official উপায় mark. The file already includes the wordmark.
class UpayLogo extends StatelessWidget {
  final double height;

  const UpayLogo({super.key, this.height = 48});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/upay_logo.svg',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
