import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/qr_router.dart';

class QrScanView extends StatefulWidget {
  final String role;
  const QrScanView({super.key, this.role = 'user'});

  @override
  State<QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<QrScanView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionTimeoutMs: 2000, // Giảm chu kỳ quét xuống 2 giây
  );
  bool _handling = false;

  Future<void> _handleBarcode(String raw) async {
    if (_handling) return;
    setState(() => _handling = true);

    final key = raw.trim();
    if (key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR không hợp lệ')),
        );
      }
      if (mounted) setState(() => _handling = false);
      return;
    }

    try {
      // Use unified QR router for all QR types
      await QRRouter.routeQR(context, key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý QR: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét QR Code'),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            icon: Icon(
              _controller.torchEnabled ? Icons.flash_on : Icons.flash_off,
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final barcode = barcodes.first;
            if (barcode.rawValue != null) {
              _handleBarcode(barcode.rawValue!);
            }
          }
        },
      ),
    );
  }
}
