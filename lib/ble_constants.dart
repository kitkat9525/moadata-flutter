import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleConstants {
  // Service UUIDs
  static final timeService = Uuid.parse('00001805-0000-1000-8000-00805f9b34fb');
  static final afeService = Uuid.parse('00001900-0000-1000-8000-00805f9b34fb');
  static final sysService = Uuid.parse('00001902-0000-1000-8000-00805f9b34fb');
  static final pamsService = Uuid.parse('0000183E-0000-1000-8000-00805f9b34fb');
  static final batteryService = Uuid.parse('0000180F-0000-1000-8000-00805f9b34fb');
  static final temperatureService = Uuid.parse('00001809-0000-1000-8000-00805f9b34fb');

  // Characteristic UUIDs
  static final timeCharacteristic = Uuid.parse('00002A2B-0000-1000-8000-00805f9b34fb');
  static final afeDataCharacteristic = Uuid.parse('0000190A-0000-1000-8000-00805f9b34fb');
  static final sysCharacteristic = Uuid.parse('0000190C-0000-1000-8000-00805f9b34fb');
  static final pamsDataCharacteristic = Uuid.parse('00001814-0000-1000-8000-00805f9b34fb');
  static final batteryLevelCharacteristic = Uuid.parse('00002A19-0000-1000-8000-00805f9b34fb');
  static final temperatureCharacteristic = Uuid.parse('00002A1C-0000-1000-8000-00805f9b34fb');

  // Notification Service: 0x1901 / 0x190B — free fall alert
  static final notiService = Uuid.parse('00001901-0000-1000-8000-00805f9b34fb');
  static final notiCharacteristic = Uuid.parse('0000190B-0000-1000-8000-00805f9b34fb');
}
