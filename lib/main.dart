import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nrf/afe.dart';
import 'package:nrf/sensor.dart';
import 'package:nrf/data.dart';
import 'package:nrf/setting.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
    [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
  );

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
        home: const IntroScreen(),
      );
}

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  IntroScreenState createState() => IntroScreenState();
}

class IntroScreenState extends State<IntroScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<DiscoveredDevice> _devicesList = [];

  late StreamSubscription<DiscoveredDevice> _scanSubscription;

  Timer? _timer;
  int _dot = 0;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _waitAndStart();
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _dot = (_dot % 3) + 1),
    );
  }

  Future<void> _waitAndStart() async {
    await _requestPermissions();

    // 🔧 플랫폼 초기화를 기다리기 위해 약간 딜레이
    await Future.delayed(const Duration(milliseconds: 500));
    _find();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await Future.wait([
      Permission.bluetooth.request(),
      Permission.bluetoothScan.request(),
      Permission.bluetoothConnect.request(),
      Permission.location.request(),
      Permission.storage.request(),
    ]);
  }

  void _find() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _devicesList.clear();
    });

     _scanSubscription = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) {
        final index = _devicesList.indexWhere((d) => d.id == device.id);
        debugPrint('bluetooth le device find: ${device.name}');
        setState(() {
          if (index >= 0) {
            _devicesList[index] = device;
          } else {
            _devicesList.add(device);
          }

          if (device.name == 'nRF54L15') {
            _connect(device);
          }
        });
      },
      onError: (e) {
        debugPrint('bluetooth le device find error: $e');
        setState(() => _isScanning = false);
      },
    );

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _connect(DiscoveredDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _isConnected = false;
    });

    try {
      await _scanSubscription.cancel();
      await Future.delayed(const Duration(milliseconds: 300));

      _ble
          .connectToDevice(
        id: device.id,
        connectionTimeout: const Duration(seconds: 30),
      )
          .listen(
        (data) {
          if (data.connectionState == DeviceConnectionState.connected) {
            debugPrint('bluetooth le connected.');
            setState(() {
              _isConnecting = false;
              _isConnected = true;
            });

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(device: device),
              ),
            );
          }
        },
        onError: (e) => debugPrint('$e'),
      );
    } catch (e) {
      debugPrint('bluetooth le device connection error: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset('assets/logo.svg', width: 50, height: 50),
            const SizedBox(height: 16),
            Text(
              'connect ring${'.' * _dot}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const HomeScreen({super.key, required this.device});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final List<Widget> _screens = [
    AFEScreen(device: widget.device),
    SensorScreen(device: widget.device),
    // DataScreen(device: widget.device),
    SettingScreen(device: widget.device),
  ];

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final DeviceConnectionState _deviceState = DeviceConnectionState.disconnected;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse('00001805-0000-1000-8000-00805f9b34fb'),
        characteristicId: Uuid.parse('00002A2B-0000-1000-8000-00805f9b34fb'),
        deviceId: widget.device.id,
      );

      if (Platform.isAndroid) {
        final mtu = await _ble.requestMtu(deviceId: widget.device.id, mtu: 247);
        debugPrint('📏 Negotiated MTU size: $mtu');
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

      await _ble.writeCharacteristicWithoutResponse(
        characteristic,
        value: bytes,
      );

      debugPrint('Time set successfully: ${now.toString()}');
    } catch (e) {
      debugPrint('Error setting time: $e');
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
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF00A9CE),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'AFE',
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.microchip),
            label: 'Sensor',
          ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.timeline),
          //   label: 'Data',
          // ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
