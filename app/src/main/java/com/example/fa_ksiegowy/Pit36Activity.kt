package com.example.fa_ksiegowy

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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Экран "PIT-36 (PRO)": выбор года, предпросмотр Przychód/Koszty/Dochód/podatek,
 * ссылка на форму личных данных и кнопка генерации PDF-отчёта (см. Pit36PdfGenerator).
 * Доступен только пользователям с Pro (проверка — в SettingsActivity перед стартом).
 */
class Pit36Activity : BaseActivity() {

    private var selectedYear = Calendar.getInstance().get(Calendar.YEAR) - 1
    private var lastResult: Pit36Calculator.Result? = null

    private val createPdfLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) writePdfTo(uri, official = false)
    }
    private val createOfficialPdfLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        if (uri != null) writePdfTo(uri, official = true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pit36)

        findViewById<Button>(R.id.btn_year_prev).setOnClickListener {
            selectedYear--; refreshYearLabel(); recalculate()
        }
        findViewById<Button>(R.id.btn_year_next).setOnClickListener {
            selectedYear++; refreshYearLabel(); recalculate()
        }
        findViewById<Button>(R.id.btn_edit_pit_data).setOnClickListener {
            startActivity(android.content.Intent(this, PitDataActivity::class.java))
        }
        findViewById<Button>(R.id.btn_generate_pit36).setOnClickListener { generateClicked(official = false) }
        findViewById<Button>(R.id.btn_generate_official_pit36).setOnClickListener { generateClicked(official = true) }

        refreshYearLabel()
    }

    override fun onResume() {
        super.onResume()
        recalculate()
    }

    private fun refreshYearLabel() {
        findViewById<TextView>(R.id.tv_pit_year).text = selectedYear.toString()
    }

    private fun recalculate() {
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val otherIncome = TaxHelper.getOtherIncome(prefs, selectedYear)
        val activityType = ActivityTypeHelper.get(prefs)
        val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
        CoroutineScope(Dispatchers.IO).launch {
            val db = AppDatabase.getInstance(applicationContext)
            val (start, endExclusive) = TaxHelper.yearRange(selectedYear)
            val entries = db.entryDao().getBetween(start, endExclusive - 1)
            val result = Pit36Calculator.calculate(entries, selectedYear, otherIncome, activityType, ryczaltRate)
            withContext(Dispatchers.Main) {
                lastResult = result
                showResult(result)
            }
        }
    }

    private fun showResult(r: Pit36Calculator.Result) {
        val money: (Double) -> String = { String.format(Locale.getDefault(), "%.2f zł", it) }
        findViewById<TextView>(R.id.tv_pit_przychod).text = money(r.przychod)
        findViewById<TextView>(R.id.tv_pit_koszty).text = money(r.koszty)
        findViewById<TextView>(R.id.tv_pit_dochod).text = money(r.dochod)
        findViewById<TextView>(R.id.tv_pit_tax).text = money(r.tax.tax)
        findViewById<TextView>(R.id.tv_pit_form_code)?.text =
            getString(R.string.pit_form_applicable, r.activityType.formCode)

        val data = PitDataStore.load(this)
        findViewById<TextView>(R.id.tv_pit_data_status).text = if (data.isComplete) {
            getString(R.string.pit_data_status_ready, "${data.firstName} ${data.lastName}".trim())
        } else {
            getString(R.string.pit_data_status_missing)
        }
    }

    private fun generateClicked(official: Boolean) {
        val data = PitDataStore.load(this)
        if (!data.isComplete) {
            Toast.makeText(this, getString(R.string.pit_data_required_error), Toast.LENGTH_LONG).show()
            startActivity(android.content.Intent(this, PitDataActivity::class.java))
            return
        }
        if (lastResult == null) {
            Toast.makeText(this, getString(R.string.pit36_calculating), Toast.LENGTH_SHORT).show()
            return
        }
        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        val activityType = ActivityTypeHelper.get(prefs)
        val formCode = activityType.formCode

        if (official) {
            if (!Pit36FormFiller.isSupported(activityType)) {
                Toast.makeText(this, getString(R.string.pit36_official_unsupported, formCode), Toast.LENGTH_LONG).show()
                return
            }
            createOfficialPdfLauncher.launch(FileNaming.pitFileName("${formCode}_OFFICIAL", selectedYear))
        } else {
            createPdfLauncher.launch(FileNaming.pitFileName(formCode, selectedYear))
        }
    }

    private fun writePdfTo(uri: Uri, official: Boolean) {
        val data = PitDataStore.load(this)
        val result = lastResult ?: return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                var usedOfficial = false
                if (official) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        usedOfficial = Pit36FormFiller.fill(this@Pit36Activity, data, result, out)
                    } ?: throw java.io.IOException("openOutputStream returned null")
                }
                if (!official || !usedOfficial) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        Pit36PdfGenerator.generate(this@Pit36Activity, data, result, out)
                    } ?: throw java.io.IOException("openOutputStream returned null")
                }
                withContext(Dispatchers.Main) {
                    val msgRes = if (official && usedOfficial) R.string.pit36_official_generated else R.string.pit36_generated
                    Toast.makeText(this@Pit36Activity, getString(msgRes), Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@Pit36Activity, getString(R.string.report_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}
