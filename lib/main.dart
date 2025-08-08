import 'package:flutter/material.dart';
import 'src/models/beacon_model.dart';
import 'src/beacon_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Scanner',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const BeaconScanner(),
    );
  }
}

class BeaconScanner extends StatefulWidget {
  const BeaconScanner({super.key});

  @override
  State<BeaconScanner> createState() => _BeaconScannerState();
}

class _BeaconScannerState extends State<BeaconScanner> {
  bool _isBeaconScanning = false;
  List<BeaconDevice> _beacons = [];
  bool _hasLocationPermissions = false;

  @override
  void initState() {
    super.initState();
    _initializeBeaconScanner();
  }

  Future<void> _initializeBeaconScanner() async {
    // İzin kontrolü ve talebi
    final hasPermissions = await _requestLocationPermissions();
    
    setState(() {
      _hasLocationPermissions = hasPermissions;
    });

    if (!hasPermissions) {
      print('Location permissions denied.');
      _showSnackBar('⚠️ Konum izni gerekli. Ayarlardan izin verin.');
      return;
    }

    _showSnackBar('✅ Beacon tarayıcı hazır!');

    // Beacon scan sonuçlarını dinle
    BeaconService.beaconScanResults.listen((beacon) {
      print("Flutter: 📡 Received beacon: ${beacon.uuid} (${beacon.major}:${beacon.minor})");
      setState(() {
        final index = _beacons.indexWhere(
          (b) =>
              b.uuid == beacon.uuid &&
              b.major == beacon.major &&
              b.minor == beacon.minor,
        );
        if (index >= 0) {
          _beacons[index] = beacon;
        } else {
          _beacons.add(beacon);
        }
        // RSSI'ye göre sırala (güçlü sinyalden zayıfa)
        _beacons.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });
  }

  Future<bool> _requestLocationPermissions() async {
    print('Konum izinleri kontrol ediliyor...');

    try {
      // iOS ve Android için gerekli izinler
      Map<Permission, PermissionStatus> permissions = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.locationAlways, // iOS için iBeacon scanning
      ].request();

      print('İzin talep sonuçları:');
      permissions.forEach((permission, status) {
        print('  ${permission.toString()}: ${status.toString()}');
      });

      // En az locationWhenInUse izni gerekli
      bool hasLocationPermission = 
          permissions[Permission.location] == PermissionStatus.granted ||
          permissions[Permission.locationWhenInUse] == PermissionStatus.granted ||
          permissions[Permission.locationAlways] == PermissionStatus.granted;

      if (!hasLocationPermission) {
        print('⚠️ Konum izinleri reddedildi.');
        _showPermissionDialog();
        return false;
      }

      print('✅ Konum izinleri onaylandı.');
      return true;
    } catch (e) {
      print('İzin talebi sırasında hata: $e');
      _showSnackBar('İzin talebi sırasında hata: $e');
      return false;
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange),
              SizedBox(width: 8),
              Text('Konum İzni Gerekli'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Beacon tarama için konum izni gereklidir:'),
              SizedBox(height: 8),
              Text('• Konum servisleri'),
              Text('• Uygulamada konum kullanımı'),
              SizedBox(height: 12),
              Text(
                'Ayarlardan izinleri etkinleştirin.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Ayarları Aç'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionStatus() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: _hasLocationPermissions
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasLocationPermissions ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasLocationPermissions ? Icons.check_circle : Icons.warning,
            color: _hasLocationPermissions ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _hasLocationPermissions 
                  ? 'Konum izinleri aktif' 
                  : 'Konum izinleri gerekli',
              style: TextStyle(
                color: _hasLocationPermissions ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          if (!_hasLocationPermissions)
            TextButton(
              onPressed: () async {
                final granted = await _requestLocationPermissions();
                setState(() {
                  _hasLocationPermissions = granted;
                });
                if (granted) {
                  _showSnackBar('✅ İzinler onaylandı!');
                }
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('İzin Ver', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleBeaconScanning() async {
    print('🌀 Beacon scanning toggle çağrıldı');
    
    // İzin kontrolü
    if (!_hasLocationPermissions) {
      final hasPermission = await _requestLocationPermissions();
      if (!hasPermission) {
        _showSnackBar('❌ Konum izni gerekli');
        return;
      }
      setState(() {
        _hasLocationPermissions = true;
      });
    }

    try {
      if (_isBeaconScanning) {
        print('🛑 Beacon scanning durduruluyor');
        await BeaconService.stopBeaconScanning();
        _showSnackBar('🛑 Beacon tarama durduruldu');
      } else {
        print('📍 Beacon scanning başlatılıyor');
        
        // Belirli UUID'lerle tarama başlat (isteğe bağlı)
        await BeaconService.startBeaconScanning(
          uuids: ["FDA50693-A4E2-4FB1-AFCF-C6EB07647825"]
        );
        
        setState(() {
          _beacons.clear(); // Önceki sonuçları temizle
        });
        
        _showSnackBar('📡 Beacon tarama başlatıldı');
      }

      setState(() {
        _isBeaconScanning = !_isBeaconScanning;
      });
    } catch (e) {
      print('Beacon scanning hatası: $e');
      _showSnackBar('❌ Beacon tarama hatası: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message))
    );
  }

  Color _getProximityColor(BeaconProximity proximity) {
    switch (proximity) {
      case BeaconProximity.immediate:
        return Colors.green;
      case BeaconProximity.near:
        return Colors.orange;
      case BeaconProximity.far:
        return Colors.red;
      case BeaconProximity.unknown:
        return Colors.grey;
    }
  }

  String _getProximityText(BeaconProximity proximity) {
    switch (proximity) {
      case BeaconProximity.immediate:
        return 'Çok Yakın';
      case BeaconProximity.near:
        return 'Yakın';
      case BeaconProximity.far:
        return 'Uzak';
      case BeaconProximity.unknown:
        return 'Bilinmiyor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon Tarayıcı'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_isBeaconScanning ? Icons.stop : Icons.radar),
            onPressed: _toggleBeaconScanning,
            tooltip: _isBeaconScanning ? 'Taramayı Durdur' : 'Taramayı Başlat',
          ),
        ],
      ),
      body: Column(
        children: [
          // İzin durumu
          _buildPermissionStatus(),
          
          // Kontrol paneli
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _hasLocationPermissions ? _toggleBeaconScanning : null,
                    icon: Icon(_isBeaconScanning ? Icons.stop : Icons.radar),
                    label: Text(
                      _isBeaconScanning ? 'Taramayı Durdur' : 'Beacon Tarama Başlat',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBeaconScanning ? Colors.red : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bulunan Beacon\'lar: ${_beacons.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _beacons.isEmpty ? Colors.grey : Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Tarama durumu
          if (_isBeaconScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: LinearProgressIndicator(),
            ),
          
          // Beacon listesi
          Expanded(
            child: _beacons.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isBeaconScanning ? Icons.radar : Icons.location_searching,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isBeaconScanning
                              ? 'Beacon\'lar aranıyor...'
                              : 'Tarama butonuna basarak beacon\'ları arayın',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _beacons.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final beacon = _beacons[index];
                      final proximityColor = _getProximityColor(beacon.proximity);
                      final proximityText = _getProximityText(beacon.proximity);
                      
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: proximityColor.withOpacity(0.1),
                          child: Icon(
                            Icons.bluetooth_searching,
                            color: proximityColor,
                          ),
                        ),
                        title: Text(
                          'UUID: ${beacon.uuid.substring(0, 8)}...',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Major: ${beacon.major} | Minor: ${beacon.minor}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.signal_cellular_alt,
                                  size: 16,
                                  color: proximityColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'RSSI: ${beacon.rssi}dBm',
                                  style: TextStyle(
                                    color: proximityColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (beacon.distance != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '${beacon.distance!.toStringAsFixed(1)}m',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: proximityColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            proximityText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}