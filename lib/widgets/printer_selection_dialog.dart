import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/network_printer_scanner.dart';
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
  String? _printerName;
  bool _isLoadingBluetooth = false;
  List<BluetoothPrinterConfig> _availableBluetoothPrinters = [];
  
  // Network scanner
  bool _isScanningNetwork = false;
  double _scanProgress = 0.0;
  List<DiscoveredPrinter> _discoveredPrinters = [];

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
    final printerName = prefs.getString('printer_name');

    if (mounted) {
      setState(() {
        _selectedBluetoothPrinter = savedPrinter;
        _wifiIp = wifiIp;
        _printerName = printerName;
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
          
          if (_selectedBluetoothPrinter != null && _availableBluetoothPrinters.isNotEmpty) {
            final exists = _availableBluetoothPrinters.any(
              (p) => p.macAddress == _selectedBluetoothPrinter!.macAddress
            );
            if (!exists) {
              _availableBluetoothPrinters.insert(0, _selectedBluetoothPrinter!);
            }
          }
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

  Future<void> _scanNetworkPrinters() async {
    if (_isScanningNetwork) return;
    
    setState(() {
      _isScanningNetwork = true;
      _scanProgress = 0.0;
      _discoveredPrinters = [];
    });

    try {
      final results = await NetworkPrinterScanner.scanNetwork(
        onProgress: (progress) {
          if (mounted) setState(() => _scanProgress = progress);
        },
        onFound: (printer) {
          if (mounted) {
            setState(() => _discoveredPrinters = [..._discoveredPrinters, printer]);
          }
        },
      );

      if (mounted) {
        setState(() {
          _discoveredPrinters = results;
          _isScanningNetwork = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isScanningNetwork = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.indigo.shade400]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.print, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(l10n.printer, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn loại máy in:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // Auto selection
            _buildPrinterTypeCard(
              icon: Icons.auto_awesome,
              iconColor: Colors.amber,
              title: 'Tự động',
              subtitle: 'Bluetooth → WiFi',
              type: PrinterType.auto,
            ),
            const SizedBox(height: 8),

            // Bluetooth selection
            _buildPrinterTypeCard(
              icon: Icons.bluetooth,
              iconColor: Colors.indigo,
              title: 'Bluetooth',
              subtitle: _selectedBluetoothPrinter?.name ?? 'Chọn máy in BT',
              type: PrinterType.bluetooth,
            ),

            if (_selectedPrinter == PrinterType.bluetooth) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoadingBluetooth)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
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
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadAvailableBluetoothPrinters,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Tải lại'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),

            // WiFi selection
            _buildPrinterTypeCard(
              icon: Icons.wifi,
              iconColor: Colors.teal,
              title: 'WiFi/Network',
              subtitle: _wifiIp.isNotEmpty ? _wifiIp : 'Nhập IP hoặc quét mạng',
              type: PrinterType.wifi,
            ),

            if (_selectedPrinter == PrinterType.wifi) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show saved printer info
                    if (_printerName != null && _wifiIp.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.print, color: Colors.teal.shade600, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_printerName!, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800, fontSize: 14)),
                                  Text(_wifiIp, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            Icon(Icons.check_circle, size: 18, color: Colors.green.shade400),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Địa chỉ IP',
                        hintText: '192.168.1.100',
                        prefixIcon: const Icon(Icons.router, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      controller: TextEditingController(text: _wifiIp),
                      onChanged: (value) => _wifiIp = value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Port: 9100 (mặc định)',
                      style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.5), fontSize: 13),
                    ),
                    const SizedBox(height: 10),

                    // Network scanner button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isScanningNetwork ? null : _scanNetworkPrinters,
                        icon: _isScanningNetwork
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.radar, size: 18),
                        label: Text(_isScanningNetwork ? 'Đang quét ${(_scanProgress * 100).toInt()}%...' : 'Quét tìm máy in trong mạng'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    // Scanning progress
                    if (_isScanningNetwork) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _scanProgress,
                          backgroundColor: Colors.teal.shade100,
                          valueColor: AlwaysStoppedAnimation(Colors.teal.shade600),
                          minHeight: 3,
                        ),
                      ),
                    ],

                    // Discovered printers list
                    if (_discoveredPrinters.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Máy in tìm thấy (${_discoveredPrinters.length}):',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.teal.shade800),
                      ),
                      const SizedBox(height: 6),
                      ...(_discoveredPrinters.map((printer) {
                        final isSelected = _wifiIp == printer.ip;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: InkWell(
                            onTap: () async {
                              setState(() {
                                _wifiIp = printer.ip;
                                _printerName = printer.name;
                              });
                              // Auto-save to SharedPreferences
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('printer_ip', printer.ip);
                              await prefs.setString('printer_name', printer.name);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.teal.shade100 : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? Colors.teal.shade400 : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.print, size: 18, color: isSelected ? Colors.teal.shade700 : Colors.grey.shade500),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          printer.ip,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: isSelected ? Colors.teal.shade800 : null,
                                          ),
                                        ),
                                        Text(
                                          '${printer.name} - ${printer.responseTimeMs}ms',
                                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) Icon(Icons.check_circle, size: 18, color: Colors.teal.shade600),
                                ],
                              ),
                            ),
                          ),
                        );
                      })),
                    ],
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
        ElevatedButton.icon(
          onPressed: () => _confirmSelection(context),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Xác nhận'),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterTypeCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required PrinterType type,
  }) {
    final isSelected = _selectedPrinter == type;
    return InkWell(
      onTap: () => setState(() => _selectedPrinter = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? iconColor.withOpacity(0.08) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? iconColor.withOpacity(0.4) : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<PrinterType>(
              value: type,
              groupValue: _selectedPrinter,
              onChanged: (value) => setState(() => _selectedPrinter = value!),
              activeColor: iconColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: isSelected ? iconColor : null)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, size: 18, color: iconColor),
          ],
        ),
      ),
    );
  }

  void _confirmSelection(BuildContext context) async {
    final navigator = Navigator.of(context);

    if (_selectedPrinter == PrinterType.bluetooth && _selectedBluetoothPrinter != null) {
      await BluetoothPrinterService.savePrinter(_selectedBluetoothPrinter!);
    }

    if (_selectedPrinter == PrinterType.wifi && _wifiIp.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_ip', _wifiIp);
      if (_printerName != null) {
        await prefs.setString('printer_name', _printerName!);
      }
    }

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
