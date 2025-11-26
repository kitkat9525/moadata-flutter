import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class DataPage extends StatefulWidget {
  final DiscoveredDevice device;

  const DataPage({super.key, required this.device});

  @override
  State<DataPage> createState() => DataPageState();
}

class DataPageState extends State<DataPage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, QualifiedCharacteristic> _characteristics = {};
  final Map<String, StreamSubscription?> _subscriptions = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data'),
      ),
    );
  }
}
