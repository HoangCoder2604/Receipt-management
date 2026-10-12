import 'dart:io';
import 'package:image/image.dart' as img;

class ReceiptImageQuality {
  final bool severelyBlurred;
  final String? warning;
  const ReceiptImageQuality(this.severelyBlurred, this.warning);

  /// A conservative focus screen: local image gradients, sampled sparsely.
  /// This is NOT a measure of OCR correctness. OCR text is checked separately.
  static Future<ReceiptImageQuality> inspect(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return const ReceiptImageQuality(true, 'Không thể giải mã ảnh.');
      if (image.width < 450 || image.height < 450) {
        return const ReceiptImageQuality(false, 'Ảnh khá nhỏ, chữ có thể khó đọc.');
      }
      final stride = (image.width ~/ 160).clamp(2, 15);
      double edge = 0;
      var count = 0;
      double gray(int x, int y) {
        final p = image.getPixel(x, y);
        return p.r.toDouble() * .299 + p.g.toDouble() * .587 + p.b.toDouble() * .114;
      }
      // Reject only exceptionally flat, unreadable images. Low-contrast
      // receipts can still be valid, hence the independent OCR evidence gate.
      for (var y = stride; y < image.height - stride; y += stride) {
        for (var x = stride; x < image.width - stride; x += stride) {
          final g = gray(x, y);
          edge += (g - gray(x + stride, y)).abs() + (g - gray(x, y + stride)).abs();
          count++;
        }
      }
      final average = count == 0 ? 0 : edge / (count * 2);
      return ReceiptImageQuality(average < 2.2, average < 2.2 ? 'Ảnh có độ tương phản chi tiết rất thấp.' : null);
    } catch (_) {
      return const ReceiptImageQuality(false, null);
    }
  }
}
