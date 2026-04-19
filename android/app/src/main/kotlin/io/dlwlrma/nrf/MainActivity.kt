package io.dlwlrma.nrf

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val foregroundChannel = "io.dlwlrma.nrf/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, foregroundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val deviceName = call.argument<String>("deviceName")
                        BleForegroundService.start(this, deviceId, deviceName)
                        result.success(null)
                    }
                    "stop" -> {
                        BleForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        BleForegroundService.stop(this)
        super.onDestroy()
    }
}
