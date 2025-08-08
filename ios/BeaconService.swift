import Flutter
import UIKit
import CoreLocation

public class BeaconService: NSObject {
    private var channel: FlutterMethodChannel?
    private var locationManager: CLLocationManager?
    
    // Beacon scanning state
    private var isBeaconScanning = false
    
    // For async operations
    private var pendingResult: FlutterResult?
    
    // Cache for last known beacon values
    private var lastKnownBeacons: [String: [String: Any]] = [:]
    
    // Signal strength optimization settings
    private var signalStrengthMultiplier: Double = 1.6  // Artırılabilir değer
    private var minimumAccuracy: Double = 0.1  // Minimum mesafe değeri
    private var maxReportableDistance: Double = 50.0  // Maksimum rapor edilebilir mesafe
    
    // Singleton instance
    static let shared = BeaconService()
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // Initialize with Flutter binary messenger
    func initialize(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "beacon_service", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("iOS: Received method call: \(call.method)")
        
        switch call.method {
        // iBeacon methods
        case "isBeaconSupported":
            result(CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self))
        case "startBeaconScanning":
            startBeaconScanning(call: call, result: result)
        case "stopBeaconScanning":
            stopBeaconScanning(result: result)
        case "requestLocationPermission":
            requestLocationPermission(result: result)
        
        // Signal optimization methods
        case "setSignalOptimization":
            setSignalOptimization(call: call, result: result)
        case "clearBeaconCache":
            clearBeaconCache(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - iBeacon Methods
    
    private func startBeaconScanning(call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("iOS: startBeaconScanning called")
        
        let authStatus = CLLocationManager.authorizationStatus()
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            NSLog("iOS: Location permission not granted for beacon scanning")
            result(FlutterError(code: "PERMISSION_DENIED", 
                            message: "Location permission not granted for beacon scanning", 
                            details: nil))
            return
        }
        
        guard CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) else {
            NSLog("iOS: Beacon monitoring not supported on this device")
            result(FlutterError(code: "NOT_SUPPORTED", 
                            message: "Beacon monitoring not supported on this device", 
                            details: nil))
            return
        }
        
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", 
                            message: "Invalid arguments for beacon scanning", 
                            details: nil))
            return
        }
        
        let uuids = args["uuids"] as? [String]
        
        if isBeaconScanning {
            stopBeaconScanningInternal()
        }
        
        if let uuidStrings = uuids, !uuidStrings.isEmpty {
            NSLog("iOS: Starting beacon scanning for \(uuidStrings.count) UUID(s)")
            
            for uuidString in uuidStrings {
                if let uuid = UUID(uuidString: uuidString) {
                    NSLog("iOS: Setting up monitoring and ranging for UUID: \(uuidString)")
                    
                    let region = CLBeaconRegion(proximityUUID: uuid, 
                                            identifier: "BeaconRegion_\(uuid.uuidString)")
                    region.notifyOnEntry = true
                    region.notifyOnExit = true
                    region.notifyEntryStateOnDisplay = true
                    
                    locationManager?.startMonitoring(for: region)
                    
                    if #available(iOS 13.0, *) {
                        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
                        locationManager?.startRangingBeacons(satisfying: constraint)
                    } else {
                        locationManager?.startRangingBeacons(in: region)
                    }
                } else {
                    NSLog("iOS: Invalid UUID format: \(uuidString)")
                }
            }
            
            isBeaconScanning = true
            NSLog("iOS: ✅ Beacon scanning started successfully")
            result(true)
        } else {
            NSLog("iOS: No UUIDs provided - this is not recommended for production apps")
            result(FlutterError(code: "NO_UUIDS", 
                            message: "No beacon UUIDs provided for scanning", 
                            details: nil))
        }
    }

    
    private func stopBeaconScanning(result: @escaping FlutterResult) {
        NSLog("iOS: stopBeaconScanning called")
        
        if isBeaconScanning {
            stopBeaconScanningInternal()
            NSLog("iOS: ✅ Beacon scanning stopped")
            result(true)
        } else {
            NSLog("iOS: Beacon scanning was not active")
            result(false)
        }
    }

    
    private func stopBeaconScanningInternal() {
        if isBeaconScanning {
            NSLog("iOS: Stopping beacon monitoring and ranging...")
            
            for region in locationManager?.monitoredRegions ?? [] {
                locationManager?.stopMonitoring(for: region)
                NSLog("iOS: Stopped monitoring for region: \(region.identifier)")
                
                if let beaconRegion = region as? CLBeaconRegion {
                    if #available(iOS 13.0, *) {
                        let constraint = CLBeaconIdentityConstraint(uuid: beaconRegion.proximityUUID)
                        locationManager?.stopRangingBeacons(satisfying: constraint)
                    } else {
                        locationManager?.stopRangingBeacons(in: beaconRegion)
                    }
                    NSLog("iOS: Stopped ranging beacons for UUID: \(beaconRegion.proximityUUID.uuidString)")
                }
            }
            
            isBeaconScanning = false
        }
    }

    private func requestLocationPermission(result: @escaping FlutterResult) {
        NSLog("iOS: requestLocationPermission called")
        
        let status = CLLocationManager.authorizationStatus()
        NSLog("iOS: Current location permission status: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways:
            NSLog("iOS: Location permission already granted (Always)")
            result(true)
        case .authorizedWhenInUse:
            NSLog("iOS: Location permission already granted (When In Use)")
            result(true)
        case .notDetermined:
            NSLog("iOS: Location permission not determined - requesting...")
            pendingResult = result
            locationManager?.requestWhenInUseAuthorization()
        case .denied:
            NSLog("iOS: Location permission denied")
            result(false)
        case .restricted:
            NSLog("iOS: Location permission restricted")
            result(false)
        @unknown default:
            NSLog("iOS: Unknown location permission status")
            result(false)
        }
    }
    
    // MARK: - Signal Optimization Methods
    
    private func setSignalOptimization(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        if let multiplier = args["signalMultiplier"] as? Double {
            signalStrengthMultiplier = multiplier
            NSLog("iOS: Signal strength multiplier set to: \(multiplier)")
        }
        
        if let minAccuracy = args["minimumAccuracy"] as? Double {
            minimumAccuracy = minAccuracy
            NSLog("iOS: Minimum accuracy set to: \(minAccuracy)")
        }
        
        if let maxDistance = args["maxReportableDistance"] as? Double {
            maxReportableDistance = maxDistance
            NSLog("iOS: Max reportable distance set to: \(maxDistance)")
        }
        
        result(true)
    }
    
    private func clearBeaconCache(result: @escaping FlutterResult) {
        lastKnownBeacons.removeAll()
        NSLog("iOS: Beacon cache cleared")
        result(true)
    }
    
    private func optimizeDistance(_ originalDistance: Double, rssi: Int) -> Double {
        // Negatif RSSI değerini pozitife çevir ve optimize et
        let adjustedRssi = abs(rssi)
        
        // Düşük sinyal gücü için mesafe optimizasyonu
        var optimizedDistance = originalDistance
        
        // Sinyal gücü çok düşükse (RSSI > 80) mesafeyi ayarla
        if adjustedRssi > 80 {
            optimizedDistance = originalDistance * signalStrengthMultiplier
        } else if adjustedRssi > 70 {
            optimizedDistance = originalDistance * (signalStrengthMultiplier * 0.8)
        }
        
        // Minimum ve maksimum değerleri kontrol et
        optimizedDistance = max(minimumAccuracy, optimizedDistance)
        optimizedDistance = min(maxReportableDistance, optimizedDistance)
        
        return optimizedDistance
    }
    
    private func getBeaconKey(uuid: String, major: Int, minor: Int) -> String {
        return "\(uuid)_\(major)_\(minor)"
    }
    
    private func processBeaconData(uuid: String, major: Int, minor: Int, rssi: Int,
                               originalDistance: Double, proximity: String) -> [String: Any] {
        let beaconKey = getBeaconKey(uuid: uuid, major: major, minor: minor)

        var finalDistance = originalDistance
        var finalProximity = proximity
        var finalRssi = rssi

        // Unknown ya da anlamsız mesafe kontrolü
        let isInvalidDistance = originalDistance < 0 || originalDistance > maxReportableDistance || proximity == "unknown"

        if isInvalidDistance {
            if let lastKnown = lastKnownBeacons[beaconKey] {
                finalDistance = lastKnown["distance"] as? Double ?? max(minimumAccuracy, 0.0)
                finalProximity = lastKnown["proximity"] as? String ?? "far"
                finalRssi = lastKnown["rssi"] as? Int ?? rssi

                NSLog("iOS: 🔄 Using cached values for beacon \(beaconKey) - Distance: \(finalDistance), Proximity: \(finalProximity)")
            } else {
                // Cache yoksa default değer ata
                finalDistance = max(minimumAccuracy, 0.0)
                finalProximity = "far"
            }
        } else {
            // Geçerli veri varsa optimize et ve cache'le
            finalDistance = optimizeDistance(originalDistance, rssi: rssi)
            finalRssi = rssi

            // Proximity'i mesafeye göre yeniden hesapla
            if finalDistance < 1.0 {
                finalProximity = "immediate"
            } else if finalDistance < 3.0 {
                finalProximity = "near"
            } else {
                finalProximity = "far"
            }

            // Cache'e kaydet
            lastKnownBeacons[beaconKey] = [
                "distance": finalDistance,
                "proximity": finalProximity,
                "rssi": finalRssi,
                "lastUpdate": Date().timeIntervalSince1970
            ]

            NSLog("iOS: 💾 Cached beacon \(beaconKey) - Distance: \(finalDistance), Proximity: \(finalProximity)")
        }

        return [
            "uuid": uuid,
            "major": major,
            "minor": minor,
            "rssi": finalRssi,
            "distance": finalDistance,
            "proximity": finalProximity,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
    }

}

