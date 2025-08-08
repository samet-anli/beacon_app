import 'dart:async';
import 'models/beacon_model.dart';
import 'beacon_service_platform_interface.dart';

class BeaconService {
  static BeaconServcePlatform get _platform =>
      BeaconServcePlatform.instance;

  // Burası iOS'un bilinmeyen mesafe göndermesine yönelik bir önlemdir.
  // Beacon'lar için en son bilinen geçerli verileri bu haritada saklıyoruz.
  static final Map<String, BeaconDevice> _lastKnownBeacons = {};

  /// iBeacon Methods

  /// Check if iBeacon is supported
  static Future<bool> get isBeaconSupported => _platform.isBeaconSupported;

  /// Start scanning for iBeacons
  static Future<void> startBeaconScanning({List<String>? uuids}) =>
      _platform.startBeaconScanning(uuids: uuids);

  /// Stop beacon scanning
  static Future<void> stopBeaconScanning() => _platform.stopBeaconScanning();

  /// Get stream of discovered beacons
  static Stream<BeaconDevice> get beaconScanResults {
    // Platformdan gelen ham veriyi dinleyen bir Stream oluştururuz.
    return _platform.beaconScanResults.map((receivedBeacon) {
      // Beacon'ın kimliğini oluşturmak için benzersiz bir anahtar
      final beaconKey = '${receivedBeacon.uuid}-${receivedBeacon.major}-${receivedBeacon.minor}';

      // Eğer gelen beacon'ın mesafesi bilinmeyen (-1.0) ise
      if (receivedBeacon.distance == -1.0 || receivedBeacon.rssi == 0) {
        // Bu beacon için son bilinen bir değer var mı kontrol et
        if (_lastKnownBeacons.containsKey(beaconKey)) {
          // Varsa, en son bilinen geçerli veriyi kullanarak yeni bir BeaconDevice oluştur ve döndür.
          // Bu, uygulamanızda kesintisiz bir veri akışı sağlar.
          return BeaconDevice(
            uuid: receivedBeacon.uuid,
            major: receivedBeacon.major,
            minor: receivedBeacon.minor,
            rssi: _lastKnownBeacons[beaconKey]!.rssi,
            distance: _lastKnownBeacons[beaconKey]!.distance,
            proximity: _lastKnownBeacons[beaconKey]!.proximity,
          );
        }
      }

      // Gelen verinin mesafesi geçerliyse (yani -1.0 değilse) veya
      // önbellekte bu beacon için bir değer yoksa,
      // bu geçerli değeri önbelleğe al ve olduğu gibi döndür.
      _lastKnownBeacons[beaconKey] = receivedBeacon;
      return receivedBeacon;
    });
  }

  /// Request location permissions (required for beacon scanning)
  static Future<bool> requestLocationPermission() =>
      _platform.requestLocationPermission();
}