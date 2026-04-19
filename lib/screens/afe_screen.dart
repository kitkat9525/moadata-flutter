import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nrf/core/ble_service.dart';
import 'package:nrf/data/ble_constants.dart';
import 'package:nrf/data/ble_data_model.dart';
import 'package:nrf/data/database_helper.dart';
import 'package:nrf/core/notification_service.dart';
import 'package:nrf/shared/ui_components.dart';
import 'package:nrf/shared/ui_constants.dart';

enum _MeasurementUiState { idle, measuring, waiting }

class AFEScreen extends StatefulWidget {
  final DiscoveredDevice? device;

  const AFEScreen({super.key, required this.device});

  @override
  AFEScreenState createState() => AFEScreenState();
}

class AFEScreenState extends State<AFEScreen> with TickerProviderStateMixin {
  final _ble = BleService.instance;
  static const _retryDelay = Duration(seconds: 30);

  /// 이 화면이 소유한 특성 구독 목록. 기기 변경 또는 dispose 시 일괄 취소한다.
  final List<StreamSubscription<List<int>>> _subscriptions = [];
  final List<Timer> _retryTimers = [];
  int _subscriptionEpoch = 0;
  String? _subscribedDeviceId;

  late QualifiedCharacteristic _dataChar;
  late QualifiedCharacteristic _sysChar;
  late QualifiedCharacteristic _notiChar;

  BleData? _latestData;

  int? _batteryMv;
  bool? _isCharging;
  int? _temperature;
  int _step = 0;
  String _activity = '-';
  int _nextMeasurementWaitMinutes = kDefaultPpgOffMin;

  int _batteryMinMv = kDefaultBatteryMinMv;
  int _batteryMaxMv = kDefaultBatteryMaxMv;

  int _singleTapCount = 0;
  int _doubleTapCount = 0;
  int _freeFallCount = 0;

