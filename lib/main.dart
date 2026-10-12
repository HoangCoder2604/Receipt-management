import 'receipt_image_quality.dart';
import 'dart:async';
import 'dart:convert';
import 'transaction_date_rules.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'expense_store.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'receipt_parser.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ReceiptlyApp()); }
const primary = Color(0xFF315DE6);
const ink = Color(0xFF17233B);
const categories = ['Ăn uống', 'Mua sắm', 'Di chuyển', 'Hóa đơn', 'Sức khỏe', 'Khác'];
const colors = [Color(0xFF4569E7), Color(0xFFFFB65D), Color(0xFF45C6B3), Color(0xFFAA89E8), Color(0xFFFF7795), Color(0xFF8FA0B6)];
final money = NumberFormat.decimalPattern('vi_VN');
String vnd(num v) => '${money.format(v.round())} ₫';

class Expense {
  final String id, merchant, category, note;
  final double amount;
  final DateTime date;
  const Expense({required this.id, required this.merchant, required this.category, required this.note, required this.amount, required this.date});
  Map<String, dynamic> toJson() => {'id':id, 'merchant':merchant, 'category':category, 'note':note, 'amount':amount, 'date':date.toIso8601String()};
  factory Expense.fromJson(Map<String,dynamic> v) => Expense(id:v['id'].toString(),merchant:v['merchant'].toString(),category:v['category'].toString(),note:(v['note']??'').toString(),amount:(v['amount'] as num).toDouble(),date:DateTime.parse(v['date'].toString()));
}

