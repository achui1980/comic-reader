import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow all orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Configure dependency injection
  configureDependencies();

  runApp(const ComicReaderApp());
}
