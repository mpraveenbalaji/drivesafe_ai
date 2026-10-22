package com.example.drivesafe_ai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * PhoneCallReceiver: BroadcastReceiver for telephony state events.
 * Core call interception and rejection logic removed.
 */
class PhoneCallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // TODO: Implement telephony state listener if fallback broadcast screening is needed
    }
}
