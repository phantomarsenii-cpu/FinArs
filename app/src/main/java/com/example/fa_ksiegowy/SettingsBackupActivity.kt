package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Резервная копия — через системное окно "Сохранить как" / "Открыть файл" (Storage
 * Access Framework). Пользователь сам выбирает, куда сохранить: память телефона,
 * Google Диск или любое другое подключённое хранилище — система показывает это
 * стандартным окном, без входа в аккаунт и настроек в коде приложения.
 *
 * Копия — это .zip: внутри backup.json (суммы, даты, комментарии, тип операции)
 * и папка receipts/ с фотографиями чеков, которые были прикреплены к записям.
 */
class SettingsBackupActivity : BaseActivity() {

    companion object {
        // Защита от Zip Bomb при восстановлении: даже маленький .zip не может
        // "развернуться" в данные, способные забить память/диск устройства.
        private const val MAX_BACKUP_ENTRIES = 20_000
        private const val MAX_JSON_ENTRY_BYTES = 50L * 1024 * 1024        // 50 МБ на backup.json
        private const val MAX_RECEIPT_ENTRY_BYTES = 25L * 1024 * 1024     // 25 МБ на один файл чека
        private const val MAX_TOTAL_UNCOMPRESSED_BYTES = 500L * 1024 * 1024 // 500 МБ суммарно на весь архив
    }

