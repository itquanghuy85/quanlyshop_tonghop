import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

class AppInfo {
  static String? _version;

  static Future<String> getVersion() async {
    if (_version != null) return _version!;

    try {
      final pubspecString = await rootBundle.loadString('pubspec.yaml');
      final pubspec = loadYaml(pubspecString);
      _version = pubspec['version']?.toString() ?? '1.0.0+1';
      return _version!;
    } catch (e) {
      // Fallback to hardcoded version if can't read pubspec
      return '1.0.0+1';
    }
  }

  static Future<String> getAppName() async {
    try {
      final pubspecString = await rootBundle.loadString('pubspec.yaml');
      final pubspec = loadYaml(pubspecString);
      return pubspec['name']?.toString() ?? 'QuanLyShop';
    } catch (e) {
      return 'QuanLyShop';
    }
  }

  static Future<String> getDescription() async {
    try {
      final pubspecString = await rootBundle.loadString('pubspec.yaml');
      final pubspec = loadYaml(pubspecString);
      return pubspec['description']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }
}