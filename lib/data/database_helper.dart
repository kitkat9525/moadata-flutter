import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nrf/data/ble_data_model.dart';

/// sqflite 기반 로컬 DB 싱글톤 헬퍼.
///
/// 스키마 버전 히스토리:
///   v1 — 초기 테이블 생성
///   v2 — sleep 컬럼 추가
///   v3 — timestamp 인덱스 추가
///   v4 — timestamp UNIQUE 제약 추가 (중복 삽입 방지)
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
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ble_data(
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT    NOT NULL UNIQUE,
            type      INTEGER NOT NULL DEFAULT 0,
            hr        INTEGER NOT NULL DEFAULT 0,
            rr        INTEGER NOT NULL DEFAULT 0,
            spo2      INTEGER NOT NULL DEFAULT 0,
            sdnn      INTEGER NOT NULL DEFAULT 0,
            rmssd     INTEGER NOT NULL DEFAULT 0,
            stress    INTEGER NOT NULL DEFAULT 0,
            sleep     INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // timestamp 기반 조회/정렬 성능을 위한 인덱스
        await db.execute(
          'CREATE INDEX idx_ble_data_timestamp ON ble_data(timestamp)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: sleep 컬럼 추가
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ble_data ADD COLUMN sleep INTEGER NOT NULL DEFAULT 0',
          );
        }
        // v2 → v3: timestamp 인덱스 추가
        if (oldVersion < 3) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_ble_data_timestamp ON ble_data(timestamp)',
          );
        }
        // v3 → v4: timestamp UNIQUE 제약 추가
        // SQLite는 ALTER TABLE로 UNIQUE 추가 불가 → 테이블 재생성
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE ble_data RENAME TO ble_data_old');
          await db.execute('''
            CREATE TABLE ble_data(
              id        INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT    NOT NULL UNIQUE,
              type      INTEGER NOT NULL DEFAULT 0,
              hr        INTEGER NOT NULL DEFAULT 0,
              rr        INTEGER NOT NULL DEFAULT 0,
              spo2      INTEGER NOT NULL DEFAULT 0,
              sdnn      INTEGER NOT NULL DEFAULT 0,
              rmssd     INTEGER NOT NULL DEFAULT 0,
              stress    INTEGER NOT NULL DEFAULT 0,
              sleep     INTEGER NOT NULL DEFAULT 0
            )
          ''');
          // 기존 데이터 이전 (중복 timestamp는 최신 id 기준으로 1개만 유지)
          await db.execute('''
            INSERT OR IGNORE INTO ble_data
              SELECT id, timestamp, type, hr, rr, spo2, sdnn, rmssd, stress, sleep
              FROM ble_data_old
              ORDER BY id ASC
          ''');
          await db.execute('DROP TABLE ble_data_old');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_ble_data_timestamp ON ble_data(timestamp)',
          );
        }
      },
    );
  }

  /// [data]를 DB에 삽입한다.
  ///
  /// 데이터 범위 검증을 수행하며, 같은 타임스탬프 레코드가 있으면 무시한다.
  Future<void> insertBleData(BleData data) async {
    if (!_isValidData(data)) {
      debugPrint('[DB] Invalid data skipped: $data');
      return;
    }
    final db = await database;
    await db.insert(
      'ble_data',
      data.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 간단한 데이터 범위 검증
  bool _isValidData(BleData data) {
    if (data.hr < 0 || data.hr > 300) return false;
    if (data.spo2 < 0 || data.spo2 > 100) return false;
    if (data.stress < 0 || data.stress > 100) return false;
    return true;
  }

  /// 최신 [limit]개의 레코드를 반환한다.
  Future<List<BleData>> getBleData({int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'ble_data',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return maps.map(BleData.fromMap).toList();
  }

  /// [days]일보다 오래된 레코드를 삭제한다.
  Future<void> clearOldData(int days) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    await db.delete(
      'ble_data',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}
