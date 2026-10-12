class ReceiptData {
  final String merchant;
  final double? total;
  final DateTime? date;
  final int confidence;
  final bool isLikelyReceipt;
  const ReceiptData({required this.merchant, required this.total, required this.date, required this.confidence, required this.isLikelyReceipt});
}

/// Conservative, fully offline Vietnamese receipt heuristics.
/// Unknown values are null rather than silently guessing from addresses/IDs.
class ReceiptParser {
  static final _total = RegExp(r'(tổng(?:\s*(?:cộng|tiền|thanh\s*toán|phải\s*trả))?|cần\s*thanh\s*toán|số\s*tiền\s*(?:phải\s*trả|thanh\s*toán)|khách\s*(?:phải\s*)?trả|thực\s*thu|grand\s*total|amount\s*due|total\s*(?:due|payment)?|payment\s*total|phải\s*trả)', caseSensitive:false);
  static final _notTotal = RegExp(r'(địa\s*chỉ|address|đường|street|phường|quận|huyện|tỉnh|thành\s*phố|số\s*nhà|mã\s*(?:đơn|giao\s*dịch|hóa\s*đơn|khách\s*hàng)|mã\s*số\s*thuế|\bmst\b|\btel\b|hotline|điện\s*thoại|phone|\bid\b|số\s*tài\s*khoản|account|\biban\b|\bvat\b|thuế|discount|giảm\s*giá|tiền\s*thừa|tiền\s*thối|\bchange\b|\bsubtotal\b|tạm\s*tính|đơn\s*giá|số\s*lượng|\bqty\b)', caseSensitive:false);
  static final _softExcluded = RegExp(r'(\bngày\b|\bdate\b|\btime\b|\bgiờ\b|\bhour\b|\bwebsite\b|\bwww\b|\bhttp)', caseSensitive:false);
  static final _receipt = RegExp(r'(hóa\s*đơn|hoá\s*đơn|receipt|invoice|bill|phiếu\s*thu|thu\s*ngân|cashier|đơn\s*giá|số\s*lượng|\bqty\b)',caseSensitive:false);
  static final _million = RegExp(r'(\d+(?:[.,]\d+)?)\s*(triệu|trieu|million)\s*(?:đồng|vnd|vnđ|đ)?',caseSensitive:false);
  static final _dateLabel = RegExp(r'(ngày\s*(?:bán|lập|giao\s*dịch|thanh\s*toán)?|date|issued|ngay\s*(?:ban|lap))',caseSensitive:false);

  static ReceiptData parse(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((s)=>s.trim()).where((s)=>s.isNotEmpty).toList();
    final merchant = _merchant(lines);
    final date = _findDate(lines);
    double? amount;
    var topScore = -999;
    for (var i=0; i<lines.length; i++) {
      final line=lines[i];
      if (_notTotal.hasMatch(line) || _softExcluded.hasMatch(line)) continue;
      final strong=_total.hasMatch(line);
      // Bare figures are permitted only on explicit total lines or clearly
      // marked currency/payment lines, not on arbitrary text or addresses.
      final currency = RegExp(r'(?:₫|\b(?:vnd|vnđ)\b|\d\s*đ\b)',caseSensitive:false).hasMatch(line);
      if (!strong && !currency) continue;
      for (final candidate in _moneyCandidates(line)) {
        final score=(strong?120:0)+(currency?25:0)+i;
        if (score>topScore) { topScore=score; amount=candidate; }
      }
    }
    // Some receipts print 'TỔNG CỘNG' on one line, amount on the next.
    if (amount==null) {
      for (var i=0; i+1<lines.length; i++) {
        if (!_total.hasMatch(lines[i]) || _notTotal.hasMatch(lines[i])) continue;
        final next=lines[i+1];
        if (_notTotal.hasMatch(next)||_softExcluded.hasMatch(next)) continue;
        final amounts=_moneyCandidates(next);
        if (amounts.length==1) amount=amounts.single;
      }
    }
    final hasTotal=lines.any((s)=>_total.hasMatch(s) && !_notTotal.hasMatch(s));
    final hasReceipt=lines.any((s)=>_receipt.hasMatch(s));
    final hasMerchant=merchant!='Cửa hàng chưa xác định';
    final confidence=((hasTotal?35:0)+(hasReceipt?25:0)+(amount!=null?20:0)+(date!=null?10:0)+(hasMerchant?10:0));
    // Requiring multiple contextual clues avoids treating plain documents as receipts.
    final likely = (amount != null && hasTotal) ||
        (amount != null && hasReceipt && (hasMerchant || date != null)) ||
        (amount != null && hasMerchant && date != null);
    return ReceiptData(merchant:merchant,total:amount,date:date,confidence:confidence,isLikelyReceipt:likely);
  }

