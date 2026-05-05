import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Exact colors from the web app's CSS variables
const kSidebarBg      = Color(0xFF1a3323); // hsl(145,30%,14%)
const kSidebarAccent  = Color(0xFF243d2c); // hsl(145,25%,22%)
const kSidebarBorder  = Color(0xFF243028); // hsl(145,20%,20%)
const kSidebarPrimary = Color(0xFFc8e07a); // hsl(75,55%,75%) — lime accent
const kSidebarText    = Color(0xFFdde8d8); // hsl(80,20%,90%)

const kPrimary    = Color(0xFF2d6b3a); // hsl(145,45%,28%)
const kBackground = Color(0xFFf7f5f0); // hsl(40,20%,97%)
const kCard       = Color(0xFFFFFFFF);
const kBorder     = Color(0xFFdde8d0); // hsl(80,15%,87%)
const kMuted      = Color(0xFFf0ede5); // hsl(40,15%,93%)
const kMutedFg    = Color(0xFF7a9080); // hsl(150,10%,45%)
const kForeground = Color(0xFF161f18); // hsl(150,15%,12%)

const kHealthy    = Color(0xFF10b981);
const kFair       = Color(0xFFf59e0b);
const kPoor       = Color(0xFFef4444);

Color healthColor(String status) {
  switch (status) {
    case 'Healthy': return kHealthy;
    case 'Fair':    return kFair;
    case 'Poor':    return kPoor;
    default:        return kMutedFg;
  }
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      primary: kPrimary,
      surface: kCard,
      onSurface: kForeground,
    ),
    scaffoldBackgroundColor: kBackground,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: kForeground,
      displayColor: kForeground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kSidebarBg,
      foregroundColor: kSidebarText,
      elevation: 0,
      titleTextStyle: GoogleFonts.inter(
        color: kSidebarText,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: const IconThemeData(color: kSidebarText),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: const BorderSide(color: kBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: kMutedFg, fontSize: 14),
      labelStyle: const TextStyle(color: kMutedFg, fontSize: 14),
    ),
    cardTheme: CardThemeData(
      color: kCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: kBorder),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerColor: kBorder,
    chipTheme: ChipThemeData(
      backgroundColor: kMuted,
      labelStyle: const TextStyle(fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
