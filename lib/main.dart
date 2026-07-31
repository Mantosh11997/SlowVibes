import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ads.dart';
import 'screens/home_screen.dart';

void main() {
  // Required before touching any plugin ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Fire and forget: the SDK takes a moment to start and nothing on the first
  // screen needs it, so awaiting here would only delay the first frame.
  unawaited(Ads.init());

  runApp(const SlowVibesApp());
}

// ---------------------------------------------------------------------------
// Colours — the whole palette lives here.
// ---------------------------------------------------------------------------
const Color kPrimary = Color(0xFF6366F1); // indigo
const Color kAccent = Color(0xFF8B5CF6); // purple
const Color kBackground = Color(0xFFF8FAFC);
const Color kSurface = Color(0xFFFFFFFF);
const Color kTextDark = Color(0xFF0F172A);
const Color kTextMuted = Color(0xFF64748B);
const Color kTextFaint = Color(0xFF94A3B8);
const Color kDivider = Color(0xFFE9EEF5);

/// The indigo → purple gradient used on every primary button.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[kPrimary, kAccent],
);

/// Soft shadow used under cards. No borders anywhere in this UI.
List<BoxShadow> get kSoftShadow => <BoxShadow>[
  BoxShadow(
    color: kTextMuted.withValues(alpha: 0.07),
    blurRadius: 24,
    offset: const Offset(0, 8),
    spreadRadius: -4,
  ),
];

/// Corner radius used throughout.
const double kRadius = 22;

class SlowVibesApp extends StatelessWidget {
  const SlowVibesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = GoogleFonts.poppinsTextTheme();

    return MaterialApp(
      title: 'Slow Vibes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: kPrimary,
              brightness: Brightness.light,
            ).copyWith(
              primary: kPrimary,
              secondary: kAccent,
              surface: kSurface,
              onSurface: kTextDark,
            ),
        scaffoldBackgroundColor: kBackground,
        textTheme: text.apply(bodyColor: kTextDark, displayColor: kTextDark),
        appBarTheme: AppBarTheme(
          backgroundColor: kBackground,
          surfaceTintColor: Colors.transparent,
          foregroundColor: kTextDark,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: kTextDark,
          ),
        ),
        // Filled input wells rather than outlined boxes.
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: kSurface,
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: kTextFaint),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kRadius),
            borderSide: const BorderSide(color: kPrimary, width: 1.6),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: kPrimary,
          inactiveTrackColor: kDivider,
          thumbColor: Colors.white,
          overlayColor: kPrimary.withValues(alpha: 0.12),
          trackHeight: 7,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kTextDark,
          contentTextStyle: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadius),
          ),
        ),
        dividerColor: kDivider,
      ),
      home: const HomeScreen(),
    );
  }
}
