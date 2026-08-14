package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

/**
 * Przechowuje ścieżkę do logo firmy wgranego przez użytkownika (przycisk "Wgraj logo
 * firmy" w bloku Sprzedawcy — patrz activity_add_invoice.xml). Plik kopiowany jest do
 * wewnętrznego magazynu aplikacji (filesDir), więc działa niezależnie od tego, czy
 * oryginalny URI z pickera pozostaje ważny (Storage Access Framework potrafi cofnąć
 * dostęp do URI po restarcie aplikacji).
 *
 * Jeśli logo NIE zostało wgrane — InvoiceHtmlPdfGenerator.buildLogoImgTag() spada z
 * powrotem na domyślne R.drawable.logo (logo FinArs), zgodnie z wymaganiem punktu 3.
 */
object InvoiceLogoStore {
    private const val PREFS = "invoice_logo_data"
    private const val KEY_PATH = "logo_path"
    private const val FILE_NAME = "seller_logo.png"

    /** Zwraca ścieżkę do zapisanego logo, albo null jeśli użytkownik nie wgrał własnego. */
    fun load(context: Context): String? {
        val path = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PATH, null)
        return if (path != null && File(path).exists()) path else null
    }

    /** Kopiuje wybrany obraz (z pickera galerii — ActivityResultContracts.GetContent) do
     *  wewnętrznego magazynu, dekodując i zapisując jako PNG (normalizacja formatu —
     *  usuwa problem z HEIC/WEBP, których WebView mógłby nie obsłużyć jednolicie).
     *  Zwraca true, jeśli zapis się powiódł. */
    fun saveFromUri(context: Context, uri: Uri): Boolean {
        return try {
            val bitmap: Bitmap = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it)
            } ?: return false

            // Ograniczenie rozmiaru, żeby nie rozdymać PDF (base64 w HTML) — logo w
            // nagłówku ma maks. 22mm wysokości/szerokości (patrz CSS .brand img.logo),
            // 480px w każdym wymiarze to więcej niż wystarczająco dla druku.
            val maxDim = 480
            val scaled = if (bitmap.width > maxDim || bitmap.height > maxDim) {
                val ratio = minOf(maxDim.toFloat() / bitmap.width, maxDim.toFloat() / bitmap.height)
                Bitmap.createScaledBitmap(bitmap, (bitmap.width * ratio).toInt(), (bitmap.height * ratio).toInt(), true)
            } else bitmap

            val outFile = File(context.filesDir, FILE_NAME)
            FileOutputStream(outFile).use { out -> scaled.compress(Bitmap.CompressFormat.PNG, 100, out) }

            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_PATH, outFile.absolutePath)
                .apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Usuwa wgrane logo — dokument wraca do domyślnego logo FinArs. */
    fun clear(context: Context) {
        val path = load(context)
        if (path != null) File(path).delete()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_PATH).apply()
    }
}
