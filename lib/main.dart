import 'package:flutter/material.dart';

import 'src/beam_controller.dart';
import 'src/home_page.dart';

void main() {
  final controller = BeamController();
  controller.init();
  runApp(NovaBeamApp(controller: controller));
}

class NovaBeamApp extends StatelessWidget {
  const NovaBeamApp({super.key, required this.controller});

  final BeamController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovaBeam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: HomePage(controller: controller),
    );
  }
}
