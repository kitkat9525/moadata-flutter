import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:fl_chart/fl_chart.dart';

class DataScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DataScreen({super.key, required this.device});

  @override
  DataScreenState createState() => DataScreenState();
}

class DataScreenState extends State<DataScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, StreamSubscription?> _subscriptions = {};
  late final Map<String, QualifiedCharacteristic> _characteristics;

  int _dataIndex = 0;

  // LED 센서 데이터
  final List<FlSpot> _led1 = [];
  final List<FlSpot> _led2 = [];
  final List<FlSpot> _led3 = [];
  final List<FlSpot> _led4 = [];
  final List<FlSpot> _led5 = [];
  final List<FlSpot> _led6 = [];

  // 가속도 센서 데이터
  final List<FlSpot> _accelX = [];
  final List<FlSpot> _accelY = [];
  final List<FlSpot> _accelZ = [];

  static const int _maxDataPoints = 100;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub?.cancel();
    }
    super.dispose();
  }

  void _init() {
    _characteristics = {
      'data': QualifiedCharacteristic(
        characteristicId: Uuid.parse('0000190A-0000-1000-8000-00805f9b34fb'),
        serviceId: Uuid.parse('00001900-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      ),
    };

    _subscriptions['data'] = _ble
        .subscribeToCharacteristic(_characteristics['data']!)
        .listen(_onDataReceived, onError: (e) => debugPrint('Error: $e'));
  }

  void _onDataReceived(List<int> data) {
    final hexDump =
        data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('Received (${data.length} bytes): [$hexDump]');

    if (data.length < 37) {
      debugPrint('⚠️ Insufficient data length. Skipping frame.');
      return;
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(data));

    final leds = List.generate(
      6,
      (i) => byteData.getUint32(7 + i * 4, Endian.little).toDouble(),
    );

    final accel = [
      byteData.getInt16(31, Endian.little).toDouble(),
      byteData.getInt16(33, Endian.little).toDouble(),
      byteData.getInt16(35, Endian.little).toDouble(),
    ];

    setState(() {
      _led1.add(FlSpot(_dataIndex.toDouble(), leds[0]));
      _led2.add(FlSpot(_dataIndex.toDouble(), leds[1]));
      _led3.add(FlSpot(_dataIndex.toDouble(), leds[2]));
      _led4.add(FlSpot(_dataIndex.toDouble(), leds[3]));
      _led5.add(FlSpot(_dataIndex.toDouble(), leds[4]));
      _led6.add(FlSpot(_dataIndex.toDouble(), leds[5]));

      _accelX.add(FlSpot(_dataIndex.toDouble(), accel[0]));
      _accelY.add(FlSpot(_dataIndex.toDouble(), accel[1]));
      _accelZ.add(FlSpot(_dataIndex.toDouble(), accel[2]));

      _dataIndex++;

      for (final list in [
        _led1,
        _led2,
        _led3,
        _led4,
        _led5,
        _led6,
        _accelX,
        _accelY,
        _accelZ
      ]) {
        if (list.length > _maxDataPoints) list.removeAt(0);
      }
    });
  }

  LineChartBarData _buildLine(List<FlSpot> spots, {Color? color}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
      color: color,
      barWidth: 2,
    );
  }

  LineChart _buildChart(List<List<FlSpot>> lines, List<Color> colors) {
    return LineChart(
      LineChartData(
        lineBarsData: List.generate(
          lines.length,
          (i) => _buildLine(lines[i], color: colors[i]),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.right,
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw Data'),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: 198,
                child: _buildChart(
                  [_led1, _led2, _led3],
                  [Colors.green, Colors.black, Colors.red],
                ),
              ),
              const SizedBox(height: 8),
              const Text('PPG', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 48),
              SizedBox(
                height: 198,
                child: _buildChart(
                  [_accelX, _accelY, _accelZ],
                  [Colors.blue, Colors.orange, Colors.purple],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Accelerometer', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
