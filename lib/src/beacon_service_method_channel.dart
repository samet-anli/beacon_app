import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/beacon_model.dart';
import 'beacon_service_platform_interface.dart';

class MethodChannelBeaconService extends BeaconServcePlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('beacon_service');

  // Beacon scan results controller
  final _beaconScanResultsController =
      StreamController<BeaconDevice>.broadcast();

  MethodChannelBeaconService() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('Flutter: Received method call: ${call.method}');

    try {
      switch (call.method) {
        case 'onBeaconScanResult':
          final arguments = call.arguments as Map<Object?, Object?>;
          print('🔥 onBeaconScanResult tetiklendi');
          print('🔥 Arguments: ${call.arguments}');
          final Map<String, dynamic> safeArguments = Map<String, dynamic>.from(
            arguments,
          );
          final result = BeaconDevice.fromMap(safeArguments);
          _beaconScanResultsController.add(result);
          break;

        default:
          print('Flutter: Unknown method call: ${call.method}');
          break;
      }
    } catch (e, stackTrace) {
      print('Flutter: Error processing method call ${call.method}: $e');
      print('Flutter: Stack trace: $stackTrace');
      print('Flutter: Arguments: ${call.arguments}');
    }
  }

  // iBeacon methods
  @override
  Future<bool> get isBeaconSupported async {
    final result = await methodChannel.invokeMethod<bool>('isBeaconSupported');
    return result ?? false;
  }

  @override
  Future<void> startBeaconScanning({List<String>? uuids}) async {
    await methodChannel.invokeMethod('startBeaconScanning', {'uuids': uuids});
  }

  @override
  Future<void> stopBeaconScanning() async {
    await methodChannel.invokeMethod('stopBeaconScanning');
  }

  @override
  Stream<BeaconDevice> get beaconScanResults =>
      _beaconScanResultsController.stream;

  @override
  Future<bool> requestLocationPermission() async {
    final result = await methodChannel.invokeMethod<bool>(
      'requestLocationPermission',
    );
    return result ?? false;
  }
}