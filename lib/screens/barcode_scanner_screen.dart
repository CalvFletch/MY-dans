import "package:flutter/material.dart";
import "package:mobile_scanner/mobile_scanner.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../services/database_service.dart";

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isScanning = false;
  late final AnimationController _pulseCtrl;
  String? _detectedCode;
  final List<ScanEntry> _pastScans = [];
  final _sheetCtrl = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadPastScans();
  }

  Future<void> _loadPastScans() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList("past_scans") ?? [];
    final scans = <ScanEntry>[];
    for (final r in raw) {
      try {
        final parts = r.split("|");
        if (parts.length == 2) {
          scans.add(ScanEntry(code: parts[0], time: DateTime.parse(parts[1])));
        }
      } catch (_) {}
    }
    setState(() => _pastScans.addAll(scans));
  }

  Future<void> _saveScan(String code) async {
    final entry = ScanEntry(code: code, time: DateTime.now());
    _pastScans.insert(0, entry);
    if (_pastScans.length > 50) _pastScans.removeLast();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(
      "past_scans",
      _pastScans.map((e) => "${e.code}|${e.time.toIso8601String()}").toList(),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    controller.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  void _startScanning() {
    if (_detectedCode != null) return;
    setState(() => _isScanning = true);
    _pulseCtrl.repeat();
  }

  void _stopScanning() {
    setState(() => _isScanning = false);
    _pulseCtrl.stop();
    _pulseCtrl.reset();
  }

  void _onBarcode(String code) async {
    if (_detectedCode != null) return;
    _saveScan(code);
    setState(() {
      _detectedCode = code;
      _isScanning = false;
    });
    _pulseCtrl.stop();
    controller.stop();

    // Try to look up the barcode in our DB
    String? foundStockcode;
    try {
      // Check if barcode matches or is contained in local DB stockcodes
      if (DatabaseService.instance.isReady) {
        final results = await DatabaseService.instance.search(code);
        if (results.isNotEmpty) {
          foundStockcode = results.first.stockcode;
        }
      }
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context, foundStockcode ?? code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Barcode"),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
            tooltip: "Toggle flash",
          ),
        ],
      ),
      body: GestureDetector(
        onLongPressStart: (_) => _startScanning(),
        onLongPressEnd: (_) => _stopScanning(),
        onLongPressCancel: () => _stopScanning(),
        child: Stack(
          children: [
            MobileScanner(
              controller: controller,
              errorBuilder: (_, error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt,
                      size: 48,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Camera unavailable",
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => controller.start(),
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ),
              onDetect: (capture) {
                if (!_isScanning) return;
                final barcode = capture.barcodes.firstOrNull;
                if (barcode != null && barcode.rawValue != null) {
                  _onBarcode(barcode.rawValue!);
                }
              },
            ),
            ScanOverlay(isScanning: _isScanning, pulseCtrl: _pulseCtrl),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.45,
              left: 0,
              right: 0,
              child: Text(
                _detectedCode != null
                    ? "Detected: $_detectedCode"
                    : _isScanning
                    ? "Scanning..."
                    : "Hold to scan",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: PastScansSheet(
        scans: _pastScans,
        sheetCtrl: _sheetCtrl,
        onTap: (code) {
          controller.stop();
          Navigator.pop(context, code);
        },
      ),
    );
  }
}

class ScanEntry {
  final String code;
  final DateTime time;
  ScanEntry({required this.code, required this.time});
}

class PastScansSheet extends StatelessWidget {
  final List<ScanEntry> scans;
  final DraggableScrollableController sheetCtrl;
  final void Function(String) onTap;
  const PastScansSheet({
    super.key,
    required this.scans,
    required this.sheetCtrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: sheetCtrl,
      initialChildSize: 0.07,
      minChildSize: 0.07,
      maxChildSize: 0.45,
      snap: true,
      snapSizes: const [0.07, 0.45],
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: const Border(top: BorderSide(color: Colors.white24)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      "Past Scans",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "${scans.length}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: scans.isEmpty
                    ? const Center(
                        child: Text(
                          "No scans yet",
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: scans.length,
                        itemBuilder: (_, i) {
                          final s = scans[i];
                          final time =
                              "${s.time.hour.toString().padLeft(2, "0")}:${s.time.minute.toString().padLeft(2, "0")}";
                          return ListTile(
                            title: Text(
                              s.code,
                              style: const TextStyle(fontSize: 14),
                            ),
                            trailing: Text(
                              time,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            dense: true,
                            onTap: () => onTap(s.code),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ScanOverlay extends StatelessWidget {
  final bool isScanning;
  final AnimationController pulseCtrl;
  const ScanOverlay({
    super.key,
    required this.isScanning,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanW = size.width * 0.82;
    final scanH = scanW * 0.35;
    final scanTop = size.height * 0.18;
    return Stack(
      children: [
        CustomPaint(
          size: size,
          painter: _ScanOverlayPainter(scanW, scanH, scanTop),
        ),
        Positioned(
          top: scanTop,
          left: (size.width - scanW) / 2,
          child: Container(
            width: scanW,
            height: scanH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isScanning ? const Color(0xFF86CC8D) : Colors.white,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: isScanning
                  ? AnimatedBuilder(
                      animation: pulseCtrl,
                      builder: (_, child) => CustomPaint(
                        painter: _PulsePainter(pulseCtrl.value),
                        size: Size(scanW, scanH),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  _PulsePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(0, progress * 2 - 2),
          end: Alignment(0, progress * 2),
          colors: const [
            Color(0x0086CC8D),
            Color(0x4086CC8D),
            Color(0x0086CC8D),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.progress != progress;
}

class _ScanOverlayPainter extends CustomPainter {
  final double scanW, scanH, scanTop;
  _ScanOverlayPainter(this.scanW, this.scanH, this.scanTop);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final cutoutLeft = (size.width - scanW) / 2;
    final cutout = RRect.fromRectAndRadius(
      Rect.fromLTWH(cutoutLeft, scanTop, scanW, scanH),
      const Radius.circular(12),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(cutout),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
