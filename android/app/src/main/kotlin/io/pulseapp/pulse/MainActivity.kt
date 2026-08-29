package io.pulseapp.pulse

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

private const val TAG = "PulseBlePeripheral"
private const val CHANNEL_NAME = "app.pulse.ble/peripheral"
private const val MIC_METHOD_CHANNEL = "app.pulse.audio/mic"
private const val MIC_EVENT_CHANNEL = "app.pulse.audio/micStream"
private const val TORCH_CHANNEL = "app.pulse.audio/torch"
private const val MIC_PERMISSION_REQUEST = 4242
private const val CAMERA_PERMISSION_REQUEST = 4243
private const val MIC_SAMPLE_RATE = 22_050

// GATT UUIDs — must match lib/features/transport/ble/ble_uuids.dart exactly.
// These are part of the public over-the-air contract; never rename.
private val SERVICE_UUID =
    UUID.fromString("0000feed-0000-1000-8000-00805f9b34fb")
private val TX_CHAR_UUID =
    UUID.fromString("a1c1feed-0001-4001-8000-00805f9b34fb")
private val RX_CHAR_UUID =
    UUID.fromString("a1c1feed-0002-4001-8000-00805f9b34fb")

private const val CCC_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"

class MainActivity : FlutterActivity() {

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var gattServer: BluetoothGattServer? = null
    private var advertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null

    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null

    // Track which central has subscribed to TX notifications.
    private val subscribedCentrals = mutableSetOf<BluetoothDevice>()

    private val mainHandler = Handler(Looper.getMainLooper())

