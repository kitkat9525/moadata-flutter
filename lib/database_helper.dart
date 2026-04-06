import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nrf/ble_data_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'ble_data.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE ble_data(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            type INTEGER,
            hr INTEGER,
            rr INTEGER,
            spo2 INTEGER,
            sdnn INTEGER,
            rmssd INTEGER,
            stress INTEGER,
            sleep INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ble_data ADD COLUMN sleep INTEGER DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> insertBleData(BleData data) async {
    final db = await database;
    await db.insert(
      'ble_data',
      data.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BleData>> getBleData({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ble_data',
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return BleData.fromMap(maps[i]);
    });
  }

  Future<void> clearOldData(int days) async {
    final db = await database;
    final date = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    await db.delete(
      'ble_data',
      where: 'timestamp < ?',
      whereArgs: [date],
    );
  }
}
