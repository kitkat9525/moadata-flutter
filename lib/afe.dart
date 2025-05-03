import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class AFEScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const AFEScreen({super.key, required this.device});

  @override
  AFEScreenState createState() => AFEScreenState();
}

class AFEScreenState extends State<AFEScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, StreamSubscription?> _subscriptions = {};
  late Map<String, QualifiedCharacteristic> _characteristics = {};

  int _hrm = 0;
  int _spo2 = 0;

  bool isMeasuring = false;
  bool isWaiting = false;
  int remainingSeconds = 30;
  late Timer _timer;

  final List<String> _logEntries = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer.cancel();
    for (final subscription in _subscriptions.values) {
      subscription?.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _startMeasurement() async {
    setState(() {
      isMeasuring = true;
      isWaiting = true;
    });

    await _sendCommand(0x01);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingSeconds > 0) {
          remainingSeconds--;
        } else {
          isWaiting = false;
        }
      });
    });
  }

  void _stopMeasurement() async {
    setState(() {
      isMeasuring = false;
      remainingSeconds = 30;
      isWaiting = false;
    });

    await _sendCommand(0x02);
    _timer.cancel();
  }

  Future<void> _sendCommand(int command) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await _ble.writeCharacteristicWithoutResponse(
        _characteristics['command']!,
        value: [command],
      );
      debugPrint('Command 0x${command.toRadixString(16)} sent with response.');
    } catch (e) {
      debugPrint('Error sending command: $e');
    }
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timestamp =
        '[${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}]';

    setState(() {
      _logEntries.add('$timestamp $message');
      if (_logEntries.length > 100) {
        _logEntries.removeAt(0);
      }
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _init() async {
    if (_characteristics.isEmpty) {
      _characteristics = {
        'hrm': QualifiedCharacteristic(
          characteristicId: Uuid.parse('0000190B-0000-1000-8000-00805f9b34fb'),
          serviceId: Uuid.parse('00001901-0000-1000-8000-00805f9b34fb'),
          deviceId: widget.device.id,
        ),
        'spo2': QualifiedCharacteristic(
          characteristicId: Uuid.parse('0000190C-0000-1000-8000-00805f9b34fb'),
          serviceId: Uuid.parse('00001901-0000-1000-8000-00805f9b34fb'),
          deviceId: widget.device.id,
        ),
        'command': QualifiedCharacteristic(
          characteristicId: Uuid.parse('00001918-0000-1000-8000-00805f9b34fb'),
          serviceId: Uuid.parse('00001900-0000-1000-8000-00805f9b34fb'),
          deviceId: widget.device.id,
        ),
      };

      _subscriptions['hrm'] =
          _ble.subscribeToCharacteristic(_characteristics['hrm']!).listen(
        (data) {
          setState(() {
            _hrm = data[0];
          });
          _addLog('HRM: $_hrm bpm');
        },
        onError: (e) => debugPrint('$e'),
      );

      _subscriptions['spo2'] =
          _ble.subscribeToCharacteristic(_characteristics['spo2']!).listen(
        (data) {
          setState(() {
            _spo2 = data[0];
          });
          _addLog('SpO₂: $_spo2%');
        },
        onError: (e) => debugPrint('$e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AFE'),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      backgroundColor: Colors.white, // 배경을 흰색으로 설정
      body: Center(
        child: isMeasuring
            ? isWaiting
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time,
                          color: Colors.blue, size: 50),
                      const SizedBox(height: 16),
                      Text(
                        '.' * ((30 - remainingSeconds) % 4 + 1),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        '센서 초기화 중입니다 (30초)',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _stopMeasurement,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('측정 취소'),
                      )
                    ],
                  )
                : Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.favorite,
                            color: Colors.red, size: 20),
                        title:
                            const Text('HRM', style: TextStyle(fontSize: 14)),
                        trailing: Text(
                          '$_hrm bpm',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Divider(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.opacity,
                            color: Colors.red, size: 20),
                        title:
                            const Text('SpO₂', style: TextStyle(fontSize: 14)),
                        trailing: Text(
                          '$_spo2%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Divider(),
                      ),
                      const SizedBox(height: 32),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey),
                            ),
                            child: ListView.builder(
                              controller: _scrollController,
                              itemCount: _logEntries.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 8),
                                  child: Text(
                                    _logEntries[index],
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _stopMeasurement,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('측정 취소'),
                      ),
                      const SizedBox(height: 32),
                    ],
                  )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, color: Colors.red, size: 50),
                  const SizedBox(height: 32),
                  const Text(
                    '손가락을 올리고 시작하세요',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _startMeasurement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('측정 시작'),
                  ),
                ],
              ),
      ),
    );
  }
}