// MARK: - CLLocationManagerDelegate

extension BeaconService: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        NSLog("iOS: Location authorization status changed to: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            pendingResult?(true)
        case .denied, .restricted:
            pendingResult?(false)
        case .notDetermined:
            // Wait for user decision
            break
        @unknown default:
            pendingResult?(false)
        }
        
        if status != .notDetermined {
            pendingResult = nil
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        NSLog("iOS: Ranged \(beacons.count) beacons in region: \(region.identifier)")
        
        for beacon in beacons {
            let proximity: String
            switch beacon.proximity {
            case .immediate:
                proximity = "immediate"
            case .near:
                proximity = "near"
            case .far:
                proximity = "far"
            case .unknown:
                proximity = "unknown"
            @unknown default:
                proximity = "unknown"
            }
            
            let beaconData = processBeaconData(
                uuid: beacon.proximityUUID.uuidString,
                major: beacon.major.intValue,
                minor: beacon.minor.intValue,
                rssi: beacon.rssi,
                originalDistance: beacon.accuracy,
                proximity: proximity
            )
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconScanResult", arguments: beaconData)
            }
        }
    }
    
    @available(iOS 13.0, *)
    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        NSLog("iOS: Ranged \(beacons.count) beacons satisfying constraint")
        
        for beacon in beacons {
            let proximity: String
            switch beacon.proximity {
            case .immediate:
                proximity = "immediate"
            case .near:
                proximity = "near"
            case .far:
                proximity = "far"
            case .unknown:
                proximity = "unknown"
            @unknown default:
                proximity = "unknown"
            }
            
            let beaconData = processBeaconData(
                uuid: beacon.proximityUUID.uuidString,
                major: beacon.major.intValue,
                minor: beacon.minor.intValue,
                rssi: beacon.rssi,
                originalDistance: beacon.accuracy,
                proximity: proximity
            )
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconScanResult", arguments: beaconData)
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NSLog("iOS: 📍 Entered beacon region: \(region.identifier)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            NSLog("iOS: Entered beacon region for UUID: \(beaconRegion.proximityUUID.uuidString)")
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionEntered", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        NSLog("iOS: 🚪 Exited beacon region: \(region.identifier)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            NSLog("iOS: Exited beacon region for UUID: \(beaconRegion.proximityUUID.uuidString)")
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionExited", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let stateString: String
        switch state {
        case .inside:
            stateString = "inside"
        case .outside:
            stateString = "outside"
        case .unknown:
            stateString = "unknown"
        @unknown default:
            stateString = "unknown"
        }
        
        NSLog("iOS: 📍 Region state determined: \(region.identifier) - \(stateString)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionState", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "state": stateString,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        NSLog("iOS: ❌ Ranging beacons failed for region \(region.identifier): \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onBeaconRangingError", arguments: [
                "uuid": region.proximityUUID.uuidString,
                "identifier": region.identifier,
                "error": error.localizedDescription,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ])
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        NSLog("iOS: ❌ Monitoring failed for region \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconMonitoringError", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region?.identifier ?? "unknown",
                    "error": error.localizedDescription,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }
}
