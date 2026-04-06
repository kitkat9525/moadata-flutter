import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nrf/afe.dart';
import 'package:nrf/data.dart';
import 'package:nrf/database.dart';
import 'package:nrf/setting.dart';
import 'package:nrf/ble_constants.dart';
import 'package:nrf/notification_service.dart';
import 'package:nrf/ui_constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
    [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
  );
  await NotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'nRF54L15',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          splashFactory: NoSplash.splashFactory,
        ),
        home: const HomeScreen(),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _targetDeviceName = 'nRF54L15';

  final GlobalKey<DataScreenState> _dataKey = GlobalKey<DataScreenState>();
  final GlobalKey<DatabaseScreenState> _dbKey = GlobalKey<DatabaseScreenState>();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  int _selectedIndex = 0;
  bool _isScanning = false;
  bool _isConnecting = false;
  DiscoveredDevice? _device;

  List<Widget> get _screens {
    return [
      AFEScreen(device: _device),
      DataScreen(key: _dataKey, device: _device),
      DatabaseScreen(key: _dbKey, device: _device),
      SettingScreen(device: _device, onSyncTime: _syncTime),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 1) { // Index for "분석" (DataScreen)
      _dataKey.currentState?.loadData();
    } else if (index == 2) { // Index for "데이터베이스" (DatabaseScreen)
      _dbKey.currentState?.refreshData();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startConnectionFlow());
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startConnectionFlow() async {
    try {
      await _requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      _scanAndConnect();
    } catch (e) {
      debugPrint('Permission/setup error: $e');
      _showConnectionToast('블루투스 권한이 필요합니다');
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  void _scanAndConnect() {
    if (_isScanning || _isConnecting) return;

    setState(() => _isScanning = true);
    _showConnectionToast('ring 검색 중');
    _scanSubscription?.cancel();
    _scanSubscription = _ble
        .scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    )
        .listen(
      (device) {
        if (device.name == _targetDeviceName) {
          _connect(device);
        }
      },
      onError: (e) {
        debugPrint('Scan error: $e');
        if (mounted) {
          setState(() => _isScanning = false);
        }
        _showConnectionToast('블루투스 스캔에 실패했습니다');
      },
    );
  }

  Future<void> _connect(DiscoveredDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _isScanning = false;
    });
    _showConnectionToast('ring 연결 중');

    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _connectionSubscription?.cancel();

    _connectionSubscription = _ble
        .connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 30),
    )
        .listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connecting:
            debugPrint('Bluetooth connecting...');
            break;
          case DeviceConnectionState.connected:
            debugPrint('Bluetooth connected.');
            final isFirstConnection = _device == null;
            setState(() {
              _device = device;
              _isConnecting = false;
            });
            _showConnectionToast(isFirstConnection ? '블루투스가 연결되었습니다' : '블루투스가 재연결되었습니다');
            _syncTime();
            break;
          case DeviceConnectionState.disconnected:
            debugPrint('Bluetooth disconnected.');
            _handleDisconnected();
            break;
          case DeviceConnectionState.disconnecting:
            debugPrint('Bluetooth disconnecting...');
            break;
        }
      },
      onError: (e) {
        debugPrint('Connection error: $e');
        _handleDisconnected(showToast: _device == null);
      },
    );
  }

  void _handleDisconnected({bool showToast = true}) {
    final hadDevice = _device != null;
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _isScanning = false;
        _device = null;
      });
    }
    if (showToast && hadDevice) {
      _showConnectionToast('블루투스 연결이 끊어졌습니다');
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _device == null && !_isScanning && !_isConnecting) {
        _scanAndConnect();
      }
    });
  }

  void _showConnectionToast(String message) {
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

  Future<void> _syncTime() async {
    final device = _device;
    if (device == null) return;

    // Wait a bit to ensure the connection is stable and services are discovered
    await Future.delayed(const Duration(milliseconds: 1000));
    
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final characteristic = QualifiedCharacteristic(
          serviceId: BleConstants.timeService,
          characteristicId: BleConstants.timeCharacteristic,
          deviceId: device.id,
        );

        if (Platform.isAndroid && retryCount == 0) {
          try {
            await _ble.requestMtu(deviceId: device.id, mtu: 247).timeout(const Duration(seconds: 2));
          } catch (e) {
            debugPrint('MTU request failed: $e');
          }
        }

        final now = DateTime.now();
        final List<int> bytes = [
          now.year & 0xFF,
          (now.year >> 8) & 0xFF,
          now.month,
          now.day,
          now.hour,
          now.minute,
          now.second,
          now.weekday,
          (now.millisecond * 256) ~/ 1000,
          1,
        ];

        await _ble.writeCharacteristicWithResponse(characteristic, value: bytes);
        debugPrint('Time synced: $now (Attempt ${retryCount + 1})');
        return; // Success
      } catch (e) {
        retryCount++;
        debugPrint('Error syncing time (Attempt $retryCount): $e');
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: kAccentColor,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '헬스'),
          BottomNavigationBarItem(icon: Icon(Icons.timeline), label: '분석'),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: '데이터베이스'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
