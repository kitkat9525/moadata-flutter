import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleConstants {
  // Service UUIDs
  static final timeService = Uuid.parse('00001805-0000-1000-8000-00805f9b34fb');
  static final afeService  = Uuid.parse('00001900-0000-1000-8000-00805f9b34fb');
  static final notiService = Uuid.parse('00001901-0000-1000-8000-00805f9b34fb');
  static final sysService  = Uuid.parse('00001902-0000-1000-8000-00805f9b34fb');

  // Characteristic UUIDs
  static final timeCharacteristic    = Uuid.parse('00002A2B-0000-1000-8000-00805f9b34fb');
  static final afeDataCharacteristic = Uuid.parse('0000190A-0000-1000-8000-00805f9b34fb');
  static final notiCharacteristic    = Uuid.parse('0000190B-0000-1000-8000-00805f9b34fb');
  // sys notify: sensor_t { uint32 battery; uint32 charge; uint32 temperature; uint32 step; uint32 activity; }
  static final sysCharacteristic     = Uuid.parse('0000190C-0000-1000-8000-00805f9b34fb');
}
