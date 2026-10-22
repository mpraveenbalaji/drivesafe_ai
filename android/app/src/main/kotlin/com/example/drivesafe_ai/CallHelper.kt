package com.example.drivesafe_ai

import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.telephony.PhoneNumberUtils
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object CallHelper {
    private const val TAG = "DriveSafe_CallHelper"
    private const val PREFS_NAME = "FlutterSharedPreferences"

    private var previousRingerMode: Int = -1
    private var previousVolumeIndex: Int = -1
    private var isMutedByDriveSafe: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingRestoreRunnable: Runnable? = null
    private val callSequenceHistory = mutableMapOf<String, MutableList<Long>>()

    fun isEmergency(number: String): Boolean {
        if (number.isBlank()) return false
        val clean = number.replace(Regex("[^0-9+]"), "")
        val emergencyCodes = setOf("911", "112", "999", "100", "101", "102", "108")
        if (emergencyCodes.contains(clean)) return true
        return try {
            PhoneNumberUtils.isEmergencyNumber(clean)
        } catch (_: Throwable) {
            false
        }
    }

    private val contactCache = java.util.concurrent.ConcurrentHashMap<String, String>()
    private var lastCacheBuildMs = 0L

    /**
     * Pre-warms in-memory contact numbers cache asynchronously so caller classification
     * runs in sub-millisecond time without disk/cursor latency during incoming calls.
     */
    fun warmContactCache(context: Context) {
        val now = System.currentTimeMillis()
        if (contactCache.isNotEmpty() && (now - lastCacheBuildMs < 120_000L)) return
        Thread {
            try {
                val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
                val projection = arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                )
                val cursor = context.contentResolver.query(uri, projection, null, null, null)
                cursor?.use {
                    val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                    val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                    while (it.moveToNext()) {
                        val num = if (numIdx != -1) it.getString(numIdx) ?: "" else ""
                        val name = if (nameIdx != -1) it.getString(nameIdx) ?: "Saved Contact" else "Saved Contact"
                        val digits = num.replace(Regex("[^0-9]"), "")
                        if (digits.length >= 7) {
                            contactCache[digits.takeLast(10)] = name
                            contactCache[digits.takeLast(7)] = name
                        }
                    }
                }
                lastCacheBuildMs = System.currentTimeMillis()
                Log.d(TAG, "Contact cache warmed with ${contactCache.size} entries")
            } catch (_: Throwable) {}
        }.start()
    }

    /**
     * Queries device contacts to find if number is saved.
     * High-performance implementation:
     * 1. Checks Telecom callerDisplayName (0ms)
     * 2. Checks fast in-memory contact cache (0.001ms)
     * 3. Checks Android indexed PhoneLookup (< 3ms)
     * Returns within < 5ms so ringtone starts immediately without delay.
     */
    fun checkSavedContact(context: Context, rawNumber: String, callerDisplayName: String? = null): Pair<Boolean, String?> {
        // 1. If Android Telecom already resolved the contact name (e.g. "Amma"), use it immediately!
        if (!callerDisplayName.isNullOrBlank()) {
            val trimmedName = callerDisplayName.trim()
            if (trimmedName.any { it.isLetter() }) {
                Log.d(TAG, "Contact match verified directly from Telecom callerDisplayName: '$trimmedName'")
                return Pair(true, trimmedName)
            }
        }

        if (rawNumber.isBlank()) return Pair(false, null)

        var clean = rawNumber.replace("tel:", "", ignoreCase = true)
        clean = Uri.decode(clean).trim()
        val digitsOnly = clean.replace(Regex("[^0-9]"), "")
        val suffix10 = if (digitsOnly.length >= 10) digitsOnly.takeLast(10) else digitsOnly
        val suffix7 = if (digitsOnly.length >= 7) digitsOnly.takeLast(7) else digitsOnly

        if (digitsOnly.length < 3) return Pair(false, null)

        // 2. Check fast in-memory contact cache (0.001 ms)
        val cachedName = contactCache[suffix10] ?: contactCache[suffix7]
        if (cachedName != null) {
            Log.d(TAG, "Contact match found in fast cache: '$cachedName'")
            return Pair(true, cachedName)
        }

        // 3. Primary lookup using indexed PhoneLookup with clean number (< 3ms)
        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(clean)
            )
            val projection = arrayOf(
                ContactsContract.PhoneLookup.DISPLAY_NAME
            )
            val cursor = context.contentResolver.query(uri, projection, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val name = it.getString(it.getColumnIndexOrThrow(ContactsContract.PhoneLookup.DISPLAY_NAME))
                    contactCache[suffix10] = name
                    Log.d(TAG, "Contact match found via PhoneLookup(clean): '$name' for $clean")
                    return Pair(true, name)
                }
            }
        } catch (_: Throwable) {}

        // 4. Secondary lookup using indexed PhoneLookup with 10-digit suffix (< 3ms)
        if (suffix10.length >= 7 && suffix10 != clean) {
            try {
                val uri = Uri.withAppendedPath(
                    ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                    Uri.encode(suffix10)
                )
                val projection = arrayOf(
                    ContactsContract.PhoneLookup.DISPLAY_NAME
                )
                val cursor = context.contentResolver.query(uri, projection, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val name = it.getString(it.getColumnIndexOrThrow(ContactsContract.PhoneLookup.DISPLAY_NAME))
                        contactCache[suffix10] = name
                        Log.d(TAG, "Contact match found via PhoneLookup(suffix): '$name'")
                        return Pair(true, name)
                    }
                }
            } catch (_: Throwable) {}
        }

        // Trigger background refresh of cache if it was empty
        if (contactCache.isEmpty()) {
            warmContactCache(context.applicationContext)
        }

        return Pair(false, null)
    }

    /**
     * Returns a list of real contacts from user's phone for display in Flutter UI.
     * Uses memory-safe case-insensitive sorting to prevent SQLite syntax exceptions.
     */
    fun getDeviceContacts(context: Context, limit: Int = 300): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        try {
            val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            val cursor = context.contentResolver.query(uri, projection, null, null, null)
            cursor?.use {
                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                val seenSuffixes = mutableSetOf<String>()
                while (it.moveToNext() && list.size < limit) {
                    var name = if (nameIdx != -1) it.getString(nameIdx) ?: "" else ""
                    val number = if (numIdx != -1) it.getString(numIdx) ?: "" else ""
                    val cleanDigits = number.replace(Regex("[^0-9]"), "")
                    val suffix = if (cleanDigits.length >= 10) cleanDigits.takeLast(10) else cleanDigits

                    if (suffix.length >= 6 && !seenSuffixes.contains(suffix)) {
                        seenSuffixes.add(suffix)
                        if (name.isBlank() || name.replace(Regex("[^0-9]"), "") == cleanDigits) {
                            name = number
                        }
                        list.add(mapOf("name" to name.trim(), "number" to number.trim()))
                    }
                }
            }
            // Sort in memory safely
            list.sortWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it["name"] ?: "" })
        } catch (t: Throwable) {
            Log.e(TAG, "Error fetching device contacts: ${t.message}")
        }
        return list
    }

    @Volatile
    private var lastScreenedNumber: String = ""
    @Volatile
    private var lastScreenedTimeMs: Long = 0L

    fun markCallScreened(number: String) {
        lastScreenedTimeMs = System.currentTimeMillis()
        lastScreenedNumber = number.replace(Regex("[^0-9]"), "")
    }

    fun wasRecentlyScreened(number: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastScreenedTimeMs > 6000) return false
        val clean = number.replace(Regex("[^0-9]"), "")
        if (clean.isBlank() || lastScreenedNumber.isBlank()) {
            return (now - lastScreenedTimeMs) < 4000
        }
        val suffix1 = if (clean.length >= 7) clean.takeLast(7) else clean
        val suffix2 = if (lastScreenedNumber.length >= 7) lastScreenedNumber.takeLast(7) else lastScreenedNumber
        return suffix1 == suffix2 || (now - lastScreenedTimeMs) < 3000
    }

    /**
     * Exact Caller Classification matching user specification:
     * 1. Saved Contact:
     *    - If address book contains contact OR Telecom callerDisplayName has a real contact name.
     * 2. Spam Call:
     *    - If raw number starts with '0' (e.g. 0..., 011, 022, 080, 0140)
     *    - OR TRAI commercial telemarketing numbers (140, 91140)
     *    - OR carrier verification failed.
     * 3. Unknown Caller:
     *    - Standard 10-digit Indian mobile number starting with 6, 7, 8, or 9
     *      (e.g., 9..., 8..., 7..., 6..., +919..., +918..., +917..., +916...).
     */
    fun classifyCaller(
        context: Context,
        rawNumber: String,
        callerDisplayName: String? = null,
        isVerificationFailed: Boolean = false
    ): Triple<String, String?, String> {
        // 1. Emergency
        if (isEmergency(rawNumber)) {
            return Triple("Emergency", "Emergency Services", "Emergency call allowed immediately")
        }

        // 2. Saved Contact check
        val (isContact, contactName) = checkSavedContact(context, rawNumber, callerDisplayName)
        if (isContact && !contactName.isNullOrBlank()) {
            return Triple("Saved Contact", contactName, "Saved Contact ($contactName)")
        }

        // Clean digits
        val digits = rawNumber.replace(Regex("[^0-9]"), "")
        val trimmed = rawNumber.trim()

        // 3. Spam check (per user specification: numbers starting with 0 or telemarketers)
        val isSpam = trimmed.startsWith("0") ||
                     digits.startsWith("0") ||
                     digits.startsWith("140") ||
                     digits.startsWith("91140") ||
                     isVerificationFailed

        if (isSpam) {
            return Triple("Spam", "Suspected Spam", "Spam Call (starts with 0 / telemarketer)")
        }

        // 4. Unknown Caller check (per user specification: 10-digit mobile starting with 6, 7, 8, or 9)
        val last10 = if (digits.length >= 10) digits.takeLast(10) else digits
        if (last10.length == 10) {
            val first = last10.first()
            if (first == '6' || first == '7' || first == '8' || first == '9') {
                return Triple("Unknown", "Unknown Caller", "Unknown Caller ($rawNumber)")
            }
        }

        // Fallback: If less than 10 digits and not saved, treat as spam/invalid
        if (digits.length < 10) {
            return Triple("Spam", "Suspected Spam", "Invalid/Short Number Spam ($rawNumber)")
        }

        return Triple("Unknown", "Unknown Caller", "Unknown Caller ($rawNumber)")
    }

    /**
     * Checks if audio settings control is allowed.
     * Audio settings may ONLY be modified when Driving Mode is active
     * AND Passenger Mode is inactive AND Manual Pause is inactive.
     */
    fun isAudioControlAllowed(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isDrivingActive = prefs.getBoolean("flutter.is_driving_active", false)
            val isPassenger = prefs.getBoolean("flutter.setting_passenger_mode", false)
            val isPaused = prefs.getBoolean("flutter.setting_manual_pause", false)
            isDrivingActive && !isPassenger && !isPaused
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Safely mutes the device ringer for an incoming call during active Driving Mode.
     * Audio control is strictly forbidden when Driving Mode is OFF or in Passenger/Pause mode.
     */
    fun muteRinger(context: Context) {
        // Enforce requirement: only control audio when drivingMode == true and not passenger/paused
        if (!isAudioControlAllowed(context)) {
            Log.d(TAG, "muteRinger skipped: Driving Mode is not active or Passenger/Pause mode is on.")
            return
        }

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Capture original user sound settings before DriveSafe modifies anything
            if (!isMutedByDriveSafe) {
                previousRingerMode = audioManager.ringerMode
                previousVolumeIndex = audioManager.getStreamVolume(AudioManager.STREAM_RING)
                isMutedByDriveSafe = true

                prefs.edit()
                    .putBoolean("internal.is_muted_by_drivesafe", true)
                    .putInt("internal.previous_ringer_mode", previousRingerMode)
                    .putInt("internal.previous_volume_index", previousVolumeIndex)
                    .apply()
            }

            try {
                audioManager.setStreamVolume(AudioManager.STREAM_RING, 0, 0)
            } catch (_: Throwable) {}
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, 0, 0)
            } catch (_: Throwable) {}
            try {
                audioManager.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_MUTE, 0)
            } catch (_: Throwable) {}
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || nm?.isNotificationPolicyAccessGranted == true) {
                    audioManager.ringerMode = AudioManager.RINGER_MODE_SILENT
                }
            } catch (_: Throwable) {}
            Log.d(TAG, "Ringer stream muted for screening while driving")

            // Failsafe: schedule restore after 30 seconds so ringer NEVER remains muted permanently
            pendingRestoreRunnable?.let { mainHandler.removeCallbacks(it) }
            val restoreTask = Runnable {
                Log.d(TAG, "Failsafe auto-restoring ringer after 30s timeout")
                restoreRinger(context.applicationContext)
            }
            pendingRestoreRunnable = restoreTask
            mainHandler.postDelayed(restoreTask, 30000)
        } catch (t: Throwable) {
            Log.w(TAG, "Safe notice: could not mute ringer stream: ${t.message}")
        }
    }

    /**
     * Safely restores ringer ONLY IF it was previously muted by DriveSafe AI.
     * When DriveSafe AI did not mute the device, this method is a complete NO-OP and
     * will never modify the user's audio settings or override silent/vibrate/volume.
     */
    fun restoreRinger(context: Context) {
        pendingRestoreRunnable?.let {
            mainHandler.removeCallbacks(it)
            pendingRestoreRunnable = null
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val wasMuted = isMutedByDriveSafe || prefs.getBoolean("internal.is_muted_by_drivesafe", false)

        // If DriveSafe never muted the phone, NEVER touch phone audio settings!
        if (!wasMuted) {
            Log.d(TAG, "restoreRinger: Phone audio was not muted by DriveSafe. Settings preserved.")
            return
        }

        try {
            if (previousRingerMode == -1) {
                previousRingerMode = prefs.getInt("internal.previous_ringer_mode", -1)
            }
            if (previousVolumeIndex == -1) {
                previousVolumeIndex = prefs.getInt("internal.previous_volume_index", -1)
            }

            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return

            // 1. Unmute ring and notification streams
            try {
                audioManager.adjustStreamVolume(AudioManager.STREAM_RING, AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: Throwable) {}
            try {
                audioManager.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: Throwable) {}

            // 2. Restore ringer mode to what the user had before DriveSafe muted it
            val targetMode = if (previousRingerMode != -1) {
                previousRingerMode
            } else {
                AudioManager.RINGER_MODE_NORMAL
            }

            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || nm?.isNotificationPolicyAccessGranted == true) {
                    audioManager.ringerMode = targetMode
                }
            } catch (_: Throwable) {}

            // 3. If original mode was NORMAL, restore volume index to original level
            if (targetMode == AudioManager.RINGER_MODE_NORMAL) {
                try {
                    val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)
                    val restoreVol = if (previousVolumeIndex > 0) previousVolumeIndex else maxVol
                    audioManager.setStreamVolume(AudioManager.STREAM_RING, restoreVol, 0)

                    val maxNotifVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)
                    audioManager.setStreamVolume(AudioManager.STREAM_NOTIFICATION, maxNotifVol, 0)
                } catch (_: Throwable) {}
            }

            Log.d(TAG, "Ringer stream restored to pre-mute mode ($targetMode) and volume ($previousVolumeIndex)")
        } catch (t: Throwable) {
            Log.w(TAG, "Safe notice: could not restore ringer stream: ${t.message}")
        } finally {
            prefs.edit()
                .putBoolean("internal.is_muted_by_drivesafe", false)
                .remove("internal.previous_ringer_mode")
                .remove("internal.previous_volume_index")
                .apply()
            isMutedByDriveSafe = false
            previousRingerMode = -1
            previousVolumeIndex = -1
        }
    }

    /**
     * Compatibility helper: only restores audio if DriveSafe had temporarily muted it.
     * Never forcibly overrides ringer to normal if DriveSafe did not mute it.
     */
    fun forceRingerNormal(context: Context) {
        restoreRinger(context)
    }

    /**
     * Records call event into SharedPreferences for display in Flutter Call History UI.
     * Uses clean JSON array of JSONObjects matching Dart PreferenceService.
     */
    @Synchronized
    fun recordCallHistory(
        context: Context,
        number: String,
        name: String?,
        category: String,
        action: String,
        note: String = "Screened by DriveSafe AI"
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val key = "flutter.call_history_records"
            val existingListString = prefs.getString(key, null)
            val list = mutableListOf<JSONObject>()

            if (!existingListString.isNullOrBlank()) {
                try {
                    val jsonArr = JSONArray(existingListString)
                    for (i in 0 until jsonArr.length()) {
                        val elem = jsonArr.get(i)
                        if (elem is JSONObject) {
                            list.add(elem)
                        } else if (elem is String) {
                            try {
                                list.add(JSONObject(elem))
                            } catch (_: Throwable) {}
                        }
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "Could not parse existing call history: ${e.message}")
                }
            }

            if (number.isBlank() && name.isNullOrBlank()) {
                return
            }

            // Deduplicate: If an entry with this number was added in the last 5 seconds, ignore duplicate
            val nowMs = System.currentTimeMillis()
            val cleanIncoming = number.replace(Regex("[^0-9]"), "")
            val incomingSuffix = if (cleanIncoming.length >= 7) cleanIncoming.takeLast(7) else cleanIncoming

            if (list.isNotEmpty()) {
                try {
                    val latest = list[0]
                    val latestTime = latest.optLong("timestampMs", 0L)
                    val latestNum = latest.optString("callerNumber", "").replace(Regex("[^0-9]"), "")
                    val latestSuffix = if (latestNum.length >= 7) latestNum.takeLast(7) else latestNum
                    if ((nowMs - latestTime) < 5000) {
                        if (incomingSuffix == latestSuffix || latestNum.isBlank() || cleanIncoming.isBlank()) {
                            Log.d(TAG, "Ignoring duplicate call event within 5s for $number")
                            return
                        }
                    }
                } catch (_: Throwable) {}
            }

            // Query device's actual system CallLog to match the exact call time
            var exactTimeMs = System.currentTimeMillis()
            try {
                val cleanDigits = number.replace(Regex("[^0-9]"), "")
                val suffix = if (cleanDigits.length >= 7) cleanDigits.takeLast(7) else cleanDigits
                val cursor = context.contentResolver.query(
                    android.provider.CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        android.provider.CallLog.Calls.DATE,
                        android.provider.CallLog.Calls.NUMBER
                    ),
                    null,
                    null,
                    "${android.provider.CallLog.Calls.DATE} DESC LIMIT 5"
                )
                cursor?.use {
                    val dateIdx = it.getColumnIndex(android.provider.CallLog.Calls.DATE)
                    val numIdx = it.getColumnIndex(android.provider.CallLog.Calls.NUMBER)
                    while (it.moveToNext()) {
                        val logDate = it.getLong(dateIdx)
                        val logNum = if (numIdx != -1) it.getString(numIdx) ?: "" else ""
                        val logDigits = logNum.replace(Regex("[^0-9]"), "")
                        if (suffix.isNotEmpty() && logDigits.endsWith(suffix) && Math.abs(exactTimeMs - logDate) < 120000) {
                            exactTimeMs = logDate
                            Log.d(TAG, "Exact call time retrieved from phone system call log: $exactTimeMs")
                            break
                        }
                    }
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Notice: could not query system call log for exact time: ${e.message}")
            }

            val localDf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault())
            localDf.timeZone = TimeZone.getDefault()
            val localIso = localDf.format(Date(exactTimeMs))

            val displayName = when {
                !name.isNullOrBlank() -> name
                category == "Saved Contact" -> "Saved Contact"
                category == "Spam" -> "Suspected Spam"
                else -> "Unknown Caller"
            }

            val event = JSONObject().apply {
                put("id", exactTimeMs.toString())
                put("timestampMs", exactTimeMs)
                put("callerNumber", number)
                put("callerName", displayName)
                put("category", category)
                put("actionTaken", action)
                put("timestamp", localIso)
                put("note", note)
            }

            list.add(0, event)

            val capped = if (list.size > 500) list.subList(0, 500) else list
            val outArray = JSONArray()
            capped.forEach { outArray.put(it) }

            prefs.edit().putString(key, outArray.toString()).commit()
            Log.d(TAG, "Call event successfully saved to history: $event")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to record call event in history: ${t.message}")
        }
    }
}
