package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import java.util.Calendar
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.apache.poi.ss.usermodel.BorderStyle
import org.apache.poi.ss.usermodel.FillPatternType
import org.apache.poi.ss.usermodel.HorizontalAlignment
import org.apache.poi.ss.usermodel.IndexedColors
import org.apache.poi.xssf.usermodel.XSSFWorkbook
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ReportActivity : BaseActivity() {
    lateinit var db: AppDatabase

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_report)
        db = AppDatabase.getInstance(this)
        findViewById<Button>(R.id.btn_report_month).setOnClickListener { generateForMonth() }
        findViewById<Button>(R.id.btn_report_year).setOnClickListener {
            runIfPro { generateForYear() }
        }
        findViewById<Button>(R.id.btn_report_custom).setOnClickListener {
            runIfPro { showCustomRangePicker() }
        }
        loadChart()
    }

    /** Загружает суммы доходов/расходов за последние 6 месяцев для графика на экране отчётов. */
    private fun loadChart() {
        CoroutineScope(Dispatchers.IO).launch {
            val cal = Calendar.getInstance()
            val monthFmt = SimpleDateFormat("LLL", Locale.getDefault())
            val points = mutableListOf<MonthlyBarChartView.MonthPoint>()

            for (i in 5 downTo 0) {
                val monthCal = cal.clone() as Calendar
                monthCal.add(Calendar.MONTH, -i)
                monthCal.set(Calendar.DAY_OF_MONTH, 1)
                monthCal.set(Calendar.HOUR_OF_DAY, 0); monthCal.set(Calendar.MINUTE, 0)
                monthCal.set(Calendar.SECOND, 0); monthCal.set(Calendar.MILLISECOND, 0)
                val from = monthCal.timeInMillis
                val label = monthFmt.format(monthCal.time)
                monthCal.add(Calendar.MONTH, 1)
                val to = monthCal.timeInMillis - 1

                val entries = db.entryDao().getBetween(from, to)
                val income = entries.filter { it.isIncome }.sumOf { it.amount }
                val expense = entries.filter { !it.isIncome }.sumOf { it.amount }
                points.add(MonthlyBarChartView.MonthPoint(label, income, expense))
            }

            withContext(Dispatchers.Main) {
                findViewById<MonthlyBarChartView>(R.id.chart_monthly).submitData(points)
            }
        }
    }

    /** Годовой и произвольный отчёт — платная функция; месячный остаётся бесплатным. */
    private fun runIfPro(action: () -> Unit) {
        if (BillingManager.isPro(this)) {
            action()
        } else {
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle(getString(R.string.pro_feature_locked_title))
                .setMessage(getString(R.string.pro_feature_locked_message))
                .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                    startActivity(Intent(this, SettingsActivity::class.java))
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }
    }

    /**
     * Произвольный период: два DatePickerDialog подряd — сначала выбираем дату "от",
     * затем "до". Лимит 30 000 zł к произвольному периоду не применяем (как и к
     * месячному отчёту) — он корректно применим только к целому календарному году.
     */
    private fun showCustomRangePicker() {
        val cal = Calendar.getInstance()
        DatePickerDialog(
            this,
            { _, fromYear, fromMonth, fromDay ->
                val fromCal = Calendar.getInstance()
                fromCal.set(fromYear, fromMonth, fromDay, 0, 0, 0)
                fromCal.set(Calendar.MILLISECOND, 0)
                val fromMillis = fromCal.timeInMillis

                DatePickerDialog(
                    this,
                    { _, toYear, toMonth, toDay ->
                        val toCal = Calendar.getInstance()
                        toCal.set(toYear, toMonth, toDay, 23, 59, 59)
                        toCal.set(Calendar.MILLISECOND, 999)
                        val toMillis = toCal.timeInMillis

                        if (toMillis < fromMillis) {
                            Toast.makeText(this, getString(R.string.custom_range_invalid), Toast.LENGTH_LONG).show()
                            return@DatePickerDialog
                        }
                        generateReport(fromMillis, toMillis, getString(R.string.report_title_custom), applyAnnualLimit = false)
                    },
                    cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
                ).apply { setTitle(getString(R.string.to)) }.show()
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).apply { setTitle(getString(R.string.from)) }.show()
    }

    private fun generateForMonth() {
        val now = System.currentTimeMillis()
        val monthMs = 30L * 24 * 60 * 60 * 1000
        // Лимит 30 000 zł годовой, к частичному периоду его применять некорректно
        // (профит за один месяц почти всегда меньше лимита, отчёт вводил бы в
        // заблуждение) — поэтому здесь налог считается по старой формуле, без лимита.
        generateReport(now - monthMs, now, getString(R.string.report_title_month), applyAnnualLimit = false, fileTypeCode = "REPORT_MONTH")
    }

    private fun generateForYear() {
        val year = TaxHelper.currentYear()
        val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
        val now = System.currentTimeMillis()
        generateReport(
            yearStart, minOf(now, yearEndExclusive - 1),
            getString(R.string.report_title_year), applyAnnualLimit = true, year = year, fileTypeCode = "REPORT_YEAR"
        )
    }

    private fun generateReport(
        from: Long, to: Long, title: String,
        applyAnnualLimit: Boolean, year: Int = TaxHelper.currentYear(), fileTypeCode: String = "REPORT_CUSTOM"
    ) {
        setButtonsEnabled(false)
        Toast.makeText(this, getString(R.string.report_generating), Toast.LENGTH_SHORT).show()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val entries = db.entryDao().getBetween(from, to)
                if (entries.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@ReportActivity, getString(R.string.no_entries), Toast.LENGTH_LONG).show()
                        setButtonsEnabled(true)
                    }
                    return@launch
                }

                val reportsDir = File(getExternalFilesDir(null), "reports")
                reportsDir.mkdirs()
                val xlsx = File(reportsDir, FileNaming.reportFileName(fileTypeCode, "xlsx"))
                val wb = XSSFWorkbook()
                val sheet = wb.createSheet(getString(R.string.report_sheet_name))

                val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())
                val prefs = getSharedPreferences("settings", MODE_PRIVATE)

                // ---- styles (types inferred as XSSFCellStyle — required by XSSFCell.setCellStyle) ----
                val titleFont = wb.createFont().apply {
                    bold = true
                    fontHeightInPoints = 14
                    color = IndexedColors.WHITE.index
                }
                val titleStyle = wb.createCellStyle().apply {
                    setFont(titleFont)
                    fillForegroundColor = IndexedColors.ROYAL_BLUE.index
                    fillPattern = FillPatternType.SOLID_FOREGROUND
                    alignment = HorizontalAlignment.CENTER
                }

                val headerFont = wb.createFont().apply {
                    bold = true
                    color = IndexedColors.WHITE.index
                }
                val headerStyle = wb.createCellStyle().apply {
                    setFont(headerFont)
                    fillForegroundColor = IndexedColors.BLUE_GREY.index
                    fillPattern = FillPatternType.SOLID_FOREGROUND
                    alignment = HorizontalAlignment.CENTER
                    borderBottom = BorderStyle.THIN
                    borderTop = BorderStyle.THIN
                    borderLeft = BorderStyle.THIN
                    borderRight = BorderStyle.THIN
                }

                val dataStyle = wb.createCellStyle().apply {
                    borderBottom = BorderStyle.THIN
                    borderTop = BorderStyle.THIN
                    borderLeft = BorderStyle.THIN
                    borderRight = BorderStyle.THIN
                }

                val moneyFormat = wb.createDataFormat().getFormat("#,##0.00")
                val moneyStyle = wb.createCellStyle().apply {
                    cloneStyleFrom(dataStyle)
                    dataFormat = moneyFormat
                }

                val incomeStyle = wb.createCellStyle().apply {
                    cloneStyleFrom(moneyStyle)
                    setFont(wb.createFont().apply { color = IndexedColors.GREEN.index })
                }
                val expenseStyle = wb.createCellStyle().apply {
                    cloneStyleFrom(moneyStyle)
                    setFont(wb.createFont().apply { color = IndexedColors.RED.index })
                }

                val totalLabelFont = wb.createFont().apply { bold = true }
                val totalLabelStyle = wb.createCellStyle().apply {
                    setFont(totalLabelFont)
                    borderTop = BorderStyle.THIN
                }
                val totalValueStyle = wb.createCellStyle().apply {
                    setFont(totalLabelFont)
                    dataFormat = moneyFormat
                    borderTop = BorderStyle.THIN
                }

                // ---- title row ----
                val titleRow = sheet.createRow(0)
                titleRow.heightInPoints = 24f
                for (c in 0..4) titleRow.createCell(c).cellStyle = titleStyle
                titleRow.getCell(0).setCellValue(title)
                sheet.addMergedRegion(org.apache.poi.ss.util.CellRangeAddress(0, 0, 0, 4))

                // ---- header row ----
                // Столбцов налога на каждую отдельную операцию больше нет: с прогрессивной
                // шкалой (0% до 30 000 zł, 12% с 30 000 до 120 000 zł, 32% свыше) налог
                // считается по совокупному годовому доходу, а не по отдельной операции —
                // делить его поровну между записями было бы некорректно и вводило в
                // заблуждение. Итоговый налог за период показан ниже, в строке "Итого".
                val headers = listOf(
                    getString(R.string.report_col_date),
                    getString(R.string.report_col_income),
                    getString(R.string.report_col_expense),
                    getString(R.string.report_col_comment),
                    getString(R.string.report_col_receipt)
                )
                val headerRow = sheet.createRow(1)
                for ((i, h) in headers.withIndex()) {
                    val cell = headerRow.createCell(i)
                    cell.setCellValue(h)
                    cell.cellStyle = headerStyle
                }

                // ---- data rows ----
                var rowN = 2
                var totalIncome = 0.0
                var totalExpense = 0.0

                for (e in entries) {
                    val r = sheet.createRow(rowN++)

                    val dateCell = r.createCell(0)
                    dateCell.setCellValue(dateFmt.format(Date(e.dateMillis)))
                    dateCell.cellStyle = dataStyle

                    val incomeVal = if (e.isIncome) e.amount else 0.0
                    val expenseVal = if (!e.isIncome) e.amount else 0.0

                    val incomeCell = r.createCell(1)
                    incomeCell.setCellValue(incomeVal)
                    incomeCell.cellStyle = incomeStyle

                    val expenseCell = r.createCell(2)
                    expenseCell.setCellValue(expenseVal)
                    expenseCell.cellStyle = expenseStyle

                    val commentCell = r.createCell(3)
                    commentCell.setCellValue(e.comment ?: "")
                    commentCell.cellStyle = dataStyle

                    val receiptCell = r.createCell(4)
                    receiptCell.setCellValue(if (e.receiptPath != null) getString(R.string.report_receipt_yes) else "")
                    receiptCell.cellStyle = dataStyle

                    totalIncome += incomeVal
                    totalExpense += expenseVal
                }

                // ---- totals ----
                rowN++
                val profitRow = sheet.createRow(rowN++)
                profitRow.createCell(0).also { it.setCellValue(getString(R.string.report_total_profit)); it.cellStyle = totalLabelStyle }
                profitRow.createCell(1).also { it.setCellValue(totalIncome - totalExpense); it.cellStyle = totalValueStyle }

                val incomeRow = sheet.createRow(rowN++)
                incomeRow.createCell(0).also { it.setCellValue(getString(R.string.report_total_income)); it.cellStyle = totalLabelStyle }
                incomeRow.createCell(1).also { it.setCellValue(totalIncome); it.cellStyle = totalValueStyle }

                val expenseRow = sheet.createRow(rowN++)
                expenseRow.createCell(0).also { it.setCellValue(getString(R.string.report_total_expense)); it.cellStyle = totalLabelStyle }
                expenseRow.createCell(1).also { it.setCellValue(totalExpense); it.cellStyle = totalValueStyle }

                // Налог считаем от прибыли (доход - расход) по официальной прогрессивной
                // шкале — так же, как на главном экране приложения (TaxHelper.calc), а
                // не плоским процентом от суммы доходов — иначе итог в отчёте не совпадает
                // с балансом в приложении и не соответствует реальной шкале PIT.
                //
                // Для годового отчёта учитываются прочие доходы (они "занимают" нижние
                // ступени шкалы первыми). Для отчёта за месяц/произвольный период прочие
                // доходы не учитываются — 30 000 zł порог годовой, применять его к части
                // года было бы некорректно.
                val totalProfitForTax = totalIncome - totalExpense
                val otherIncomeForTax = if (applyAnnualLimit) TaxHelper.getOtherIncome(prefs, year) else 0.0
                val activityType = ActivityTypeHelper.get(prefs)
                val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
                val correctedTotalTax = when (activityType) {
                    ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA ->
                        TaxHelper.calc(totalProfitForTax, otherIncomeForTax).tax
                    ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(totalProfitForTax).tax
                    ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczaltByCategory(entries.filter { it.isIncome }, ryczaltRate).tax
                }

                val taxRow = sheet.createRow(rowN++)
                taxRow.createCell(0).also { it.setCellValue(getString(R.string.report_total_tax)); it.cellStyle = totalLabelStyle }
                taxRow.createCell(1).also { it.setCellValue(correctedTotalTax); it.cellStyle = totalValueStyle }

                // Чистая прибыль = прибыль минус налог — тот же показатель, что и
                // "tv_stat_net_profit" на главном экране приложения.
                val netProfit = totalProfitForTax - correctedTotalTax
                val netProfitRow = sheet.createRow(rowN)
                netProfitRow.createCell(0).also { it.setCellValue(getString(R.string.report_total_net_profit)); it.cellStyle = totalLabelStyle }
                netProfitRow.createCell(1).also { it.setCellValue(netProfit); it.cellStyle = totalValueStyle }

                // ---- column widths (manual — avoids java.awt dependency on Android) ----
                sheet.setColumnWidth(0, 20 * 256)
                sheet.setColumnWidth(1, 14 * 256)
                sheet.setColumnWidth(2, 14 * 256)
                sheet.setColumnWidth(3, 36 * 256)
                sheet.setColumnWidth(4, 10 * 256)

                FileOutputStream(xlsx).use { fos ->
                    wb.write(fos)
                    wb.close()
                }

                val zipf = File(reportsDir, xlsx.name.replace(".xlsx", ".zip"))
                ZipOutputStream(FileOutputStream(zipf)).use { zos ->
                    FileInputStream(xlsx).use { fis ->
                        zos.putNextEntry(ZipEntry("report.xlsx"))
                        fis.copyTo(zos)
                        zos.closeEntry()
                    }
                    for (e in entries) {
                        e.receiptPath?.let { path ->
                            val f = File(path)
                            if (f.exists()) {
                                FileInputStream(f).use { fis ->
                                    zos.putNextEntry(ZipEntry("receipts/${f.name}"))
                                    fis.copyTo(zos)
                                    zos.closeEntry()
                                }
                            }
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    shareFile(zipf)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    setButtonsEnabled(true)
                    Toast.makeText(this@ReportActivity, getString(R.string.report_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun setButtonsEnabled(enabled: Boolean) {
        findViewById<Button>(R.id.btn_report_month).isEnabled = enabled
        findViewById<Button>(R.id.btn_report_year).isEnabled = enabled
        findViewById<Button>(R.id.btn_report_custom).isEnabled = enabled
    }

    private fun shareFile(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        Toast.makeText(this, getString(R.string.report_ready), Toast.LENGTH_SHORT).show()
        startActivity(Intent.createChooser(intent, getString(R.string.report_share_title)))
    }
}
