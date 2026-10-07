import 'package:flutter/material.dart';

// ──── uPay Brand Colors ────
class AppColors {
  static const Color primaryBlue = Color(0xFF1B3A6B);
  static const Color darkBlue = Color(0xFF0D2240);
  static const Color lightBlue = Color(0xFF4A90D9);
  static const Color accentYellow = Color(0xFFFFC107);
  static const Color brightYellow = Color(0xFFFFD740);
  static const Color goldYellow = Color(0xFFE5A100);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF5F5F5);
  static const Color lightGrey = Color(0xFFEEEEEE);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color darkGrey = Color(0xFF616161);
  static const Color black = Color(0xFF212121);
  static const Color green = Color(0xFF4CAF50);
  static const Color red = Color(0xFFE53935);
  static const Color orange = Color(0xFFFF9800);

  // Wallet card colors
  static const Color walletPrimary = Color(0xFFE8F5E9);
  static const Color walletDisbursement = Color(0xFFFFF3E0);
  static const Color walletSecondary = Color(0xFFF3E5F5);
  static const Color walletRemittance = Color(0xFFF9FBE7);
}

class AppTextStyles {
  static TextStyle heading = const TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.black,
  );

  static TextStyle subheading = const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  static TextStyle body = const TextStyle(
    fontSize: 16,
    color: AppColors.darkGrey,
  );

  static TextStyle caption = const TextStyle(
    fontSize: 12,
    color: AppColors.grey,
  );

  static TextStyle buttonText = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.white,
  );

  static TextStyle sectionHeader = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.primaryBlue,
  );
}
