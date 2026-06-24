import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a barcode for a stockcode. Tap to copy, long-press for fullscreen scan.
class BarcodeGenerator extends StatelessWidget {
  final String code;
  final VoidCallback? onClose;

  const BarcodeGenerator({super.key, required this.code, this.onClose});

  /// Show barcode in a dialog
  static void show(BuildContext context, String code) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Barcode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BarcodeGenerator(code: code),
              const SizedBox(height: 8),
              Text(code, style: const TextStyle(fontSize: 18, fontFamily: 'monospace', color: Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        if (onClose != null) onClose!();
      },
      onLongPress: () {},
      child: Container(
        height: 80,
        width: double.infinity,
        color: Colors.white,
        child: CustomPaint(
          painter: _BarcodePainter(code),
        ),
      ),
    );
  }
}

/// Simple Code 128-like barcode painter
class _BarcodePainter extends CustomPainter {
  final String code;
  _BarcodePainter(this.code);

  // Code 128B character patterns (simplified)
  static const _patterns = {
    0: '11011001100', 1: '11001101100', 2: '11001100110', 3: '10010011000',
    4: '10010001100', 5: '10001001100', 6: '10011001000', 7: '10011000100',
    8: '10001100100', 9: '11001001000', 10: '11001000100', 11: '11000100100',
    12: '10110011100', 13: '10011011100', 14: '10011001110', 15: '10111001100',
    16: '10011101100', 17: '10011100110', 18: '11001110010', 19: '11001011100',
    20: '11001001110', 21: '11011100100', 22: '11001110100', 23: '11101101110',
    24: '11101001100', 25: '11100101100', 26: '11100100110', 27: '11101100100',
    28: '11100110100', 29: '11100110010', 30: '11011011000', 31: '11011000110',
    32: '11000110110', 33: '10100011000', 34: '10001011000', 35: '10001000110',
    36: '10110001000', 37: '10001101000', 38: '10001100010', 39: '11010001000',
    40: '11000101000', 41: '11000100010', 42: '10110111000', 43: '10110001110',
    44: '10001101110', 45: '10111011000', 46: '10111000110', 47: '10001110110',
    48: '11101110110', 49: '11010001110', 50: '11000101110', 51: '11011101000',
    52: '11011100010', 53: '11011101110', 54: '11101011000', 55: '11101000110',
    56: '11100010110', 57: '11101101000', 58: '11101100010', 59: '11100011010',
    60: '11101111010', 61: '11001000010', 62: '11110001010', 63: '10100110000',
    64: '10100001100', 65: '10010110000', 66: '10010000110', 67: '10000101100',
    68: '10000100110', 69: '10110010000', 70: '10110000100', 71: '10011010000',
    72: '10011000010', 73: '10000110100', 74: '10000110010', 75: '11000010010',
    76: '11001010000', 77: '11110111010', 78: '11000010100', 79: '10001111010',
    80: '10100111100', 81: '10010111100', 82: '10010011110', 83: '10111100100',
    84: '10011110100', 85: '10011110010', 86: '11110100100', 87: '11110010100',
    88: '11110010010', 89: '11011011110', 90: '11011110110', 91: '11110110110',
    92: '10101111000', 93: '10100011110', 94: '10001011110', 95: '10111101000',
    96: '10111100010', 97: '11110101000', 98: '11110100010', 99: '10111011110',
    100: '10111101110', 101: '11101011110', 102: '11110101110',
    103: '11010000100', 104: '11010010000', 105: '11010011100', 106: '1100011101011',
  };

  // Start/Stop patterns
  static const _startB = '11010010000';
  static const _stop = '1100011101011';

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;

    final chars = code.codeUnits;
    if (chars.isEmpty) return;

    // Build the barcode pattern
    final pattern = StringBuffer(_startB);
    int checksum = 104; // Start B
    for (int i = 0; i < chars.length; i++) {
      final val = chars[i] - 32;
      if (val >= 0 && val < 103) {
        pattern.write(_patterns[val] ?? '');
        checksum += val * (i + 1);
      }
    }
    checksum = checksum % 103;
    pattern.write(_patterns[checksum] ?? '');
    pattern.write(_stop);

    final bars = pattern.toString();
    if (bars.isEmpty) return;

    final barWidth = size.width / bars.length;
    var x = 0.0;
    for (int i = 0; i < bars.length; i++) {
      if (bars[i] == '1') {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, barWidth * 1.1, size.height * 0.85),
          paint,
        );
      }
      x += barWidth;
    }

    // Draw human-readable code below
    final textPainter = TextPainter(
      text: TextSpan(
        text: code,
        style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: size.width);
    textPainter.paint(canvas, Offset((size.width - textPainter.width) / 2, size.height * 0.86));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
