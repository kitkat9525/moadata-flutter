import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:nrf/ble_constants.dart';
import 'package:nrf/ble_data_model.dart';
import 'package:nrf/notification_service.dart';
import 'package:nrf/database_helper.dart';
import 'package:nrf/ui_components.dart';
import 'package:nrf/ui_constants.dart';

class AFEScreen extends StatefulWidget {
  final DiscoveredDevice? device;

  const AFEScreen({super.key, required this.device});

  @override
  AFEScreenState createState() => AFEScreenState();
}

class AFEScreenState extends State<AFEScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<StreamSubscription?> _subscriptions = [];
  String? _subscribedDeviceId;

  late final QualifiedCharacteristic _dataChar;
  late final QualifiedCharacteristic _pamsChar;
  late final QualifiedCharacteristic _tempChar;
  late final QualifiedCharacteristic _batteryChar;
  late final QualifiedCharacteristic _notiChar;

  // AFE
  BleData? _latestData;

  // Sensor
  int _step = 0;
  String _activity = '-';
  double? _temperature;
  int? _battery;
  int _singleTapCount = 0;
  int _doubleTapCount = 0;
  int _freeFallCount = 0;

  @override
  void initState() {
    super.initState();
    _syncSubscriptions();
  }

  @override
  void didUpdateWidget(covariant AFEScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device?.id != widget.device?.id) {
      _syncSubscriptions();
    }
  }

  @override
  void dispose() {
    _disposeSubscriptions();
    super.dispose();
  }

  void _syncSubscriptions() {
    final device = widget.device;
    if (device == null) {
      _disposeSubscriptions(resetValues: true);
      return;
    }
    if (_subscribedDeviceId == device.id) return;

    _disposeSubscriptions(resetValues: false);
    _init();
    _subscribedDeviceId = device.id;
  }

  void _disposeSubscriptions({bool resetValues = false}) {
    for (final sub in _subscriptions) {
      sub?.cancel();
    }
    _subscriptions.clear();
    _subscribedDeviceId = null;

    if (resetValues && mounted) {
      setState(() {
        _latestData = null;
        _step = 0;
        _activity = '-';
        _temperature = null;
        _battery = null;
        _singleTapCount = 0;
        _doubleTapCount = 0;
        _freeFallCount = 0;
      });
    }
  }

  void _init() {
    _dataChar    = _buildChar(BleConstants.afeService,         BleConstants.afeDataCharacteristic);
    _pamsChar    = _buildChar(BleConstants.pamsService,        BleConstants.pamsDataCharacteristic);
    _batteryChar = _buildChar(BleConstants.batteryService,     BleConstants.batteryLevelCharacteristic);
    _tempChar    = _buildChar(BleConstants.temperatureService, BleConstants.temperatureCharacteristic);
    _notiChar    = _buildChar(BleConstants.notiService,        BleConstants.notiCharacteristic);

    _subscribe(_dataChar,    _onDataReceived,    'data_t');
    _subscribe(_pamsChar,    _onPamsReceived,    'PAMS');
    _subscribe(_tempChar,    _onTempReceived,    'HTS');
    _subscribe(_notiChar,    _onNotiReceived,    'NOTI');
    _subscribeBattery();
  }

  QualifiedCharacteristic _buildChar(Uuid serviceId, Uuid charId) =>
      QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: charId,
        deviceId: widget.device!.id,
      );

  void _subscribe(QualifiedCharacteristic char, void Function(List<int>) onData, String name) {
    debugPrint('Subscribing to $name...');
    final sub = _ble.subscribeToCharacteristic(char).listen(
      onData,
      onError: (e) => debugPrint('$name subscribe error: $e'),
      onDone: () => debugPrint('$name stream closed'),
    );
    _subscriptions.add(sub);
  }

  void _subscribeBattery() {
    final sub = _ble.subscribeToCharacteristic(_batteryChar).listen(
      _onBatteryReceived,
      onError: (_) async {
        try {
          final data = await _ble.readCharacteristic(_batteryChar);
          _onBatteryReceived(data);
        } catch (_) {}
      },
    );
    _subscriptions.add(sub);
  }

  void _onDataReceived(List<int> data) {
    if (data.length < 19) return;
    try {
      final bleData = BleData.fromBytes(data);
      setState(() => _latestData = bleData);
      DatabaseHelper().insertBleData(bleData);
    } catch (e) {
      debugPrint('data_t parse error: $e');
    }
  }

  void _onPamsReceived(List<int> data) {
    if (data.length < 8) return;
    final step = data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);
    String? activity;
    if (data.length >= 9) {
      activity = switch (data[8]) {
        0x00 => 'Still',
        0x01 => 'Walk',
        0x02 => 'Run',
        _ => 'Unknown',
      };
    }
    setState(() {
      _step = step;
      if (activity != null) _activity = activity;
    });
  }

  void _onBatteryReceived(List<int> data) {
    if (data.isEmpty) return;
    setState(() => _battery = data[0].clamp(0, 100));
  }

  void _onNotiReceived(List<int> data) {
    debugPrint('BLE Notification: $data');
    if (data.isEmpty) return;
    final type = data[0];
    switch (type) {
      case 0x00: 
        debugPrint('Free Fall triggered');
        setState(() => _freeFallCount++);
        _handleFreeFall(); 
        break;
      case 0x02:
        debugPrint('Sleep start triggered');
        NotificationService.showSleepStartAlert();
        _showToast('수면 시작이 감지되었습니다');
        break;
      case 0x04: 
        debugPrint('Single Tap triggered');
        setState(() => _singleTapCount++); 
        break;
      case 0x08: 
        debugPrint('Double Tap triggered');
        setState(() => _doubleTapCount++); 
        break;
      default:
        debugPrint('Unknown notification: $type');
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleFreeFall() {
    NotificationService.showFreeFallAlert();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: const Text('Free Fall Detected'),
        content: Text('낙상이 감지되었습니다.\n총 $_freeFallCount 회 발생'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _onTempReceived(List<int> data) {
    if (data.length < 5) return;
    final b = ByteData.sublistView(Uint8List.fromList(data));
    setState(() => _temperature = b.getFloat32(1, Endian.little));
  }

  // ── UI Helpers ────────────────────────────────────────────────────────────

  Widget _buildSection(String title, List<Widget> items) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: title,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          ),
          ...items,
        ],
      ),
    );
  }

  Widget _buildItem(String title, String subtitle, String value, String unit, {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: kScreenTopPadding, bottom: 24.0),
          children: [
            if (_latestData != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Last Sync: ${_latestData!.timestamp.toString().split('.').first}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            _buildSection('바이탈', [
              _buildItem('Heart Rate', '심박수', '${_latestData?.hr ?? '--'}', 'bpm'),
              _buildItem('SpO2', '혈중 산소포화도', '${_latestData?.spo2 ?? '--'}', '%'),
              _buildItem('RR Interval', '평균 RR 간격', '${_latestData?.rr ?? '--'}', 'ms', isLast: true),
            ]),
            _buildSection('HRV 분석', [
              _buildItem('SDNN', '자율신경 균형', '${_latestData?.sdnn ?? '--'}', 'ms'),
              _buildItem('RMSSD', '부교감 활성도', '${_latestData?.rmssd ?? '--'}', 'ms', isLast: true),
            ]),
            _buildSection('스트레스 및 활동', [
              _buildItem('Stress', '스트레스 지수', '${_latestData?.stress ?? '--'}', ''),
              _buildItem('Activity', '활동 상태', _activity, ''),
              _buildItem('Step Count', '걸음 수', '$_step', 'steps', isLast: true),
            ]),
            _buildSection('제스처 및 센서', [
              _buildItem('Free Fall', '낙상 발생 횟수', '$_freeFallCount', 'times'),
              _buildItem('Single Tap', '싱글 탭 횟수', '$_singleTapCount', 'times'),
              _buildItem('Double Tap', '더블 탭 횟수', '$_doubleTapCount', 'times'),
              _buildItem('Temperature', '체온', _temperature != null ? _temperature!.toStringAsFixed(1) : '--', '°C'),
              _buildItem('Battery', '배터리 잔량', _battery != null ? '$_battery' : '--', '%', isLast: true),
            ]),
          ],
        ),
      ),
    );
  }
}
