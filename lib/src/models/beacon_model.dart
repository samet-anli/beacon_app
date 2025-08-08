// iBeacon device
class BeaconDevice {
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final double? distance;
  final BeaconProximity proximity;

  BeaconDevice({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    this.distance,
    required this.proximity,
  });

 factory BeaconDevice.fromMap(Map<String, dynamic> map) {
  final rawProximity = (map['proximity'] as String? ?? '').trim().toLowerCase();

  return BeaconDevice(
    uuid: map['uuid'] as String? ?? '',
    major: map['major'] as int? ?? 0,
    minor: map['minor'] as int? ?? 0,
    rssi: map['rssi'] as int? ?? -999,
    distance: (map['distance'] as num?)?.toDouble(),
    proximity: BeaconProximity.values.firstWhere(
      (e) => e.name.toLowerCase() == rawProximity,
      orElse: () => BeaconProximity.unknown,
    ),
  );
}


  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'rssi': rssi,
      'distance': distance,
      'proximity': proximity.name,
    };
  }

  @override
  String toString() {
    return 'BeaconDevice(uuid: $uuid, major: $major, minor: $minor, rssi: $rssi)';
  }
}

// Enum for beacon proximity
enum BeaconProximity { immediate, near, far, unknown }