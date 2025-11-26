import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nrf/home.dart';
import 'package:nrf/data.dart';
import 'package:nrf/setting.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        splashFactory: NoSplash.splashFactory,
      ),
      home: const IntroPage(),
    );
  }
}

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<StatefulWidget> createState() => IntroPageState();
}

class IntroPageState extends State<IntroPage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final List<DiscoveredDevice> _list = [];

  late StreamSubscription<DiscoveredDevice> _subscription;
  late Timer _timer;

  int _dot = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissions();
      await _find();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _dot = (_dot % 4) + 1;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _subscription.cancel();
    _timer.cancel();
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

  Future<void> _find() async {
    _subscription = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      setState(() {});

      if (device.name == 'nRF54L15') {
        _connect(device);
      }
    });
  }

  Future<void> _connect(DiscoveredDevice device) async {
    await _subscription.cancel();

    _ble.connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 30),
    ).listen((data) {
      if (data.connectionState == DeviceConnectionState.connected) {
        if (!mounted) {
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => MainPage(device: device)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 195,
              height: 195,
              fit: BoxFit.contain,
            ),
            Text('connect'),
            Text('.' * _dot),
          ],
        ),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  final DiscoveredDevice device;

  const MainPage({super.key, required this.device});

  @override
  State<StatefulWidget> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  late final List<Widget> _children = [
    HomePage(device: widget.device),
    DataPage(device: widget.device),
    SettingPage(device: widget.device),
  ];

  int _selectedIndex = 0;

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
      body: IndexedStack(
        index: _selectedIndex,
        children: _children,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: const Color(0xFF00A9CE),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Data',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}