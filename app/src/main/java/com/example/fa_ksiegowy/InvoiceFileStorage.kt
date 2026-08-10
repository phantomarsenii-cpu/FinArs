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
 * Zapisuje wygenerowane PDF-y faktur/rachunków w publicznym, wspólnym dla
 * wszystkich aplikacji katalogu Documents/FinArs/Invoices, tak by klient
 * mógł je łatwo znaleźć dowolnym menedżerem plików i wysłać dalej.
 *
 * Android 10+ (API 29+): zapis przez MediaStore (Scoped Storage) —
 * aplikacja NIE potrzebuje uprawnienia WRITE_EXTERNAL_STORAGE.
 * Android 8–9 (API 26–28): bezpośredni zapis pliku do publicznego katalogu
 * Documents (wymaga WRITE_EXTERNAL_STORAGE, zadeklarowanego w Manifest
 * z maxSdkVersion="28" — na nowszych wersjach jest ignorowane/niepotrzebne).
 */
object InvoiceFileStorage {

    private const val RELATIVE_FOLDER = "FinArs/Invoices"
    private const val MIME_PDF = "application/pdf"

    data class SavedPdf(val uri: Uri, val displayPath: String)

    /**
     * Zapisuje PDF pod wskazaną nazwą, wywołując [writer] z otwartym
     * OutputStream. Zwraca URI (do otwierania/udostępniania) i ścieżkę
     * do wyświetlenia użytkownikowi.
     */
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
            // Podczas zapisu plik jest "niedokończony" dla innych aplikacji — zdejmujemy
            // flagę dopiero po zapisaniu zawartości (patrz niżej).
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
            // Sprzątamy niedokończony wpis, żeby nie zostawiać "ducha" w MediaStore.
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
        // file:// URI-ów nie wolno przekazywać do innych aplikacji od API 24 (FileUriExposedException) —
        // używamy FileProvider, tak jak przy udostępnianiu czeków/raportów w reszcie aplikacji.
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        return SavedPdf(uri, file.absolutePath)
    }

    /** Intent do otwarcia zapisanego PDF w systemowej przeglądarce PDF. */
    fun viewIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, MIME_PDF)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** Intent do wysłania PDF przez inną aplikację (WhatsApp, Telegram, e-mail…). */
    fun shareIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_SEND).apply {
            type = MIME_PDF
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

    /**
     * Best-effort otwarcie katalogu Documents/FinArs/Invoices w systemowym
     * menedżerze plików. Nie wszystkie menedżery plików obsługują otwieranie
     * konkretnego podkatalogu przez Intent — jeśli się nie uda, wywołujący
     * powinien złapać ActivityNotFoundException i pokazać ścieżkę tekstem.
     */
    fun openFolderIntent(): Intent {
        val docId = "primary:${Environment.DIRECTORY_DOCUMENTS}/$RELATIVE_FOLDER"
        val folderUri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", docId)
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(folderUri, DocumentsContract.Document.MIME_TYPE_DIR)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    val displayFolderPath: String get() = "Documents/$RELATIVE_FOLDER"

    /**
     * На части urządzeń/wersji Androida (np. niektóre One UI) system rzuca
     * SecurityException przy próbie START_ACTIVITY z FLAG_GRANT_READ_URI_PERMISSION
     * dla URI z generic MediaStore.Files collection ("content://media/.../file/...") —
     * mimo że aplikacja jest właścicielem wpisu. Awaryjnie kopiujemy plik do
     * wewnętrznego cache aplikacji i oddajemy URI przez FileProvider, dla którego
     * grant zawsze się udaje (nasz własny provider, nasza aplikacja).
     */
    fun resolveViewableUri(context: Context, original: Uri): Uri {
        return try {
            val cacheDir = File(context.cacheDir, "invoice_view_cache")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val tmp = File(cacheDir, "invoice_${System.currentTimeMillis()}.pdf")
            val input = context.contentResolver.openInputStream(original)
                ?: return original
            input.use { inp -> tmp.outputStream().use { out -> inp.copyTo(out) } }
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", tmp)
        } catch (e: Exception) {
            original
        }
    }

    /**
     * Otwiera Intent ACTION_VIEW dla PDF, z automatycznym fallbackiem na
     * [resolveViewableUri], jeśli pierwsza próba startActivity rzuci wyjątkiem
     * (SecurityException z powodu MediaStore, ActivityNotFoundException itd.).
     * Zwraca true, jeśli udało się otworzyć (którymkolwiek sposobem).
     */
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
            // ActivityNotFoundException, SecurityException (znany problem MediaStore
            // na niektórych urządzeniach) — próbujemy raz jeszcze przez lokalną kopię.
        }
        return try {
            val fallback = resolveViewableUri(context, original)
            context.startActivity(viewIntent(fallback))
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Nadpisuje już zapisany plik PDF nową zawartością (np. po zmianie statusu
     * faktury na opłaconą) — próbuje kolejnych trybów otwarcia strumienia, bo
     * różne dostawcy URI (MediaStore vs FileProvider) różnie obsługują "wt".
     * Zwraca true, jeśli zapis się powiódł.
     */
    fun overwritePdf(context: Context, uriString: String, writer: (OutputStream) -> Unit): Boolean {
        val uri = try {
            Uri.parse(uriString)
        } catch (e: Exception) {
            return false
        }
        val modes = listOf("wt", "rwt", "w")
        for (mode in modes) {
            try {
                val out = context.contentResolver.openOutputStream(uri, mode) ?: continue
                out.use { writer(it) }
                return true
            } catch (e: Exception) {
                // próbujemy kolejnego trybu
            }
        }
        return false
    }

    /**
     * Usuwa zapisany plik PDF (dziala zarowno dla URI z MediaStore, jak i z
     * FileProvider na starszych Androidach) — uzywane przy kasowaniu bledngo
     * wpisu z historii faktur.
     */
    fun deleteFile(context: Context, uriString: String): Boolean {
        return try {
            val uri = Uri.parse(uriString)
            context.contentResolver.delete(uri, null, null) > 0
        } catch (e: Exception) {
            false
        }
    }
}

