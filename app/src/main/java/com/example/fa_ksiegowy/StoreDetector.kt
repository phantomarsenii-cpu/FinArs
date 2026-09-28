package com.example.fa_ksiegowy

import android.content.Context
import android.os.Build
import android.util.Log

/**
 * Определяет, из какого магазина установлено приложение — по системному
 * "installer package name" (тот, кто вызвал PackageInstaller при установке APK).
 *
 * Используется SubscriptionService, чтобы решить, какой ключ RevenueCat API
 * использовать: боевой (Google Play) или тестовый (установка через adb/Termux).
 */
object StoreDetector {

    private const val TAG = "StoreDetector"

    // Пакет самого Google Play (Play Store) — стандартный installer при установке с Play Console / из Play Store.
    private const val GOOGLE_PLAY_INSTALLER = "com.android.vending"

    fun detect(context: Context): StoreSource {
        val installer = installerPackageName(context)
        Log.i(TAG, "installerPackageName = $installer")
        return when (installer) {
            GOOGLE_PLAY_INSTALLER -> StoreSource.GOOGLE_PLAY
            else -> StoreSource.OTHER
        }
    }

    @Suppress("DEPRECATION")
    private fun installerPackageName(context: Context): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // getInstallerPackageName() устарел с API 30 — новый метод даёт более надёжный
                // результат (учитывает "initiating package" в случае цепочки установщиков).
                context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                context.packageManager.getInstallerPackageName(context.packageName)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read installer package name", e)
            null
        }
    }
}
