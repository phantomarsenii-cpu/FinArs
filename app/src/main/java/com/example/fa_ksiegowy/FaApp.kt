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
 *
 * В DEBUG-сборке (adb install / Android Studio) сохраняет полный текст краша
 * (стектрейс) в файл в папке "Загрузки" (finars_crash_ГГГГММДД_ЧЧММСС.txt),
 * чтобы его можно было прочитать через Termux — удобно при разработке.
 *
 * В RELEASE-сборке (то, что уходит в Google Play / Galaxy Store) стектрейс
 * НЕ пишется в публичную папку — детальная информация об ошибке (имена
 * классов/методов, внутренняя структура приложения) не должна быть доступна
 * произвольному приложению на устройстве пользователя. Вместо этого лог
 * пишется только во внутреннее приватное хранилище приложения (доступное
 * исключительно самому FinArs), просто как резерв на случай, если
 * пользователь сам захочет прислать лог в поддержку.
 *
 * После записи лога вызывается стандартный обработчик системы — поведение
 * приложения при краше (закрытие) не меняется, только добавляется файл.
 */
class FaApp : Application() {

    override fun onCreate() {
        super.onCreate()
        // Инициализация RevenueCat: определяет магазин установки (Google Play / Galaxy
        // Store / прочее) и конфигурирует Purchases SDK соответствующим ключом.
        // См. SubscriptionService.kt и StoreDetector.kt.
        SubscriptionService.init(this)
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

        val isDebuggable = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) {
            // Релиз: только приватное хранилище приложения — не видно ни другим
            // приложениям, ни через файловый менеджер/Термукс без root.
            val file = File(context.filesDir, fileName)
            FileOutputStream(file).use { it.write(text.toByteArray()) }
            return
        }

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
