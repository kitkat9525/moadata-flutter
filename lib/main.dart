import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nrf/core/ble_service.dart';
import 'package:nrf/core/notification_service.dart';
import 'package:nrf/data/ble_constants.dart';
import 'package:nrf/screens/afe_screen.dart';
import 'package:nrf/screens/data_screen.dart';
import 'package:nrf/screens/database_screen.dart';
import 'package:nrf/screens/settings_screen.dart';
import 'package:nrf/shared/ui_constants.dart';

// ── 공통 유틸 ──────────────────────────────────────────────────────────────────

/// BLE 사용에 필요한 블루투스·위치 권한을 요청한다.
Future<void> _requestPermissions() async {
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.location,
  ].request();
}

/// 현재 시각을 BLE 시간 특성 포맷(10 bytes)으로 변환한다.
///
/// CTS(Current Time Service) 특성 구조:
/// [yearLo, yearHi, month, day, hour, min, sec, weekday, fractions256, adjustReason]
List<int> _buildTimeBytes() {
  final now = DateTime.now();
  return [
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
}

// ── App ────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await NotificationService.init();

  final prefs = await SharedPreferences.getInstance();
  final lastDeviceId = prefs.getString(kPrefLastDeviceId);

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
        home: lastDeviceId != null ? const HomeScreen() : const IntroScreen(),
      );
}

// ── Intro Screen ───────────────────────────────────────────────────────────────

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

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
            const Center(
              child: Text(
                'FLOFIT',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111111),
                  letterSpacing: 4.0,
                ),
              ),
            ),
            const Spacer(),
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

// ── Device List Bottom Sheet ───────────────────────────────────────────────────

class _DeviceListSheet extends StatefulWidget {
  final void Function(DiscoveredDevice) onDeviceConnected;

  const _DeviceListSheet({required this.onDeviceConnected});

  @override
  State<_DeviceListSheet> createState() => _DeviceListSheetState();
}

class _DeviceListSheetState extends State<_DeviceListSheet> {
  final _ble = BleService.instance;

  final List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  String? _connectingDeviceId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _ble.stopScan();
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

