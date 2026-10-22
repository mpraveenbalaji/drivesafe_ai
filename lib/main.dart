import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const DriveSafeApp());
}

class DriveSafeApp extends StatelessWidget {
  const DriveSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DriveSafe AI',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B52),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      ),
      home: const SplashScreen(),
    );
  }
}
