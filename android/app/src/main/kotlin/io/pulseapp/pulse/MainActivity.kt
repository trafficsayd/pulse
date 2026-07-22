package io.pulseapp.pulse

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var blePeripheral: BlePeripheralChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.pulse.ble/peripheral",
        )
        val peripheral = BlePeripheralChannel(applicationContext, channel)
        channel.setMethodCallHandler(peripheral)
        blePeripheral = peripheral
    }

    override fun onDestroy() {
        blePeripheral?.dispose()
        blePeripheral = null
        super.onDestroy()
    }
}
