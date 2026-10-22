package com.example.drivesafe_ai

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * NativeMotionEngine: Hardware-level motion and speed sensor helper for Android.
 * - Detects bodily steps and cadence with noise rejection (requires sustained steps, not 2 accidental steps).
 * - Immediately returns to 0.0 km/h when steps cease.
 * - Listens to GPS Doppler speed.
 * - IMPORTANT: Does NOT overwrite driving state or ringer in SharedPreferences;
 *   decision authority remains strictly with MovementService in Flutter.
 */
class NativeMotionEngine private constructor() : SensorEventListener, LocationListener {

    companion object {
        private const val TAG = "NativeMotionEngine"

        val instance: NativeMotionEngine by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
            NativeMotionEngine()
        }
    }

    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sensorManager: SensorManager? = null
    private var locationManager: LocationManager? = null

    private var isTracking = false

    // GPS tracking variables
    private var lastLocation: Location? = null
    private var anchorLocation: Location? = null
    private var anchorTimeMs: Long = 0L

    private var currentGpsSpeedKmh: Double = 0.0
    private var lastGpsFixTimeMs: Long = 0L

    // Accelerometer & Step Tracking variables
    private val accelHistory = ArrayList<Float>()
    private val stepTimestamps = ArrayList<Long>()
    private var lastStepTimeMs: Long = 0L

    // Fused State (for reporting to Flutter)
    var fusedSpeedKmh: Double = 0.0
        private set
    var fusedMotionType: String = "IDLE" // IDLE, WALKING, RUNNING, DRIVING
        private set
    var fusedMotionLabel: String = "Idle / Stopped in Traffic"
        private set

    fun init(appContext: Context, channel: MethodChannel) {
        this.context = appContext.applicationContext
        this.methodChannel = channel
        this.sensorManager = appContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        this.locationManager = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        startTracking()
    }

    @Synchronized
    fun startTracking() {
        if (isTracking) return
        isTracking = true
        Log.d(TAG, "Starting NativeMotionEngine sensor tracking")

        // 1. Register Accelerometer & Step Detector
        sensorManager?.let { sm ->
            val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            if (accel != null) {
                sm.registerListener(this, accel, SensorManager.SENSOR_DELAY_UI)
            }
            val stepDetector = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
            if (stepDetector != null) {
                sm.registerListener(this, stepDetector, SensorManager.SENSOR_DELAY_UI)
            }
        }

        // 2. Register LocationManager with GPS and Network providers
        locationManager?.let { lm ->
            try {
                if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        1000L,
                        0.0f,
                        this,
                        Looper.getMainLooper()
                    )
                }
            } catch (_: Throwable) {}

            try {
                if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    lm.requestLocationUpdates(
                        LocationManager.NETWORK_PROVIDER,
                        1000L,
                        0.0f,
                        this,
                        Looper.getMainLooper()
                    )
                }
            } catch (_: Throwable) {}
        }

        startEvaluationTicker()
    }

    @Synchronized
    fun stopTracking() {
        if (!isTracking) return
        isTracking = false
        Log.d(TAG, "Stopping NativeMotionEngine sensor tracking")
        sensorManager?.unregisterListener(this)
        try {
            locationManager?.removeUpdates(this)
        } catch (_: Throwable) {}
        evaluationRunnable?.let { mainHandler.removeCallbacks(it) }
    }

    private var evaluationRunnable: Runnable? = null

    private fun startEvaluationTicker() {
        evaluationRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                if (isTracking) {
                    evaluateMotionState()
                    mainHandler.postDelayed(this, 1000L)
                }
            }
        }
        evaluationRunnable = runnable
        mainHandler.postDelayed(runnable, 1000L)
    }

    // --- SensorEventListener Implementation ---

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || !isTracking) return

        val now = System.currentTimeMillis()

        if (event.sensor.type == Sensor.TYPE_STEP_DETECTOR) {
            val interval = now - lastStepTimeMs
            if (interval in 300..1200) {
                recordStep(now)
            } else {
                lastStepTimeMs = now
            }
            return
        }

        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            val mag = sqrt((x * x + y * y + z * z).toDouble()).toFloat()
            val dynamicAccel = abs(mag - 9.80665f)

            synchronized(accelHistory) {
                accelHistory.add(dynamicAccel)
                if (accelHistory.size > 30) {
                    accelHistory.removeAt(0)
                }
            }

            // High-confidence step impact detection:
            // Heel strike produces dynamic impact > 2.8 m/s²
            // Human cadence interval between steps is 350ms to 950ms (approx 1.0 to 2.8 steps/sec)
            if (dynamicAccel > 2.8f) {
                val interval = now - lastStepTimeMs
                if (interval in 350..950) {
                    recordStep(now)
                } else if (interval > 950) {
                    // Possible beginning of a stride sequence
                    lastStepTimeMs = now
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun recordStep(timeMs: Long) {
        lastStepTimeMs = timeMs
        synchronized(stepTimestamps) {
            stepTimestamps.add(timeMs)
            // Keep steps from the last 3.5 seconds
            stepTimestamps.removeAll { timeMs - it > 3500L }
        }
    }

    // --- LocationListener Implementation ---

    override fun onLocationChanged(location: Location) {
        if (!isTracking) return
        val now = System.currentTimeMillis()
        lastGpsFixTimeMs = now

        var speed = 0.0
        // 1. Hardware Doppler ground speed
        if (location.hasSpeed() && location.speed > 0.3f) {
            speed = (location.speed * 3.6).toDouble()
        }

        // 2. Sliding Accumulating Anchor delta calculation
        if (anchorLocation == null || anchorTimeMs == 0L) {
            anchorLocation = location
            anchorTimeMs = now
        } else {
            val elapsedSec = (now - anchorTimeMs) / 1000.0
            val distMeters = anchorLocation!!.distanceTo(location).toDouble()

            if (elapsedSec >= 1.2 || distMeters >= 2.0) {
                if (elapsedSec > 0.3) {
                    val deltaSpeed = (distMeters / elapsedSec) * 3.6
                    if (distMeters >= 1.5 && deltaSpeed > speed && deltaSpeed < 180.0) {
                        speed = deltaSpeed
                    }
                }
                anchorLocation = location
                anchorTimeMs = now
            }
        }

        lastLocation = location
        currentGpsSpeedKmh = speed
        evaluateMotionState()
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}

    // --- Sensor Evaluation & Dispatch to Flutter ---

    @Synchronized
    private fun evaluateMotionState() {
        val now = System.currentTimeMillis()

        // GPS fix expiration: if no GPS fix in last 5 seconds, clear old GPS speed
        if (now - lastGpsFixTimeMs > 5000L) {
            currentGpsSpeedKmh = 0.0
        }

        // 1. Pedestrian Steps Analysis
        var stepCount = 0
        synchronized(stepTimestamps) {
            // Drop steps older than 3.5 seconds
            stepTimestamps.removeAll { now - it > 3500L }
            stepCount = stepTimestamps.size
        }

        // Noise Filter:
        // Must have at least 5 rhythmic steps within 3.5 seconds to confirm real walking!
        // Taking 1 or 2 steps (e.g. at desk or picking up phone) will NOT trigger walking!
        // AND: As soon as steps cease for > 1.4 seconds, user has stopped!
        val isActivelyWalking = stepCount >= 5 && (now - lastStepTimeMs) <= 1400L

        var determinedSpeed = currentGpsSpeedKmh
        var motionType = "IDLE"
        var motionLabel = "Idle / Stopped in Traffic"

        if (currentGpsSpeedKmh >= 15.0) {
            // Confirmed high GPS speed
            motionType = "DRIVING"
            motionLabel = "Driving (In Motion)"
        } else if (isActivelyWalking) {
            // Sustained walking confirmed by step cadence
            val stepsPerSec = (stepCount / 3.0).coerceAtLeast(1.0)
            val estimatedSpeed = stepsPerSec * 0.75 * 3.6

            if (stepsPerSec >= 2.3) {
                motionType = "RUNNING"
                motionLabel = "Running / Jogging"
                determinedSpeed = if (currentGpsSpeedKmh in 6.0..14.9) currentGpsSpeedKmh else estimatedSpeed.coerceIn(6.5, 11.0)
            } else {
                motionType = "WALKING"
                motionLabel = "Walking"
                determinedSpeed = if (currentGpsSpeedKmh in 1.0..6.5) currentGpsSpeedKmh else estimatedSpeed.coerceIn(2.8, 5.0)
            }
        } else {
            // No sustained steps and low/zero GPS -> At rest / Stopped in traffic
            if (currentGpsSpeedKmh < 1.0) {
                determinedSpeed = 0.0
                motionType = "IDLE"
                motionLabel = "Stopped in Traffic / Idle"
            } else if (currentGpsSpeedKmh < 6.0) {
                motionType = "WALKING"
                motionLabel = "Walking"
            } else if (currentGpsSpeedKmh < 15.0) {
                motionType = "RUNNING"
                motionLabel = "Running / Jogging"
            }
        }

        fusedSpeedKmh = determinedSpeed
        fusedMotionType = motionType
        fusedMotionLabel = motionLabel

        // NOTE: We do NOT write to flutter.is_driving_active in SharedPreferences here!
        // That is exclusively controlled by MovementService in Flutter so simulation
        // and hysteresis rules are NEVER overwritten by this background loop.

        // Notify Flutter UI via MethodChannel ONLY if sustained pedestrian motion is verified.
        // We NEVER broadcast 0.0 km/h or idle state from here to prevent wiping real GPS vehicle speed!
        if (isActivelyWalking) {
            val payload = mapOf(
                "speedKmh" to fusedSpeedKmh,
                "motionType" to fusedMotionType,
                "motionLabel" to fusedMotionLabel,
                "timestamp" to now
            )

            mainHandler.post {
                try {
                    methodChannel?.invokeMethod("onNativeMotionUpdate", payload)
                } catch (_: Throwable) {}
            }
        }
    }

    fun getStatusMap(): Map<String, Any> {
        return mapOf(
            "speedKmh" to fusedSpeedKmh,
            "motionType" to fusedMotionType,
            "motionLabel" to fusedMotionLabel
        )
    }
}
