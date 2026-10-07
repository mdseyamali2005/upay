import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UpayApp());
}

class UpayApp extends StatelessWidget {
  const UpayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'উপায় - uPay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B3A6B),
          primary: const Color(0xFF1B3A6B),
          secondary: const Color(0xFFFFC107),
        ),
        textTheme: GoogleFonts.notoSansBengaliTextTheme(),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}
