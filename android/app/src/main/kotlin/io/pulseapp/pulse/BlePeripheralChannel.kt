package io.pulseapp.pulse

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Native side of the `app.pulse.ble/peripheral` MethodChannel that the Dart
 * [RealBlePeripheral] scaffolding was written against.
 *
 * Responsibilities:
 *  * advertise the Pulse GATT service so central scanners can find us;
 *  * host a [BluetoothGattServer] with the TX (peripheral->central, NOTIFY)
 *    and RX (central->peripheral, WRITE) characteristics;
 *  * bridge data-plane events back into Dart:
 *      - `onCentralConnected` / `onCentralDisconnected`
 *      - `onRxWrite` with the raw frame bytes
 *  * `txNotify` method: push a frame to the connected central via TX notify.
 *
 * Payload framing/crypto stay in Dart — this class shuttles opaque bytes.
 */
@SuppressLint("MissingPermission") // Runtime permissions are requested by the
// Dart BlePermissionGate before any method here is invoked.
class BlePeripheralChannel(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var connectedDevice: BluetoothDevice? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> startAdvertising(call, result)
            "stopAdvertising" -> {
                stopEverything()
                result.success(null)
            }
            "txNotify" -> txNotify(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startAdvertising(call: MethodCall, result: MethodChannel.Result) {
        val serviceUuid = call.argument<String>("serviceUuid")
        val txUuid = call.argument<String>("txCharacteristicUuid")
        val rxUuid = call.argument<String>("rxCharacteristicUuid")
        if (serviceUuid == null || txUuid == null || rxUuid == null) {
            result.error("bad_args", "serviceUuid/txCharacteristicUuid/rxCharacteristicUuid required", null)
            return
        }

        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter: BluetoothAdapter? = manager?.adapter
        if (manager == null || adapter == null || !adapter.isEnabled) {
            result.error("bt_off", "Bluetooth is disabled", null)
            return
        }
        val leAdvertiser = adapter.bluetoothLeAdvertiser
        if (leAdvertiser == null) {
            result.error("no_advertiser", "BLE advertising is not supported on this device", null)
            return
        }

        // Rebuild from scratch on every start so a stale server can't leak.
        stopEverything()

        val tx = BluetoothGattCharacteristic(
            UUID.fromString(txUuid),
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        // Client Characteristic Configuration Descriptor — centrals write it
        // to enable notifications; without it setNotifyValue() fails.
        tx.addDescriptor(
            BluetoothGattDescriptor(
                UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        val rx = BluetoothGattCharacteristic(
            UUID.fromString(rxUuid),
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )

        val service = BluetoothGattService(
            UUID.fromString(serviceUuid),
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        )
        service.addCharacteristic(tx)
        service.addCharacteristic(rx)

        val server = manager.openGattServer(context, serverCallback)
        if (server == null) {
            result.error("gatt_open_failed", "openGattServer returned null", null)
            return
        }
        server.addService(service)
        gattServer = server
        txCharacteristic = tx

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(UUID.fromString(serviceUuid)))
            .build()

        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                mainHandler.post { result.success(null) }
            }

            override fun onStartFailure(errorCode: Int) {
                mainHandler.post {
                    stopEverything()
                    result.error("advertise_failed", "AdvertiseCallback error $errorCode", null)
                }
            }
        }
        advertiseCallback = cb
        advertiser = leAdvertiser
        leAdvertiser.startAdvertising(settings, data, cb)
    }

    private fun txNotify(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val server = gattServer
        val tx = txCharacteristic
        val device = connectedDevice
        if (bytes == null) {
            result.error("bad_args", "bytes required", null)
            return
        }
        if (server == null || tx == null || device == null) {
            result.error("not_connected", "No central is connected", null)
            return
        }
        @Suppress("DEPRECATION")
        tx.value = bytes
        @Suppress("DEPRECATION")
        val ok = server.notifyCharacteristicChanged(device, tx, false)
        if (ok) result.success(null) else result.error("notify_failed", "notifyCharacteristicChanged=false", null)
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                connectedDevice = device
                mainHandler.post { channel.invokeMethod("onCentralConnected", null) }
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                if (connectedDevice?.address == device.address) connectedDevice = null
                mainHandler.post { channel.invokeMethod("onCentralDisconnected", null) }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
            mainHandler.post { channel.invokeMethod("onRxWrite", mapOf("bytes" to value)) }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            // CCCD write (enable/disable notify) — always acknowledge.
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, ByteArray(0))
        }
    }

    private fun stopEverything() {
        try {
            advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        } catch (_: Exception) {
        }
        advertiseCallback = null
        advertiser = null
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        txCharacteristic = null
        connectedDevice = null
    }

    fun dispose() = stopEverything()
}
