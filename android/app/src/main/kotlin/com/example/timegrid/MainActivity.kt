package com.example.timegrid

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth,
// which hosts the biometric prompt in a fragment.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareToGmail" -> result.success(
                        shareToGmail(
                            to = call.argument<String>("to").orEmpty(),
                            subject = call.argument<String>("subject").orEmpty(),
                            body = call.argument<String>("body").orEmpty(),
                            filePath = call.argument<String>("filePath").orEmpty(),
                        )
                    )

                    "shareToWhatsApp" -> result.success(
                        shareToWhatsApp(
                            text = call.argument<String>("text").orEmpty(),
                            filePath = call.argument<String>("filePath").orEmpty(),
                        )
                    )

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * A content:// URI for the produced timesheet.
     *
     * The file is copied into the app's own cache first and exposed through a
     * FileProvider, because Android refuses to hand a raw file path to
     * another app. The copy leaves the original export untouched.
     */
    private fun shareableUri(filePath: String): Uri {
        val source = File(filePath)
        val shared = File(cacheDir, "shared").apply { mkdirs() }
        val target = File(shared, source.name)
        source.copyTo(target, overwrite = true)
        return FileProvider.getUriForFile(this, "$packageName.sharing", target)
    }

    private fun mimeTypeFor(filePath: String): String {
        return when (filePath.substringAfterLast('.', "").lowercase()) {
            "pdf" -> "application/pdf"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "csv" -> "text/csv"
            "json" -> "application/json"
            else -> "application/octet-stream"
        }
    }

    private fun isInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Opens [target]; falls back to a plain chooser, then reports "no_app". */
    private fun open(target: Intent, fallback: Intent): String {
        return try {
            startActivity(target.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            "opened"
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(
                    Intent.createChooser(fallback, null)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                "opened"
            } catch (_: ActivityNotFoundException) {
                "no_app"
            }
        }
    }

    private fun shareToGmail(
        to: String,
        subject: String,
        body: String,
        filePath: String,
    ): String {
        val uri = try {
            shareableUri(filePath)
        } catch (_: Exception) {
            return "error"
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeTypeFor(filePath)
            putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, body)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // Gmail is opened directly when it is installed, so the message is
        // ready to review with the office address already in the "to" field.
        return if (isInstalled("com.google.android.gm")) {
            open(Intent(intent).setPackage("com.google.android.gm"), intent)
        } else {
            open(intent, intent)
        }
    }

    private fun shareToWhatsApp(text: String, filePath: String): String {
        val uri = try {
            shareableUri(filePath)
        } catch (_: Exception) {
            return "error"
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeTypeFor(filePath)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // WhatsApp does not let an app pick the chat, so its own contact
        // picker opens with the timesheet already attached.
        return if (isInstalled("com.whatsapp")) {
            open(Intent(intent).setPackage("com.whatsapp"), intent)
        } else {
            open(intent, intent)
        }
    }

    companion object {
        private const val CHANNEL = "com.example.timegrid/sharing"
    }
}
