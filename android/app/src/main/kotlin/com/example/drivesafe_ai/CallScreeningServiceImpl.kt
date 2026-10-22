package com.example.drivesafe_ai

import android.content.Context
import android.net.Uri
import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log

class CallScreeningServiceImpl : CallScreeningService() {

    companion object {
        private const val TAG = "CallScreeningService"
        private const val PREFS_NAME = "FlutterSharedPreferences"
    }

    override fun onScreenCall(callDetails: Call.Details) {
        val responseBuilder = CallResponse.Builder()
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val isDrivingActive = prefs.getBoolean("flutter.is_driving_active", false)
            val isPassenger = prefs.getBoolean("flutter.setting_passenger_mode", false)
            val isPaused = prefs.getBoolean("flutter.setting_manual_pause", false)

            val handleUri: Uri? = callDetails.handle
            var rawNumber = handleUri?.schemeSpecificPart ?: ""
            if (rawNumber.startsWith("tel:", ignoreCase = true)) {
                rawNumber = rawNumber.substring(4)
            }
            rawNumber = Uri.decode(rawNumber).trim()

            val callerDisplayName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                callDetails.callerDisplayName
            } else null

            Log.d(TAG, "CallScreening onScreenCall: number='$rawNumber' callerName='$callerDisplayName' | Driving=$isDrivingActive Passenger=$isPassenger Paused=$isPaused")

            // 1. Caller classification matching user specification
            val isVerificationFailed = isCallerVerificationFailed(callDetails)
            val (category, contactName, callerNote) = CallHelper.classifyCaller(
                context = this,
                rawNumber = rawNumber,
                callerDisplayName = callerDisplayName,
                isVerificationFailed = isVerificationFailed
            )

            // 2. Emergency safeguard
            if (category == "Emergency") {
                Log.d(TAG, "Emergency call detected ($rawNumber) - allowing immediately.")
                respondToCall(callDetails, responseBuilder.build())
                return
            }

            // 3. If Not Driving / Stopped in Traffic / Passenger / Paused -> Calls ring normally
            // Requirement 2 & 3: Do NOT override phone settings or record normal calls into DriveSafe Call History!
            // Control strictly remains with the phone.
            if (!isDrivingActive || isPassenger || isPaused) {
                CallHelper.restoreRinger(this)
                val reason = when {
                    isPassenger -> "Passenger Mode active"
                    isPaused -> "Detection paused"
                    else -> "Stopped in traffic / At rest (speed < 15 km/h)"
                }
                Log.d(TAG, "Normal call allowed without screening ($reason): $rawNumber ($contactName)")
                respondToCall(callDetails, responseBuilder.build())
                return
            }

            // 4. Moving / Driving Active (speed >= 15 km/h) -> Enforce user rules!
            val ruleAction = when (category) {
                "Saved Contact" -> prefs.getString("flutter.rule_contact_action", "Allow") ?: "Allow"
                "Spam" -> prefs.getString("flutter.rule_spam_action", "Reject") ?: "Reject"
                else -> prefs.getString("flutter.rule_unknown_action", "Silence") ?: "Silence"
            }

            Log.d(TAG, "CallScreening enforcing rule: category=$category action=$ruleAction for $rawNumber ($contactName)")

            var executedAction = "Allowed"
            when (ruleAction) {
                "Reject" -> {
                    // In reject mode, drop call immediately without putting phone into silent mode
                    responseBuilder.setDisallowCall(true)
                    responseBuilder.setRejectCall(true)
                    responseBuilder.setSkipNotification(true)
                    responseBuilder.setSkipCallLog(false)
                    executedAction = "Rejected"
                }
                "Silence" -> {
                    CallHelper.muteRinger(this)
                    responseBuilder.setSilenceCall(true)
                    responseBuilder.setSkipNotification(true)
                    executedAction = "Silenced"
                }
                "Allow", "Ask me" -> {
                    CallHelper.restoreRinger(this)
                    responseBuilder.setDisallowCall(false)
                    responseBuilder.setRejectCall(false)
                    responseBuilder.setSilenceCall(false)
                    responseBuilder.setSkipNotification(false)
                    executedAction = "Allowed"
                }
            }

            // CRITICAL: Deliver the decision to Android Telecom immediately!
            // Ringtone starts instantly without any pause or delay.
            respondToCall(callDetails, responseBuilder.build())
            CallHelper.markCallScreened(rawNumber)

            val note = when (category) {
                "Saved Contact" -> "Saved Contact (${contactName ?: "Address Book"}) • Action: $executedAction while driving"
                "Spam" -> "Spam Call (starts with 0 / telemarketer) • Action: $executedAction while driving"
                else -> "Unknown Caller • Action: $executedAction while driving"
            }

            // Record call history asynchronously so disk I/O never blocks the audio pipeline
            Thread {
                try {
                    CallHelper.recordCallHistory(
                        context = applicationContext,
                        number = rawNumber,
                        name = contactName,
                        category = category,
                        action = executedAction,
                        note = note
                    )
                } catch (_: Throwable) {}
            }.start()
        } catch (t: Throwable) {
            Log.e(TAG, "Safe catch: prevented CallScreeningService crash: ${t.message}", t)
            try {
                respondToCall(callDetails, responseBuilder.build())
            } catch (_: Throwable) {}
        }
    }

    private fun isCallerVerificationFailed(callDetails: Call.Details): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val method = callDetails.javaClass.getMethod("getCallerNumberVerificationStatus")
                val status = method.invoke(callDetails) as? Int
                if (status == 2) {
                    return true
                }
            } catch (_: Throwable) {}
        }
        return false
    }
}
