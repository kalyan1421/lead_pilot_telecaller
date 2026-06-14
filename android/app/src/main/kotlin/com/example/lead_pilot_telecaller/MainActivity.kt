package com.example.lead_pilot_telecaller

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCallWithNotesBubble" -> {
                        val leadId = call.argument<String>("leadId").orEmpty()
                        val leadName = call.argument<String>("leadName").orEmpty()
                        val phoneNumber = call.argument<String>("phoneNumber")
                        val leadScore = call.argument<Int>("leadScore") ?: 0
                        val temperature = call.argument<String>("temperature").orEmpty()
                        val intent = call.argument<String>("intent").orEmpty()
                        val scriptOpeningLine = call.argument<String>("scriptOpeningLine").orEmpty()
                        @Suppress("UNCHECKED_CAST")
                        val memoryFacts = (call.argument<List<*>>("memoryFacts") ?: emptyList<String>())
                            .filterIsInstance<String>()
                        val lastCallTs = call.argument<String>("lastCallTs").orEmpty()
                        val lastCallScore = call.argument<Int>("lastCallScore") ?: 0
                        val lastCallSummary = call.argument<String>("lastCallSummary").orEmpty()

                        if (phoneNumber.isNullOrBlank()) {
                            result.success(
                                mapOf(
                                    "launched" to false,
                                    "overlayPermissionGranted" to hasOverlayPermission(),
                                )
                            )
                            return@setMethodCallHandler
                        }

                        result.success(
                            startCallWithNotesBubble(
                                leadId, leadName, phoneNumber,
                                leadScore, temperature, intent,
                                scriptOpeningLine, memoryFacts,
                                lastCallTs, lastCallScore, lastCallSummary,
                            )
                        )
                    }

                    "getCallNotes" -> {
                        val leadId = call.argument<String>("leadId").orEmpty()
                        result.success(getCallNotes(leadId))
                    }

                    "stopCallNotesBubble" -> {
                        stopCallNotesBubble()
                        result.success(true)
                    }

                    "showCallAppChooser" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")

                        if (phoneNumber.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        result.success(showCallAppChooser(phoneNumber))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun startCallWithNotesBubble(
        leadId: String,
        leadName: String,
        phoneNumber: String,
        leadScore: Int = 0,
        temperature: String = "",
        intent: String = "",
        scriptOpeningLine: String = "",
        memoryFacts: List<String> = emptyList(),
        lastCallTs: String = "",
        lastCallScore: Int = 0,
        lastCallSummary: String = "",
    ): Map<String, Any> {
        if (!hasOverlayPermission()) {
            openOverlayPermissionSettings()
            return mapOf(
                "launched" to false,
                "overlayPermissionGranted" to false,
            )
        }

        val serviceIntent = Intent(this, CallNotesOverlayService::class.java).apply {
            putExtra(CallNotesOverlayService.EXTRA_LEAD_ID, leadId)
            putExtra(CallNotesOverlayService.EXTRA_LEAD_NAME, leadName)
            putExtra(CallNotesOverlayService.EXTRA_PHONE_NUMBER, phoneNumber)
            putExtra(CallNotesOverlayService.EXTRA_LEAD_SCORE, leadScore)
            putExtra(CallNotesOverlayService.EXTRA_TEMPERATURE, temperature)
            putExtra(CallNotesOverlayService.EXTRA_INTENT, intent)
            putExtra(CallNotesOverlayService.EXTRA_SCRIPT_OPENING, scriptOpeningLine)
            putStringArrayListExtra(
                CallNotesOverlayService.EXTRA_MEMORY_FACTS,
                ArrayList(memoryFacts),
            )
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_TS, lastCallTs)
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_SCORE, lastCallScore)
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_SUMMARY, lastCallSummary)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        val launched = showCallAppChooser(phoneNumber)
        if (!launched) {
            stopCallNotesBubble()
        }

        return mapOf(
            "launched" to launched,
            "overlayPermissionGranted" to true,
        )
    }

    private fun showCallAppChooser(phoneNumber: String): Boolean {
        val dialIntent = Intent(Intent.ACTION_DIAL).apply {
            data = Uri.parse("tel:$phoneNumber")
        }
        val chooser = Intent.createChooser(dialIntent, "Complete action using")

        return try {
            startActivity(chooser)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun getCallNotes(leadId: String): String {
        if (leadId.isBlank()) return ""

        val preferences = getSharedPreferences(
            CallNotesOverlayService.NOTES_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        return preferences.getString(CallNotesOverlayService.noteKey(leadId), "").orEmpty()
    }

    private fun stopCallNotesBubble() {
        val intent = Intent(this, CallNotesOverlayService::class.java).apply {
            action = CallNotesOverlayService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun hasOverlayPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun openOverlayPermissionSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
            } else {
                Intent(Settings.ACTION_SETTINGS)
            }
        startActivity(intent)
    }

    private companion object {
        const val CHANNEL = "lead_pilot/call_actions"
    }
}
