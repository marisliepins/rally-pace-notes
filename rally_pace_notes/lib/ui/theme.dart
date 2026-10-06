import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

const kBg = Color(0xFF0B0D10);
const kPanel = Color(0xFF151A21);
const kLine = Color(0xFF262D37);
const kText = Color(0xFFF2F4F7);
const kDim = Color(0xFF7D8896);
const kAccent = Color(0xFFFF6A1F); // rally orange
const kLeft = Color(0xFF4FC3F7); // left turns: cyan
const kRight = Color(0xFFFFC23D); // right turns: amber
const kGood = Color(0xFF46D37E);
const kWarn = Color(0xFFFFB020);
const kBad = Color(0xFFFF4D4D);

const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
  ).copyWith(surface: kPanel, primary: kAccent);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(backgroundColor: kBg),
  );
}
