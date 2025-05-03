import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SensorScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const SensorScreen({super.key, required this.device});

  @override
  SensorScreenState createState() => SensorScreenState();
}

class SensorScreenState extends State<SensorScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, StreamSubscription?> _subscriptions = {};
  late final Map<String, QualifiedCharacteristic> _characteristics;

  int _x = 0;
  int _y = 0;
  int _z = 0;
  int _tap = 0;
  int _step = 0;
  String _activity = "Idle";
  int _fall = 0;

  Timer? _walkTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription?.cancel();
    }

    _walkTimer?.cancel();
    super.dispose();
  }

  void _init() async {
    _characteristics = {
      'x': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190D-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'y': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190E-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'z': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190F-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'tap': QualifiedCharacteristic(
        characteristicId: Uuid.parse('00001910-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'walk': QualifiedCharacteristic(
        characteristicId: Uuid.parse('00001911-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'fall': QualifiedCharacteristic(
        characteristicId: Uuid.parse('00001912-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001902-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
    };

    _subscriptions['x'] =
        _ble.subscribeToCharacteristic(_characteristics['x']!).listen(
              (data) => setState(() => _x =
                  ByteData.sublistView(Uint8List.fromList(data))
                      .getInt16(0, Endian.little)),
              onError: (e) => debugPrint('$e'),
            );

    _subscriptions['y'] =
        _ble.subscribeToCharacteristic(_characteristics['y']!).listen(
              (data) => setState(() => _y =
                  ByteData.sublistView(Uint8List.fromList(data))
                      .getInt16(0, Endian.little)),
              onError: (e) => debugPrint('$e'),
            );

    _subscriptions['z'] =
        _ble.subscribeToCharacteristic(_characteristics['z']!).listen(
              (data) => setState(() => _z =
                  ByteData.sublistView(Uint8List.fromList(data))
                      .getInt16(0, Endian.little)),
              onError: (e) => debugPrint('$e'),
            );

    _subscriptions['tap'] =
        _ble.subscribeToCharacteristic(_characteristics['tap']!).listen(
              (data) => setState(() => _tap = _tap + 1),
              onError: (e) => debugPrint('$e'),
            );

    _subscriptions['fall'] =
        _ble.subscribeToCharacteristic(_characteristics['fall']!).listen(
              (data) => setState(() => _fall = _fall + 1),
              onError: (e) => debugPrint('$e'),
            );

    _walkTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final data = await _ble.readCharacteristic(_characteristics['walk']!);
        if (data.length == 4) {
          final stepCount = (data[0]) | (data[1] << 8) | (data[2] << 16);
          final activityByte = data[3];
          String activity;

          switch (activityByte) {
            case 0x00:
              activity = "Idle";
              break;
            case 0x01:
              activity = "Walking";
              break;
            case 0x02:
              activity = "Running";
              break;
            default:
              activity = "Unknown";
          }

          setState(() {
            _step = stepCount;
            _activity = activity;
          });
        }
      } catch (e) {
        debugPrint('Walk read error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor'),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          // ListTile(
          //   leading: const Icon(FontAwesomeIcons.microchip,
          //       color: Colors.black, size: 20),
          //   title: const Text('X axis (only AFE Mode)',
          //       style: TextStyle(fontSize: 14)),
          //   trailing: Text(
          //     '$_x',
          //     style: const TextStyle(
          //         fontSize: 14,
          //         color: Colors.black,
          //         fontWeight: FontWeight.bold),
          //   ),
          // ),
          // const Padding(
          //   padding: EdgeInsets.symmetric(horizontal: 16.0),
          //   child: Divider(),
          // ),
          // ListTile(
          //   leading: const Icon(FontAwesomeIcons.microchip,
          //       color: Colors.black, size: 20),
          //   title: const Text('Y axis (only AFE Mode)',
          //       style: TextStyle(fontSize: 14)),
          //   trailing: Text(
          //     '$_y',
          //     style: const TextStyle(
          //         fontSize: 14,
          //         color: Colors.black,
          //         fontWeight: FontWeight.bold),
          //   ),
          // ),
          // const Padding(
          //   padding: EdgeInsets.symmetric(horizontal: 16.0),
          //   child: Divider(),
          // ),
          // ListTile(
          //   leading: const Icon(FontAwesomeIcons.microchip,
          //       color: Colors.black, size: 20),
          //   title: const Text('Z axis (only AFE Mode)',
          //       style: TextStyle(fontSize: 14)),
          //   trailing: Text(
          //     '$_z',
          //     style: const TextStyle(
          //         fontSize: 14,
          //         color: Colors.black,
          //         fontWeight: FontWeight.bold),
          //   ),
          // ),
          // const Padding(
          //   padding: EdgeInsets.symmetric(horizontal: 16.0),
          //   child: Divider(),
          // ),
          ListTile(
            leading: const Icon(Icons.touch_app, color: Colors.black, size: 20),
            title: const Text('Double Tap', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '$_tap',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading:
                const Icon(Icons.directions_run, color: Colors.black, size: 20),
            title: const Text('Activity', style: TextStyle(fontSize: 14)),
            trailing: Text(
              _activity,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(FontAwesomeIcons.shoePrints,
                color: Colors.black, size: 18),
            title: const Text('Step', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '$_step',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.warning, color: Colors.orange, size: 20),
            title: const Text('Freefall Alarm', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '$_fall',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.thermostat, color: Colors.red, size: 20),
            title: const Text('Temperature', style: TextStyle(fontSize: 14)),
            trailing: const Text(
              '-',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading:
                const Icon(Icons.battery_full, color: Colors.black, size: 20),
            title: const Text('Battery', style: TextStyle(fontSize: 14)),
            trailing: const Text(
              '-',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