  static String _merchant(List<String> lines) {
    var bestScore=-999;
    String? best;
    for (var i=0; i<lines.length && i<10; i++) {
      final line=lines[i];
      if (line.length<3 || line.length>65) continue;
      if (_notTotal.hasMatch(line)||_softExcluded.hasMatch(line)||_total.hasMatch(line)||_receipt.hasMatch(line)) continue;
      // Product rows are not shop names: e.g. 'CAFE SỮA 38,000'.
      if (_moneyCandidates(line).isNotEmpty) continue;
      if (RegExp(r'^(?:mô\s*tả|thành\s*tiền|số\s*lượng|ho[aá]\s*[đd][ơo]n|h[oó]a\s*[đd][ơo]n|thanh\s*to[aá]n|b[aá]n\s*\d+|m[oô]\s*t[aả])',caseSensitive:false).hasMatch(line)) continue;
      if (RegExp(r'(?:\d[./:-]){2,}|\d{4,}|[@]|\bwww\b|\bcom\b',caseSensitive:false).hasMatch(line)) continue;
      final letters=RegExp(r'[a-zA-ZÀ-ỹ]').allMatches(line).length;
      if (letters<3 || letters < line.length*.43) continue;
      var score=30-i*2;
      if (RegExp(r'^(cửa\s*hàng|siêu\s*thị|quán|nhà\s*hàng|coffee|cafe|shop|mart|store|công\s*ty|cty|highlands)',caseSensitive:false).hasMatch(line)) score+=20;
      if (i==0) score+=6;
      if (score>bestScore) {bestScore=score;best=line;}
    }
    // Do not manufacture a merchant from an arbitrary isolated sentence.
    return bestScore>=19 ? best! : 'Cửa hàng chưa xác định';
  }

  static DateTime? _findDate(List<String> lines) {
    final matches=<({DateTime date,int score})>[];
    for (var i=0;i<lines.length;i++) {
      final line=lines[i].replaceAllMapped(RegExp(r'(?<=\d)[oO](?=\d)'),(_)=>'0');
      if (RegExp(r'(địa\s*chỉ|address|hotline|tel|phone|mã\s*đơn)',caseSensitive:false).hasMatch(line)) continue;
      final label=_dateLabel.hasMatch(line);
      final patterns=<RegExp>[
        RegExp(r'\b(20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b'),
        RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b'),
        RegExp(r'(?:ngày\s*)?(\d{1,2})\s*(?:tháng|thg|th)\.?\s*(\d{1,2})\s*[,/-]?\s*(?:năm\s*)?(20\d{2})',caseSensitive:false),
      ];
      for (var p=0;p<patterns.length;p++) {
        for (final m in patterns[p].allMatches(line)) {
          int y,mon,d;
          if (p==0) {y=int.parse(m[1]!);mon=int.parse(m[2]!);d=int.parse(m[3]!);}
          else {d=int.parse(m[1]!);mon=int.parse(m[2]!);y=int.parse(m[3]!);if(y<100)y+=2000;}
          final date=_validDate(y,mon,d);
          if(date!=null) matches.add((date:date,score:(label?100:0)-i));
        }
      }
      final spaced=RegExp(r'(?:ngày|date)\s*[:：]?\s*(\d{1,2})\s+(\d{1,2})\s+(20\d{2})',caseSensitive:false);
      for(final m in spaced.allMatches(line)) {
        final date=_validDate(int.parse(m[3]!),int.parse(m[2]!),int.parse(m[1]!));
        if(date!=null)matches.add((date:date,score:100-i));
      }
    }
    if(matches.isEmpty)return null;
    matches.sort((a,b)=>b.score.compareTo(a.score));
    return matches.first.date;
  }
  static DateTime? _validDate(int y,int m,int d) {
    if(y<2000||y>2100||m<1||m>12||d<1||d>31)return null;
    final date=DateTime(y,m,d);
    return (date.year==y&&date.month==m&&date.day==d)?date:null;
  }

