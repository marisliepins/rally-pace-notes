import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/drive_screen.dart';
import 'ui/theme.dart';

void main() {
  final controller = AppController()..init();
  runApp(RallyApp(controller: controller));
}

class RallyApp extends StatelessWidget {
  const RallyApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rally Pace Notes',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: DriveScreen(c: controller),
    );
  }
}
