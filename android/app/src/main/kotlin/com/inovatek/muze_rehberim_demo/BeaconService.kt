package com.inovatek.muze_rehberim_demo

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import android.app.Activity

// Beacon scanning değişkenleri
private var isBeaconScanning = false
private val beaconScanResults: MutableMap<String, BeaconDevice> = mutableMapOf()

// Beacon device data class
data class BeaconDevice(
    val uuid: String,
    val major: Int,
    val minor: Int,
    val rssi: Int,
    val distance: Double?,
    val proximity: BeaconProximity,
    val address: String,
    val timestamp: Long = System.currentTimeMillis()
)

enum class BeaconProximity {
    IMMEDIATE,  // 0-0.5m
    NEAR,       // 0.5-3m  
    FAR,        // 3m+
    UNKNOWN     // Cannot determine
}

class BeaconHandler(
    private val context: Context,
    private var activity: Activity?,
    private val channel: MethodChannel
) : MethodCallHandler {
    
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    
    private var pendingResult: Result? = null

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1001
    }

    init {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Beacon methods
            "isBeaconSupported" -> result.success(bluetoothLeScanner != null)
            "startBeaconScanning" -> startBeaconScanning(call, result)
            "stopBeaconScanning" -> stopBeaconScanning(result)
            "requestLocationPermission" -> requestLocationPermission(result)
            
            else -> result.notImplemented()
        }
    }

    // Activity güncellemesi için
    fun updateActivity(newActivity: Activity?) {
        activity = newActivity
    }

    // İzin sonuçlarını işlemek için
    fun handlePermissionResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingResult?.success(granted)
                pendingResult = null
                return true
            }
        }
        return false
    }

    // Cleanup method
    fun cleanup() {
        stopBeaconScanningInternal()
    }

    private fun startBeaconScanning(call: MethodCall, result: Result) {
        android.util.Log.d("BeaconHandler", "🔍 Starting beacon scanning...")
        
        if (!checkLocationPermissions()) {
            android.util.Log.e("BeaconHandler", "❌ Location permissions not granted")
            result.error("PERMISSION_DENIED", "Location permissions not granted", null)
            return
        }
        
        if (!checkBlePermissions()) {
            android.util.Log.e("BeaconHandler", "❌ BLE permissions not granted") 
            result.error("PERMISSION_DENIED", "BLE permissions not granted", null)
            return
        }
        
        if (bluetoothAdapter?.isEnabled != true) {
            android.util.Log.e("BeaconHandler", "❌ Bluetooth is not enabled")
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
            return
        }
        
        if (isBeaconScanning) {
            android.util.Log.d("BeaconHandler", "⚠️ Already scanning beacons")
            result.success(null)
            return
        }
        
        val scanTimeout: Int? = call.argument("timeout")
        val targetUuids: List<String>? = call.argument("uuids")
        
        android.util.Log.d("BeaconHandler", "🎯 Scan timeout: ${scanTimeout}ms")
        android.util.Log.d("BeaconHandler", "🎯 Target UUIDs: $targetUuids")
        
        try {
            beaconScanResults.clear()
            
            val scanSettings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .setReportDelay(0L)
                .build()
            
            val scanFilters: MutableList<ScanFilter> = mutableListOf()
            
            // inside startBeaconScanning, replace your setServiceUuid block with this:

            val APPLE_MANUFACTURER_ID = 0x004C

            targetUuids?.forEach { uuidString ->
                try {
                    val uuid = UUID.fromString(uuidString)
                    val uuidBytes = uuidToBytes(uuid) // sizin fonksiyonunuz

                    // iBeacon manufacturer payload = 0x02, 0x15, <16-byte-uuid>, <major(2)>, <minor(2)>, <txPower(1)>
                    // For filtering by UUID we create a data array starting with 0x02,0x15 + uuidBytes
                    val data = ByteArray(2 + uuidBytes.size)
                    data[0] = 0x02
                    data[1] = 0x15
                    System.arraycopy(uuidBytes, 0, data, 2, uuidBytes.size)

                    // mask: 0xFF for bytes we want to match (everything in `data`)
                    val mask = ByteArray(data.size) { 0xFF.toByte() }

                    scanFilters.add(
                        ScanFilter.Builder()
                            .setManufacturerData(APPLE_MANUFACTURER_ID, data, mask)
                            .build()
                    )

                    android.util.Log.d("BeaconHandler", "🎯 Added iBeacon manufacturer UUID filter: $uuidString")
                } catch (e: Exception) {
                    android.util.Log.w("BeaconHandler", "⚠️ Invalid UUID format: $uuidString")
                }
            }

            
            if (scanFilters.isEmpty()) {
                android.util.Log.d("BeaconHandler", "🎯 Using general BLE scan for beacons")
            }
            
            isBeaconScanning = true
            bluetoothLeScanner?.startScan(scanFilters.takeIf { it.isNotEmpty() }, scanSettings, beaconScanCallback)
            
            android.util.Log.d("BeaconHandler", "✅ Beacon scanning started successfully")
            
            scanTimeout?.let { timeoutMs ->
                Handler(Looper.getMainLooper()).postDelayed({
                    if (isBeaconScanning) {
                        android.util.Log.d("BeaconHandler", "⏰ Beacon scan timeout reached")
                        stopBeaconScanningInternal()
                        channel.invokeMethod("onBeaconScanTimeout", null)
                    }
                }, timeoutMs.toLong())
            }
            
            result.success(null)
            
        } catch (e: Exception) {
            android.util.Log.e("BeaconHandler", "❌ Failed to start beacon scanning", e)
            isBeaconScanning = false
            result.error("SCAN_FAILED", "Failed to start beacon scanning: ${e.message}", null)
        }
    }

    private fun stopBeaconScanning(result: Result) {
        android.util.Log.d("BeaconHandler", "🛑 Stopping beacon scanning...")
        
        val wasScanningBefore = isBeaconScanning
        stopBeaconScanningInternal()
        
        android.util.Log.d("BeaconHandler", "✅ Beacon scanning stopped (was scanning: $wasScanningBefore)")
        result.success(null)
    }

    private fun stopBeaconScanningInternal() {
        if (isBeaconScanning) {
            try {
                bluetoothLeScanner?.stopScan(beaconScanCallback)
                android.util.Log.d("BeaconHandler", "BLE scan stopped")
            } catch (e: Exception) {
                android.util.Log.w("BeaconHandler", "Error stopping BLE scan: ${e.message}")
            }
            
            isBeaconScanning = false
            
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onBeaconScanFinished", mapOf(
                    "totalBeaconsFound" to beaconScanResults.size,
                    "scanDuration" to System.currentTimeMillis()
                ))
            }
        }
    }

    private val beaconScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            try {
                val scanRecord = result.scanRecord
                val device = result.device
                val rssi = result.rssi
                
                android.util.Log.d("BeaconHandler", "📡 BLE scan result from ${device.address}, RSSI: $rssi")
                
                val manufacturerData = scanRecord?.manufacturerSpecificData
                var beacon: BeaconDevice? = null
                
                if (manufacturerData != null) {
                    for (i in 0 until manufacturerData.size()) {
                        val manufacturerId = manufacturerData.keyAt(i)
                        val data = manufacturerData.valueAt(i)
                        
                        android.util.Log.d("BeaconHandler", "📡 Manufacturer ID: 0x${manufacturerId.toString(16)}, Data length: ${data?.size ?: 0}")
                        
                        if (data != null && data.size >= 23) {
                            beacon = parseIBeaconFromManufacturerData(data, device.address, rssi, manufacturerId)
                            if (beacon != null) break
                        }
                    }
                }
                
                if (beacon == null) {
                    val serviceData = scanRecord?.serviceData
                    serviceData?.forEach { (parcelUuid, data) ->
                        if (data.size >= 20) {
                            beacon = parseIBeaconFromServiceData(data, device.address, rssi, parcelUuid.uuid)
                            if (beacon != null) return@forEach
                        }
                    }
                }
                
                beacon?.let { foundBeacon ->
                    val beaconKey = "${foundBeacon.uuid}_${foundBeacon.major}_${foundBeacon.minor}"
                    
                    val existingBeacon = beaconScanResults[beaconKey]
                    val shouldNotify = existingBeacon == null || 
                                    Math.abs(existingBeacon.rssi - foundBeacon.rssi) > 3 || 
                                    (System.currentTimeMillis() - existingBeacon.timestamp) > 5000
                    
                    beaconScanResults[beaconKey] = foundBeacon
                    
                    if (shouldNotify) {
                        android.util.Log.d("BeaconHandler", "📍 Beacon found: UUID=${foundBeacon.uuid.take(8)}..., Major=${foundBeacon.major}, Minor=${foundBeacon.minor}, RSSI=${foundBeacon.rssi}, Distance=${foundBeacon.distance?.let { "%.2fm".format(it) } ?: "unknown"}")
                        
                        Handler(Looper.getMainLooper()).post {
                            val beaconData = mapOf(
                                "uuid" to foundBeacon.uuid,
                                "major" to foundBeacon.major,
                                "minor" to foundBeacon.minor,
                                "rssi" to foundBeacon.rssi,
                                "distance" to foundBeacon.distance,
                                "proximity" to foundBeacon.proximity.name.lowercase(),
                                "address" to foundBeacon.address,
                                "timestamp" to foundBeacon.timestamp
                            )
                            
                            channel.invokeMethod("onBeaconScanResult", beaconData)
                        }
                    }
                }
                
            } catch (e: Exception) {
                android.util.Log.e("BeaconHandler", "❌ Error processing beacon scan result", e)
            }
        }
        
        override fun onScanFailed(errorCode: Int) {
            android.util.Log.e("BeaconHandler", "❌ Beacon scan failed with error code: $errorCode")
            
            val errorMessage = when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "Scan already started"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "App registration failed"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported" 
                SCAN_FAILED_INTERNAL_ERROR -> "Internal error"
                SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> "Out of hardware resources"
                else -> "Unknown error ($errorCode)"
            }
            
            isBeaconScanning = false
            
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onBeaconScanError", mapOf(
                    "errorCode" to errorCode,
                    "errorMessage" to errorMessage
                ))
            }
        }
    }

    private fun parseIBeaconFromManufacturerData(data: ByteArray, address: String, rssi: Int, manufacturerId: Int): BeaconDevice? {
        try {
            if (data.size >= 23 && data[0] == 0x02.toByte() && data[1] == 0x15.toByte()) {
                return parseIBeaconData(data, address, rssi, 2)
            }
            
            if (data.size >= 21) {
                return parseIBeaconData(data, address, rssi, 0)
            }
            
            return null
            
        } catch (e: Exception) {
            android.util.Log.e("BeaconHandler", "❌ Failed to parse manufacturer beacon data", e)
            return null
        }
    }

    private fun parseIBeaconFromServiceData(data: ByteArray, address: String, rssi: Int, serviceUuid: UUID): BeaconDevice? {
        try {
            val uuid = serviceUuid.toString().uppercase()
            
            val major = if (data.size >= 2) {
                ((data[0].toUByte().toInt() shl 8) or data[1].toUByte().toInt())
            } else 0
            
            val minor = if (data.size >= 4) {
                ((data[2].toUByte().toInt() shl 8) or data[3].toUByte().toInt())
            } else 0
            
            val txPower = if (data.size >= 5) data[4].toInt() else -59
            
            val distance = calculateDistance(rssi, txPower)
            val proximity = calculateProximity(distance)
            
            android.util.Log.d("BeaconHandler", "🔍 Parsed service beacon - UUID: $uuid, Major: $major, Minor: $minor")
            
            return BeaconDevice(
                uuid = uuid,
                major = major,
                minor = minor,
                rssi = rssi,
                distance = distance,
                proximity = proximity,
                address = address
            )
            
        } catch (e: Exception) {
            android.util.Log.e("BeaconHandler", "❌ Failed to parse service beacon data", e)
            return null
        }
    }

    private fun parseIBeaconData(data: ByteArray, address: String, rssi: Int, uuidStartIndex: Int): BeaconDevice? {
        try {
            if (data.size < uuidStartIndex + 20) return null
            
            val uuidBytes = data.sliceArray(uuidStartIndex until uuidStartIndex + 16)
            val uuid = bytesToUuid(uuidBytes).toString().uppercase()
            
            val majorIndex = uuidStartIndex + 16
            val major = if (data.size >= majorIndex + 2) {
                ((data[majorIndex].toUByte().toInt() shl 8) or data[majorIndex + 1].toUByte().toInt())
            } else 0
            
            val minorIndex = majorIndex + 2
            val minor = if (data.size >= minorIndex + 2) {
                ((data[minorIndex].toUByte().toInt() shl 8) or data[minorIndex + 1].toUByte().toInt())
            } else 0
            
            val txPowerIndex = minorIndex + 2
            val txPower = if (data.size > txPowerIndex) data[txPowerIndex].toInt() else -59
            
            val distance = calculateDistance(rssi, txPower)
            val proximity = calculateProximity(distance)
            
            android.util.Log.d("BeaconHandler", "🔍 Parsed beacon - UUID: ${uuid.take(8)}..., Major: $major, Minor: $minor, TxPower: $txPower")
            
            return BeaconDevice(
                uuid = uuid,
                major = major,
                minor = minor,
                rssi = rssi,
                distance = distance,
                proximity = proximity,
                address = address
            )
            
        } catch (e: Exception) {
            android.util.Log.e("BeaconHandler", "❌ Failed to parse beacon data", e)
            return null
        }
    }

    private fun uuidToBytes(uuid: UUID): ByteArray {
        val buffer = ByteArray(16)
        val mostSigBits = uuid.mostSignificantBits
        val leastSigBits = uuid.leastSignificantBits
        
        for (i in 0..7) {
            buffer[i] = (mostSigBits shr (8 * (7 - i))).toByte()
            buffer[8 + i] = (leastSigBits shr (8 * (7 - i))).toByte()
        }
        
        return buffer
    }

    private fun bytesToUuid(bytes: ByteArray): UUID {
        if (bytes.size != 16) throw IllegalArgumentException("UUID bytes must be 16 bytes")
        
        var mostSigBits = 0L
        var leastSigBits = 0L
        
        for (i in 0..7) {
            mostSigBits = (mostSigBits shl 8) or (bytes[i].toUByte().toLong())
            leastSigBits = (leastSigBits shl 8) or (bytes[8 + i].toUByte().toLong())
        }
        
        return UUID(mostSigBits, leastSigBits)
    }

    private fun calculateDistance(rssi: Int, txPower: Int): Double? {
    return try {
        if (rssi == 0) {
            null // ölçülemiyor
        } else {
            val pathLossExponent = 2.2 // 2.0 = açık alan, 2.2-3.5 iç mekan
            val distance = Math.pow(10.0, ((txPower - rssi).toDouble()) / (10 * pathLossExponent))
            // Aşırı düşük değerleri (yakında) clamp et
            if (distance < 0.1) 0.1 else distance
        }
    } catch (e: Exception) {
        null
    }
}


    private fun calculateProximity(distance: Double?): BeaconProximity {
        return when {
            distance == null -> BeaconProximity.UNKNOWN
            distance < 0.5 -> BeaconProximity.IMMEDIATE
            distance < 3.0 -> BeaconProximity.NEAR
            else -> BeaconProximity.FAR
        }
    }

    private fun requestLocationPermission(result: Result) {
        if (checkLocationPermissions()) {
            result.success(true)
            return
        }
        
        pendingResult = result
        activity?.let { activity ->
            val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_ADVERTISE
                )
            } else {
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.BLUETOOTH,
                    Manifest.permission.BLUETOOTH_ADMIN
                )
            }
            
            ActivityCompat.requestPermissions(
                activity,
                permissions,
                LOCATION_PERMISSION_REQUEST_CODE
            )
        } ?: result.success(false)
    }

    // === Permission Check Methods ===

    private fun checkBlePermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasScan = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val hasConnect = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            hasScan && hasConnect
        } else {
            val hasBluetooth = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED
            val hasAdmin = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
            hasBluetooth && hasAdmin
        }
    }

    private fun checkLocationPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
               ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }
}