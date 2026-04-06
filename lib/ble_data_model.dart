import 'dart:typed_data';

/// The type of BLE data being received.
enum BleDataType {
  minute,
  hour,
  day,
  unknown;

  /// Creates a [BleDataType] from an integer value.
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

/// Represents the data received from the BLE device.
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

  /// Factory constructor to create a [BleData] instance from a list of bytes.
  factory BleData.fromBytes(List<int> data) {
    final b = ByteData.sublistView(Uint8List.fromList(data));
    
    final year = b.getUint16(0, Endian.little);
    final month = b.getUint8(2);
    final day = b.getUint8(3);
    final hour = b.getUint8(4);
    final minute = b.getUint8(5);
    final second = b.getUint8(6);
    
    DateTime timestamp;
    try {
      // Validate components for DateTime constructor
      if (year < 1970 || month < 1 || month > 12 || day < 1 || day > 31 || 
          hour > 23 || minute > 59 || second > 59) {
        throw const FormatException('Invalid timestamp');
      }
      timestamp = DateTime(year, month, day, hour, minute, second);
    } catch (e) {
      timestamp = DateTime.now();
    }

    return BleData(
      timestamp: timestamp,
      type: BleDataType.fromInt(b.getUint8(7)),
      hr: b.getUint16(8, Endian.little),
      rr: b.getUint16(10, Endian.little),
      spo2: b.getUint16(12, Endian.little),
      sdnn: b.getUint16(14, Endian.little),
      rmssd: b.getUint16(16, Endian.little),
      stress: b.getUint8(18),
      sleep: BleSleepType.fromInt(data.length > 19 ? b.getUint8(19) : 0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type': type.toInt(),
      'hr': hr,
      'rr': rr,
      'spo2': spo2,
      'sdnn': sdnn,
      'rmssd': rmssd,
      'stress': stress,
      'sleep': sleep.toInt(),
    };
  }

  factory BleData.fromMap(Map<String, dynamic> map) {
    return BleData(
      timestamp: DateTime.parse(map['timestamp']),
      type: BleDataType.fromInt(map['type']),
      hr: map['hr'],
      rr: map['rr'],
      spo2: map['spo2'],
      sdnn: map['sdnn'],
      rmssd: map['rmssd'],
      stress: map['stress'],
      sleep: BleSleepType.fromInt(map['sleep'] ?? 0),
    );
  }

  @override
  String toString() {
    return 'BleData(timestamp: $timestamp, type: $type, hr: $hr, rr: $rr, spo2: $spo2, sdnn: $sdnn, rmssd: $rmssd, stress: $stress, sleep: $sleep)';
  }
}