  _MeasurementUiState _measurementState = _MeasurementUiState.idle;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _loadBatteryPrefs();
    _syncSubscriptions();
  }

  /// 배터리 전압 범위와 다음 측정 대기 시간을 SharedPreferences에서 다시 읽는다.
  ///
  /// 설정 화면에서 전압 범위를 변경한 뒤 이 화면으로 돌아올 때 호출된다.
  Future<void> reloadBatteryPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _batteryMinMv = prefs.getInt(kPrefBatteryMinMv) ?? kDefaultBatteryMinMv;
      _batteryMaxMv = prefs.getInt(kPrefBatteryMaxMv) ?? kDefaultBatteryMaxMv;
      _nextMeasurementWaitMinutes = prefs.getInt(kPrefPpgOffMin) ?? kDefaultPpgOffMin;
    });
  }

  Future<void> _loadBatteryPrefs() => reloadBatteryPrefs();

  /// 배터리 전압(mV)을 0~100% 백분율로 선형 변환한다.
  int _mvToPercent(int mv) {
    if (_batteryMaxMv <= _batteryMinMv) return 0;
    final pct = (mv - _batteryMinMv) / (_batteryMaxMv - _batteryMinMv) * 100;
    return pct.round().clamp(0, 100);
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
    _pulseController.dispose();
    _disposeSubscriptions();
    super.dispose();
  }

  void _syncSubscriptions() {
    final device = widget.device;
    if (device == null) {
      _resetMeasurementUi();
      _disposeSubscriptions();
      return;
    }
    if (_subscribedDeviceId == device.id) return;

    _resetMeasurementUi();
    _disposeSubscriptions();
    _init();
    _subscribedDeviceId = device.id;
  }

  void _disposeSubscriptions() {
    _subscriptionEpoch++;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    for (final timer in _retryTimers) {
      timer.cancel();
    }
    _retryTimers.clear();
    _subscribedDeviceId = null;
  }

  void _setMeasurementState(_MeasurementUiState state) {
    if (!mounted || _measurementState == state) return;
    setState(() => _measurementState = state);
  }

  void _resetMeasurementUi() {
    if (!mounted) {
      _measurementState = _MeasurementUiState.idle;
      return;
    }
    setState(() => _measurementState = _MeasurementUiState.idle);
  }

  Future<void> _init() async {
    final device = widget.device;
    if (device == null) return;

    // GATT 서비스 디스커버리 완료 대기
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || widget.device?.id != device.id) return;

    _dataChar = _buildChar(device.id, BleConstants.afeService,  BleConstants.afeDataCharacteristic);
    _sysChar  = _buildChar(device.id, BleConstants.sysService,  BleConstants.sysCharacteristic);
    _notiChar = _buildChar(device.id, BleConstants.notiService, BleConstants.notiCharacteristic);

    _subscribe(_dataChar, _onDataReceived, 'data_t');
    _subscribe(_sysChar,  _onSysReceived,  'sys');
    _subscribe(_notiChar, _onNotiReceived, 'noti');
  }

  QualifiedCharacteristic _buildChar(String deviceId, Uuid serviceId, Uuid charId) =>
      QualifiedCharacteristic(
        serviceId: serviceId,
        characteristicId: charId,
        deviceId: deviceId,
      );

  void _subscribe(
    QualifiedCharacteristic char,
    void Function(List<int>) onData,
    String name, {
    int retryCount = 0,
  }) {
    final epochAtStart = _subscriptionEpoch;
    debugPrint('Subscribing to $name (attempt ${retryCount + 1})...');
    try {
      final sub = _ble.subscribeToCharacteristic(
        char,
        onData: onData,
        onError: (e) {
          final msg = e.toString();
          if (msg.contains('isconnected')) return;
          debugPrint('$name subscribe error: $e');
          _scheduleRetry(
            epochAtStart,
            char,
            onData,
            name,
            retryCount: retryCount + 1,
          );
        },
        onDone: () => debugPrint('$name stream closed'),
      );
      _subscriptions.add(sub);
    } catch (e) {
      debugPrint('$name subscribe setup error: $e');
      _scheduleRetry(
        epochAtStart,
        char,
        onData,
        name,
        retryCount: retryCount + 1,
      );
    }
  }

  void _scheduleRetry(
    int epoch,
    QualifiedCharacteristic char,
    void Function(List<int>) onData,
    String name, {
    required int retryCount,
  }) {
    late final Timer timer;
    timer = Timer(_retryDelay, () {
      _retryTimers.remove(timer);
      if (!mounted) return;
      if (epoch != _subscriptionEpoch) return;
      if (widget.device?.id != char.deviceId) return;
      if (_subscribedDeviceId != char.deviceId) return;
      _subscribe(char, onData, name, retryCount: retryCount);
    });
    _retryTimers.add(timer);
  }

  // ── 데이터 핸들러 ──────────────────────────────────────────────────────────

  void _onDataReceived(List<int> data) {
    if (!mounted || data.length < 19) return;
    try {
      final bleData = BleData.fromBytes(data);
      debugPrint('[data_t] parsed: $bleData');
      setState(() => _latestData = bleData);
      DatabaseHelper().insertBleData(bleData); // UI 업데이트와 독립적으로 저장
    } catch (e) {
      debugPrint('[data_t] parse error: $e');
    }
  }

  /// sensor_t 파싱 (little-endian uint32 × 6, 총 24 bytes)
  ///
  /// | offset | field       | 비고                  |
  /// |--------|-------------|-----------------------|
  /// | 0      | afe         | 0=대기, 1=측정 중     |
  /// | 4      | battery     | mV                    |
  /// | 8      | charge      | 0=비충전, 1=충전 중    |
  /// | 12     | temperature | °C × 10               |
  /// | 16     | step        | 걸음 수               |
  /// | 20     | activity    | 0=Still 1=Walk 2=Run  |
  void _onSysReceived(List<int> data) {
    if (!mounted || data.length < 24) return;
    try {
      final b = ByteData.sublistView(Uint8List.fromList(data));
      final afe         = b.getUint32(0,  Endian.little);
      final battery     = b.getUint32(4,  Endian.little);
      final charge      = b.getUint32(8,  Endian.little);
      final temperature = b.getUint32(12, Endian.little);
      final step        = b.getUint32(16, Endian.little);
      final activityRaw = b.getUint32(20, Endian.little);

      final activity = switch (activityRaw) {
        0 => 'Still',
        1 => 'Walk',
        2 => 'Run',
        _ => 'Unknown',
      };

      _setMeasurementState(
        afe == 1 ? _MeasurementUiState.measuring : _MeasurementUiState.waiting,
      );

      setState(() {
        _batteryMv   = battery;
        _isCharging  = charge == 1;
        _temperature = temperature;
        _step        = step;
        _activity    = activity;
      });
    } catch (e) {
      debugPrint('[sys] parse error: $e');
    }
  }

  /// event_t 파싱: [sleep, free_fall, single_tap, double_tap] (각 1 byte)
  void _onNotiReceived(List<int> data) {
    if (!mounted || data.length < 4) return;

    final sleep     = data[0];
    final freeFall  = data[1];
    final singleTap = data[2];
    final doubleTap = data[3];

    if (sleep == 1) {
      NotificationService.showSleepStartAlert();
      _showToast('수면 시작이 감지되었습니다');
    }
    if (freeFall == 1) {
      setState(() => _freeFallCount++);
      _handleFreeFall();
    }
    if (singleTap == 1) setState(() => _singleTapCount++);
    if (doubleTap == 1) setState(() => _doubleTapCount++);
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
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

  // ── UI 빌더 ───────────────────────────────────────────────────────────────

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

  Widget _buildPulseIndicator() {
    return SizedBox(
      width: 64,
      height: 24,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) => CustomPaint(
          painter: _EcgPainter(_pulseController.value),
        ),
      ),
    );
  }

  Widget _buildSectionStatus() {
    switch (_measurementState) {
      case _MeasurementUiState.measuring:
        return _buildPulseIndicator();
      case _MeasurementUiState.waiting:
        return Text(
          '다음 측정 대기 ($_nextMeasurementWaitMinutes분)',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
        );
      case _MeasurementUiState.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildItem(
    String title,
    String subtitle,
    String value,
    String unit, {
    bool isLast = false,
    bool isMeasuring = false,
  }) {
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
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  ],
                ),
              ),
              if (isMeasuring)
                _buildPulseIndicator()
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
                    const SizedBox(width: 4),
                    Text(unit,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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

  Widget _buildSectionWithStatus(String title, List<Widget> items) {
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Text(title, style: buildSectionTitleStyle()),
                if (_latestData != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _latestData!.timestamp.toString().split('.').first,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                _buildSectionStatus(),
              ],
            ),
          ),
          ...items,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScreenBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: kScreenTopPadding, bottom: 24.0),
          children: [
            _buildSectionWithStatus('바이탈', [
              _buildItem('Heart Rate', '심박수', '${_latestData?.hr ?? 0}', 'bpm',
                  isMeasuring: false),
              _buildItem('SpO2', '혈중 산소포화도', '${_latestData?.spo2 ?? 0}', '%',
                  isMeasuring: false),
              _buildItem('RR Interval', '평균 RR 간격', '${_latestData?.rr ?? 0}', 'ms',
                  isLast: true,
                  isMeasuring: false),
            ]),
            _buildSectionWithStatus('HRV 분석', [
              _buildItem('SDNN', '자율신경 균형', '${_latestData?.sdnn ?? 0}', 'ms',
                  isMeasuring: false),
              _buildItem('RMSSD', '부교감 활성도', '${_latestData?.rmssd ?? 0}', 'ms',
                  isLast: true,
                  isMeasuring: false),
            ]),
            _buildSectionWithStatus('스트레스 및 활동', [
              _buildItem('Stress', '스트레스 지수', '${_latestData?.stress ?? 0}', '',
                  isMeasuring: false),
              _buildItem('Activity', '활동 상태', _activity, ''),
              _buildItem('Step Count', '걸음 수', '$_step', 'steps', isLast: true),
            ]),
            _buildSection('제스처 및 센서', [
              _buildItem('Free Fall', '낙상 발생 횟수', '$_freeFallCount', 'times'),
              _buildItem('Single Tap', '싱글 탭 횟수', '$_singleTapCount', 'times'),
              _buildItem('Double Tap', '더블 탭 횟수', '$_doubleTapCount', 'times'),
              _buildItem(
                'Temperature', '체온',
                _temperature != null ? (_temperature! / 10.0).toStringAsFixed(1) : '0', '°C',
                isMeasuring: false,
              ),
              _buildItem(
                'Battery', '배터리 잔량',
                _batteryMv != null
                    ? (_isCharging == true
                        ? '충전 중 ${_mvToPercent(_batteryMv!)}'
                        : '${_mvToPercent(_batteryMv!)}')
                    : '0',
                '%',
                isLast: true,
                isMeasuring: false,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── ECG 파형 애니메이션 Painter ──────────────────────────────────────────────

class _EcgPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0

  _EcgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h * 0.5;

    final path = Path()
      ..moveTo(0,        mid)
      ..lineTo(w * 0.12, mid)
      ..lineTo(w * 0.20, mid * 0.72)
      ..lineTo(w * 0.27, mid)
      ..lineTo(w * 0.31, mid * 1.18)
      ..lineTo(w * 0.38, h * 0.04)
      ..lineTo(w * 0.45, h * 0.92)
      ..lineTo(w * 0.52, mid)
      ..lineTo(w * 0.58, mid * 0.65)
      ..lineTo(w * 0.68, mid)
      ..lineTo(w,        mid);

    final bgPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, bgPaint);

    final metrics = path.computeMetrics().first;
    final drawn = metrics.extractPath(0, metrics.length * progress);
    final fgPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(drawn, fgPaint);
  }

  @override
  bool shouldRepaint(_EcgPainter old) => old.progress != progress;
}
