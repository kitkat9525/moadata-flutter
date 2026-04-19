import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:nrf/core/android_foreground_service.dart';

/// BLE 연결 상태
enum BleConnectionStatus { disconnected, scanning, connecting, connected }

/// 앱 전체에서 [FlutterReactiveBle] 인스턴스를 하나만 사용하는 싱글톤 BLE 서비스.
///
/// 스캔·연결·특성 읽기/쓰기 등 모든 BLE 작업의 단일 진입점이다.
/// 특성 구독([subscribeToCharacteristic])의 생명주기는 호출자가 직접 관리해야 한다.
class BleService {
  BleService._();
  static final BleService instance = BleService._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  DiscoveredDevice?   _connectedDevice;

  StreamSubscription<DiscoveredDevice>?    _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  final _deviceController = StreamController<DiscoveredDevice?>.broadcast();

  /// 현재 연결 상태 스트림
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;

  /// 연결된 기기 스트림. 연결 시 기기 객체, 해제 시 null을 방출한다.
  Stream<DiscoveredDevice?> get deviceStream => _deviceController.stream;

  BleConnectionStatus get status          => _status;
  DiscoveredDevice?   get connectedDevice => _connectedDevice;
  bool                get isConnected     => _status == BleConnectionStatus.connected;

  // ── 스캔 ───────────────────────────────────────────────────────────────────

  /// BLE 기기를 스캔한다.
  ///
  /// [deviceId] 또는 [deviceName]이 매칭되는 기기에 대해 [onFound]를 호출한다.
  /// 둘 다 null이면 발견되는 모든 기기를 [onFound]로 전달한다.
  /// [scanTimeoutSeconds] 경과 후 스캔이 자동 종료되고 [onTimeout]이 호출된다.
  void startScan({
    String? deviceId,
    String? deviceName,
    void Function(DiscoveredDevice device)? onFound,
    void Function()? onTimeout,
    int scanTimeoutSeconds = 10,
  }) {
    if (_status == BleConnectionStatus.scanning  ||
        _status == BleConnectionStatus.connecting ||
        _status == BleConnectionStatus.connected) {
      return;
    }

    _setStatus(BleConnectionStatus.scanning);
    _scanSubscription?.cancel();

    _scanSubscription = _ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
      (device) {
        if (deviceId == null && deviceName == null) {
          onFound?.call(device);
          return;
        }
        final matchById   = deviceId   != null && device.id   == deviceId;
        final matchByName = deviceName != null && device.name == deviceName;
        if (matchById || matchByName) {
          onFound?.call(device);
        }
      },
      onError: (e) {
        debugPrint('[BleService] Scan error: $e');
        _scanSubscription?.cancel();
        _scanSubscription = null;
        _setStatus(BleConnectionStatus.disconnected);
      },
    );

    Future.delayed(Duration(seconds: scanTimeoutSeconds), () {
      if (_status != BleConnectionStatus.scanning) return;
      debugPrint('[BleService] Scan timeout.');
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _setStatus(BleConnectionStatus.disconnected);
      onTimeout?.call();
    });
  }

  /// 진행 중인 스캔을 중단한다.
  void stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_status == BleConnectionStatus.scanning) {
      _setStatus(BleConnectionStatus.disconnected);
    }
  }

  // ── 연결 ───────────────────────────────────────────────────────────────────

  /// [device]에 연결한다.
  ///
  /// - [onConnected]: 연결 성공 시 1회 호출
  /// - [onDisconnected]: 연결 해제 시 호출
  /// - [onError]: 오류 발생 시 호출
  ///
  /// 지속적인 상태 감지는 [deviceStream] / [statusStream]을 구독하라.
  void connect(
    DiscoveredDevice device, {
    void Function()? onConnected,
    void Function()? onDisconnected,
    void Function(Object error)? onError,
  }) {
    if (_status == BleConnectionStatus.connecting ||
        _status == BleConnectionStatus.connected) {
      return;
    }

    stopScan();
    _setStatus(BleConnectionStatus.connecting);

    _connectionSubscription?.cancel();
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 30),
        )
        .listen(
      (update) {
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            _connectedDevice = device;
            _setStatus(BleConnectionStatus.connected);
            _deviceController.add(device);
            unawaited(AndroidForegroundService.start(
              deviceId: device.id,
              deviceName: device.name,
            ));
            onConnected?.call();
          case DeviceConnectionState.disconnected:
            _onDisconnected();
            onDisconnected?.call();
          default:
            break;
        }
      },
      onError: (e) {
        debugPrint('[BleService] Connection error: $e');
        _onDisconnected();
        onError?.call(e);
      },
    );
  }

  /// 현재 연결을 강제 해제한다.
  void disconnect() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _onDisconnected();
    unawaited(AndroidForegroundService.stop());
  }

  void _onDisconnected() {
    _connectedDevice = null;
    _setStatus(BleConnectionStatus.disconnected);
    _deviceController.add(null);
    unawaited(AndroidForegroundService.stop());
  }

  // ── 특성 ───────────────────────────────────────────────────────────────────

  /// BLE 특성을 구독한다.
  ///
  /// 반환된 [StreamSubscription]은 호출자가 직접 관리하고 dispose 시 cancel해야 한다.
  StreamSubscription<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic, {
    required void Function(List<int> data) onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    return _ble.subscribeToCharacteristic(characteristic).listen(
      onData,
      onError: onError ?? (e) {
        // 연결 해제로 인한 스트림 종료 에러는 무시
        if (e.toString().contains('isconnected')) return;
        debugPrint('[BleService] Characteristic error: $e');
      },
      onDone: onDone,
    );
  }

  /// BLE 특성 값을 읽는다.
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) async {
    return await _ble.readCharacteristic(characteristic);
  }

  /// BLE 특성에 값을 쓴다 (write with response).
  Future<void> writeCharacteristic(
    QualifiedCharacteristic characteristic,
    List<int> value,
  ) async {
    await _ble.writeCharacteristicWithResponse(characteristic, value: value);
  }

  /// Android에서 MTU 협상을 요청한다. iOS에서는 무시된다.
  Future<void> requestMtu(String deviceId, {int mtu = 247}) async {
    if (!Platform.isAndroid) return;
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: mtu).timeout(const Duration(seconds: 2));
      debugPrint('[BleService] MTU negotiated to $mtu.');
    } catch (e) {
      debugPrint('[BleService] MTU request failed: $e');
    }
  }

  // ── 내부 ───────────────────────────────────────────────────────────────────

  void _setStatus(BleConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  /// 앱 종료 시 스트림 리소스를 해제한다.
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _statusController.close();
    _deviceController.close();
  }
}