  static List<double> _moneyCandidates(String line) {
    // Remove common timestamps, dates, phone-number-like sequences, and IDs.
    var clean=line.replaceAll(RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b'), ' ');
    clean=clean.replaceAll(RegExp(r'\b\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\b'),' ');
    final regex=RegExp(r'(?<![\d/.-])(?:\d{1,3}(?:[., ]\d{3})+|\d{4,9})(?:[.,]\d{2})?(?![\d/.-])');
    final result=<double>[];
    for (final match in _million.allMatches(clean)) {
      final amount = double.tryParse(match[1]!.replaceAll(',','.'));
      if (amount != null && amount > 0 && amount <= 1000) result.add(amount * 1000000);
    }
    clean = clean.replaceAll(_million, ' ');
    for(final m in regex.allMatches(clean)) {
      final token=m.group(0)!.trim().replaceAll(' ','');
      String normalized=token;
      if(RegExp(r'^\d{1,3}(?:[.,]\d{3})+$').hasMatch(normalized)) {
        normalized=normalized.replaceAll(RegExp(r'[.,]'),'');
      } else if(normalized.contains(',')&&normalized.contains('.')) {
        final idx=normalized.lastIndexOf(RegExp(r'[.,]'));
        normalized='${normalized.substring(0,idx).replaceAll(RegExp(r'[.,]'),'')}.${normalized.substring(idx+1)}';
      } else if(RegExp(r'^\d{4,9}[.,]\d{2}$').hasMatch(normalized)) {
        normalized=normalized.replaceAll(',','.');
      }
      final number=double.tryParse(normalized);
      if(number!=null&&number>=1000&&number<=1000000000)result.add(number);
    }
    return result;
  }
}


/// A line and its bounding rectangle from Google ML Kit (image pixel units).
/// Kept framework-independent so the parsing logic can be unit tested offline.
class ReceiptOcrLine {
  final String text;
  final double left, top, width, height;
  const ReceiptOcrLine(this.text, this.left, this.top, this.width, this.height);
  double get middleY => top + height / 2;
  double get middleX => left + width / 2;
}

/// Position-aware receipt parsing: merge columns on the same printed row,
/// then prefer price/date/merchant evidence supported by the receipt layout.
class ReceiptLayoutParser {
  static final _label = RegExp(
    r'(tổng(?:\s*(?:cộng|tiền|thanh\s*toán|phải\s*trả))?|thành\s*tiền|khách\s*trả|amount\s*due|grand\s*total|total\b|phải\s*trả)',
    caseSensitive: false);
  static final _excluded = RegExp(
    r'(địa\s*chỉ|address|\b(?:đường|street|phường|quận|huyện|mst|hotline|tel|phone|tax|vat|change|discount|subtotal|qty)\b|mã\s*(?:số|đơn|hóa\s*đơn)|số\s*(?:nhà|điện\s*thoại))',
    caseSensitive: false);
  static final _date = RegExp(r'(ngày|date|issued|\btime\b)', caseSensitive: false);

