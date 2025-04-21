import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class AFEScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const AFEScreen({super.key, required this.device});

  @override
  AFEScreenState createState() => AFEScreenState();
}

class AFEScreenState extends State<AFEScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, StreamSubscription?> _subscriptions = {};
  late final Map<String, QualifiedCharacteristic> _characteristics;

  int _hrm = 0;
  int _spo2 = 0;

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
    super.dispose();
  }

  void _init() async {
    _characteristics = {
      'hrm': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190B-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001901-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
      'spo2': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190C-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001901-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
    };

    _subscriptions['hrm'] =
        _ble.subscribeToCharacteristic(_characteristics['hrm']!).listen(
              (data) => setState(() => _hrm = data[0]),
              onError: (e) => debugPrint('$e'),
            );

    _subscriptions['spo2'] =
        _ble.subscribeToCharacteristic(_characteristics['spo2']!).listen(
              (data) => setState(() => _spo2 = data[0]),
              onError: (e) => debugPrint('$e'),
            );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AFE'),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.red, size: 20),
            title: const Text('HRM', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '$_hrm bpm',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(),
          ),
          ListTile(
            leading: const Icon(Icons.opacity, color: Colors.red, size: 20),
            title: const Text('SpO₂', style: TextStyle(fontSize: 14)),
            trailing: Text(
              '$_spo2%',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
