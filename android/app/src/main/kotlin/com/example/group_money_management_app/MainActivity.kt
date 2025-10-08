package com.example.group_money_management_app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app_checker"
    private val TAG = "AppChecker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call,
                result ->
            when (call.method) {
                "isAppInstalled" -> {
                    val packageName = call.argument<String>("package_name")
                    val isInstalled = isAppAvailable(packageName)
                    result.success(isInstalled)
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("package_name")
                    val launched = launchApp(packageName)
                    result.success(launched)
                }
                "launchAppWithDetails" -> {
                    val packageName = call.argument<String>("package_name")
                    val details = launchAppWithDetails(packageName)
                    result.success(details)
                }
                // "openInPlayStore" -> {
                //     val packageName = call.argument<String>("package_name")
                //     val opened = openInPlayStore(packageName)
                //     result.success(opened)
                // }
                // "openAppSettings" -> {
                //     val packageName = call.argument<String>("package_name")
                //     val opened = openAppSettings(packageName)
                //     result.success(opened)
                // }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAppAvailable(packageName: String?): Boolean {
        return try {
            packageManager.getPackageInfo(packageName!!, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun launchApp(packageName: String?): Boolean {
        if (packageName == null) return false

        Log.d(TAG, "Attempting to launch app: $packageName")

        return try {
            // Method 1: Try getting launch intent from package manager
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                Log.d(TAG, "Found launch intent for: $packageName")
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)
                return true
            }

            // Method 2: Try finding launcher activity manually
            val mainIntent =
                    Intent(Intent.ACTION_MAIN, null).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        setPackage(packageName)
                    }

            val apps = packageManager.queryIntentActivities(mainIntent, 0)
            if (apps.isNotEmpty()) {
                val resolveInfo = apps[0]
                val activityName = resolveInfo.activityInfo.name
                Log.d(TAG, "Found launcher activity: $activityName")

                val component = ComponentName(packageName, activityName)
                val activityIntent =
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                            setComponent(component)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }

                startActivity(activityIntent)
                return true
            }

            Log.w(TAG, "No launcher activity found for: $packageName")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: $packageName", e)
            false
        }
    }

    private fun launchAppWithDetails(packageName: String?): Map<String, Any> {
        val result = mutableMapOf<String, Any>()

        if (packageName == null) {
            result["success"] = false
            result["error"] = "Package name is null"
            return result
        }

        Log.d(TAG, "=== Attempting to launch with details: $packageName ===")

        try {
            // Method 1: Try package manager launch intent
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                Log.d(TAG, "Method 1: Using package manager launch intent")
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(launchIntent)

                result["success"] = true
                result["method"] = "package_manager_intent"
                result["activity"] = launchIntent.component?.className ?: "unknown"
                return result
            }

            // Method 2: Manual launcher activity search
            val mainIntent =
                    Intent(Intent.ACTION_MAIN, null).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        setPackage(packageName)
                    }

            val apps = packageManager.queryIntentActivities(mainIntent, 0)
            if (apps.isNotEmpty()) {
                val resolveInfo = apps[0]
                val activityName = resolveInfo.activityInfo.name
                Log.d(TAG, "Method 2: Using manual launcher activity: $activityName")

                val component = ComponentName(packageName, activityName)
                val activityIntent =
                        Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_LAUNCHER)
                            setComponent(component)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        }

                startActivity(activityIntent)

                result["success"] = true
                result["method"] = "manual_launcher_activity"
                result["activity"] = activityName
                return result
            }

            // Method 3: Try common activity patterns
            val commonActivities =
                    listOf(
                            "$packageName.MainActivity",
                            "$packageName.SplashActivity",
                            "$packageName.LoginActivity",
                            "$packageName.HomeActivity",
                            "$packageName.ui.MainActivity",
                            "$packageName.activities.MainActivity",
                            "$packageName.activity.MainActivity"
                    )

            for (activityName in commonActivities) {
                try {
                    Log.d(TAG, "Method 3: Trying common activity: $activityName")
                    val component = ComponentName(packageName, activityName)
                    val intent =
                            Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_LAUNCHER)
                                setComponent(component)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            }

                    startActivity(intent)

                    result["success"] = true
                    result["method"] = "common_activity_pattern"
                    result["activity"] = activityName
                    return result
                } catch (e: Exception) {
                    Log.d(TAG, "Failed to launch with activity: $activityName")
                }
            }

            Log.w(TAG, "All launch methods failed for: $packageName")
            result["success"] = false
            result["error"] = "No viable launch method found"
            result["method"] = "none"
        } catch (e: Exception) {
            Log.e(TAG, "Error in launchAppWithDetails: $packageName", e)
            result["success"] = false
            result["error"] = e.message ?: "Unknown error"
            result["method"] = "exception"
        }

        return result
    }

    private fun openAppSettings(packageName: String?): Boolean {
        if (packageName == null) return false

        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error opening app settings for: $packageName", e)
            false
        }
    }
}
