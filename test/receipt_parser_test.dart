import 'package:flutter_test/flutter_test.dart';
import 'package:receiptly/receipt_parser.dart';
void main(){
  test('extracts a Vietnamese receipt total and date',(){
    final r=ReceiptParser.parse('SIÊU THỊ MINIMART\nNgày: 12/10/2026\nBánh mì 15.000\nSữa 25.000\nTỔNG CỘNG 40.000 VND');
    expect(r.merchant,'SIÊU THỊ MINIMART');
    expect(r.total,40000);
    expect(r.date,DateTime(2026,10,12));
  });
  test('prioritizes grand total over change',(){
    final r=ReceiptParser.parse('COFFEE HOUSE\nTotal 75,000\nChange 25,000');
    expect(r.total,75000);
  });
  test('recognizes ISO date and localized dates', () {
    expect(ReceiptParser.parse('QUÁN CÀ PHÊ\nNgày: 2026-09-05\nTổng tiền: 45.000đ').date, DateTime(2026,9,5));
    expect(ReceiptParser.parse('SHOP\nNgày 5 tháng 9 năm 2026\nTHANH TOÁN 45.000đ').date, DateTime(2026,9,5));
  });
  test('does not silently invent a date', () {
    final parsed = ReceiptParser.parse('NHÀ HÀNG A\nTỔNG CỘNG 50.000đ');
    expect(parsed.date, isNull);
    expect(parsed.isLikelyReceipt, isTrue);
  });
  test('non-receipt text is flagged', () {
    final parsed = ReceiptParser.parse('Lịch sinh hoạt\nTôi sẽ tới 05/09/2026.\nGiá dự kiến 45.000đ');
    expect(parsed.isLikelyReceipt, isFalse);
  });
  test('address house number and phone do not become total', () {
    final r = ReceiptParser.parse('CỬA HÀNG ABC\nĐịa chỉ: 123 Nguyễn Văn Linh, Đà Nẵng\nHotline 0905123456\nNgày: 05/09/2026\nTỔNG THANH TOÁN: 85.000đ');
    expect(r.merchant, 'CỬA HÀNG ABC');
    expect(r.total, 85000);
    expect(r.date, DateTime(2026, 9, 5));
  });
  test('does not treat house numbers as money', () {
    final r = ReceiptParser.parse('CỬA HÀNG ABC\nĐịa chỉ: 150.000 đường A\nMã hóa đơn: 1200000\nNgày: 05/09/2026');
    expect(r.total, isNull);
    expect(r.isLikelyReceipt, isFalse);
  });
  test('labeled total on next line', () {
    final r = ReceiptParser.parse('SHOP A\nNgày: 05/09/2026\nTỔNG CỘNG\n150.000');
    expect(r.total, 150000);
  });
  test('date line outranks other unrelated dates', () {
    final r = ReceiptParser.parse('SHOP A\nThông báo 01/01/2025\nNgày: 05/09/2026\nTỔNG CỘNG 150.000đ');
    expect(r.date, DateTime(2026,9,5));
  });
  test('layout joins split amount and excludes address numbers', () {
    final r = ReceiptLayoutParser.parse([
      const ReceiptOcrLine('QUÁN CÀ PHÊ AN', 90, 10, 240, 26),
      const ReceiptOcrLine('Địa chỉ: 150.000 Nguyễn Văn Linh', 10, 50, 360, 16),
      const ReceiptOcrLine('Ngày: 05/09/2026', 12, 75, 220, 16),
      const ReceiptOcrLine('Cà phê', 12, 110, 140, 17),
      const ReceiptOcrLine('25.000', 280, 110, 90, 17),
      const ReceiptOcrLine('TỔNG THANH TOÁN', 12, 160, 200, 18),
      const ReceiptOcrLine('85.000đ', 290, 160, 80, 18),
    ]);
    expect(r.total, 85000);
    expect(r.date, DateTime(2026, 9, 5));
    expect(r.merchant, 'QUÁN CÀ PHÊ AN');
  });
  test('real receipt without receipt/invoice words is accepted', () {
    final r = ReceiptParser.parse('TIỆM BÁNH HOA MAI\nNgày: 05/09/2026\nBánh mì 20.000\nTỔNG TIỀN 20.000');
    expect(r.total, 20000);
    expect(r.isLikelyReceipt, isTrue);
  });
  test('real receipt with unreadable shop still recognized by total', () {
    final r = ReceiptParser.parse('XYZ\nTỔNG CỘNG 85.000đ');
    expect(r.total, 85000);
    expect(r.isLikelyReceipt, isTrue);
  });
  test('layout total suffices even when name is not recognized', () {
    final r = ReceiptLayoutParser.parse([
      const ReceiptOcrLine('TỔNG CỘNG', 10, 70, 130, 17),
      const ReceiptOcrLine('85.000', 230, 70, 80, 17),
    ]);
    expect(r.total, 85000);
    expect(r.isLikelyReceipt, isTrue);
  });
  test('layout avoids guessing total from address and phone', () {
    final r = ReceiptLayoutParser.parse([
      const ReceiptOcrLine('SHOP ABC', 40, 5, 200, 25),
      const ReceiptOcrLine('Địa chỉ: 250.000 Đường A', 10, 50, 260, 16),
      const ReceiptOcrLine('Hotline 0905000000', 10, 70, 200, 16),
    ]);
    expect(r.total, isNull);
    expect(r.isLikelyReceipt, isFalse);
  });


// Position-aware parsing tests are intentionally independent of device/MLKit.

test('product descriptions with price are not merchant names', () {
  final r = ReceiptParser.parse('ĐẸP COFFEE\nĐC: 3 Nguyễn Văn Bình\nHÓA ĐƠN\nNgày: 06/06/2025\nCAFE SỮA 38,000\nTổng: 86,000');
  expect(r.merchant, 'ĐẸP COFFEE');
});
test('layout avoids priced item in merchant selection', () {
  final r = ReceiptLayoutParser.parse([
    const ReceiptOcrLine('ĐẸP COFFEE', 60, 10, 200, 23),
    const ReceiptOcrLine('Ngày: 06/06/2025', 10, 45, 170, 15),
    const ReceiptOcrLine('CAFE SỮA', 10, 90, 120, 15),
    const ReceiptOcrLine('38,000', 230, 90, 75, 15),
    const ReceiptOcrLine('Tổng: 86,000', 10, 130, 250, 18),
  ]);
  expect(r.merchant, 'ĐẸP COFFEE');
});
test('actual sample Dep Coffee receipt', () {
  final r = ReceiptParser.parse('ĐẸP COFFEE\nĐC: 3 Nguyễn Văn Bình, Quận 1\nHÓA ĐƠN BÁN HÀNG\nNgày: 06/06/2025\nCAFE SỮA 38,000\nNƯỚC ÉP CÀ RỐT 48,000\nTổng: 86,000');
  expect(r.merchant, 'ĐẸP COFFEE');
  expect(r.total, 86000);
  expect(r.date, DateTime(2025,6,6));
});
test('actual sample An Nam millions', () {
  final r = ReceiptParser.parse('AN NAM\nHOÁ ĐƠN\nNgày: 20/07/2030\nMÔ TẢ 10 triệu VND\nTỔNG CỘNG 70 triệu VND');
  expect(r.total, 70000000);
  expect(r.date, DateTime(2030,7,20));
});
test('actual sample The Noodle House abbreviated date', () {
  final r = ReceiptParser.parse('HÓA ĐƠN THANH TOÁN\nNgày: 16 thg 3, 2022\nTHE NOODLE HOUSE - 225NVT\nĐịa chỉ: 225 Đường Nguyễn Văn Thoại\nTổng tiền: 590,000');
  expect(r.total, 590000);
  expect(r.date, DateTime(2022,3,16));
});
test('allows editing ambiguous no-date OCR instead of blocking', () {
  final r = ReceiptParser.parse('SHOP A\nTỔNG CỘNG 50.000đ');
  expect(ReceiptValidation.evaluate(r, recognizedCharacters: 26, lineCount: 2, recognizedText: 'SHOP A\nTỔNG CỘNG 50.000đ').accepted, isTrue);
});

  test('clearly unrelated schoolwork is rejected', () {
    final r = ReceiptParser.parse('ĐỀ KIỂM TRA TOÁN\nBài tập chương 3\nTính diện tích tam giác');
    final assessment = ReceiptValidation.evaluate(r,
      recognizedCharacters: 63, lineCount: 3,
      recognizedText: 'ĐỀ KIỂM TRA TOÁN\nBài tập chương 3\nTính diện tích tam giác');
    expect(assessment.decision, ScanDecision.rejected);
  });
  test('legitimate receipt missing date remains editable', () {
    final r = ReceiptParser.parse('QUÁN CAFE\nCAFE SỮA 38.000đ\nTỔNG CỘNG 38.000đ');
    final assessment = ReceiptValidation.evaluate(r,
      recognizedCharacters: 47, lineCount: 3,
      recognizedText: 'QUÁN CAFE\nCAFE SỮA 38.000đ\nTỔNG CỘNG 38.000đ');
    expect(assessment.accepted, isTrue);
  });

}
