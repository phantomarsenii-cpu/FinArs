package com.example.fa_ksiegowy

import android.content.Context
import android.util.Log
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDCheckBox
import com.tom_roush.pdfbox.pdmodel.interactive.form.PDTextField
import java.io.OutputStream
import java.util.Locale

/**
 * Заполняет ОФИЦИАЛЬНЫЙ бланк PIT-36 (шаблон в assets/forms/pit36_2025.pdf,
 * версия PIT-36(32) за 2025 rok) через настоящие поля AcroForm — не рисует
 * текст поверх картинки, а пишет прямо в поля бланка (p_1, p_12, p_87 и т.д.,
 * имена полей в PDF в точности совпадают с номерами позиций формы).
 *
 * ВАЖНО — сознательно ограниченный охват автозаполнения:
 *   Автоматически заполняются только:
 *     • идентификационные данные (PESEL, ФИО, адрес, urząd, способ rozliczenia),
 *     • ОДНА строка E.1: "Pozarolnicza działalność gospodarcza" (poz. 87–91)
 *       для зарегистрированного JDG на skali, либо "Działalność nierejestrowana"
 *       (poz. 116–119) — это именно то, что учитывает бухгалтерия приложения.
 *   НЕ заполняются автоматически: строки других источников дохода (etat,
 *   zlecenia и т.д.), odliczenia, ulgi, zaliczki już zapłacone, PIT/O, суммарные
 *   поля разделов E.1 "RAZEM", F, G, H, I, J, K (итоговый podatek należny).
 *   Причина: без данных о других доходах и odliczeniach автозаполнение итоговой
 *   суммы к уплате могло бы ввести пользователя в заблуждение. Эти поля нужно
 *   дозаполнить вручную (в Acrobat/na podatki.gov.pl) на основании PIT-11 и
 *   собственных odliczeń, используя расчёт из экрана PIT-36 приложения как
 *   черновую оценку.
 *   Шаблон датирован 2025 годом (PIT-36(32)) — для другого года подачи нужно
 *   использовать актуальный бланк с сайта podatki.gov.pl.
 */
object Pit36FormFiller {
    private const val TEMPLATE_ASSET = "forms/pit36_2025.pdf"
    private var resourceLoaderInitialized = false

    private fun ensureInit(context: Context) {
        if (!resourceLoaderInitialized) {
            PDFBoxResourceLoader.init(context.applicationContext)
            resourceLoaderInitialized = true
        }
    }

    private fun moneySimple(v: Double): String = String.format(Locale.US, "%.2f", v).replace(".", ",")

    private fun setText(doc: PDDocument, name: String, value: String?) {
        if (value.isNullOrBlank()) return
        try {
            val field = doc.documentCatalog.acroForm?.getField(name) as? PDTextField
            field?.setValue(value)
        } catch (e: Exception) {
            Log.w("Pit36FormFiller", "Field $name not set: ${e.message}")
        }
    }

    private fun check(doc: PDDocument, name: String) {
        try {
            val field = doc.documentCatalog.acroForm?.getField(name) as? PDCheckBox
            field?.check()
        } catch (e: Exception) {
            Log.w("Pit36FormFiller", "Checkbox $name not set: ${e.message}")
        }
    }

    /**
     * @return true если удалось заполнить официальный бланк (шаблон найден и обработан),
     *         false — если что-то пошло не так (например, ассет отсутствует) и стоит
     *         откатиться на информационный лист (Pit36PdfGenerator).
     */
    fun fill(
        context: Context,
        data: PitPersonalData,
        result: Pit36Calculator.Result,
        out: OutputStream
    ): Boolean {
        ensureInit(context)
        return try {
            context.assets.open(TEMPLATE_ASSET).use { input ->
                PDDocument.load(input).use { doc ->
                    val acro = doc.documentCatalog.acroForm
                    acro?.setNeedAppearances(true)

                    // B.1 — идентификация
                    setText(doc, "p_1", data.pesel)
                    setText(doc, "p_12", data.lastName)
                    setText(doc, "p_13", data.firstName)
                    setText(doc, "p_15", "Polska")
                    setText(doc, "p_16", data.voivodeship)
                    setText(doc, "p_17", data.county)
                    setText(doc, "p_18", data.commune)
                    setText(doc, "p_19", data.street)
                    setText(doc, "p_20", data.houseNumber)
                    setText(doc, "p_21", data.apartmentNumber)
                    setText(doc, "p_22", data.city)
                    setText(doc, "p_23", data.postalCode)
                    setText(doc, "p_9", data.taxOffice)

                    // poz. 6 — sposób rozliczenia: indywidualnie (a) / wspólnie z małżonkiem (b)
                    if (data.jointWithSpouse) check(doc, "p_6b") else check(doc, "p_6a")

                    // E.1 — ровно одна строка: то, что реально отслеживает бухгалтерия приложения
                    val przychod = moneySimple(result.przychod)
                    val koszty = moneySimple(result.koszty)
                    val dochod = if (result.dochod >= 0) moneySimple(result.dochod) else null
                    val strata = if (result.dochod < 0) moneySimple(-result.dochod) else null

                    if (result.activityType.isRegisteredJdg) {
                        // 3. Pozarolnicza działalność gospodarcza — poz. 87 (przychód), 88 (koszty), 89 (dochód), 90 (strata)
                        setText(doc, "p_87", przychod)
                        setText(doc, "p_88", koszty)
                        dochod?.let { setText(doc, "p_89", it) }
                        strata?.let { setText(doc, "p_90", it) }
                    } else {
                        // 8. Działalność nierejestrowana — poz. 116 (przychód), 117 (koszty), 118 (dochód), 119 (strata)
                        setText(doc, "p_116", przychod)
                        setText(doc, "p_117", koszty)
                        dochod?.let { setText(doc, "p_118", it) }
                        strata?.let { setText(doc, "p_119", it) }
                    }

                    doc.save(out)
                }
            }
            true
        } catch (e: Exception) {
            Log.e("Pit36FormFiller", "Failed to fill official PIT-36 template", e)
            false
        }
    }

    /** Официальное заполнение доступно только для skali (PIT-36) — для liniowy/ryczałt используется info-sheet. */
    fun isSupported(activityType: ActivityType): Boolean =
        activityType == ActivityType.NIEZAREJESTROWANA || activityType == ActivityType.JDG_SKALA
}
