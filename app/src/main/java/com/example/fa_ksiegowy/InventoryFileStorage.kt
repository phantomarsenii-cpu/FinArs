package com.example.fa_ksiegowy

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.io.OutputStream

/**
 * Zapisuje PDF-y raportów inwentaryzacji w publicznym katalogu
 * Documents/FinArs/Inventory — dokładnie ten sam wzorzec, co
 * [InvoiceFileStorage] dla faktur/rachunków (osobny katalog, żeby nie
 * mieszać dokumentów sprzedaży z raportami magazynowymi).
 */
object InventoryFileStorage {

    private const val RELATIVE_FOLDER = "FinArs/Inventory"
    private const val MIME_PDF = "application/pdf"

    data class SavedPdf(val uri: Uri, val displayPath: String)

    fun savePdf(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, fileName, writer)
        } else {
            saveViaLegacyFile(context, fileName, writer)
        }
    }

    private fun saveViaMediaStore(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, MIME_PDF)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOCUMENTS}/$RELATIVE_FOLDER")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed for $fileName")

        try {
            resolver.openOutputStream(uri)?.use { out -> writer(out) }
                ?: throw IllegalStateException("Could not open output stream for $uri")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        return SavedPdf(uri, "Documents/$RELATIVE_FOLDER/$fileName")
    }

    private fun saveViaLegacyFile(context: Context, fileName: String, writer: (OutputStream) -> Unit): SavedPdf {
        @Suppress("DEPRECATION")
        val documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val targetDir = File(documentsDir, RELATIVE_FOLDER)
        if (!targetDir.exists()) targetDir.mkdirs()
        val file = File(targetDir, fileName)
        file.outputStream().use { out -> writer(out) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        return SavedPdf(uri, file.absolutePath)
    }

    /** Intent do otwarcia zapisanego PDF w systemowej przeglądarce PDF. */
    fun viewIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, MIME_PDF)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    fun openFolderIntent(): Intent {
        val docId = "primary:${Environment.DIRECTORY_DOCUMENTS}/$RELATIVE_FOLDER"
        val folderUri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(folderUri, DocumentsContract.Document.MIME_TYPE_DIR)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    val displayFolderPath: String get() = "Documents/$RELATIVE_FOLDER"

    /** Patrz [InvoiceFileStorage.resolveViewableUri] — ten sam obejście dla
     *  urządzeń, na których START_ACTIVITY z generic MediaStore URI rzuca SecurityException. */
    fun resolveViewableUri(context: Context, original: Uri): Uri {
        return try {
            val cacheDir = File(context.cacheDir, "inventory_view_cache")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val tmp = File(cacheDir, "inventory_${System.currentTimeMillis()}.pdf")
            val input = context.contentResolver.openInputStream(original)
                ?: return original
            input.use { inp -> tmp.outputStream().use { out -> inp.copyTo(out) } }
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", tmp)
        } catch (e: Exception) {
            original
        }
    }

    /** Zwraca true, jeśli udało się otworzyć PDF (którymkolwiek sposobem). */
    fun openPdfSafely(context: Context, uriString: String): Boolean {
        val original = try {
            Uri.parse(uriString)
        } catch (e: Exception) {
            return false
        }
        try {
            context.startActivity(viewIntent(original))
            return true
        } catch (e: Exception) {
            // próbujemy raz jeszcze przez lokalną kopię
        }
        return try {
            val fallback = resolveViewableUri(context, original)
            context.startActivity(viewIntent(fallback))
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Usuwa zapisany plik PDF (MediaStore lub FileProvider) — używane przy
     *  kasowaniu wpisu z historii inwentaryzacji. */
    fun deleteFile(context: Context, uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            context.contentResolver.delete(uri, null, null) > 0
        } catch (e: Exception) {
            false
        }
    }
}
