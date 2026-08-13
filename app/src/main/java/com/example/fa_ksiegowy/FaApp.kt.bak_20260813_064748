package com.example.fa_ksiegowy

import android.app.Activity
import android.app.Application
import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Application-класс: ставит глобальный обработчик необработанных исключений.
 * Сохраняет полный текст краша (стектрейс) в файл в папке "Загрузки"
 * (finars_crash_ГГГГММДД_ЧЧММСС.txt), чтобы его можно было прочитать через
 * Termux (cat /storage/emulated/0/Download/finars_crash_*.txt) — обычный
 * logcat не показывает логи чужого приложения без прав root.
 *
 * После записи лога вызывается стандартный обработчик системы — поведение
 * приложения при краше (закрытие) не меняется, только добавляется файл.
 */
class FaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        LimitsNotificationWorker.createChannel(this)
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                saveCrashLog(this, throwable)
            } catch (e: Throwable) {
                // Если даже запись лога не удалась — не мешаем системному обработчику
            }
            defaultHandler?.uncaughtException(thread, throwable)
        }

        // Отслеживаем переход приложения на передний план/в фон для блокировки по PIN.
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                AppLockState.onActivityStarted(activity)
            }
            override fun onActivityStopped(activity: Activity) {
                AppLockState.onActivityStopped()
            }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    private fun saveCrashLog(context: Context, throwable: Throwable) {
        val sw = StringWriter()
        throwable.printStackTrace(PrintWriter(sw))
        val text = "FinArs crash log\n" +
            SimpleDateFormat("dd.MM.yyyy HH:mm:ss", Locale.US).format(Date()) + "\n\n" +
            sw.toString()
        val fileName = "finars_crash_" +
            SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".txt"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri != null) {
                context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
            }
        } else {
            @Suppress("DEPRECATION")
            val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            downloads.mkdirs()
            val file = File(downloads, fileName)
            FileOutputStream(file).use { it.write(text.toByteArray()) }
        }
    }
}
