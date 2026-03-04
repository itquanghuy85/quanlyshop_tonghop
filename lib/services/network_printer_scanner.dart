import 'dart:async';
import 'dart:io';

/// Model for a discovered network printer
class DiscoveredPrinter {
  final String ip;
  final String name;
  final int port;
  final int responseTimeMs;

  DiscoveredPrinter({
    required this.ip,
    required this.name,
    this.port = 9100,
    this.responseTimeMs = 0,
  });

  @override
  String toString() => 'DiscoveredPrinter($name @ $ip:$port, ${responseTimeMs}ms)';
}

/// Network printer scanner - scans the local subnet for printers on port 9100
class NetworkPrinterScanner {
  static const int defaultPort = 9100;
  static const int _scanTimeoutMs = 1500;
  static const int _batchSize = 25; // Scan 25 IPs concurrently

  /// Get the device's local WiFi/LAN IP address
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      for (final iface in interfaces) {
        // Skip virtual/VPN interfaces, prefer common WiFi/LAN names
        final name = iface.name.toLowerCase();
        if (name.contains('vmware') ||
            name.contains('virtual') ||
            name.contains('vbox') ||
            name.contains('docker') ||
            name.contains('vethernet')) continue;

        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Prefer common private network ranges
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }

      // Fallback: return any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          return addr.address;
        }
      }
    } catch (e) {
      print('SCANNER: Error getting local IP: $e');
    }
    return null;
  }

  /// Extract subnet prefix from IP (e.g., "192.168.1" from "192.168.1.105")
  static String? getSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Scan a single IP:port for a printer with a short timeout
  static Future<DiscoveredPrinter?> _probeIp(String ip, int port, int timeoutMs) async {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      sw.stop();

      // Connection succeeded — this is likely a printer
      String printerName = 'Máy in WiFi ($ip)';

      // Try to detect printer type by sending a status query
      try {
        // Send ESC/POS status request (DLE EOT 1) - printer will respond
        socket.add([0x10, 0x04, 0x01]); // DLE EOT - Transmit printer status
        await socket.flush();

        // Wait briefly for response
        bool gotResponse = false;
        final sub = socket.listen((data) {
          if (data.isNotEmpty) gotResponse = true;
        }, onError: (_) {});
        await Future.delayed(const Duration(milliseconds: 300));
        await sub.cancel();

        if (gotResponse) {
          printerName = 'Máy in nhiệt ($ip)';
        }
      } catch (_) {
        // No response is fine - still a valid printer connection
      }

      try {
        await socket.close();
      } catch (_) {}

      return DiscoveredPrinter(
        ip: ip,
        name: printerName,
        port: port,
        responseTimeMs: sw.elapsedMilliseconds,
      );
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Scan the local network subnet for printers.
  /// [onProgress] callback reports progress (0.0 to 1.0).
  /// [onFound] callback is called immediately when a printer is found.
  static Future<List<DiscoveredPrinter>> scanNetwork({
    String? subnetOverride,
    int port = defaultPort,
    void Function(double progress)? onProgress,
    void Function(DiscoveredPrinter printer)? onFound,
  }) async {
    final localIp = await getLocalIp();
    if (localIp == null) {
      print('SCANNER: Could not determine local IP');
      return [];
    }

    final subnet = subnetOverride ?? getSubnet(localIp);
    if (subnet == null) {
      print('SCANNER: Invalid subnet from IP $localIp');
      return [];
    }

    print('SCANNER: Local IP: $localIp, Scanning subnet: $subnet.0/24 on port $port');

    final results = <DiscoveredPrinter>[];
    int scanned = 0;

    // Scan IPs 1-254 in batches
    for (int batchStart = 1; batchStart <= 254; batchStart += _batchSize) {
      final batchEnd = (batchStart + _batchSize - 1).clamp(1, 254);
      final futures = <Future<DiscoveredPrinter?>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final targetIp = '$subnet.$i';
        // Skip our own IP
        if (targetIp == localIp) {
          scanned++;
          continue;
        }
        futures.add(_probeIp(targetIp, port, _scanTimeoutMs));
      }

      final batchResults = await Future.wait(futures);
      for (final printer in batchResults) {
        if (printer != null) {
          results.add(printer);
          onFound?.call(printer);
          print('SCANNER: Found printer at ${printer.ip} (${printer.responseTimeMs}ms)');
        }
      }

      scanned += futures.length;
      onProgress?.call(scanned / 254.0);
    }

    // Sort by response time (fastest first)
    results.sort((a, b) => a.responseTimeMs.compareTo(b.responseTimeMs));

    print('SCANNER: Scan complete. Found ${results.length} printer(s)');
    return results;
  }

  /// Quick scan: only scan common printer IPs (x.x.x.1, x.x.x.100-120, x.x.x.200-210, etc.)
  static Future<List<DiscoveredPrinter>> quickScan({
    int port = defaultPort,
    void Function(DiscoveredPrinter printer)? onFound,
  }) async {
    final localIp = await getLocalIp();
    if (localIp == null) return [];

    final subnet = getSubnet(localIp);
    if (subnet == null) return [];

    // Common printer IP ranges
    final targets = <int>[
      1, 2, 3, 4, 5, // Gateway/first devices
      ...List.generate(30, (i) => 100 + i), // 100-129
      ...List.generate(20, (i) => 200 + i), // 200-219
      ...List.generate(10, (i) => 240 + i), // 240-249
      250, 251, 252, 253, 254,
    ];

    print('SCANNER: Quick scan ${targets.length} IPs on $subnet.0/24');

    final futures = targets.map((i) {
      final ip = '$subnet.$i';
      return _probeIp(ip, port, _scanTimeoutMs);
    }).toList();

    final results = (await Future.wait(futures)).whereType<DiscoveredPrinter>().toList();

    for (final p in results) {
      onFound?.call(p);
    }

    results.sort((a, b) => a.responseTimeMs.compareTo(b.responseTimeMs));
    return results;
  }
}
