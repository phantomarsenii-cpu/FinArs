package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Update: экран выставления Faktura korygująca (корректировочной фактуры) к уже
 * выставленному документу. Открывается из InvoiceHistoryActivity по кнопке "↺"
 * на строке фактуры (см. InvoiceAdapter/item_invoice.xml), обязательный extra —
 * EXTRA_INVOICE_ID.
 *
 * Дельта (correctedAmount - originalAmount) может быть, по желанию пользователя
 * (галочка cb_apply_to_income, отмечена по умолчанию), сразу же записана как Entry
 * (isIncome=true, amount=delta) — это тот же самый механизм, которым обычные
 * приходы уже участвуют в расчёте Dochód/Podatek/лимитов (см. TaxHelper/LimitsHelper),
 * поэтому отдельно трогать их не нужно: отрицательная delta корректно уменьшит
 * Przychód, положительная — увеличит.
 */
class AddInvoiceCorrectionActivity : BaseActivity() {

    companion object {
        const val EXTRA_INVOICE_ID = "invoiceId"
    }

    private lateinit var originalInvoice: Invoice
    private val moneyFmt = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_invoice_correction)

        val invoiceId = intent.getLongExtra(EXTRA_INVOICE_ID, -1L)
        if (invoiceId < 0) {
            finish()
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            val invoice = AppDatabase.getInstance(applicationContext).invoiceDao().getById(invoiceId)
            withContext(Dispatchers.Main) {
                if (invoice == null) {
                    finish()
                    return@withContext
                }
                originalInvoice = invoice
                bindOriginalInvoiceInfo()
            }
        }

        findViewById<Button>(R.id.btn_save_correction).setOnClickListener { saveCorrection() }
    }

    private fun bindOriginalInvoiceInfo() {
        findViewById<TextView>(R.id.tv_original_invoice_info).text =
            getString(R.string.correction_original_invoice_label, originalInvoice.invoiceNumber, originalInvoice.buyerName)
        val amountStr = String.format(Locale.getDefault(), "%.2f", originalInvoice.amount)
        findViewById<TextView>(R.id.tv_original_amount).text =
            "${getString(R.string.correction_original_amount_label)}: $amountStr zł · ${moneyFmt.format(Date(originalInvoice.issueDateMillis))}"
        findViewById<EditText>(R.id.et_corrected_amount).setText(
            String.format(Locale.US, "%.2f", originalInvoice.amount)
        )
    }

    private fun saveCorrection() {
        val correctedText = findViewById<EditText>(R.id.et_corrected_amount).text.toString().replace(",", ".").trim()
        val corrected = correctedText.toDoubleOrNull()
        if (corrected == null) {
            Toast.makeText(this, getString(R.string.enter_amount), Toast.LENGTH_SHORT).show()
            return
        }
        val reason = findViewById<EditText>(R.id.et_reason).text.toString().trim()
        if (reason.isBlank()) {
            Toast.makeText(this, getString(R.string.correction_reason_required_error), Toast.LENGTH_SHORT).show()
            return
        }
        val delta = corrected - originalInvoice.amount
        if (delta == 0.0) {
            Toast.makeText(this, getString(R.string.correction_zero_delta_error), Toast.LENGTH_SHORT).show()
            return
        }
        val applyToIncome = findViewById<CheckBox>(R.id.cb_apply_to_income).isChecked
        val btn = findViewById<Button>(R.id.btn_save_correction)
        btn.isEnabled = false

        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val correctionNumber = (db.invoiceCorrectionDao().getMaxCorrectionNumber() ?: 0) + 1
            val issueDateMillis = System.currentTimeMillis()
            val fileName = FileNaming.invoiceCorrectionFileName(correctionNumber, issueDateMillis)

            val saved = InvoiceFileStorage.savePdf(applicationContext, fileName) { out ->
                InvoicePdfGenerator.generateCorrection(
                    context = this@AddInvoiceCorrectionActivity,
                    seller = InvoiceSellerDataStore.load(applicationContext),
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    originalInvoiceNumber = originalInvoice.invoiceNumber,
                    originalIssueDateMillis = originalInvoice.issueDateMillis,
                    buyerName = originalInvoice.buyerName,
                    buyerNip = originalInvoice.buyerNip,
                    buyerStreet = originalInvoice.buyerStreet,
                    buyerPostalCode = originalInvoice.buyerPostalCode,
                    buyerCity = originalInvoice.buyerCity,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    reason = reason,
                    out = out
                )
            }

            db.invoiceCorrectionDao().insert(
                InvoiceCorrection(
                    originalInvoiceId = originalInvoice.id,
                    correctionNumber = correctionNumber,
                    issueDateMillis = issueDateMillis,
                    reason = reason,
                    originalAmount = originalInvoice.amount,
                    correctedAmount = corrected,
                    deltaAmount = delta,
                    pdfFilePath = saved.uri.toString(),
                    pdfFileName = fileName,
                    appliedToIncome = applyToIncome
                )
            )

            if (applyToIncome) {
                db.entryDao().insert(
                    Entry(
                        amount = delta,
                        isIncome = true,
                        comment = getString(R.string.correction_pdf_title) + " ${correctionNumber} — " +
                            getString(R.string.correction_pdf_to_invoice) + " ${originalInvoice.invoiceNumber}",
                        dateMillis = issueDateMillis,
                        receiptPath = null,
                        ryczaltCategory = null
                    )
                )
            }

            withContext(Dispatchers.Main) {
                Toast.makeText(this@AddInvoiceCorrectionActivity, getString(R.string.correction_saved_toast), Toast.LENGTH_SHORT).show()
                InvoiceFileStorage.openPdfSafely(this@AddInvoiceCorrectionActivity, saved.uri.toString())
                finish()
            }
        }
    }
}

