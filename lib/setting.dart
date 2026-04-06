import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:mcumgr_flutter/models/image_upload_alignment.dart';
import 'package:mcumgr_flutter/models/firmware_upgrade_mode.dart';
import 'package:nrf/ble_constants.dart';
import 'package:nrf/ui_components.dart';
import 'package:nrf/ui_constants.dart';

class SettingScreen extends StatefulWidget {
  final DiscoveredDevice? device;
  final Future<void> Function() onSyncTime;

  const SettingScreen({super.key, required this.device, required this.onSyncTime});

  @override
  SettingScreenState createState() => SettingScreenState();
}

class SettingScreenState extends State<SettingScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  double _progress = 0.0;
  bool _isUpdating = false;
  double _calibrationSeconds = 30;
  double _ppgOnMinutes = 1;
  double _ppgOffMinutes = 1;
  double _sleepOnMinutes = 1;
  double _sleepOffMinutes = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildOtaButton(),
            ],
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
            divisions: 60,
          valueLabelBuilder: _formatMinutesLabel,
          minLabel: '0분',
          maxLabel: '1시간',
          onChanged: (value) => setState(() => _ppgOnMinutes = value),
          onChangeEnd: (_) => _writeSystemSettings(),
        ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '꺼짐 시간',
            value: _ppgOffMinutes,
            divisions: 60,
          valueLabelBuilder: _formatMinutesLabel,
          minLabel: '0분',
          maxLabel: '1시간',
          onChanged: (value) => setState(() => _ppgOffMinutes = value),
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
            divisions: 60,
          valueLabelBuilder: _formatMinutesLabel,
          minLabel: '0분',
          maxLabel: '1시간',
          onChanged: (value) => setState(() => _sleepOnMinutes = value),
          onChangeEnd: (_) => _writeSystemSettings(),
        ),
          const SizedBox(height: 20),
          _buildSliderItem(
            label: '꺼짐 시간',
            value: _sleepOffMinutes,
            divisions: 60,
          valueLabelBuilder: _formatMinutesLabel,
          minLabel: '0분',
          maxLabel: '1시간',
          onChanged: (value) => setState(() => _sleepOffMinutes = value),
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
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
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
            overlayColor: kAccentColor.withOpacity(0.12),
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
            Text(
              minLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const Spacer(),
            Text(
              maxLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
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
      await _ble.writeCharacteristicWithResponse(characteristic, value: payload);
      debugPrint('System settings updated: $payload');
    } catch (e) {
      debugPrint('Failed to update system settings: $e');
    }
  }

  Widget _buildOtaButton() {
    return AppCard(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isUpdating || widget.device == null ? null : () => _firmwareOverTheAir(widget.device!.id),
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
      
      setState(() {
        _progress = 0.0;
        _isUpdating = true;
      });

      _showOtaDialog();

      updateManager.setup();

      updateManager.updateStateStream?.listen((event) {
        if (event == FirmwareUpgradeState.success) {
          _onUpdateComplete();
        }
      });

      updateManager.progressStream.listen((event) {
        if (mounted) {
          setState(() => _progress = event.bytesSent / event.imageSize);
        }
      });

      const configuration = FirmwareUpgradeConfiguration(
        estimatedSwapTime: Duration(seconds: 30),
        byteAlignment: ImageUploadAlignment.fourByte,
        eraseAppSettings: true,
        pipelineDepth: 1,
        firmwareUpgradeMode: FirmwareUpgradeMode.testOnly,
      );

      await updateManager.updateWithImageData(
        imageData: imageData,
        configuration: configuration,
      );
    } catch (e) {
      debugPrint('Firmware update error: $e');
      _onUpdateComplete();
    }
  }

  void _onUpdateComplete() {
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Use local setState to update progress in dialog
            // In a more complex app, we'd use a ValueNotifier or a Stream
            Timer.periodic(const Duration(milliseconds: 100), (timer) {
              if (!_isUpdating) {
                timer.cancel();
              } else {
                setDialogState(() {});
              }
            });

            return AlertDialog(
              title: const Text('OTA update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Uploading new signed image...'),
                  const Text('(1 minute reboot time after completion)', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 10),
                  Text('${(_progress * 100).toStringAsFixed(1)}%'),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
