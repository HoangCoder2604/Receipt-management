import 'dart:convert';
import 'transaction_date_rules.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Single-device SQLite storage, with idempotent migration from legacy prefs.
class ExpenseStore {
  Database? _database;
  Future<Database> get db async {
    if (_database != null) return _database!;
    final directory = await getDatabasesPath();
    _database = await openDatabase(path.join(directory, 'receiptly.db'), version: 1,
      onCreate: (database, version) async {
        await database.execute('''CREATE TABLE expenses (
          id TEXT PRIMARY KEY, merchant TEXT NOT NULL, category TEXT NOT NULL,
          note TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL)''');
      });
    return _database!;
  }

  Future<void> initialize() async {
    final database = await db;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sqlite_migration_done_v1') == true) return;
    final raw = prefs.getString('expenses_v1');
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('Dữ liệu cũ không hợp lệ');
      final records = decoded.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      await database.transaction((txn) async {
        for (final record in records) {
          await txn.insert('expenses', _validated(record, allowLegacyFuture: true), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
    }
    // Flag is set only after the database transaction succeeded. Keep legacy data.
    final done = await prefs.setBool('sqlite_migration_done_v1', true);
    if (!done) throw StateError('Không thể đánh dấu chuyển dữ liệu hoàn tất');
  }

  Map<String, Object?> _validated(Map<String, dynamic> data, {bool allowLegacyFuture = false}) {
    final id = data['id']?.toString() ?? '';
    final merchant = data['merchant']?.toString() ?? '';
    final category = data['category']?.toString() ?? '';
    final note = data['note']?.toString() ?? '';
    final amount = (data['amount'] as num).toDouble();
    final transactionDate = DateTime.parse(data['date'].toString());
    if (!allowLegacyFuture && !TransactionDateRules.isValid(transactionDate)) {
      throw const FormatException('Ngày giao dịch không hợp lệ hoặc nằm trong tương lai');
    }
    final date = transactionDate.toIso8601String();
    if (id.isEmpty || merchant.trim().isEmpty || amount <= 0 || !amount.isFinite) {
      throw const FormatException('Giao dịch không hợp lệ');
    }
    return {'id': id, 'merchant': merchant, 'category': category, 'note': note, 'amount': amount, 'date': date};
  }

  Future<List<Map<String, dynamic>>> all() async {
    final database = await db;
    return database.query('expenses', orderBy: 'date DESC');
  }
  Future<void> upsert(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert('expenses', _validated(data), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> delete(String id) async {
    final database = await db;
    await database.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }
  Future<void> importRecords(List<Map<String, dynamic>> data) async {
    final records = data.map(_validated).toList();
    final database = await db;
    await database.transaction((txn) async {
      for (final record in records) {
        await txn.insert('expenses', record, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