    private var methodChannel: MethodChannel? = null
    private var micEventSink: EventChannel.EventSink? = null
    @Volatile private var micRecording = false
    @Volatile private var audioRecord: AudioRecord? = null
    private var micThread: Thread? = null
    private var pendingTorchResult: MethodChannel.Result? = null
    private var torchCameraId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    startAdvertising()
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMic" -> {
                        startMicOrRequestPermission()
                        result.success(null)
                    }
                    "stopMic" -> {
                        stopMic()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    micEventSink = events
                    startMicOrRequestPermission()
                }

                override fun onCancel(arguments: Any?) {
                    stopMic()
                    micEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TORCH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasTorch" -> result.success(findTorchCameraId() != null)
                    "startTorch" -> startTorchOrRequestPermission(result)
                    "stopTorch" -> {
                        setTorch(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startMicOrRequestPermission() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                MIC_PERMISSION_REQUEST,
            )
            return
        }
        startMic()
    }

    @SuppressLint("MissingPermission")
    private fun startMic() {
        if (micRecording) return
        val minBuffer = AudioRecord.getMinBufferSize(
            MIC_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            micEventSink?.error("mic_unavailable", "Invalid audio buffer size", null)
            return
        }
        val bufferSize = maxOf(minBuffer, 4096)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            MIC_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize,
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            micEventSink?.error("mic_unavailable", "AudioRecord failed to initialise", null)
            return
        }

        try {
            recorder.startRecording()
        } catch (error: RuntimeException) {
            recorder.release()
            micEventSink?.error("mic_start_failed", error.message, null)
            return
        }

        audioRecord = recorder
        micRecording = true
        micThread = Thread({
            val buffer = ByteArray(bufferSize)
            while (micRecording) {
                val count = recorder.read(buffer, 0, buffer.size)
                if (count > 0) {
                    val chunk = buffer.copyOf(count)
                    mainHandler.post {
                        if (micRecording) micEventSink?.success(chunk)
                    }
                } else if (count == AudioRecord.ERROR_DEAD_OBJECT) {
                    break
                }
            }
        }, "PulseMicRecorder").also { it.start() }
    }

    private fun stopMic() {
        micRecording = false
        val recorder = audioRecord
        audioRecord = null
        try {
            recorder?.stop()
        } catch (_: IllegalStateException) {
            // The recorder may already have stopped after an audio-route change.
        }
        recorder?.release()
        val thread = micThread
        micThread = null
        if (thread != null && thread !== Thread.currentThread()) {
            try {
                thread.join(250)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }

    private fun findTorchCameraId(): String? {
        torchCameraId?.let { return it }
        return try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val candidates = manager.cameraIdList.filter { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
            val backCamera = candidates.firstOrNull { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            }
            (backCamera ?: candidates.firstOrNull()).also { torchCameraId = it }
        } catch (error: Exception) {
            Log.w(TAG, "Torch probe failed", error)
            null
        }
    }

    private fun startTorchOrRequestPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingTorchResult?.error(
                "torch_request_replaced",
                "A newer torch request replaced this one",
                null,
            )
            pendingTorchResult = result
            requestPermissions(
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST,
            )
            return
        }
        setTorch(true)
        result.success(null)
    }

    private fun setTorch(enabled: Boolean) {
        val cameraId = findTorchCameraId() ?: return
        try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            manager.setTorchMode(cameraId, enabled)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to set torch=$enabled", error)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            MIC_PERMISSION_REQUEST -> {
                if (granted) {
                    startMic()
                } else {
                    micEventSink?.error(
                        "mic_permission_denied",
                        "Microphone permission was denied",
                        null,
                    )
                }
            }
            CAMERA_PERMISSION_REQUEST -> {
                val result = pendingTorchResult
                pendingTorchResult = null
                if (granted) {
                    setTorch(true)
                    result?.success(null)
                } else {
                    result?.error(
                        "camera_permission_denied",
                        "Camera permission is required for the torch",
                        null,
                    )
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising() {
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        if (bluetoothAdapter == null || bluetoothAdapter?.bluetoothLeAdvertiser == null) {
            Log.w(TAG, "Device does not support BLE advertising")
            return
        }

        if (!hasBlePermissions()) {
            Log.w(TAG, "BLE permissions not granted")
            return
        }

        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        startGattServer()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0) // advertise until stopped
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val advertiseData = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()

        val scanResponseData = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        advertiser?.startAdvertising(settings, advertiseData, scanResponseData, advertiseCallback)
        Log.i(TAG, "Started advertising Pulse GATT service")
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.i(TAG, "Advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "Advertising failed to start: errorCode=$errorCode")
        }
    }

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        val server = bluetoothManager?.openGattServer(this, gattServerCallback)
        if (server == null) {
            Log.e(TAG, "Failed to open GATT server")
            return
        }

        // TX characteristic — peripheral writes here, central reads via notify.
        txCharacteristic = BluetoothGattCharacteristic(
            TX_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        ).apply {
            // Notification CCC descriptor.
            addDescriptor(
                BluetoothGattDescriptor(
                    UUID.fromString(CCC_DESCRIPTOR_UUID),
                    BluetoothGattDescriptor.PERMISSION_READ or
                        BluetoothGattDescriptor.PERMISSION_WRITE,
                ).apply {
                    value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                }
            )
        }

        // RX characteristic — central writes here.
        rxCharacteristic = BluetoothGattCharacteristic(
            RX_CHAR_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )

        val service = BluetoothGattService(
            SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        ).apply {
            addCharacteristic(txCharacteristic)
            addCharacteristic(rxCharacteristic)
        }

        server.addService(service)
        gattServer = server
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            when (newState) {
                BluetoothGattServer.STATE_CONNECTED -> {
                    Log.i(TAG, "Central connected: ${device?.address}")
                    mainHandler.post {
                        methodChannel?.invokeMethod("onCentralConnected", null)
                    }
                }
                BluetoothGattServer.STATE_DISCONNECTED -> {
                    Log.i(TAG, "Central disconnected")
                    subscribedCentrals.clear()
                    mainHandler.post {
                        methodChannel?.invokeMethod("onCentralDisconnected", null)
                    }
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic?,
        ) {
            if (characteristic?.uuid == TX_CHAR_UUID) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, ByteArray(0))
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (characteristic?.uuid == RX_CHAR_UUID && value != null) {
                // Central → peripheral data received. Forward to Flutter.
                mainHandler.post {
                    methodChannel?.invokeMethod("onDataReceived", mapOf("data" to value))
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
            }
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            descriptor: BluetoothGattDescriptor?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (descriptor?.uuid == UUID.fromString(CCC_DESCRIPTOR_UUID)) {
                if (value?.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == true) {
                    device?.let { subscribedCentrals.add(it) }
                } else if (value?.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE) == true) {
                    device?.let { subscribedCentrals.remove(it) }
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun sendToCentral(data: ByteArray) {
        val tx = txCharacteristic ?: return
        tx.value = data
        for (central in subscribedCentrals) {
            gattServer?.notifyCharacteristicChanged(central, tx, false)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertising() {
        advertiser?.stopAdvertising(advertiseCallback)
        gattServer?.close()
        gattServer = null
        advertiser = null
        subscribedCentrals.clear()
        Log.i(TAG, "Stopped advertising and closed GATT server")
    }

    @Suppress("DEPRECATION")
    private fun hasBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    override fun onDestroy() {
        stopMic()
        setTorch(false)
        pendingTorchResult?.error("activity_destroyed", "Activity destroyed", null)
        pendingTorchResult = null
        stopAdvertising()
        super.onDestroy()
    }
}
