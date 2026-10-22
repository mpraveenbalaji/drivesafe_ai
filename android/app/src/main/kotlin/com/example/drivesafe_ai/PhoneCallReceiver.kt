package com.example.drivesafe_ai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.util.Log

class PhoneCallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "DriveSafe_CallReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
    }

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val action = intent.action
            if (action != TelephonyManager.ACTION_PHONE_STATE_CHANGED && action != "android.intent.action.PHONE_STATE") {
                return
            }

            val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            val incomingNumber = try {
                intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: ""
            } catch (e: SecurityException) {
                Log.w(TAG, "READ_CALL_LOG permission not granted for EXTRA_INCOMING_NUMBER: ${e.message}")
                ""
            }

            Log.d(TAG, "Phone State Change: $stateStr | Number: $incomingNumber")

            if (stateStr == TelephonyManager.EXTRA_STATE_IDLE) {
                CallHelper.restoreRinger(context)
                return
            }

            if (stateStr == TelephonyManager.EXTRA_STATE_RINGING) {
                val cleanIncomingDigits = incomingNumber.replace(Regex("[^0-9]"), "")
                if (cleanIncomingDigits.length < 3) {
                    Log.d(TAG, "Incoming number is blank or invalid ('$incomingNumber'). Skipping receiver.")
                    return
                }

                // If CallScreeningServiceImpl already screened and logged this call, avoid duplicate processing!
                if (CallHelper.wasRecentlyScreened(incomingNumber)) {
                    Log.d(TAG, "Call $incomingNumber already handled by CallScreeningService. Skipping duplicate receiver action.")
                    return
                }

                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val isDrivingActive = prefs.getBoolean("flutter.is_driving_active", false)
                val isPassenger = prefs.getBoolean("flutter.setting_passenger_mode", false)
                val isPaused = prefs.getBoolean("flutter.setting_manual_pause", false)

                // Requirement 2 & 3: When not driving, do NOT record to Call History and restore ringer!
                if (!isDrivingActive || isPassenger || isPaused) {
                    CallHelper.restoreRinger(context)
                    Log.d(TAG, "Not driving (driving=$isDrivingActive, passenger=$isPassenger, paused=$isPaused). Letting call ring normally without screening history.")
                    return
                }

                val (category, contactName, callerNote) = CallHelper.classifyCaller(
                    context = context,
                    rawNumber = incomingNumber
                )

                if (category == "Emergency") {
                    CallHelper.restoreRinger(context)
                    Log.d(TAG, "Emergency number $incomingNumber ringing - letting through!")
                    return
                }

                val ruleAction = when (category) {
                    "Saved Contact" -> prefs.getString("flutter.rule_contact_action", "Allow") ?: "Allow"
                    "Spam" -> prefs.getString("flutter.rule_spam_action", "Reject") ?: "Reject"
                    else -> prefs.getString("flutter.rule_unknown_action", "Silence") ?: "Silence"
                }

                Log.d(TAG, "Receiver rule evaluation: category=$category ruleAction=$ruleAction for $incomingNumber ($contactName)")

                CallHelper.markCallScreened(incomingNumber)

                when (ruleAction) {
                    "Silence" -> {
                        CallHelper.muteRinger(context)
                        CallHelper.recordCallHistory(
                            context = context,
                            number = incomingNumber,
                            name = contactName,
                            category = category,
                            action = "Silenced",
                            note = if (category == "Saved Contact") "Saved Contact (${contactName ?: "Address Book"}) • Action: Silenced while driving"
                                   else if (category == "Spam") "Spam Call (starts with 0 / telemarketer) • Action: Silenced while driving"
                                   else "Unknown Caller • Action: Silenced while driving"
                        )
                    }
                    "Reject" -> {
                        // In reject mode, drop call immediately without putting phone into silent mode
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            try {
                                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                                telecomManager?.endCall()
                                Log.d(TAG, "Call rejected via TelecomManager.endCall()")
                            } catch (e: Throwable) {
                                Log.w(TAG, "Notice: endCall failed or not permitted: ${e.message}")
                            }
                        }
                        CallHelper.recordCallHistory(
                            context = context,
                            number = incomingNumber,
                            name = contactName,
                            category = category,
                            action = "Rejected",
                            note = if (category == "Saved Contact") "Saved Contact (${contactName ?: "Address Book"}) • Action: Rejected while driving"
                                   else if (category == "Spam") "Spam Call (starts with 0 / telemarketer) • Action: Rejected while driving"
                                   else "Unknown Caller • Action: Rejected while driving"
                        )
                    }
                    "Allow", "Ask me" -> {
                        CallHelper.restoreRinger(context)
                        CallHelper.recordCallHistory(
                            context = context,
                            number = incomingNumber,
                            name = contactName,
                            category = category,
                            action = "Allowed",
                            note = if (category == "Saved Contact") "Saved Contact (${contactName ?: "Address Book"}) • Action: Allowed while driving"
                                   else if (category == "Spam") "Spam Call (starts with 0 / telemarketer) • Action: Allowed while driving"
                                   else "Unknown Caller • Action: Allowed while driving"
                        )
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Safe catch: prevented PhoneCallReceiver crash: ${t.message}", t)
        }
    }
}
