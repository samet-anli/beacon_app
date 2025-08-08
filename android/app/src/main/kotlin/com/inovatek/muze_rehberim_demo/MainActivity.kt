package com.inovatek.muze_rehberim_demo

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "beacon_service"
    private lateinit var beaconHandler: BeaconHandler
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // MethodChannel oluştur
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // BeaconHandler'ı başlat
        beaconHandler = BeaconHandler(
            context = applicationContext,
            activity = this,
            channel = channel
        )
        
        // MethodCallHandler'ı ayarla
        channel.setMethodCallHandler(beaconHandler)
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Activity oluşturulduktan sonra handler'a bildir
        if (::beaconHandler.isInitialized) {
            beaconHandler.updateActivity(this)
        }
    }
    
    override fun onResume() {
        super.onResume()
        
        // Activity tekrar aktif olduğunda handler'a bildir
        if (::beaconHandler.isInitialized) {
            beaconHandler.updateActivity(this)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Cleanup yapmayı unutma
        if (::beaconHandler.isInitialized) {
            beaconHandler.cleanup()
        }
    }
    
    // İzin sonuçlarını beacon handler'a ilet
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (::beaconHandler.isInitialized) {
            val handled = beaconHandler.handlePermissionResult(requestCode, permissions, grantResults)
            if (!handled) {
                super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            }
        }
    }
}