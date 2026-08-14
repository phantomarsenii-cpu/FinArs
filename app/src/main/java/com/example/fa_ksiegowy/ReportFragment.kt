package com.example.fa_ksiegowy

import android.app.DatePickerDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import java.util.Calendar
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

class ReportFragment : Fragment() {
    lateinit var db: AppDatabase
    /** true = biezacy miesiac, false = biezacy rok — dla karty "Podsumowanie"/"Trend" (nie ma to wplywu na przyciski eksportu ponizej, ktore maja wlasny zakres). */
    private var summaryIsMonth: Boolean = true

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_report, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        // Update: setContentView/BottomNavBar.attach убраны — этот экран теперь фрагмент
        // внутри MainActivity, у которого нав-бар и рекламный баннер уже созданы один раз
        // на уровне Activity (см. MainActivity.kt), а не пересоздаются здесь.
        db = AppDatabase.getInstance(requireContext())
        requireView().findViewById<Button>(R.id.btn_report_month).setOnClickListener { generateForMonth() }
        requireView().findViewById<Button>(R.id.btn_report_year).setOnClickListener {
            runIfPro { generateForYear() }
        }
        requireView().findViewById<Button>(R.id.btn_report_custom).setOnClickListener {
            runIfPro { showCustomRangePicker() }
        }
        requireView().findViewById<View>(R.id.btn_period).setOnClickListener { showPeriodPicker() }
        loadSummary()
        loadTrend()
    }

    private fun showPeriodPicker() {
        AppDialog.showOptionPicker(
            context = requireContext(),
            title = getString(R.string.select_period),
            options = listOf("month" to getString(R.string.period_this_month), "year" to getString(R.string.period_this_year))
        ) { selected ->
            summaryIsMonth = selected == "month"
            requireView().findViewById<TextView>(R.id.tv_period).text =
                if (summaryIsMonth) getString(R.string.period_this_month) else getString(R.string.period_this_year)
            loadSummary()
        }
    }

    /** Wypelnia karte "Podsumowanie" (donut + legenda) oraz karte rozkladu procentowego. */
    private fun loadSummary() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val cal = Calendar.getInstance()
            val from: Long
            val to: Long
            if (summaryIsMonth) {
                cal.set(Calendar.DAY_OF_MONTH, 1)
                cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
                from = cal.timeInMillis
                to = System.currentTimeMillis()
            } else {
                val year = TaxHelper.currentYear()
                val (yearStart, _) = TaxHelper.yearRange(year)
                from = yearStart
                to = System.currentTimeMillis()
            }

            val entries = db.entryDao().getBetween(from, to)
            val income = entries.filter { it.isIncome }.sumOf { it.amount }
            val expense = entries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense
            val prefs = requireContext().getSharedPreferences("settings", android.content.Context.MODE_PRIVATE)
            val activityType = ActivityTypeHelper.get(prefs)
            val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
            val year = TaxHelper.currentYear()
            val otherIncome = if (!summaryIsMonth) TaxHelper.getOtherIncome(prefs, year) else 0.0
            val tax = when (activityType) {
                ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(profit, otherIncome)
                ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(profit)
                ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczaltByCategory(entries.filter { it.isIncome }, ryczaltRate)
            }.tax.coerceAtLeast(0.0)

            val total = (income + expense + tax).coerceAtLeast(0.01)
            val incomePct = (income / total * 100).toInt()
            val expensePct = (expense / total * 100).toInt()
            val taxPct = (tax / total * 100).toInt()

            withContext(Dispatchers.Main) {
                requireView().findViewById<DonutChartView>(R.id.donut_chart).submitData(
                    listOf(
                        DonutChartView.Segment(income, ContextCompat.getColor(requireContext(), R.color.income_green)),
                        DonutChartView.Segment(expense, ContextCompat.getColor(requireContext(), R.color.expense_red)),
                        DonutChartView.Segment(tax, ContextCompat.getColor(requireContext(), R.color.accent_purple))
                    ),
                    getString(R.string.summary_total),
                    formatMoney(income + expense)
                )
                requireView().findViewById<TextView>(R.id.tv_legend_income).text = formatMoney(income) + " zł"
                requireView().findViewById<TextView>(R.id.tv_legend_expense).text = formatMoney(expense) + " zł"
                requireView().findViewById<TextView>(R.id.tv_legend_tax).text = formatMoney(tax) + " zł"

                requireView().findViewById<TextView>(R.id.tv_breakdown_income).text = formatMoney(income) + " zł"
                requireView().findViewById<TextView>(R.id.tv_breakdown_expense).text = formatMoney(expense) + " zł"
                requireView().findViewById<TextView>(R.id.tv_breakdown_tax_label).text = getString(R.string.legend_tax_pct, taxPct)
                requireView().findViewById<TextView>(R.id.tv_breakdown_tax).text = formatMoney(tax) + " zł"

                requireView().findViewById<ProgressBar>(R.id.pb_income).progress = incomePct
                requireView().findViewById<ProgressBar>(R.id.pb_expense).progress = expensePct
                requireView().findViewById<ProgressBar>(R.id.pb_tax).progress = taxPct
                requireView().findViewById<TextView>(R.id.tv_breakdown_income_pct).text = "$incomePct%"
                requireView().findViewById<TextView>(R.id.tv_breakdown_expense_pct).text = "$expensePct%"
                requireView().findViewById<TextView>(R.id.tv_breakdown_tax_pct).text = "$taxPct%"
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%,.0f", v)

    /** Ładuje zysk netto (przychod - wydatki) za ostatnie 6 miesiecy dla karty "Trend". */
    private fun loadTrend() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val cal = Calendar.getInstance()
            val monthFmt = SimpleDateFormat("LLL", Locale.getDefault())
            val points = mutableListOf<TrendLineChartView.Point>()

            for (i in 5 downTo 0) {
                val monthCal = cal.clone() as Calendar
                monthCal.add(Calendar.MONTH, -i)
                monthCal.set(Calendar.DAY_OF_MONTH, 1)
                monthCal.set(Calendar.HOUR_OF_DAY, 0); monthCal.set(Calendar.MINUTE, 0)
                monthCal.set(Calendar.SECOND, 0); monthCal.set(Calendar.MILLISECOND, 0)
                val from = monthCal.timeInMillis
                val label = monthFmt.format(monthCal.time).replaceFirstChar { it.uppercase() }
                monthCal.add(Calendar.MONTH, 1)
                val to = monthCal.timeInMillis - 1

                val entries = db.entryDao().getBetween(from, to)
                val income = entries.filter { it.isIncome }.sumOf { it.amount }
                val expense = entries.filter { !it.isIncome }.sumOf { it.amount }
                points.add(TrendLineChartView.Point(label, income - expense))
            }

            withContext(Dispatchers.Main) {
                requireView().findViewById<TrendLineChartView>(R.id.trend_chart).submitData(points)
            }
        }
    }

    /** Годовой и произвольный отчёт — платная функция; месячный остаётся бесплатным. */
    private fun runIfPro(action: () -> Unit) {
        if (BillingManager.isPro(requireContext())) {
            action()
        } else {
            androidx.appcompat.app.AlertDialog.Builder(requireContext())
                .setTitle(getString(R.string.pro_feature_locked_title))
                .setMessage(getString(R.string.pro_feature_locked_message))
                .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                    (activity as? MainActivity)?.openTab(BottomNavBar.Tab.SETTINGS)
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
            requireContext(),
            { _, fromYear, fromMonth, fromDay ->
                val fromCal = Calendar.getInstance()
                fromCal.set(fromYear, fromMonth, fromDay, 0, 0, 0)
                fromCal.set(Calendar.MILLISECOND, 0)
                val fromMillis = fromCal.timeInMillis

                DatePickerDialog(
                    requireContext(),
                    { _, toYear, toMonth, toDay ->
                        val toCal = Calendar.getInstance()
                        toCal.set(toYear, toMonth, toDay, 23, 59, 59)
                        toCal.set(Calendar.MILLISECOND, 999)
                        val toMillis = toCal.timeInMillis

                        if (toMillis < fromMillis) {
                            Toast.makeText(requireContext(), getString(R.string.custom_range_invalid), Toast.LENGTH_LONG).show()
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
        Toast.makeText(requireContext(), getString(R.string.report_generating), Toast.LENGTH_SHORT).show()
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            try {
                val entries = db.entryDao().getBetween(from, to)
                if (entries.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        Toast.makeText(requireContext(), getString(R.string.no_entries), Toast.LENGTH_LONG).show()
                        setButtonsEnabled(true)
                    }
                    return@launch
                }

                val reportsDir = File(requireContext().getExternalFilesDir(null), "reports")
                reportsDir.mkdirs()
                val xlsx = File(reportsDir, FileNaming.reportFileName(fileTypeCode, "xlsx"))
                val wb = XSSFWorkbook()
                val sheet = wb.createSheet(getString(R.string.report_sheet_name))

                val dateFmt = SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault())
                val prefs = requireContext().getSharedPreferences("settings", android.content.Context.MODE_PRIVATE)

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
                    Toast.makeText(requireContext(), getString(R.string.report_error, e.message ?: ""), Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun setButtonsEnabled(enabled: Boolean) {
        requireView().findViewById<Button>(R.id.btn_report_month).isEnabled = enabled
        requireView().findViewById<Button>(R.id.btn_report_year).isEnabled = enabled
        requireView().findViewById<Button>(R.id.btn_report_custom).isEnabled = enabled
    }

    private fun shareFile(file: File) {
        val uri = FileProvider.getUriForFile(requireContext(), "${requireContext().packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        Toast.makeText(requireContext(), getString(R.string.report_ready), Toast.LENGTH_SHORT).show()
        startActivity(Intent.createChooser(intent, getString(R.string.report_share_title)))
    }
}
