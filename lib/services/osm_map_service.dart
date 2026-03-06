import 'package:url_launcher/url_launcher.dart';

class OsmMapService {
  static List<double>? parseLatLng(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    final normalized = text
        .replaceAll(';', ',')
        .replaceAll('|', ',')
        .replaceAll(' ', ',');
    final parts = normalized
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;

    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

    return [lat, lon];
  }

  static Future<bool> openPoint(double lat, double lon) async {
    final url =
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=18/$lat/$lon';
    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openDirections({
    required double toLat,
    required double toLon,
    double? fromLat,
    double? fromLon,
  }) async {
    final route = (fromLat != null && fromLon != null)
        ? '$fromLat,$fromLon;$toLat,$toLon'
        : ';$toLat,$toLon';

    final uri = Uri.parse(
      'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=$route',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
