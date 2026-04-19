import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:mcumgr_flutter/models/image_upload_alignment.dart';
import 'package:mcumgr_flutter/models/firmware_upgrade_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restart_app/restart_app.dart';
import 'package:nrf/core/ble_service.dart';
import 'package:nrf/data/ble_constants.dart';
import 'package:nrf/shared/ui_components.dart';
import 'package:nrf/shared/ui_constants.dart';

class SettingScreen extends StatefulWidget {
  final DiscoveredDevice? device;
  final Future<void> Function() onSyncTime;

  const SettingScreen({super.key, required this.device, required this.onSyncTime});

  @override
  SettingScreenState createState() => SettingScreenState();
}

class SettingScreenState extends State<SettingScreen> {
  final _ble = BleService.instance;

  final ValueNotifier<double> _otaProgressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String> _otaStatusNotifier = ValueNotifier<String>('');

  bool _isUpdating = false;

  StreamSubscription? _updateStateSub;
  StreamSubscription? _progressSub;

  double _calibrationSeconds = 30;
  double _ppgOnMinutes = 1;
  double _ppgOffMinutes = 1;
  double _sleepOnMinutes = 1;
  double _sleepOffMinutes = 1;

  double _batteryMinMv = 3500;
  double _batteryMaxMv = 4200;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _calibrationSeconds = (prefs.getInt(kPrefCalibSec)    ?? kDefaultCalibSec).toDouble();
      _ppgOnMinutes       = (prefs.getInt(kPrefPpgOnMin)    ?? kDefaultPpgOnMin).toDouble().clamp(1, 60);
      _ppgOffMinutes      = (prefs.getInt(kPrefPpgOffMin)   ?? kDefaultPpgOffMin).toDouble().clamp(1, 60);
      _sleepOnMinutes     = (prefs.getInt(kPrefSleepOnMin)  ?? kDefaultSleepOnMin).toDouble().clamp(1, 60);
      _sleepOffMinutes    = (prefs.getInt(kPrefSleepOffMin) ?? kDefaultSleepOffMin).toDouble().clamp(1, 60);
      _batteryMinMv       = (prefs.getInt(kPrefBatteryMinMv) ?? kDefaultBatteryMinMv).toDouble();
      _batteryMaxMv       = (prefs.getInt(kPrefBatteryMaxMv) ?? kDefaultBatteryMaxMv).toDouble();
    });
  }

  Future<void> _saveIntervalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefCalibSec,    _calibrationSeconds.round());
    await prefs.setInt(kPrefPpgOnMin,    _ppgOnMinutes.round().clamp(1, 60).toInt());
    await prefs.setInt(kPrefPpgOffMin,   _ppgOffMinutes.round().clamp(1, 60).toInt());
    await prefs.setInt(kPrefSleepOnMin,  _sleepOnMinutes.round().clamp(1, 60).toInt());
    await prefs.setInt(kPrefSleepOffMin, _sleepOffMinutes.round().clamp(1, 60).toInt());
  }

  Future<void> _saveBatteryVoltagePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kPrefBatteryMinMv, _batteryMinMv.round());
    await prefs.setInt(kPrefBatteryMaxMv, _batteryMaxMv.round());
  }

  @override
  void dispose() {
    _otaProgressNotifier.dispose();
    _otaStatusNotifier.dispose();
    _updateStateSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isUpdating,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isUpdating) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('업데이트 진행 중에는 화면을 나갈 수 없습니다.')),
          );
        }
      },
      child: Scaffold(
        backgroundColor: kScreenBackgroundColor,
        body: SafeArea(
          child: Padding(
            padding: kScreenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDeviceSection(),
                        const SizedBox(height: 24),
                        _buildPpgIntervalSection(),
                        const SizedBox(height: 24),
                        _buildSleepIntervalSection(),
                        const SizedBox(height: 24),
                        _buildBatteryVoltageSection(),
                        const SizedBox(height: 24),
                        _buildOtaButton(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Device (${widget.device?.name ?? 'Not connected'})',
                style: const TextStyle(fontSize: 18),
              ),
              const Spacer(),
              Icon(
                Icons.bluetooth,
                color: widget.device == null ? Colors.grey : Colors.blue,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoItem('MAC Address', widget.device?.id ?? '--'),
          const SizedBox(height: 16),
          _buildInfoItem('Firmware Version', 'v1.0.0'),
          const SizedBox(height: 16),
          _buildInfoItem('Region', 'KOREA (KR)'),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _isUpdating
                  ? null
                  : () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(kPrefLastDeviceId);
                      Restart.restartApp();
                    },
              icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 18),
              label: const Text(
                '기기 연결 해제',
                style: TextStyle(
                    color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPpgIntervalSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '측정 주기 조절 (PPG)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '캘리브레이션 시간',
            value: _calibrationSeconds,
            min: 0,
            max: 60,
            divisions: 60,
            valueLabelBuilder: _formatSecondsLabel,
            minLabel: '0초',
            maxLabel: '1분',
            onChanged: (value) => setState(() => _calibrationSeconds = value),
            onChangeEnd: (_) => _writeSystemSettings(),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '측정 시간',
            value: _ppgOnMinutes,
            min: 1,
            divisions: 60,
            valueLabelBuilder: _formatMinutesLabel,
            minLabel: '1분',
            maxLabel: '1시간',
            onChanged: (value) => setState(() => _ppgOnMinutes = value.clamp(1, 60)),
            onChangeEnd: (_) => _writeSystemSettings(),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '꺼짐 시간',
            value: _ppgOffMinutes,
            min: 1,
            divisions: 60,
            valueLabelBuilder: _formatMinutesLabel,
            minLabel: '1분',
            maxLabel: '1시간',
            onChanged: (value) => setState(() => _ppgOffMinutes = value.clamp(1, 60)),
            onChangeEnd: (_) => _writeSystemSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepIntervalSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '측정 주기 조절 (수면)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '측정 시간',
            value: _sleepOnMinutes,
            min: 1,
            divisions: 60,
            valueLabelBuilder: _formatMinutesLabel,
            minLabel: '1분',
            maxLabel: '1시간',
            onChanged: (value) => setState(() => _sleepOnMinutes = value.clamp(1, 60)),
            onChangeEnd: (_) => _writeSystemSettings(),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '꺼짐 시간',
            value: _sleepOffMinutes,
            min: 1,
            divisions: 60,
            valueLabelBuilder: _formatMinutesLabel,
            minLabel: '1분',
            maxLabel: '1시간',
            onChanged: (value) => setState(() => _sleepOffMinutes = value.clamp(1, 60)),
            onChangeEnd: (_) => _writeSystemSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderItem({
    required String label,
    required double value,
    double min = 0,
    double max = 60,
    int? divisions,
    required String Function(int value) valueLabelBuilder,
    required String minLabel,
    required String maxLabel,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const Spacer(),
            Text(
              valueLabelBuilder(value.round()),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: kAccentColor,
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: kAccentColor,
            overlayColor: kAccentColor.withValues(alpha: 0.12),
            trackHeight: 4,
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        Row(
          children: [
            Text(minLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const Spacer(),
            Text(maxLabel, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }

  String _formatMinutesLabel(int minutes) {
    if (minutes == 60) return '1시간';
    return '$minutes분';
  }

  String _formatSecondsLabel(int seconds) {
    if (seconds == 60) return '1분';
    return '$seconds초';
  }

  Future<void> _writeSystemSettings() async {
    final device = widget.device;
    if (device == null) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: BleConstants.sysService,
      characteristicId: BleConstants.sysCharacteristic,
      deviceId: device.id,
    );

    final payload = <int>[
      _calibrationSeconds.round().clamp(0, 60).toInt(),
      _ppgOnMinutes.round().clamp(0, 60).toInt(),
      _ppgOffMinutes.round().clamp(0, 60).toInt(),
      _sleepOnMinutes.round().clamp(0, 60).toInt(),
      _sleepOffMinutes.round().clamp(0, 60).toInt(),
    ];

    try {
      if (widget.device?.id != device.id) return;
      await _ble.writeCharacteristic(characteristic, payload);
      await _saveIntervalPrefs(); // 기기 전송 성공 후 앱에도 저장
      debugPrint('System settings updated: $payload');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('설정이 기기에 저장되었습니다.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to update system settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정 저장에 실패했습니다. 연결 상태를 확인해주세요.')),
        );
      }
    }
  }

  Widget _buildBatteryVoltageSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '배터리 전압 범위',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '배터리 mV → % 변환 기준값',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '최소 전압 (방전)',
            value: _batteryMinMv,
            min: 3000,
            max: 4000,
            divisions: 20,
            valueLabelBuilder: (v) => '${v}mV',
            minLabel: '3000mV',
            maxLabel: '4000mV',
            onChanged: (value) {
              if (value >= _batteryMaxMv) return;
              setState(() => _batteryMinMv = value);
            },
            onChangeEnd: (_) => _saveBatteryVoltagePrefs(),
          ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '최대 전압 (완충)',
            value: _batteryMaxMv,
            min: 3500,
            max: 4500,
            divisions: 20,
            valueLabelBuilder: (v) => '${v}mV',
            minLabel: '3500mV',
            maxLabel: '4500mV',
            onChanged: (value) {
              if (value <= _batteryMinMv) return;
              setState(() => _batteryMaxMv = value);
            },
            onChangeEnd: (_) => _saveBatteryVoltagePrefs(),
          ),
        ],
      ),
    );
  }

  Widget _buildOtaButton() {
    return AppCard(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isUpdating || widget.device == null
              ? null
              : () => _firmwareOverTheAir(widget.device!.id),
          icon: const Icon(Icons.system_update),
          label: const Text('OTA update'),
          style: FilledButton.styleFrom(
            backgroundColor: kAccentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Future<void> _firmwareOverTheAir(String deviceId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final imageData = await file.readAsBytes();
      final managerFactory = FirmwareUpdateManagerFactory();
      final updateManager = await managerFactory.getUpdateManager(deviceId);

      if (mounted) {
        setState(() {
          _isUpdating = true;
          _otaProgressNotifier.value = 0.0;
          _otaStatusNotifier.value = '준비 중...';
        });
      }

      _showOtaDialog();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      updateManager.setup();

      _updateStateSub = updateManager.updateStateStream?.listen((event) {
        if (!mounted) return;
        debugPrint('FOTA State: $event');

        switch (event) {
          case FirmwareUpgradeState.none:
            _otaStatusNotifier.value = '대기 중';
            break;
          case FirmwareUpgradeState.validate:
            _otaStatusNotifier.value = '파일 검증 중...';
            break;
          case FirmwareUpgradeState.upload:
            _otaStatusNotifier.value = '펌웨어 업로드 중...';
            break;
          case FirmwareUpgradeState.test:
            _otaStatusNotifier.value = '테스트 부팅 중...';
            break;
          case FirmwareUpgradeState.confirm:
            _otaStatusNotifier.value = '확정 중...';
            break;
          case FirmwareUpgradeState.reset:
            _otaStatusNotifier.value = '기기 리셋 중...';
            break;
          case FirmwareUpgradeState.success:
            _otaStatusNotifier.value = '업데이트 성공!';
            Future.delayed(const Duration(seconds: 1), _onUpdateComplete);
            break;
        }
      }, onError: (e) {
        debugPrint('FOTA State Error: $e');
        _handleOtaError('업데이트 도중 오류가 발생했습니다.');
      });

      _progressSub = updateManager.progressStream.listen((event) {
        if (mounted) {
          final progress = event.bytesSent / event.imageSize;
          _otaProgressNotifier.value = progress;
        }
      }, onError: (e) {
        debugPrint('FOTA Progress Error: $e');
      });

      const configuration = FirmwareUpgradeConfiguration(
        estimatedSwapTime: Duration(seconds: 30),
        byteAlignment: ImageUploadAlignment.fourByte,
        eraseAppSettings: false,
        pipelineDepth: 1,
        firmwareUpgradeMode: FirmwareUpgradeMode.confirmOnly,
      );

      await updateManager.updateWithImageData(
        imageData: imageData,
        configuration: configuration,
      );
    } catch (e) {
      debugPrint('Firmware update root error: $e');
      _handleOtaError('기기와의 통신이 원활하지 않습니다.');
    }
  }

  void _handleOtaError(String message) {
    if (mounted) {
      _onUpdateComplete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _onUpdateComplete() {
    _updateStateSub?.cancel();
    _progressSub?.cancel();
    if (mounted) {
      setState(() => _isUpdating = false);
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showOtaDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('OTA 업데이트'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: _otaStatusNotifier,
                builder: (context, status, _) => Text(
                  status,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: kAccentColor),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '업데이트가 진행되는 동안 기기와 앱을\n가까이 두어 연결을 유지해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<double>(
                valueListenable: _otaProgressNotifier,
                builder: (context, progress, child) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade200,
                        color: kAccentColor,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
