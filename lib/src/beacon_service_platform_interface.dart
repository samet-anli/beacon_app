// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models/beacon_model.dart';
import 'beacon_service_method_channel.dart';

abstract class BeaconServcePlatform extends PlatformInterface {
  BeaconServcePlatform() : super(token: _token);

  static final Object _token = Object();

  static BeaconServcePlatform _instance =
      MethodChannelBeaconService();

  static BeaconServcePlatform get instance => _instance;

  static set instance(BeaconServcePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // iBeacon Methods
  Future<bool> get isBeaconSupported;
  Future<void> startBeaconScanning({List<String>? uuids});
  Future<void> stopBeaconScanning();
  Stream<BeaconDevice> get beaconScanResults;
  Future<bool> requestLocationPermission();
}