    _ble.startScan(
      onFound: (device) {
        if (!mounted) return;
        if (device.name.isEmpty) return;
        if (!_devices.any((d) => d.id == device.id)) {
          setState(() => _devices.add(device));
        }
      },
      onTimeout: () {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _stopScan() {
    _ble.stopScan();
    if (mounted) setState(() => _isScanning = false);
  }

  void _connectToDevice(DiscoveredDevice device) {
    if (_connectingDeviceId != null) return;

    _stopScan();
    setState(() {
      _connectingDeviceId = device.id;
      _errorMessage = null;
    });

    _ble.connect(
      device,
      onConnected: () {
        if (!mounted) return;
        widget.onDeviceConnected(device);
      },
      onDisconnected: () {
        if (mounted) {
          setState(() {
            _connectingDeviceId = null;
            _errorMessage = '연결에 실패했습니다.';
          });
          _startScan();
        }
      },
      onError: (_) {
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
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
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
                          strokeWidth: 2, color: kAccentColor),
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
          if (_errorMessage != null && _connectingDeviceId == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          _devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.bluetooth_searching,
                          size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        _isScanning ? '기기를 검색하고 있습니다...' : '검색된 기기가 없습니다',
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

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        enabled: _connectingDeviceId == null || isConnecting,
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kAccentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.bluetooth, color: kAccentColor, size: 22),
                        ),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          device.id,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
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

// ── Home Screen ────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  /// [_DeviceListSheet]에서 선택한 기기.
  /// null이면 SharedPreferences의 마지막 기기 ID로 자동 재연결한다.
  final DiscoveredDevice? selectedDevice;

  const HomeScreen({super.key, this.selectedDevice});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const _targetDeviceName = 'FLOFIT';
  static const _initialReconnectDelay = Duration(seconds: 60);
  static const _disconnectReconnectDelay = Duration(seconds: 5);

  final _ble = BleService.instance;

  /// 연결·해제 이벤트를 수신하는 BleService 기기 스트림 구독.
  StreamSubscription<DiscoveredDevice?>? _deviceStreamSub;

  final GlobalKey<AFEScreenState>       _afeKey  = GlobalKey<AFEScreenState>();
  final GlobalKey<DataScreenState>     _dataKey = GlobalKey<DataScreenState>();
  final GlobalKey<DatabaseScreenState> _dbKey   = GlobalKey<DatabaseScreenState>();

  int _selectedIndex = 0;
  bool _pendingReconnectToast = false;
  DiscoveredDevice? _device;
  String? _lastDeviceId;

  List<Widget> get _screens => [
        AFEScreen(key: _afeKey, device: _device),
        DataScreen(key: _dataKey, device: _device),
        DatabaseScreen(key: _dbKey, device: _device),
        SettingScreen(device: _device, onSyncTime: _syncTime),
      ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) _afeKey.currentState?.reloadBatteryPrefs();
    if (index == 1) _dataKey.currentState?.loadData();
    if (index == 2) _dbKey.currentState?.refreshData();
  }

  @override
  void initState() {
    super.initState();

    _deviceStreamSub = _ble.deviceStream.listen((device) {
      if (!mounted) return;
      setState(() => _device = device);
      if (device == null) _onDeviceDisconnected();
    });

    _loadLastDeviceId().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ble.isConnected && _ble.connectedDevice != null) {
          // DeviceListSheet에서 이미 연결된 상태로 진입한 경우
          final device = _ble.connectedDevice!;
          setState(() {
            _device = device;
            _lastDeviceId = device.id;
          });
          _saveLastDeviceId(device.id);
          _syncTime();
        } else if (widget.selectedDevice != null) {
          _connect(widget.selectedDevice!);
        } else {
          _startConnectionFlow();
        }
      });
    });
  }

  Future<void> _loadLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _lastDeviceId = prefs.getString(kPrefLastDeviceId));
  }

  Future<void> _saveLastDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefLastDeviceId, id);
  }

  @override
  void dispose() {
    _deviceStreamSub?.cancel();
    super.dispose();
  }

  // ── 연결 플로우 ────────────────────────────────────────────────────────────

  Future<void> _startConnectionFlow() async {
    try {
      await _requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));
      _scanAndConnect();
    } catch (e) {
      debugPrint('[HomeScreen] Permission error: $e');
      _showToast('블루투스 권한이 필요합니다');
    }
  }

  void _scanAndConnect() {
    _ble.startScan(
      deviceId: _lastDeviceId,
      deviceName: _lastDeviceId == null ? _targetDeviceName : null,
      onFound: (device) => _connect(device),
      onTimeout: () {
        debugPrint('[HomeScreen] Scan timeout, retrying...');
        final retryDelay = _pendingReconnectToast
            ? _disconnectReconnectDelay
            : _initialReconnectDelay;
        Future.delayed(retryDelay, () {
          if (mounted && !_ble.isConnected) _scanAndConnect();
        });
      },
    );
  }

  void _connect(DiscoveredDevice device) {
    _ble.connect(
      device,
      onConnected: () {
        if (!mounted) return;
        _showToast(_pendingReconnectToast ? '다시 연결되었습니다' : '연결되었습니다');
        _pendingReconnectToast = false;
        _saveLastDeviceId(device.id);
        setState(() => _lastDeviceId = device.id);
        _syncTime();
      },
      onError: (e) => debugPrint('[HomeScreen] Connection error: $e'),
    );
  }

  void _onDeviceDisconnected() {
    _pendingReconnectToast = true;
    Future.delayed(_disconnectReconnectDelay, () {
      if (mounted && !_ble.isConnected) _scanAndConnect();
    });
  }

  // ── 시간 동기화 ────────────────────────────────────────────────────────────

  Future<void> _syncTime() async {
    final device = _ble.connectedDevice;
    if (device == null) return;

    // GATT 서비스 디스커버리 완료 대기
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted || _ble.connectedDevice?.id != device.id) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: BleConstants.timeService,
      characteristicId: BleConstants.timeCharacteristic,
      deviceId: device.id,
    );

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // Android MTU 협상은 첫 번째 시도에서만 수행
        if (retryCount == 0) await _ble.requestMtu(device.id);

        if (!mounted || _ble.connectedDevice?.id != device.id) return;

        await _ble.writeCharacteristic(characteristic, _buildTimeBytes());
        debugPrint('[HomeScreen] Time synced (attempt ${retryCount + 1})');
        return;
      } catch (e) {
        retryCount++;
        debugPrint('[HomeScreen] Time sync failed (attempt $retryCount): $e');
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
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
