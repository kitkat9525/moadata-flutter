import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:nrf/maxm32664.dart';

class HomePage extends StatefulWidget {
  final DiscoveredDevice device;

  const HomePage({super.key, required this.device});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, QualifiedCharacteristic> _characteristics = {};
  final Map<String, StreamSubscription?> _subscriptions = {};
  late QualifiedCharacteristic characteristic;
  late StreamSubscription subscription;

  @override
  void initState() {
    super.initState();

    characteristic = QualifiedCharacteristic(
      characteristicId: Uuid.parse('0000190A-0000-1000-8000-00805f9b34fb'),
      serviceId: Uuid.parse('00001900-0000-1000-8000-00805f9b34fb'),
      deviceId: widget.device.id,
    );

    subscription = _ble.subscribeToCharacteristic(characteristic).listen((data) {
      final bytes = Uint8List.fromList(data);
      final report = MAXM32664Report.fromBytes(bytes);      
    });
  }

  @override
  void dispose() {
    super.dispose();
    subscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
      ),
    );
  }
}

class HeartWidget extends StatelessWidget {
  const HeartWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('❤️Heart Rate'),
                Text('00:00 AM'),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                DataWidget(text: 'HRM', data: '0', unit: 'BPM'),
                SizedBox(width: 25),
                DataWidget(text: 'SpO₂', data: '0', unit: '%'),
                SizedBox(width: 25),
                DataWidget(text: 'R-R', data: '0', unit: 'ms'),
                SizedBox(width: 25),
                DataWidget(text: 'HRV', data: '0', unit: 'ms'),
                SizedBox(width: 25),
                DataWidget(text: 'RMSSD', data: '0', unit: 'ms'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WalkWidget extends StatelessWidget {
  const WalkWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [],),
      ),
    );
  }
}

class DataWidget extends StatelessWidget {
  const DataWidget({
    super.key,
    required this.text,
    required this.data,
    required this.unit,
  });

  final String text;
  final String data;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        Row(
          children: [
            Text(data),
            Text(unit),
          ],
        ),
      ],
    );
  }
}