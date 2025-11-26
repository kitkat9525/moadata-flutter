import 'dart:typed_data';

class MAXM32664Report {
  final DateTime timestamp;
  final int led1;
  final int led4;
  final int led5;
  final int led6;
  final int accX;
  final int accY;
  final int accZ;
  final int hr;
  final int hrConfidence;
  final int rr;
  final int rrConfidence;
  final int activityClass;
  final int r;
  final int spo2Confidence;
  final int spo2;
  final int spo2Complete;
  final int spo2LowSignalQuality;
  final int spo2MotionFlag;
  final int spo2LowPiFlag;
  final int spo2UnreliableRFlag;
  final int spo2State;
  final int scdState;

  MAXM32664Report({
    required this.timestamp,
    required this.led1,
    required this.led4,
    required this.led5,
    required this.led6,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.hr,
    required this.hrConfidence,
    required this.rr,
    required this.rrConfidence,
    required this.activityClass,
    required this.r,
    required this.spo2Confidence,
    required this.spo2,
    required this.spo2Complete,
    required this.spo2LowSignalQuality,
    required this.spo2MotionFlag,
    required this.spo2LowPiFlag,
    required this.spo2UnreliableRFlag,
    required this.spo2State,
    required this.scdState,
  });

  factory MAXM32664Report.fromBytes(Uint8List data) {
    final byteData = ByteData.sublistView(data);

    int offset = 0;

    int year = byteData.getUint16(offset, Endian.little);
    offset += 2;
    int month = byteData.getUint8(offset++);
    int day = byteData.getUint8(offset++);
    int hour = byteData.getUint8(offset++);
    int minute = byteData.getUint8(offset++);
    int second = byteData.getUint8(offset++);

    final timestamp = DateTime(year, month, day, hour, minute, second);

    int led1 = byteData.getUint32(offset, Endian.little);
    offset += 4;
    offset += 4 * 2; // skip led2, led3
    int led4 = byteData.getUint32(offset, Endian.little);
    offset += 4;
    int led5 = byteData.getUint32(offset, Endian.little);
    offset += 4;
    int led6 = byteData.getUint32(offset, Endian.little);
    offset += 4;

    int accX = byteData.getInt16(offset, Endian.little);
    offset += 2;
    int accY = byteData.getInt16(offset, Endian.little);
    offset += 2;
    int accZ = byteData.getInt16(offset, Endian.little);
    offset += 2;

    int opMode = byteData.getUint8(offset++);
    int hr = byteData.getUint16(offset, Endian.little);
    offset += 2;
    int hrConfidence = byteData.getUint8(offset++);
    int rr = byteData.getUint16(offset, Endian.little);
    offset += 2;
    int rrConfidence = byteData.getUint8(offset++);
    int activityClass = byteData.getUint8(offset++);
    int r = byteData.getUint16(offset, Endian.little);
    offset += 2;
    int spo2Confidence = byteData.getUint8(offset++);
    int spo2 = byteData.getUint16(offset, Endian.little);
    offset += 2;
    int spo2Complete = byteData.getUint8(offset++);
    int spo2LowSignalQuality = byteData.getUint8(offset++);
    int spo2MotionFlag = byteData.getUint8(offset++);
    int spo2LowPiFlag = byteData.getUint8(offset++);
    int spo2UnreliableRFlag = byteData.getUint8(offset++);
    int spo2State = byteData.getUint8(offset++);
    int scdState = byteData.getUint8(offset++);

    return MAXM32664Report(
      timestamp: timestamp,
      led1: led1,
      led4: led4,
      led5: led5,
      led6: led6,
      accX: accX,
      accY: accY,
      accZ: accZ,
      hr: hr,
      hrConfidence: hrConfidence,
      rr: rr,
      rrConfidence: rrConfidence,
      activityClass: activityClass,
      r: r,
      spo2Confidence: spo2Confidence,
      spo2: spo2,
      spo2Complete: spo2Complete,
      spo2LowSignalQuality: spo2LowSignalQuality,
      spo2MotionFlag: spo2MotionFlag,
      spo2LowPiFlag: spo2LowPiFlag,
      spo2UnreliableRFlag: spo2UnreliableRFlag,
      spo2State: spo2State,
      scdState: scdState,
    );
  }
}