  static ReceiptData parse(List<ReceiptOcrLine> raw, {String fallbackText = ''}) {
    final lines = raw.where((e) => e.text.trim().isNotEmpty && e.width > 0 && e.height > 0).toList()
      ..sort((a, b) => a.middleY.compareTo(b.middleY));
    if (lines.isEmpty) return ReceiptParser.parse(fallbackText);
    final heights = lines.map((e) => e.height).toList()..sort();
    final rowTolerance = (heights[heights.length ~/ 2] * .65).clamp(5.0, 28.0);
    final rows = <List<ReceiptOcrLine>>[];
    for (final line in lines) {
      if (rows.isNotEmpty &&
          (line.middleY - rows.last.map((e) => e.middleY).reduce((a,b)=>a+b) / rows.last.length).abs() <= rowTolerance) {
        rows.last.add(line);
      } else {
        rows.add([line]);
      }
    }
    for (final row in rows) {row.sort((a,b)=>a.left.compareTo(b.left));}
    final texts = rows.map((row) => row.map((e)=>e.text.trim()).join('  ')).toList();
    final base = ReceiptParser.parse(texts.join('\n'));
    final money = _extractAmount(rows, texts);
    final merchant = _extractMerchant(rows, texts, base.merchant);
    // Layout lines sometimes split a date label and the value onto separate
    // rows; the legacy parser supports the commonly joined same-row forms.
    final date = base.date ?? _extractAdjacentDate(texts);
    final hasTotal = texts.any((e)=>_label.hasMatch(e) && !_excluded.hasMatch(e));
    final hasReceipt = texts.any((e)=>RegExp(r'(hóa\s*đơn|hoá\s*đơn|receipt|invoice|bill|thu\s*ngân|đơn\s*giá)', caseSensitive:false).hasMatch(e));
    final amount = money ?? base.total;
    // No single receipt keyword or identified shop name is mandatory.
    // Many genuine Vietnamese receipts omit 'hóa đơn' / 'tổng cộng',
    // and ML Kit can misread the shop sign.
    final merchantKnown = merchant != 'Cửa hàng chưa xác định';
    final reliable = (amount != null && hasTotal) ||
        (amount != null && hasReceipt && (merchantKnown || date != null)) ||
        (amount != null && merchantKnown && date != null);
    final confidence = ((hasTotal ? 40 : 0) + (amount != null ? 25 : 0) +
       (date != null ? 15 : 0) + (merchant != 'Cửa hàng chưa xác định' ? 10 : 0) +
       (hasReceipt ? 10 : 0)).clamp(0, 100);
    return ReceiptData(merchant: merchant, total: amount, date: date,
      confidence: confidence, isLikelyReceipt: reliable);
  }

  static double? _extractAmount(List<List<ReceiptOcrLine>> rows, List<String> texts) {
    final picks = <({double value, double score})>[];
    for (var i=0;i<rows.length;i++) {
      final text = texts[i];
      if (_excluded.hasMatch(text) || _date.hasMatch(text)) continue;
      final strong = _label.hasMatch(text);
      if (!strong) continue;
      final values = ReceiptParser._moneyCandidates(text);
      if (values.length == 1) {
        picks.add((value: values.single, score: 1000 + i.toDouble()));
      } else if (values.length > 1) {
        // A number aligned to the right is normally the row's total.
        for (final part in rows[i]) {
          for (final value in ReceiptParser._moneyCandidates(part.text)) {
            picks.add((value:value, score:700 + part.left + i.toDouble()));
          }
        }
      } else if (i+1<rows.length && !_excluded.hasMatch(texts[i+1]) && !_date.hasMatch(texts[i+1])) {
        final next = ReceiptParser._moneyCandidates(texts[i+1]);
        if (next.length == 1) picks.add((value:next.single, score:600+i.toDouble()));
      }
    }
    if (picks.isEmpty) return null;
    picks.sort((a,b)=>b.score.compareTo(a.score));
    return picks.first.value;
  }

  static String _extractMerchant(List<List<ReceiptOcrLine>> rows,List<String> texts,String fallback) {
    var bestScore = double.negativeInfinity;
    String? best;
    final n = rows.length < 9 ? rows.length : 9;
    final minLeft = rows.expand((row)=>row).map((e)=>e.left).reduce((a,b)=>a<b?a:b);
    final maxRight = rows.expand((row)=>row).map((e)=>e.left+e.width).reduce((a,b)=>a>b?a:b);
    final imageCenter = (minLeft+maxRight)/2;
    final heights = rows.expand((row)=>row).map((e)=>e.height).toList()..sort();
    final normalHeight = heights[heights.length~/2];
    for (var i=0;i<n;i++) {
      for (final e in rows[i]) {
        final text=e.text.trim();
        if(text.length<3 || text.length>55 || _excluded.hasMatch(text) || _date.hasMatch(text) || _label.hasMatch(text)) continue;
        // Avoid merchant candidates taken from line items / priced rows.
        if(ReceiptParser._moneyCandidates(text).isNotEmpty ||
            ReceiptParser._moneyCandidates(texts[i]).isNotEmpty) continue;
        if(RegExp(r'(?:\d[./:-]){2,}|\d{4,}|[@]|www|\b(?:receipt|invoice|bill)\b|h[oó]a\s*[đd][ơo]n|h[oó]a\s*[đd]ơn|^b[aá]n\s*\d+',caseSensitive:false).hasMatch(text)) continue;
        final letters=RegExp(r'[a-zA-ZÀ-ỹ]').allMatches(text).length;
        if(letters<3 || letters<text.length*.55) continue;
        var score = 35.0-i*5;
        score += ((e.height/normalHeight).clamp(.5,2.0)-1)*15;
        final width = (maxRight-minLeft).abs();
        if(width>0)score += (1-((e.middleX-imageCenter).abs()/(width/2)).clamp(0.0,1.0))*10;
        if(RegExp(r'(cửa\s*hàng|siêu\s*thị|coffee|cafe|shop|mart|store|quán|nhà\s*hàng)',caseSensitive:false).hasMatch(text)) score+=15;
        if(score>bestScore){bestScore=score;best=text;}
      }
    }
    return bestScore>=28 ? best! : fallback;
  }