class ReceiptlyApp extends StatelessWidget {
  const ReceiptlyApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false,title:'Receiptly',theme:ThemeData(useMaterial3:true,scaffoldBackgroundColor:const Color(0xFFF6F8FC),colorScheme:ColorScheme.fromSeed(seedColor:primary),fontFamily:'Roboto',appBarTheme:const AppBarTheme(backgroundColor:Color(0xFFF6F8FC),centerTitle:false,foregroundColor:ink)),home:const HomePage());
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _dayRefresh;
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_clampSelectedMonth);
    }
  }
  void _clampSelectedMonth() {
    if (TransactionDateRules.isFutureMonth(selectedMonth)) {
      selectedMonth = TransactionDateRules.currentMonth();
    }
  }
  @override void dispose() {
    _dayRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  List<Expense> items=[];
  bool loading=true, scanning=false;
  int tab=0;
  DateTime selectedMonth=DateTime(DateTime.now().year,DateTime.now().month);
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dayRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_clampSelectedMonth);
    });
    _load();
  }
  final ExpenseStore store = ExpenseStore();
  Future<void> _load() async {
    try {
      await store.initialize();
      final rows = await store.all();
      items = rows.map(Expense.fromJson).toList();
    } catch (error) {
      if (mounted) _toast('Không thể đọc dữ liệu: $error');
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> _reload() async {
    final rows = await store.all();
    if (mounted) setState(() => items = rows.map(Expense.fromJson).toList());
  }
  Future<void> _exportBackup() async {
    try {
      final records = await store.all();
      final content = jsonEncode({'format': 'receiptly-backup', 'version': 1,
        'exportedAt': DateTime.now().toIso8601String(), 'expenses': records});
      final folder = await getTemporaryDirectory();
      final file = File('${folder.path}/receiptly-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json');
      await file.writeAsString(content, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Sao lưu Receiptly'));
    } catch (error) { _toast('Xuất dữ liệu thất bại: $error'); }
  }
  Future<void> _importBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final raw = file.bytes == null ? await File(file.path!).readAsString() : utf8.decode(file.bytes!);
      final obj = jsonDecode(raw);
      if (obj is! Map || obj['format'] != 'receiptly-backup' || obj['version'] != 1 || obj['expenses'] is! List) {
        throw const FormatException('Không đúng định dạng sao lưu Receiptly');
      }
      final parsed = (obj['expenses'] as List).map((e) => Expense.fromJson(Map<String,dynamic>.from(e as Map))).toList();
      final invalid = parsed.where((expense) => !TransactionDateRules.isValid(expense.date)).length;
      if (invalid > 0) {
        throw FormatException('Bản sao lưu có $invalid giao dịch ở tương lai hoặc trước năm 2000. Hãy kiểm tra ngày giao dịch trước khi nhập.');
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Nhập bản sao lưu?'),
        content: Text('Tìm thấy ${parsed.length} giao dịch. Giao dịch trùng ID sẽ được cập nhật; dữ liệu hiện tại khác ID được giữ lại.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Nhập'))],
      ));
      if (confirm != true) return;
      await store.importRecords(parsed.map((e) => e.toJson()).toList());
      await _reload();
      _toast('Đã nhập ${parsed.length} giao dịch');
    } catch (error) { _toast('Không thể nhập dữ liệu: $error'); }
  }
  Future<void> _openDataMenu() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Dữ liệu & sao lưu'), subtitle: Text('Lưu SQLite trên điện thoại • không cần tài khoản')),
        ListTile(leading: const Icon(Icons.ios_share), title: const Text('Xuất sao lưu JSON'), onTap: () { Navigator.pop(ctx); _exportBackup(); }),
        ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Nhập sao lưu JSON'), onTap: () { Navigator.pop(ctx); _importBackup(); }),
        const SizedBox(height: 18),
      ]),
    ));
  }
  void _toast(String s){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}
  List<Expense> get monthItems => items.where((e)=>e.date.year==selectedMonth.year && e.date.month==selectedMonth.month).toList()..sort((a,b)=>b.date.compareTo(a.date));
  Future<void> _entry({ReceiptData? parsed, Expense? editing}) async {
    final result=await showModalBottomSheet<Expense>(context:context,isScrollControlled:true,backgroundColor:Colors.white,showDragHandle:true,builder:(_)=>EntrySheet(parsed:parsed,editing:editing));
    if(result==null)return;
    if (!TransactionDateRules.isValid(result.date)) {
      _toast('Không thể lưu giao dịch trong tương lai.');
      return;
    }
    try { await store.upsert(result.toJson()); await _reload();
      if (mounted) setState(() => selectedMonth = DateTime(result.date.year,result.date.month));
      _toast('Đã lưu khoản chi');
    } catch (error) { _toast('Không thể lưu dữ liệu: $error'); }
  }
  Future<void> _scan(ImageSource source) async {
    if(scanning)return;
    final picked=await ImagePicker().pickImage(source:source,imageQuality:85,maxWidth:1800);
    if(picked==null)return;
    setState(()=>scanning=true);
    final recognizer=TextRecognizer(script:TextRecognitionScript.latin);
    try{
      final quality = await ReceiptImageQuality.inspect(picked.path);
      final recognized=await recognizer.processImage(InputImage.fromFilePath(picked.path));
      final positionedLines = <ReceiptOcrLine>[
        for (final block in recognized.blocks)
          for (final line in block.lines)
            ReceiptOcrLine(line.text, line.boundingBox.left, line.boundingBox.top,
              line.boundingBox.width, line.boundingBox.height),
      ];
      final parsed = ReceiptLayoutParser.parse(positionedLines,
        fallbackText: recognized.text);
      if (!mounted) return;
      if (recognized.text.trim().isEmpty) {
        _toast('Không tìm thấy chữ. Hãy chụp rõ hơn.');
        return;
      }
      final assessment = ReceiptValidation.evaluate(
        parsed,
        recognizedCharacters: recognized.text.trim().length,
        lineCount: positionedLines.length,
        severelyBlurred: quality.severelyBlurred,
        recognizedText: recognized.text,
      );
      if (!assessment.accepted) {
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Không nhận diện được hóa đơn'),
          content: Text(assessment.reason),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
        ));
        return;
      }
      if (assessment.needsReview && mounted) {
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Cần kiểm tra kết quả OCR'),
          content: Text(assessment.reason),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Kiểm tra và sửa'))],
        ));
      }
      if (!mounted) return;
      await _entry(parsed:parsed);
    }catch(e){_toast('Không đọc được hóa đơn: $e');}
    finally{await recognizer.close();if(mounted)setState(()=>scanning=false);}
  }
  void _showScanPicker(){showModalBottomSheet(context:context,showDragHandle:true,builder:(_) => SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,4,20,22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Quét hóa đơn',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Chọn cách lấy hình. OCR xử lý ngay trên điện thoại.'),ListTile(leading:const Icon(Icons.photo_camera_outlined),title:const Text('Chụp hóa đơn'),onTap:(){Navigator.pop(context);_scan(ImageSource.camera);}),ListTile(leading:const Icon(Icons.photo_library_outlined),title:const Text('Chọn ảnh từ thư viện'),onTap:(){Navigator.pop(context);_scan(ImageSource.gallery);})]))));}
  Future<void> _delete(Expense e) async {try {await store.delete(e.id); await _reload(); _toast('Đã xóa giao dịch');} catch(error) {_toast('Xóa thất bại: $error');}}
  @override Widget build(BuildContext context){ final data=monthItems;final total=data.fold<double>(0,(s,e)=>s+e.amount);return Scaffold(appBar:AppBar(title:Row(children:[Container(padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:primary,borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.receipt_long,color:Colors.white,size:21)),const SizedBox(width:10),const Text('Receiptly',style:TextStyle(fontWeight:FontWeight.w800,letterSpacing:-.7))]),actions:[IconButton(tooltip:'Sao lưu / Khôi phục',onPressed:_openDataMenu,icon:const Icon(Icons.backup_outlined)),IconButton(tooltip:'Thông tin',onPressed:()=>showAboutDialog(context:context,applicationName:'Receiptly',applicationVersion:'1.0.0',children:[const Text('Theo dõi chi tiêu offline • Google ML Kit OCR • dữ liệu lưu trên thiết bị.')]),icon:const Icon(Icons.info_outline))]),body:loading?const Center(child:CircularProgressIndicator()):SafeArea(child:tab==0?_dashboard(data,total):tab==1?_transactions(data):_insights(data,total)),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Tổng quan'),NavigationDestination(icon:Icon(Icons.list_alt_outlined),selectedIcon:Icon(Icons.list_alt),label:'Giao dịch'),NavigationDestination(icon:Icon(Icons.pie_chart_outline),selectedIcon:Icon(Icons.pie_chart),label:'Thống kê')]),floatingActionButton:scanning?const FloatingActionButton(onPressed:null,child:CircularProgressIndicator(color:primary)):FloatingActionButton.extended(backgroundColor:primary,foregroundColor:Colors.white,onPressed:_showScanPicker,icon:const Icon(Icons.document_scanner_outlined),label:const Text('Quét hóa đơn',style:TextStyle(fontWeight:FontWeight.w700)))); }
  Widget _monthControl() {
    final canNext = TransactionDateRules.canGoToNextMonth(selectedMonth);
    return Row(children: [
      IconButton(
        tooltip: 'Tháng trước',
        onPressed: () => setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1)),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(child: Center(child: Text('Tháng ${selectedMonth.month}/${selectedMonth.year}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
      IconButton(
        tooltip: canNext ? 'Tháng sau' : 'Không thể xem tháng tương lai',
        onPressed: canNext ? () {
          // Check against the REAL current date at click time, not only at build time.
          if (!TransactionDateRules.canGoToNextMonth(selectedMonth)) return;
          setState(() => selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1));
        } : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ]);
  }
  Widget _dashboard(List<Expense> data,double total)=>ListView(padding:const EdgeInsets.fromLTRB(18,6,18,110),children:[_monthControl(),const SizedBox(height:10),Container(padding:const EdgeInsets.all(24),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF385FE4),Color(0xFF7895F5)]),borderRadius:BorderRadius.circular(24)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Tổng chi trong tháng',style:TextStyle(color:Colors.white70,fontSize:15)),const SizedBox(height:10),FittedBox(fit:BoxFit.scaleDown,child:Text(vnd(total),style:const TextStyle(fontSize:35,color:Colors.white,fontWeight:FontWeight.w900))),const SizedBox(height:22),Row(children:[const Icon(Icons.receipt_outlined,color:Colors.white70,size:18),const SizedBox(width:6),Text('${data.length} giao dịch',style:const TextStyle(color:Colors.white))])])),const SizedBox(height:24),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Giao dịch gần đây',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:ink)),TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('Xem tất cả'))]),if(data.isEmpty)_empty() else ...data.take(5).map(_tile),const SizedBox(height:16),OutlinedButton.icon(onPressed:()=>_entry(),icon:const Icon(Icons.add),label:const Text('Thêm giao dịch thủ công'),style:OutlinedButton.styleFrom(padding:const EdgeInsets.all(16)))]);
  Widget _empty()=>Container(padding:const EdgeInsets.symmetric(vertical:44,horizontal:22),child:Column(children:[const Icon(Icons.wallet_outlined,color:Color(0xFF9EADD1),size:57),const SizedBox(height:14),const Text('Chưa có giao dịch',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Quét hóa đơn hoặc nhập khoản chi đầu tiên.',textAlign:TextAlign.center,style:TextStyle(color:Colors.black54))]));
  Widget _tile(Expense e){final index=categories.indexOf(e.category);return Card(margin:const EdgeInsets.only(bottom:10),color:Colors.white,elevation:0,child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:5),leading:CircleAvatar(radius:23,backgroundColor:colors[index<0?5:index].withValues(alpha:.14),child:Icon([Icons.restaurant,Icons.shopping_bag,Icons.directions_car,Icons.bolt,Icons.medical_services,Icons.more_horiz][index<0?5:index],color:colors[index<0?5:index])),title:Text(e.merchant,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${e.category} • ${DateFormat('dd/MM/yyyy').format(e.date)}'),trailing:Text(vnd(e.amount),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:13)),onTap:()=>_entry(editing:e),onLongPress:()=>showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Xóa giao dịch?'),content:Text(e.merchant),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Hủy')),TextButton(onPressed:(){Navigator.pop(ctx);_delete(e);},child:const Text('Xóa'))]))));}
  Widget _transactions(List<Expense> data)=>ListView(padding:const EdgeInsets.fromLTRB(18,8,18,110),children:[_monthControl(),const SizedBox(height:15),Row(children:[const Expanded(child:Text('Giao dịch',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800))),IconButton.filledTonal(onPressed:()=>_entry(),icon:const Icon(Icons.add))]),const SizedBox(height:12),if(data.isEmpty)_empty() else ...data.map(_tile),const SizedBox(height:8),const Text('Chạm để chỉnh sửa • Nhấn giữ để xóa',textAlign:TextAlign.center,style:TextStyle(color:Colors.black45,fontSize:12))]);
  Widget _insights(List<Expense> data, double total) {
    final sums = List<double>.filled(categories.length, 0);
    for (final expense in data) {
      final index = categories.indexOf(expense.category);
      sums[index < 0 ? 5 : index] += expense.amount;
    }
    final days = List.generate(7, (_) => List<double>.filled(categories.length, 0));
    final now = DateTime.now();
    for (final expense in items) {
      final age = DateTime(now.year, now.month, now.day)
          .difference(DateTime(expense.date.year, expense.date.month, expense.date.day))
          .inDays;
      if (age >= 0 && age < 7) { final index = categories.indexOf(expense.category); days[6 - age][index < 0 ? 5 : index] += expense.amount; }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 110),
      children: [
        _monthControl(),
        const SizedBox(height: 10),
        const Text('Phân tích chi tiêu', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        _panel(
          Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Theo danh mục', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ),
              const SizedBox(height: 18),
              SizedBox(height: 190, child: AnimatedPieChart(values: sums)),
              const SizedBox(height: 14),
              ...List.generate(categories.length, (index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  CircleAvatar(radius: 5, backgroundColor: colors[index]),
                  const SizedBox(width: 10),
                  Expanded(child: Text(categories[index])),
                  Text(vnd(sums[index]), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              )),
            ],
          ),
        ),
        const SizedBox(height: 17),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('7 ngày gần nhất', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              SizedBox(height: 175, child: AnimatedBars(values: days)),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('6 ngày trước', style: TextStyle(color: Colors.black45, fontSize: 12)),
                  Text('Hôm nay', style: TextStyle(color: Colors.black45, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.only(top: 15),
            child: Text('Hãy thêm giao dịch để biểu đồ có dữ liệu.', textAlign: TextAlign.center),
          ),
      ],
    );
  }
  Widget _panel(Widget child)=>Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22)),child:child);
}

class EntrySheet extends StatefulWidget {final ReceiptData? parsed;final Expense? editing;const EntrySheet({super.key,this.parsed,this.editing});@override State<EntrySheet> createState()=>_EntrySheetState();}
class _EntrySheetState extends State<EntrySheet> {
  late final TextEditingController merchant,amount,note;
  late DateTime date;
  String category=categories[0];
  @override void initState(){super.initState();final e=widget.editing;merchant=TextEditingController(text:e?.merchant??widget.parsed?.merchant??'');amount=TextEditingController(text:e!=null?e.amount.round().toString():(widget.parsed?.total?.round().toString()??''));note=TextEditingController(text:e?.note??'');date=e?.date??widget.parsed?.date??DateTime.now();category=e?.category??categories[0];}
  @override void dispose(){merchant.dispose();amount.dispose();note.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    final now = TransactionDateRules.today();
    final future = TransactionDateRules.isFuture(date);
    return Padding(
      padding: EdgeInsets.only(left: 22, right: 22,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 22),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.editing != null ? 'Sửa giao dịch' :
              widget.parsed != null ? 'Kiểm tra hóa đơn' : 'Thêm khoản chi',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            if (widget.parsed != null)
              Text(widget.parsed!.date == null
                ? 'Không tìm thấy ngày hóa đơn. Hãy chọn đúng ngày trước khi lưu.'
                : future
                  ? 'Ngày trên hóa đơn nằm trong tương lai. Hãy kiểm tra và chọn ngày hợp lệ.'
                  : 'Đã nhận diện ngày hóa đơn. Hãy kiểm tra thông tin trước khi lưu.',
                style: TextStyle(color: widget.parsed!.date == null || future
                    ? Colors.deepOrange : Colors.black54)),
            const SizedBox(height: 18),
            TextField(controller: merchant, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tên cửa hàng / nội dung',
                prefixIcon: Icon(Icons.storefront), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: amount, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tiền (VND)',
                prefixIcon: Icon(Icons.payments_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: category,
              decoration: const InputDecoration(labelText: 'Danh mục',
                prefixIcon: Icon(Icons.category_outlined), border: OutlineInputBorder()),
              items: categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (value) { if (value != null) setState(() => category = value); }),
            const SizedBox(height: 10),
            ListTile(contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text('Ngày: ${DateFormat('dd/MM/yyyy').format(date)}'),
              subtitle: future ? const Text('Ngày tương lai không hợp lệ',
                style: TextStyle(color: Colors.deepOrange)) : null,
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final today = TransactionDateRules.today();
                final initial = date.isAfter(today) ? today :
                  date.isBefore(DateTime(2000)) ? DateTime(2000) : date;
                final picked = await showDatePicker(context: context,
                  initialDate: initial, firstDate: DateTime(2000), lastDate: today);
                if (picked != null && mounted) setState(() => date = picked);
              }),
            TextField(controller: note, maxLines: 2,
              decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)',
                border: OutlineInputBorder())),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, height: 52,
              child: FilledButton.icon(onPressed: () {
                final value = double.tryParse(amount.text.trim()
                  .replaceAll(RegExp(r'[, .\s₫đ]'), ''));
                if (merchant.text.trim().isEmpty || value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Vui lòng nhập tên và số tiền hợp lệ')));
                  return;
                }
                // Check AGAIN on save in case the day changed while this sheet was open.
                if (!TransactionDateRules.isValid(date)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Không được lưu giao dịch tương lai. Hãy chọn ngày hiện tại hoặc quá khứ.')));
                  setState(() {});
                  return;
                }
                Navigator.pop(context, Expense(
                  id: widget.editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                  merchant: merchant.text.trim(), amount: value,
                  category: category, note: note.text.trim(), date: date));
              }, icon: const Icon(Icons.check), label: const Text('Lưu giao dịch'))),
          ],
        ),
      ),
    );
  }
}

