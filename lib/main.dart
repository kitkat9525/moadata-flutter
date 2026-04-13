import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  // SharedPreferences에서 마지막 연결된 기기 ID 가져오기
  final prefs = await SharedPreferences.getInstance();
  final lastDeviceId = prefs.getString('last_device_id');
  
  runApp(MyApp(lastDeviceId: lastDeviceId));
}

class MyApp extends StatelessWidget {
  final String? lastDeviceId;
  
  const MyApp({super.key, this.lastDeviceId});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FLOFIT',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          splashFactory: NoSplash.splashFactory,
        ),
        // 마지막 연결 기기가 있으면 바로 홈 화면으로, 없으면 인트로 화면으로 이동
        home: lastDeviceId != null 
          ? const HomeScreen() 
          : const IntroScreen(),
      );
}

// ─── Intro Screen ────────────────────────────────────────────────────────────

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _onSearchPressed(BuildContext context) async {
    await _requestPermissions();
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceListSheet(
        onDeviceConnected: (device) {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomeScreen(selectedDevice: device),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // 중앙 로고 영역
            const Center(
              child: Text(
                'FLOFIT',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111111),
                  letterSpacing: 4.0, // 로고 느낌을 위한 넓은 자간
                ),
              ),
            ),
            const Spacer(),
            // 하단 버튼 영역
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _onSearchPressed(context),
                  child: const Text(
                    '검색 시작하기',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Device List Bottom Sheet ─────────────────────────────────────────────────

class _DeviceListSheet extends StatefulWidget {
  final void Function(DiscoveredDevice) onDeviceConnected;

  const _DeviceListSheet({required this.onDeviceConnected});

  @override
  State<_DeviceListSheet> createState() => _DeviceListSheetState();
}

class _DeviceListSheetState extends State<_DeviceListSheet> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  final List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  String? _connectingDeviceId; // 현재 연결 시도 중인 기기 ID
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  void _startScan() {
    if (mounted) {
      setState(() {
        _isScanning = true;
        _errorMessage = null;
        _devices.clear();
      });
    }
    _scanSubscription?.cancel();
    _scanSubscription = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
      (device) {
        if (!mounted) return;
        if (!_devices.any((d) => d.id == device.id)) {
          setState(() => _devices.add(device));
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    if (mounted) setState(() => _isScanning = false);
  }

  void _connectToDevice(DiscoveredDevice device) {
    if (_connectingDeviceId != null) return; // 이미 다른 연결 진행 중이면 무시

    _stopScan();
    setState(() {
      _connectingDeviceId = device.id;
      _errorMessage = null;
    });

    _connectionSubscription?.cancel();
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 20),
        )
        .listen(
      (update) {
        if (update.connectionState == DeviceConnectionState.connected) {
          _connectionSubscription?.cancel();
          _connectionSubscription = null;
          widget.onDeviceConnected(device);
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          if (mounted) {
            setState(() {
              _connectingDeviceId = null;
              _errorMessage = '연결에 실패했습니다.';
            });
            _startScan();
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _connectingDeviceId = null;
            _errorMessage = '연결 중 오류가 발생했습니다.';
          });
          _startScan();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '검색된 기기',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (_isScanning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAccentColor,
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: kAccentColor),
                    onPressed: _connectingDeviceId != null ? null : _startScan,
                    tooltip: '다시 검색',
                  ),
                ],
              ),
            ],
          ),

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),

          const SizedBox(height: 8),

          // 디바이스 목록
          _devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.bluetooth_searching,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        _isScanning
                            ? '기기를 검색하고 있습니다...'
                            : '검색된 기기가 없습니다',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isConnecting = _connectingDeviceId == device.id;
                      final name = device.name.isNotEmpty ? device.name : '이름 없음';
                      
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        enabled: _connectingDeviceId == null || isConnecting,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kAccentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.bluetooth,
                              color: kAccentColor, size: 22),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          device.id,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kAccentColor,
                                ),
                              )
                            : const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () => _connectToDevice(device),
                      );
                    },
                  ),
                ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Home Screen ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final DiscoveredDevice? selectedDevice;

  const HomeScreen({super.key, this.selectedDevice});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _targetDeviceName = 'FLOFIT';

  final GlobalKey<DataScreenState> _dataKey = GlobalKey<DataScreenState>();
  final GlobalKey<DatabaseScreenState> _dbKey = GlobalKey<DatabaseScreenState>();

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  int _selectedIndex = 0;
  bool _isScanning = false;
  bool _isConnecting = false;
  DiscoveredDevice? _device;
  String? _lastDeviceId;

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
    _loadLastDeviceId().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.selectedDevice != null) {
          _connect(widget.selectedDevice!);
        } else {
          _startConnectionFlow();
        }
      });
    });
  }

  Future<void> _loadLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastDeviceId = prefs.getString('last_device_id');
      });
    }
  }

  Future<void> _saveLastDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_device_id', id);
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
    _showConnectionToast(_lastDeviceId != null ? '기기 찾는 중...' : 'ring 검색 중');
    _scanSubscription?.cancel();
    _scanSubscription = _ble
        .scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    )
        .listen(
      (device) {
        // 마지막으로 연결했던 ID가 있다면 해당 ID를 우선 확인, 아니면 이름으로 확인
        if (_lastDeviceId != null) {
          if (device.id == _lastDeviceId) {
            _connect(device);
          }
        } else if (device.name == _targetDeviceName) {
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
    _showConnectionToast('연결 중...');

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
              _lastDeviceId = device.id;
            });
            _saveLastDeviceId(device.id); // 성공 시 ID 저장
            _showConnectionToast(isFirstConnection ? '연결되었습니다' : '재연결되었습니다');
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
    
    // Check if still mounted and device is still the same
    if (!mounted || _device?.id != device.id) return;

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

        // Final check before write
        if (!mounted || _device?.id != device.id) return;

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
