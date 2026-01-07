import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_printer_service.dart';
import '../l10n/app_localizations.dart';
import '../models/printer_types.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

class PrinterSelectionDialog extends StatefulWidget {
  const PrinterSelectionDialog({super.key});

  @override
  State<PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<PrinterSelectionDialog> {
  PrinterType _selectedPrinter = PrinterType.auto;
  BluetoothPrinterConfig? _selectedBluetoothPrinter;
  String _wifiIp = '';
  bool _isLoadingBluetooth = false;
  List<BluetoothPrinterConfig> _availableBluetoothPrinters = [];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
    _loadAvailableBluetoothPrinters();
  }

  Future<void> _loadSavedSettings() async {
    final savedPrinter = await BluetoothPrinterService.getSavedPrinter();
    final prefs = await SharedPreferences.getInstance();
    final wifiIp = prefs.getString('printer_ip') ?? '';

    if (mounted) {
      setState(() {
        _selectedBluetoothPrinter = savedPrinter;
        _wifiIp = wifiIp;
        // Determine default selection based on saved settings
        if (savedPrinter != null) {
          _selectedPrinter = PrinterType.bluetooth;
        } else if (wifiIp.isNotEmpty) {
          _selectedPrinter = PrinterType.wifi;
        } else {
          _selectedPrinter = PrinterType.auto;
        }
      });
    }
  }

  Future<void> _loadAvailableBluetoothPrinters() async {
    setState(() => _isLoadingBluetooth = true);
    try {
      final printers = await BluetoothPrinterService.getPairedPrinters();
      if (mounted) {
        setState(() {
          _availableBluetoothPrinters = printers
              .map((p) => BluetoothPrinterConfig(name: p.name, macAddress: p.macAdress))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading Bluetooth printers: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingBluetooth = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.printer),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn loại máy in:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),

            // Auto selection
            ListTile(
              title: const Text('Tự động (Bluetooth → WiFi)'),
              subtitle: const Text('Thử Bluetooth trước, nếu không được thì WiFi'),
              leading: Radio<PrinterType>(
                value: PrinterType.auto,
                groupValue: _selectedPrinter,
                onChanged: (value) => setState(() => _selectedPrinter = value!),
              ),
            ),

            // Bluetooth selection
            ListTile(
              title: const Text('Bluetooth'),
              leading: Radio<PrinterType>(
                value: PrinterType.bluetooth,
                groupValue: _selectedPrinter,
                onChanged: (value) => setState(() => _selectedPrinter = value!),
              ),
            ),

            if (_selectedPrinter == PrinterType.bluetooth) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Máy in Bluetooth:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingBluetooth)
                      const Center(child: CircularProgressIndicator())
                    else if (_availableBluetoothPrinters.isEmpty)
                      const Text('Không tìm thấy máy in Bluetooth đã pair')
                    else
                      DropdownButton<BluetoothPrinterConfig>(
                        value: _selectedBluetoothPrinter,
                        hint: const Text('Chọn máy in'),
                        isExpanded: true,
                        items: _availableBluetoothPrinters.map((printer) {
                          return DropdownMenuItem(
                            value: printer,
                            child: Text('${printer.name} (${printer.macAddress})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedBluetoothPrinter = value);
                        },
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _loadAvailableBluetoothPrinters,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tải lại'),
                    ),
                  ],
                ),
              ),
            ],

            // WiFi selection
            ListTile(
              title: const Text('WiFi/Network'),
              leading: Radio<PrinterType>(
                value: PrinterType.wifi,
                groupValue: _selectedPrinter,
                onChanged: (value) => setState(() => _selectedPrinter = value!),
              ),
            ),

            if (_selectedPrinter == PrinterType.wifi) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cấu hình WiFi:',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'IP Address',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: _wifiIp),
                      onChanged: (value) => _wifiIp = value,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Port: 9100 (mặc định)',
                      style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => _confirmSelection(context),
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }

  void _confirmSelection(BuildContext context) async {
    // Capture navigator before any awaits to avoid using BuildContext across async gaps
    final navigator = Navigator.of(context);

    // Save settings based on selection
    if (_selectedPrinter == PrinterType.bluetooth && _selectedBluetoothPrinter != null) {
      await BluetoothPrinterService.savePrinter(_selectedBluetoothPrinter!);
    }

    if (_selectedPrinter == PrinterType.wifi && _wifiIp.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_ip', _wifiIp);
    }

    // Return the selected printer configuration
    navigator.pop({
      'type': _selectedPrinter,
      'bluetoothPrinter': _selectedBluetoothPrinter,
      'wifiIp': _wifiIp,
    });
  }
}

// Utility function to show printer selection dialog
Future<Map<String, dynamic>?> showPrinterSelectionDialog(BuildContext context) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => const PrinterSelectionDialog(),
  );
}