class AnimatedPieChart extends StatefulWidget{final List<double> values;const AnimatedPieChart({super.key,required this.values});@override State<AnimatedPieChart> createState()=>_AnimatedPieChartState();}
class _AnimatedPieChartState extends State<AnimatedPieChart> with SingleTickerProviderStateMixin {late final AnimationController controller;@override void initState(){super.initState();controller=AnimationController(vsync:this,duration:const Duration(milliseconds:800))..forward();}@override void didUpdateWidget(covariant AnimatedPieChart oldWidget){super.didUpdateWidget(oldWidget);controller.forward(from:0);}@override void dispose(){controller.dispose();super.dispose();}@override Widget build(BuildContext context)=>AnimatedBuilder(animation:controller,builder:(_,__)=>CustomPaint(painter:PiePainter(widget.values,controller.value),child:const SizedBox.expand()));}
class PiePainter extends CustomPainter{final List<double> values;final double progress;PiePainter(this.values,this.progress);@override void paint(Canvas canvas,Size size){final center=Offset(size.width/2,size.height/2);final radius=math.min(size.width,size.height)*.44;final rect=Rect.fromCircle(center:center,radius:radius);final total=values.fold<double>(0,(a,b)=>a+b);final bg=Paint()..color=const Color(0xFFE9EDF6)..strokeWidth=24..style=PaintingStyle.stroke;canvas.drawCircle(center,radius,bg);if(total<=0)return;var start=-math.pi/2;for(var i=0;i<values.length;i++){final angle=2*math.pi*values[i]/total*progress;canvas.drawArc(rect,start,angle,false,Paint()..color=colors[i]..strokeWidth=24..strokeCap=StrokeCap.butt..style=PaintingStyle.stroke);start+=angle;}final p=TextPainter(text:TextSpan(text:'${(progress*100).round()}%',style:const TextStyle(color:ink,fontSize:25,fontWeight:FontWeight.w900)),textDirection:ui.TextDirection.ltr)..layout();p.paint(canvas,center-Offset(p.width/2,p.height/2));}@override bool shouldRepaint(covariant PiePainter old)=>old.progress!=progress||old.values!=values;}
class AnimatedBars extends StatefulWidget {
  final List<List<double>> values; // 7 days x categories
  const AnimatedBars({super.key, required this.values});
  @override State<AnimatedBars> createState() => _AnimatedBarsState();
}
class _AnimatedBarsState extends State<AnimatedBars> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override void initState() { super.initState(); controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))..forward(); }
  @override void didUpdateWidget(covariant AnimatedBars oldWidget) { super.didUpdateWidget(oldWidget); controller.forward(from: 0); }
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => CustomPaint(painter: BarsPainter(widget.values, controller.value), child: const SizedBox.expand()),
  );
}
class BarsPainter extends CustomPainter {
  final List<List<double>> values;
  final double progress;
  BarsPainter(this.values, this.progress);
  @override void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final totals = values.map((day) => day.fold<double>(0, (a,b) => a+b)).toList();
    final maxTotal = totals.fold<double>(0, (a,b) => math.max(a,b));
    final width = size.width / values.length;
    final plotHeight = size.height - 10;
    for (var day = 0; day < values.length; day++) {
      var bottom = size.height;
      for (var category = 0; category < values[day].length; category++) {
        final value = values[day][category];
        if (value <= 0 || maxTotal <= 0) continue;
        final height = value / maxTotal * plotHeight * progress;
        final rect = Rect.fromLTWH(day * width + width * .20, bottom - height, width * .60, height);
        canvas.drawRect(rect, Paint()..color = colors[category < colors.length ? category : colors.length-1]);
        bottom -= height;
      }
    }
  }
  @override bool shouldRepaint(covariant BarsPainter old) => old.progress != progress || old.values != values;
}
