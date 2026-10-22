package com.example.drivesafe_ai

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "drivesafe_ai/call_screening"
    private val REQUEST_ID_CALL_SCREENING = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        NativeMotionEngine.instance.init(applicationContext, channel)
        CallHelper.warmContactCache(applicationContext)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startNativeMotionTracking" -> {
                    NativeMotionEngine.instance.startTracking()
                    result.success(true)
                }
                "stopNativeMotionTracking" -> {
                    NativeMotionEngine.instance.stopTracking()
                    result.success(true)
                }
                "getNativeMotionStatus" -> {
                    result.success(NativeMotionEngine.instance.getStatusMap())
                }
                "isRoleGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
                        val isHeld = roleManager?.isRoleHeld(RoleManager.ROLE_CALL_SCREENING) ?: false
                        result.success(isHeld)
                    } else {
                        result.success(true)
                    }
                }
                "requestRole" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
                        if (roleManager != null && !roleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
                            pendingResult = result
                            startActivityForResult(intent, REQUEST_ID_CALL_SCREENING)
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "syncDrivingState" -> {
                    val isActive = call.argument<Boolean>("isActive") ?: false
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.is_driving_active", isActive).commit()
                    if (!isActive) {
                        CallHelper.restoreRinger(this)
                    }
                    result.success(true)
                }
                "restoreRinger" -> {
                    CallHelper.restoreRinger(this)
                    result.success(true)
                }
                "getCallHistory" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val historyJson = prefs.getString("flutter.call_history_records", "[]") ?: "[]"
                    result.success(historyJson)
                }
                "getDeviceContacts" -> {
                    val contacts = CallHelper.getDeviceContacts(this, 300)
                    result.success(contacts)
                }
                "openMap" -> {
                    val lat = call.argument<Double>("lat") ?: 0.0
                    val lng = call.argument<Double>("lng") ?: 0.0
                    try {
                        val gmmIntentUri = Uri.parse("geo:$lat,$lng?q=$lat,$lng(My+Location)")
                        val mapIntent = Intent(Intent.ACTION_VIEW, gmmIntentUri)
                        mapIntent.setPackage("com.google.android.apps.maps")
                        startActivity(mapIntent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val browserUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng")
                            val fallbackIntent = Intent(Intent.ACTION_VIEW, browserUri)
                            startActivity(fallbackIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MAP_ERROR", e.message, null)
                        }
                    }
                }
                "areNativePermissionsGranted" -> {
                    val contactsGranted = checkSelfPermission(android.Manifest.permission.READ_CONTACTS) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val phoneGranted = checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val callLogGranted = checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val locationGranted = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    result.success(contactsGranted && phoneGranted && callLogGranted && locationGranted)
                }
                "requestNativePermissions" -> {
                    val perms = mutableListOf(
                        android.Manifest.permission.READ_CONTACTS,
                        android.Manifest.permission.READ_PHONE_STATE,
                        android.Manifest.permission.READ_CALL_LOG,
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        perms.add(android.Manifest.permission.ANSWER_PHONE_CALLS)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        perms.add(android.Manifest.permission.POST_NOTIFICATIONS)
                    }
                    requestPermissions(perms.toTypedArray(), 2002)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ID_CALL_SCREENING) {
            val isHeld = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
                roleManager?.isRoleHeld(RoleManager.ROLE_CALL_SCREENING) ?: false
            } else {
                true
            }
            pendingResult?.success(isHeld)
            pendingResult = null
        }
    }
}