  static DateTime? _extractAdjacentDate(List<String> texts) {
    for(var i=0;i+1<texts.length;i++) {
      if(!_date.hasMatch(texts[i])) continue;
      final parsed=ReceiptParser.parse('Ngày: ${texts[i+1]}');
      if(parsed.date!=null)return parsed.date;
    }
    return null;
  }
}

/// Evidence-based decision. Never treat image clarity alone as proof of
/// extraction correctness; unidentified fields require rescan/manual entry.
/// Three outcomes: reject only clearly unrelated text/unreadable images;
/// otherwise show editable suggestions, even with missing OCR fields.
enum ScanDecision { rejected, review, ready }

class ReceiptValidation {
  final ScanDecision decision;
  final String reason;
  const ReceiptValidation(this.decision, this.reason);
  bool get accepted => decision != ScanDecision.rejected;
  bool get needsReview => decision == ScanDecision.review;

  static final _receiptEvidence = RegExp(
    r'(h[oó]a\s*[đd][ơo]n|hoá\s*đơn|receipt|invoice|bill|tổng\s*(?:cộng|tiền|thanh\s*toán)|total\b|thanh\s*toán|thành\s*tiền|tiền\s*khách|đơn\s*giá|số\s*lượng|số\s*tiền|vnd|vnđ|₫|\d\s*đ\b)',
    caseSensitive: false,
  );
  static final _clearlyUnrelated = RegExp(
    r'(mục\s*lục|bài\s*tập|chương\s*trình\s*học|giáo\s*trình|đề\s*kiểm\s*tra|bài\s*giảng|tin\s*nhắn|conversation|chat\s*history|thời\s*khóa\s*biểu|curriculum|chapter\s*\d+)',
    caseSensitive: false,
  );

  static ReceiptValidation evaluate(
    ReceiptData parsed, {
    required int recognizedCharacters,
    required int lineCount,
    bool severelyBlurred = false,
    String recognizedText = '',
  }) {
    if (severelyBlurred && recognizedCharacters < 50) {
      return const ReceiptValidation(ScanDecision.rejected,
          'Ảnh quá mờ hoặc chữ không đọc được. Vui lòng chụp lại rõ hơn.');
    }
    if (recognizedCharacters < 10 || lineCount < 2) {
      return const ReceiptValidation(ScanDecision.rejected,
          'Ảnh không có đủ văn bản để phân tích. Vui lòng chọn ảnh hóa đơn rõ hơn.');
    }
    final hasEvidence = _receiptEvidence.hasMatch(recognizedText) ||
        parsed.isLikelyReceipt;
    final unrelatedMatches = _clearlyUnrelated.allMatches(recognizedText).length;
    if (!hasEvidence && unrelatedMatches >= 1 &&
        parsed.total == null) {
      return const ReceiptValidation(ScanDecision.rejected,
          'Ảnh này có vẻ là tài liệu hoặc nội dung khác, không phải hóa đơn. Vui lòng chọn ảnh hóa đơn.');
    }
    final hasMerchant = parsed.merchant.trim().isNotEmpty &&
        parsed.merchant != 'Cửa hàng chưa xác định';
    if (parsed.total == null || !hasMerchant || parsed.date == null || !hasEvidence) {
      return const ReceiptValidation(ScanDecision.review,
          'Đã đọc được chữ nhưng có thông tin chưa chắc chắn. Hãy kiểm tra tên cửa hàng, tổng tiền và ngày trước khi lưu.');
    }
    return const ReceiptValidation(ScanDecision.ready,
        'Đã nhận diện thông tin. Vui lòng đối chiếu với hóa đơn trước khi lưu.');
  }
}