    private val dateForName = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US)
    private val dateForDisplay = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())

    private val createDocLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/zip")) { uri ->
        if (uri != null) writeBackupTo(uri)
    }
    private val openDocLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) confirmRestore(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_backup)

        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
        findViewById<Button>(R.id.btn_backup_now).setOnClickListener {
            val name = "fa_ksiegowy_backup_${dateForName.format(Date())}.zip"
            createDocLauncher.launch(name)
        }
        findViewById<Button>(R.id.btn_restore_now).setOnClickListener {
            openDocLauncher.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
        }
        findViewById<Button>(R.id.btn_clear_all).setOnClickListener { confirmClearAll() }

        showLastBackupTime()
    }

    private fun writeBackupTo(uri: Uri) {
        setButtonsEnabled(false)
        Toast.makeText(this, getString(R.string.backup_in_progress), Toast.LENGTH_SHORT).show()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val db = AppDatabase.getInstance(applicationContext)
                val entries = db.entryDao().getAll()

                val arr = JSONArray()
                for (e in entries) {
                    val o = JSONObject()
                    o.put("amount", e.amount)
                    o.put("isIncome", e.isIncome)
                    o.put("comment", e.comment ?: "")
                    o.put("dateMillis", e.dateMillis)
                    val receiptFile = e.receiptPath?.let { File(it) }
                    if (receiptFile != null && receiptFile.exists()) {
                        o.put("receiptFile", receiptFile.name)
                    }
                    arr.put(o)
                }

                contentResolver.openOutputStream(uri)?.use { out ->
                    ZipOutputStream(out).use { zos ->
                        zos.putNextEntry(ZipEntry("backup.json"))
                        zos.write(arr.toString().toByteArray(Charsets.UTF_8))
                        zos.closeEntry()

                        val addedNames = HashSet<String>()
                        for (e in entries) {
                            val path = e.receiptPath ?: continue
                            val f = File(path)
                            if (!f.exists() || !addedNames.add(f.name)) continue
                            zos.putNextEntry(ZipEntry("receipts/${f.name}"))
                            f.inputStream().use { it.copyTo(zos) }
                            zos.closeEntry()
                        }
                    }
                } ?: throw java.io.IOException("openOutputStream returned null")

                val prefs = getSharedPreferences("settings", MODE_PRIVATE)
                prefs.edit().putLong("lastBackupMillis", System.currentTimeMillis()).apply()

                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    showLastBackupTime()
                    Toast.makeText(this@SettingsBackupActivity, getString(R.string.backup_success, entries.size), Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    Toast.makeText(this@SettingsBackupActivity, getString(R.string.backup_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    /** Восстановление ДОБАВЛЯЕТ записи из копии к уже имеющимся на устройстве
     *  (не заменяет и не удаляет их). Для "чистого" восстановления сначала
     *  используйте "Очистить все данные" ниже, а затем восстановление. */
    private fun confirmRestore(uri: Uri) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.backup_restore_confirm_title))
            .setMessage(getString(R.string.backup_restore_confirm_message))
            .setPositiveButton(getString(R.string.backup_restore)) { _, _ -> runRestore(uri) }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    private fun runRestore(uri: Uri) {
        setButtonsEnabled(false)
        Toast.makeText(this, getString(R.string.backup_in_progress), Toast.LENGTH_SHORT).show()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                var jsonText: String? = null
                // оригинальное_имя_файла_в_архиве -> новый абсолютный путь на устройстве
                val restoredReceiptPaths = HashMap<String, String>()
                val receiptsDir = getExternalFilesDir(null)!!
                var receiptCounter = 0
                var entryCount = 0
                var totalUncompressedBytes = 0L

                contentResolver.openInputStream(uri)?.use { input ->
                    ZipInputStream(input).use { zis ->
                        var entry = zis.nextEntry
                        while (entry != null) {
                            entryCount++
                            if (entryCount > MAX_BACKUP_ENTRIES) {
                                throw IllegalStateException(getString(R.string.backup_invalid_file))
                            }
                            // Защита от Zip Slip: запись всегда идёт под сгенерированным именем
                            // (receipt_restored_...) в фиксированную папку — но на всякий случай
                            // отбрасываем записи с подозрительными именами (../, абсолютные пути),
                            // не полагаясь только на то, что имя из архива нигде не используется как путь.
                            val safeName = entry.name
                            if (safeName.contains("..") || safeName.startsWith("/")) {
                                zis.closeEntry()
                                entry = zis.nextEntry
                                continue
                            }
                            when {
                                safeName == "backup.json" -> {
                                    val bytes = readEntryLimited(zis, MAX_JSON_ENTRY_BYTES)
                                    totalUncompressedBytes += bytes.size
                                    if (totalUncompressedBytes > MAX_TOTAL_UNCOMPRESSED_BYTES) {
                                        throw IllegalStateException(getString(R.string.backup_invalid_file))
                                    }
                                    jsonText = bytes.toString(Charsets.UTF_8)
                                }
                                safeName.startsWith("receipts/") -> {
                                    val originalName = safeName.removePrefix("receipts/")
                                    val ext = originalName.substringAfterLast('.', "jpg")
                                    receiptCounter++
                                    val newFile = File(receiptsDir, "receipt_restored_${System.currentTimeMillis()}_$receiptCounter.$ext")
                                    val written = copyEntryLimited(zis, newFile, MAX_RECEIPT_ENTRY_BYTES)
                                    totalUncompressedBytes += written
                                    if (totalUncompressedBytes > MAX_TOTAL_UNCOMPRESSED_BYTES) {
                                        newFile.delete()
                                        throw IllegalStateException(getString(R.string.backup_invalid_file))
                                    }
                                    restoredReceiptPaths[originalName] = newFile.absolutePath
                                }
                            }
                            zis.closeEntry()
                            entry = zis.nextEntry
                        }
                    }
                } ?: throw java.io.IOException("openInputStream returned null")

                val json = jsonText ?: throw IllegalStateException(getString(R.string.backup_invalid_file))
                val arr = JSONArray(json)

                val db = AppDatabase.getInstance(applicationContext)
                var restored = 0
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val receiptFile = o.optString("receiptFile", "")
                    val receiptPath = if (receiptFile.isNotEmpty()) restoredReceiptPaths[receiptFile] else null
                    db.entryDao().insert(
                        Entry(
                            amount = o.getDouble("amount"),
                            isIncome = o.getBoolean("isIncome"),
                            comment = o.optString("comment", ""),
                            dateMillis = o.getLong("dateMillis"),
                            receiptPath = receiptPath
                        )
                    )
                    restored++
                }

                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    Toast.makeText(this@SettingsBackupActivity, getString(R.string.backup_restored, restored), Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    Toast.makeText(this@SettingsBackupActivity, getString(R.string.backup_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    /** Читает текущую zip-запись в память, но не более [maxBytes] — если запись
     *  оказывается больше (например, "раздутый" zip bomb), сразу бросает ошибку
     *  вместо того чтобы вычитывать её целиком. */
    private fun readEntryLimited(zis: ZipInputStream, maxBytes: Long): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        var total = 0L
        while (true) {
            val read = zis.read(buffer)
            if (read < 0) break
            total += read
            if (total > maxBytes) throw IllegalStateException(getString(R.string.backup_invalid_file))
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    /** Копирует текущую zip-запись в файл, но не более [maxBytes]. Возвращает
     *  число записанных байт. При превышении лимита останавливается и бросает ошибку. */
    private fun copyEntryLimited(zis: ZipInputStream, destination: File, maxBytes: Long): Long {
        val buffer = ByteArray(8 * 1024)
        var total = 0L
        destination.outputStream().use { fos ->
            while (true) {
                val read = zis.read(buffer)
                if (read < 0) break
                total += read
                if (total > maxBytes) throw IllegalStateException(getString(R.string.backup_invalid_file))
                fos.write(buffer, 0, read)
            }
        }
        return total
    }

    private fun showLastBackupTime() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val last = prefs.getLong("lastBackupMillis", -1L)
        findViewById<TextView>(R.id.tv_last_backup).text = if (last <= 0L) {
            getString(R.string.backup_never)
        } else {
            getString(R.string.backup_last_time, dateForDisplay.format(Date(last)))
        }
    }

    private fun setButtonsEnabled(enabled: Boolean) {
        findViewById<Button>(R.id.btn_backup_now).isEnabled = enabled
        findViewById<Button>(R.id.btn_restore_now).isEnabled = enabled
    }

    /** Необратимо удаляет все доходы/расходы (только записи в базе — файлы чеков
     *  на диске не трогает). Логически относится к управлению данными приложения. */
    private fun confirmClearAll() {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.clear_all_confirm_title))
            .setMessage(getString(R.string.clear_all_confirm_message))
            .setPositiveButton(getString(R.string.clear_all_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).entryDao().deleteAll()
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@SettingsBackupActivity, getString(R.string.clear_all_done), Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
