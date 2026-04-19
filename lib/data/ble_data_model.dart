import 'dart:typed_data';

/// BLE 데이터 타입
enum BleDataType {
  minute,
  hour,
  day,
  unknown;

  static BleDataType fromInt(int value) {
    return switch (value) {
      0 => BleDataType.minute,
      1 => BleDataType.hour,
      2 => BleDataType.day,
      _ => BleDataType.unknown,
    };
  }

  int toInt() {
    return switch (this) {
      BleDataType.minute => 0,
      BleDataType.hour => 1,
      BleDataType.day => 2,
      BleDataType.unknown => 3,
    };
  }
}

/// 수면 단계 타입
enum BleSleepType {
  none,
  awake,
  light,
  deep,
  rem,
  unknown;

  static BleSleepType fromInt(int value) {
    return switch (value) {
      0 => BleSleepType.none,
      1 => BleSleepType.awake,
      2 => BleSleepType.light,
      3 => BleSleepType.deep,
      4 => BleSleepType.rem,
      _ => BleSleepType.unknown,
    };
  }

  int toInt() {
    return switch (this) {
      BleSleepType.none => 0,
      BleSleepType.awake => 1,
      BleSleepType.light => 2,
      BleSleepType.deep => 3,
      BleSleepType.rem => 4,
      BleSleepType.unknown => 255,
    };
  }
}

/// BLE 기기에서 수신된 바이탈 데이터
class BleData {
  final DateTime timestamp;
  final BleDataType type;
  final int hr;
  final int rr;
  final int spo2;
  final int sdnn;
  final int rmssd;
  final int stress;
  final BleSleepType sleep;

  BleData({
    required this.timestamp,
    required this.type,
    required this.hr,
    required this.rr,
    required this.spo2,
    required this.sdnn,
    required this.rmssd,
    required this.stress,
    required this.sleep,
  });

  /// BLE 바이트 배열에서 [BleData] 인스턴스를 생성한다.
  factory BleData.fromBytes(List<int> data) {
    final b = ByteData.sublistView(Uint8List.fromList(data));

    final year   = b.getUint16(0, Endian.little);
    final month  = b.getUint8(2);
    final day    = b.getUint8(3);
    final hour   = b.getUint8(4);
    final minute = b.getUint8(5);
    final second = b.getUint8(6);

    final timestamp = _parseTimestamp(year, month, day, hour, minute, second)
        ?? DateTime.now();

    return BleData(
      timestamp: timestamp,
      type:   BleDataType.fromInt(b.getUint8(7)),
      hr:     b.getUint16(8,  Endian.little),
      rr:     b.getUint16(10, Endian.little),
      spo2:   b.getUint16(12, Endian.little),
      sdnn:   b.getUint16(14, Endian.little),
      rmssd:  b.getUint16(16, Endian.little),
      stress: b.getUint8(18),
      sleep:  BleSleepType.fromInt(data.length > 19 ? b.getUint8(19) : 0),
    );
  }

  /// 타임스탬프 값 유효성 검사 후 [DateTime]을 반환한다.
  ///
  /// 잘못된 값이면 null을 반환한다.
  static DateTime? _parseTimestamp(
    int year, int month, int day, int hour, int minute, int second,
  ) {
    try {
      if (year < 1970 || year > 2100) return null;
      if (month < 1 || month > 12) return null;
      if (day < 1) return null;
      if (hour > 23 || minute > 59 || second > 59) return null;

      final dt = DateTime(year, month, day, hour, minute, second);
      // DateTime은 잘못된 날짜(예: 2월 30일)를 자동 보정하므로 역검증이 필요하다
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type':      type.toInt(),
      'hr':        hr,
      'rr':        rr,
      'spo2':      spo2,
      'sdnn':      sdnn,
      'rmssd':     rmssd,
      'stress':    stress,
      'sleep':     sleep.toInt(),
    };
  }

  /// DB 맵에서 [BleData]를 생성한다. null 필드는 기본값(0)으로 처리한다.
  factory BleData.fromMap(Map<String, dynamic> map) {
    DateTime timestamp;
    try {
      timestamp = DateTime.parse(map['timestamp'] as String);
    } catch (_) {
      timestamp = DateTime.now();
    }

    return BleData(
      timestamp: timestamp,
      type:   BleDataType.fromInt((map['type']   as int?) ?? 0),
      hr:     (map['hr']     as int?) ?? 0,
      rr:     (map['rr']     as int?) ?? 0,
      spo2:   (map['spo2']   as int?) ?? 0,
      sdnn:   (map['sdnn']   as int?) ?? 0,
      rmssd:  (map['rmssd']  as int?) ?? 0,
      stress: (map['stress'] as int?) ?? 0,
      sleep:  BleSleepType.fromInt((map['sleep'] as int?) ?? 0),
    );
  }

  @override
  String toString() =>
      'BleData(timestamp: $timestamp, type: $type, hr: $hr, rr: $rr, '
      'spo2: $spo2, sdnn: $sdnn, rmssd: $rmssd, stress: $stress, sleep: $sleep)';
}
