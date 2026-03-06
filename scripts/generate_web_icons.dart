// Generate web icons from assets/images/icon.png
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final iconFile = File('assets/images/icon.png');
  if (!iconFile.existsSync()) {
    print('ERROR: assets/images/icon.png not found');
    exit(1);
  }

  final bytes = iconFile.readAsBytesSync();
  final source = img.decodeImage(bytes);
  if (source == null) {
    print('ERROR: Could not decode icon.png (${bytes.length} bytes, header: ${bytes.take(8).toList()})');
    exit(1);
  }

  print('Source icon: ${source.width}x${source.height}');

  // Generate web icons
  final sizes = {
    'web/favicon.png': 32,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };

  for (final entry in sizes.entries) {
    final resized = img.copyResize(source, width: entry.value, height: entry.value, interpolation: img.Interpolation.average);
    File(entry.key).writeAsBytesSync(img.encodePng(resized));
    print('Generated ${entry.key} (${entry.value}x${entry.value})');
  }

  print('Done! All web icons generated from app icon.');
}
