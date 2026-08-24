#!/data/data/com.termux/files/usr/bin/bash
# FinArs — update_project-44-single-activity-stage3-report-fragment-tabfix.sh
#
# ЭТАП 3 миграции на единый MainActivity-хост + ИСПРАВЛЕНИЕ БАГА переключения
# вкладок Start<->Magazyn:
#
#   БАГ (исправлен): BottomNavBar.attachHost() сравнивал нажатую вкладку со
#   значением current, зафиксированным ОДИН РАЗ при вызове attachHost() в
#   onCreate — из-за этого после первого переключения (напр. Start -> Magazyn)
#   клики по остальным вкладкам просто игнорировались. Теперь клик всегда
#   вызывает onTabSelected(tab), а актуальную проверку 'уже на этой вкладке'
#   делает MainActivity.switchTo() с живым полем currentTab.
#
#   - ReportActivity УДАЛЁН, заменён на ReportFragment внутри MainActivity.
#   - MainActivity переключает Start/Magazyn/Raporty через show/hide (без
#     recreate) — баннер и нав-бар НЕ пересоздаются при переходе между ними.
#   - Кнопка 'Raporty' на дашборде Start теперь мгновенно переключает вкладку
#     (а не открывает отдельный экран).
#   - BottomNavBar: 'Start'/'Magazyn'/'Raporty' из оставшегося экрана-Activity
#     (Ustawienia) теперь ведут в MainActivity с нужной вкладкой.
#   - Уведомление 'напоминание об авансовом платеже' (LimitsNotificationWorker)
#     теперь открывает MainActivity на вкладке Raporty.
#
# ВАЖНО: Ustawienia ПОКА ОСТАЁТСЯ отдельной Activity — баннер/нав-бар на ней
# по-прежнему пересоздаются при переходе. Переключение между Start/Magazyn/
# Raporty внутри MainActivity теперь МГНОВЕННОЕ и без мигания баннера.
set -euo pipefail

echo "=== FinArs: единый Activity-хост, этап 3 (ReportFragment) + фикс переключения вкладок ==="

REPO_ROOT="$HOME/FA_ksiegowy"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)

if [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "ERROR: не похоже на корень репозитория FinArs."
    exit 1
fi

echo "--- Backing up files that will be modified or deleted ---"
[ -f "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/fragment_report.xml" ] && cp "app/src/main/res/layout/fragment_report.xml" "app/src/main/res/layout/fragment_report.xml.bak_${TS}" || true
[ -f "app/src/main/AndroidManifest.xml" ] && cp "app/src/main/AndroidManifest.xml" "app/src/main/AndroidManifest.xml.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/activity_report.xml" ] && cp "app/src/main/res/layout/activity_report.xml" "app/src/main/res/layout/activity_report.xml.bak_${TS}" || true

echo "Writing app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import androidx.fragment.app.Fragment

/**
 * Постоянный хост для главных вкладок. Заменяет собой бывшие MineActivity/
 * MagazinActivity/ReportActivity — все прежние ссылки на них теперь указывают сюда.
 *
 * Update: миграция на единый Activity-хост с фрагментами — нижняя навигация и рекламный
 * баннер создаются ОДИН РАЗ за всё время жизни этой Activity и не пересоздаются при
 * переключении вкладок. Переключение между уже переведёнными на фрагменты вкладками идёт
 * через show/hide (а не replace) — так у каждой вкладки сохраняется состояние (скролл,
 * загруженные данные) между переключениями, а не пересоздаётся с нуля.
 *
 * Этап 3: переведены Start (MineFragment), Magazyn (MagazinFragment) и Raporty
 * (ReportFragment). Ustawienia пока ещё отдельная Activity — переключение на неё
 * по-старому запускает Activity (см. BottomNavBar.attach на ней самой). Будет переведена
 * на следующем этапе.
 */
class MainActivity : BaseActivity() {

    private var currentTab: BottomNavBar.Tab = BottomNavBar.Tab.START

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        currentTab = savedInstanceState
            ?.getString(KEY_CURRENT_TAB)
            ?.let { runCatching { BottomNavBar.Tab.valueOf(it) }.getOrNull() }
            ?: tabFromIntentExtra(intent) ?: BottomNavBar.Tab.START

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .add(R.id.fragment_container, createFragment(currentTab), tagFor(currentTab))
                .commit()
        }

        setupNav()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Тап по уведомлению (например, "низкий остаток товара" или "напоминание об
        // авансовом платеже") при уже запущенном MainActivity — не пересоздаём Activity,
        // просто переключаемся на нужную вкладку.
        tabFromIntentExtra(intent)?.let { switchTo(it) }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_CURRENT_TAB, currentTab.name)
    }

    private fun tabFromIntentExtra(intent: Intent?): BottomNavBar.Tab? =
        when (intent?.getStringExtra(EXTRA_OPEN_TAB)) {
            TAB_MAGAZIN -> BottomNavBar.Tab.MAGAZIN
            TAB_REPORTS -> BottomNavBar.Tab.REPORTS
            TAB_START -> BottomNavBar.Tab.START
            else -> null
        }

    private fun setupNav() {
        BottomNavBar.attachHost(this, currentTab) { tab -> switchTo(tab) }
    }

    /**
     * Переключение вкладки. Start/Magazyn/Raporty — фрагменты внутри этой же Activity
     * (show/hide, без recreate — баннер и нав-бар не трогаются). Ustawienia пока
     * отдельная Activity — обычный startActivity, как было раньше (следующий этап миграции).
     */
    private fun switchTo(tab: BottomNavBar.Tab) {
        if (tab == currentTab) return

        if (tab != BottomNavBar.Tab.START && tab != BottomNavBar.Tab.MAGAZIN && tab != BottomNavBar.Tab.REPORTS) {
            val target = when (tab) {
                BottomNavBar.Tab.SETTINGS -> SettingsActivity::class.java
                else -> return
            }
            startActivity(Intent(this, target))
            finish()
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
            return
        }

        val fm = supportFragmentManager
        val tx = fm.beginTransaction()
        fm.findFragmentByTag(tagFor(currentTab))?.let { tx.hide(it) }

        val targetTag = tagFor(tab)
        val existing = fm.findFragmentByTag(targetTag)
        if (existing != null) {
            tx.show(existing)
        } else {
            tx.add(R.id.fragment_container, createFragment(tab), targetTag)
        }
        tx.commit()

        currentTab = tab
        BottomNavBar.updateVisual(this, currentTab)
    }

    /** Публичный вход для фрагментов (например, кнопка "Raporty" на дашборде
     * MineFragment) — переключает вкладку мгновенно, тем же механизмом, что и
     * нижняя навигация, без пересоздания Activity/баннера. */
    fun openTab(tab: BottomNavBar.Tab) = switchTo(tab)

    private fun tagFor(tab: BottomNavBar.Tab) = "tab_${tab.name}"

    private fun createFragment(tab: BottomNavBar.Tab): Fragment = when (tab) {
        BottomNavBar.Tab.MAGAZIN -> MagazinFragment()
        BottomNavBar.Tab.REPORTS -> ReportFragment()
        else -> MineFragment()
    }

    companion object {
        private const val KEY_CURRENT_TAB = "current_tab"

        /** Публичные константы для Intent-экстра "какую вкладку открыть" — используются
         * воркерами уведомлений (см. StockNotificationWorker, LimitsNotificationWorker)
         * при тапе по push-уведомлению. */
        const val EXTRA_OPEN_TAB = "open_tab"
        const val TAB_MAGAZIN = "MAGAZIN"
        const val TAB_REPORTS = "REPORTS"
        const val TAB_START = "START"
    }
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" << 'FINARS_EOF'
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
                    startActivity(Intent(requireContext(), SettingsActivity::class.java))
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
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Wires up the persistent bottom navigation bar included (via
 * @layout/bottom_nav_bar) at the bottom of the main tab screens plus the
 * central "+" button.
 *
 * Update: миграция на единый MainActivity-хост (фрагменты вместо отдельных Activity —
 * чтобы нижняя навигация и рекламный баннер не пересоздавались при переключении вкладок).
 * Этап 3: Start (MineFragment), Magazyn (MagazinFragment) и Raporty (ReportFragment)
 * переведены на фрагменты внутри MainActivity — attachHost()/updateVisual() используются
 * MainActivity. Ustawienia пока ещё отдельная Activity — использует старый attach(), как
 * и раньше; "Start"/"Magazyn"/"Raporty" из НЕЁ теперь ведут в MainActivity (с нужной
 * вкладкой через Intent-экстра), а не в удалённые MineActivity/MagazinActivity/ReportActivity.
 */
object BottomNavBar {

    enum class Tab { START, TRANSACTIONS, MAGAZIN, REPORTS, SETTINGS }

    /** Для оставшихся экранов-Activity (Ustawienia). */
    fun attach(activity: AppCompatActivity, current: Tab) {
        bindToMainActivityTab(activity, R.id.nav_start, Tab.START, current)
        bindToMainActivityTab(activity, R.id.nav_magazin, Tab.MAGAZIN, current)
        bindToMainActivityTab(activity, R.id.nav_reports, Tab.REPORTS, current)
        bind(activity, R.id.nav_settings, Tab.SETTINGS, current, SettingsActivity::class.java)
        attachAddButton(activity)
        attachAdBanner(activity)
    }

    /**
     * Для MainActivity (фрагмент-хост): переключает вкладку на месте — Activity, нав-бар
     * и рекламный баннер НЕ пересоздаются. MainActivity сам решает, что делать с выбранной
     * вкладкой (переключить фрагмент или запустить оставшуюся Activity) через onTabSelected.
     */
    fun attachHost(mainActivity: AppCompatActivity, current: Tab, onTabSelected: (Tab) -> Unit) {
        listOf(
            Tab.START to R.id.nav_start,
            Tab.MAGAZIN to R.id.nav_magazin,
            Tab.REPORTS to R.id.nav_reports,
            Tab.SETTINGS to R.id.nav_settings
        ).forEach { (tab, viewId) ->
            // Update: раньше здесь была проверка "if (tab != current)", но attachHost()
            // вызывается ОДИН РАЗ в onCreate — current фиксировался в замыкании навсегда
            // и не обновлялся при переключении вкладок, из-за чего после первого перехода
            // (например Start -> Magazyn) клики по остальным вкладкам просто игнорировались.
            // Актуальную проверку "уже на этой вкладке — ничего не делать" корректно
            // делает MainActivity.switchTo() с живым полем currentTab — здесь она не нужна.
            mainActivity.findViewById<View>(viewId)?.setOnClickListener {
                onTabSelected(tab)
            }
        }
        updateVisual(mainActivity, current)
        attachAddButton(mainActivity)
        attachAdBanner(mainActivity)
    }

    /** Обновляет только подсветку активной вкладки — БЕЗ повторного создания баннера
     * или переустановки обработчиков клика. Вызывать при каждом переключении вкладки
     * внутри MainActivity (после attachHost, который вызывается один раз в onCreate). */
    fun updateVisual(activity: AppCompatActivity, current: Tab) {
        activity.findViewById<View>(R.id.nav_start)?.let { applyVisual(activity, it, current == Tab.START) }
        activity.findViewById<View>(R.id.nav_magazin)?.let { applyVisual(activity, it, current == Tab.MAGAZIN) }
        activity.findViewById<View>(R.id.nav_reports)?.let { applyVisual(activity, it, current == Tab.REPORTS) }
        activity.findViewById<View>(R.id.nav_settings)?.let { applyVisual(activity, it, current == Tab.SETTINGS) }
    }

    private fun attachAddButton(activity: AppCompatActivity) {
        activity.findViewById<View>(R.id.nav_add)?.setOnClickListener {
            activity.startActivity(Intent(activity, AddEntryActivity::class.java))
        }
    }

    /**
     * Единый рекламный баннер, зафиксированный над нижней навигацией. На MainActivity
     * (Start/Magazyn) он создаётся ОДИН РАЗ за всё время жизни Activity и никогда не
     * пересоздаётся при переключении вкладок фрагментов. На остальных экранах-Activity
     * (Raporty/Ustawienia) он пока пересоздаётся при каждом переходе — уйдёт после того,
     * как и они станут фрагментами внутри MainActivity.
     * Скрывается автоматически при активной Pro-подписке, уничтожается вместе с Activity.
     */
    private fun attachAdBanner(activity: AppCompatActivity) {
        val container = activity.findViewById<FrameLayout>(R.id.ad_container) ?: return
        val adView = AdsManager.setupAndLoadBanner(activity, container)
        activity.lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) {
                if (BillingManager.isPro(activity)) {
                    AdsManager.hideBanner(container, adView)
                }
            }
            override fun onDestroy(owner: LifecycleOwner) {
                adView.destroy()
            }
        })
    }

    private fun applyVisual(activity: AppCompatActivity, group: View, active: Boolean) {
        val pill = (group as? ViewGroup)?.getChildAt(0) as? ViewGroup
        val icon = pill?.getChildAt(0) as? ImageView
        val label = (group as? ViewGroup)?.getChildAt(1) as? TextView

        val color = if (active) {
            ContextCompat.getColor(activity, R.color.accent_blue_light)
        } else {
            ContextCompat.getColor(activity, R.color.text_secondary)
        }
        icon?.setColorFilter(color)
        label?.setTextColor(color)
        // Podswietlona "piguleczka" pod ikona aktywnej zakladki — zywszy,
        // bardziej zgodny z makietem akcent zamiast samej zmiany koloru.
        pill?.setBackgroundResource(if (active) R.drawable.nav_active_pill_bg else 0)
    }

    /** "Start"/"Magazyn"/"Raporty" с оставшегося экрана-Activity (Ustawienia) ведут в
     * MainActivity (единый фрагмент-хост), а не в удалённые MineActivity/MagazinActivity/
     * ReportActivity. FLAG_ACTIVITY_CLEAR_TOP переиспользует уже существующий (singleTask)
     * экземпляр MainActivity вместо создания нового поверх стека. */
    private fun bindToMainActivityTab(activity: AppCompatActivity, viewId: Int, tab: Tab, current: Tab) {
        val group = activity.findViewById<View>(viewId) ?: return
        val active = tab == current
        applyVisual(activity, group, active)

        group.setOnClickListener {
            if (!active) {
                val intent = Intent(activity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
                    when (tab) {
                        Tab.MAGAZIN -> putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_MAGAZIN)
                        Tab.REPORTS -> putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_REPORTS)
                        else -> { /* Tab.START — вкладка по умолчанию, экстра не нужна */ }
                    }
                }
                activity.startActivity(intent)
                activity.finish()
                @Suppress("DEPRECATION")
                activity.overridePendingTransition(0, 0)
            }
        }
    }

    private fun bind(
        activity: AppCompatActivity,
        viewId: Int,
        tab: Tab,
        current: Tab,
        target: Class<*>
    ) {
        val group = activity.findViewById<View>(viewId) ?: return
        val active = tab == current
        applyVisual(activity, group, active)

        group.setOnClickListener {
            if (!active) {
                activity.startActivity(Intent(activity, target))
                activity.finish()
                // Update: стандартная анимация перехода между Activity (fade/slide) заставляла
                // нижнюю навигацию и рекламный баннер визуально "мигать" при переключении вкладок,
                // хотя оба экрана выглядят там одинаково — убираем анимацию для мгновенного,
                // незаметного переключения (deprecated с API 34, но метод по-прежнему рабочий
                // на всех версиях; замена overrideActivityTransition усложнила бы код без
                // выигрыша, т.к. переход всё равно должен быть нулевым).
                @Suppress("DEPRECATION")
                activity.overridePendingTransition(0, 0)
            }
        }
    }
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.Manifest
import android.app.NotificationChannel
import android.app.PendingIntent
import android.content.Intent
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Ежедневная фоновая проверка лимитов и сроков, запускается через WorkManager
 * (переживает перезапуски устройства и не требует, чтобы приложение было открыто).
 * Уведомления показываются не чаще одного раза в день на каждый повод — состояние
 * "уже показали сегодня" хранится в prefs, чтобы не спамить пользователя при
 * каждом запуске воркера.
 */
class LimitsNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        try {
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val limits = LimitsHelper.compute(applicationContext)
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val today = SDF_DAY.format(java.util.Date())

            // 1) Лимит działalności nierejestrowanej — 80% / 95% / превышение.
            if (limits.activityType == ActivityType.NIEZAREJESTROWANA) {
                val m = limits.monthly
                when {
                    m.exceeded -> notifyOnce(
                        prefs, "n_exceeded_$today",
                        ctx.getString(R.string.notif_limit_exceeded_title),
                        ctx.getString(R.string.notif_limit_exceeded_text),
                        LimitsActivity::class.java
                    )
                    m.percent >= 95 -> notifyOnce(
                        prefs, "n_95_$today",
                        ctx.getString(R.string.notif_limit_95_title),
                        ctx.getString(R.string.notif_limit_95_text),
                        LimitsActivity::class.java
                    )
                    m.percent >= 80 -> notifyOnce(
                        prefs, "n_80_$today",
                        ctx.getString(R.string.notif_limit_80_title),
                        ctx.getString(R.string.notif_limit_80_text),
                        LimitsActivity::class.java
                    )
                }
            }

            // 2) Приближение к порогу 120 000 zł (переход на 32%).
            if (limits.bracket.percent in 90..999) {
                notifyOnce(
                    prefs, "bracket90_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_bracket_title),
                    ctx.getString(R.string.notif_bracket_text),
                    LimitsActivity::class.java
                )
            }

            // 3) Приближение к лимиту zwolnienia z VAT (240 000 zł) — раз в день.
            if (limits.vat.percent in 90..999) {
                notifyOnce(
                    prefs, "vat90_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_vat_title),
                    ctx.getString(R.string.notif_vat_text),
                    LimitsActivity::class.java
                )
            }

            // 3b) Лимит zwolnienia z VAT ПРЕВЫШЕН, а регистрация ещё не подтверждена —
            // это уже юридически срочный вопрос (7 дней на подачу VAT-R), поэтому
            // повторяем оповещение до N раз в день (см. настройку частоты в Ustawieniach),
            // а не один раз, как для мягких предупреждений выше.
            if (limits.vat.exceeded && !VatComplianceHelper.isVatRegisteredConfirmed(prefs)) {
                notifyRepeatable(
                    prefs, "vat_exceeded_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_vat_exceeded_critical_title),
                    ctx.getString(R.string.notif_vat_exceeded_critical_text),
                    SettingsTaxActivity::class.java
                )
            }

            // 3c) Лимит 20 000 zł gotówki dla osób fizycznych ПРЕВЫШЕН, а kasa fiskalna
            // ещё не подтверждена — тоже повторяем до N раз в день.
            val cashStatus = CashLimitHelper.computeCurrentYear(applicationContext)
            if (cashStatus.exceeded && !VatComplianceHelper.isKasaFiskalnaConfirmed(prefs)) {
                notifyRepeatable(
                    prefs, "kasa_exceeded_${TaxHelper.currentYear()}",
                    ctx.getString(R.string.notif_kasa_exceeded_title),
                    ctx.getString(R.string.notif_kasa_exceeded_text),
                    SettingsTaxActivity::class.java
                )
            }

            // 4) Напоминание об авансовом платеже — до 20 числа каждого месяца.
            val cal = Calendar.getInstance()
            val day = cal.get(Calendar.DAY_OF_MONTH)
            if (day in 15..20) {
                notifyOnce(
                    prefs, "advance_${cal.get(Calendar.YEAR)}_${cal.get(Calendar.MONTH)}",
                    ctx.getString(R.string.notif_advance_title),
                    ctx.getString(R.string.notif_advance_text),
                    // Update: ReportActivity удалён — теперь MainActivity (единый хост),
                    // с флагом, какую вкладку открыть при тапе по уведомлению.
                    MainActivity::class.java,
                    android.os.Bundle().apply { putString(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_REPORTS) }
                )
            }

            // 5) Напоминание о сроке подачи PIT (15 lutego – 30 kwietnia).
            val month = cal.get(Calendar.MONTH) // 0-based
            if (month == Calendar.FEBRUARY || month == Calendar.MARCH ||
                (month == Calendar.APRIL && day <= 30)
            ) {
                notifyOnce(
                    prefs, "pit_deadline_${cal.get(Calendar.YEAR)}_$month",
                    ctx.getString(R.string.notif_pit_deadline_title),
                    ctx.getString(R.string.notif_pit_deadline_text),
                    Pit36Activity::class.java
                )
            }

            return Result.success()
        } catch (e: Exception) {
            return Result.retry()
        }
    }

    private fun notifyOnce(
        prefs: android.content.SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null,
        intentExtras: android.os.Bundle? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        showNotification(applicationContext, key.hashCode(), title, text, targetActivity, intentExtras)
    }

    /** Как notifyOnce, но допускает до N повторов В ТЕЧЕНИЕ ОДНОГО ДНЯ — N задаётся
     *  пользователем в Ustawieniach (zob. VatComplianceHelper.getPushFrequency,
     *  по умолчанию 3). Используется только для действительно срочных ситуаций
     *  (превышен лимit VAT/kasy, просроченная фактура) — обычные предупреждения
     *  "приближаетесь к лимиту" по-прежнему используют notifyOnce (раз в день). */
    private fun notifyRepeatable(
        prefs: android.content.SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null
    ) {
        notifyRepeatableStatic(applicationContext, prefs, key, title, text, targetActivity)
    }

    companion object {
        private val SDF_DAY = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
        const val CHANNEL_ID = "fa_limits_channel"
        private const val UNIQUE_WORK_NAME = "fa_limits_daily_check"

        /** Общая реализация повторяемого (до N раз/день) оповещения — используется
         *  и здесь, и в InvoiceReminderWorker (просроченные фактуры). */
        fun notifyRepeatableStatic(
            context: Context, prefs: android.content.SharedPreferences,
            key: String, title: String, text: String, targetActivity: Class<*>? = null
        ) {
            val today = SDF_DAY.format(java.util.Date())
            val maxPerDay = VatComplianceHelper.getPushFrequency(prefs)
            val countKey = "notif_count_${key}_$today"
            val shown = prefs.getInt(countKey, 0)
            if (shown >= maxPerDay) return
            prefs.edit().putInt(countKey, shown + 1).apply()
            showNotification(context, (key + "_" + shown).hashCode(), title, text, targetActivity)
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notif_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = context.getString(R.string.notif_channel_description)
                }
                mgr.createNotificationChannel(channel)
            }
        }

        fun showNotification(
            context: Context, id: Int, title: String, text: String,
            targetActivity: Class<*>? = null,
            intentExtras: android.os.Bundle? = null
        ) {
            // Логируем в историю уведомлений (экран открывается через колокольчик на
            // Start) независимо от того, было ли реально показано системное
            // уведомление — так пользователь не теряет запись, даже если разрешение
            // POST_NOTIFICATIONS не выдано.
            NotificationLog.add(context, title, text, targetActivity)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                if (!granted) return
            }
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
            // Тап по уведомлению должен открывать соответствующий экран приложения —
            // раньше при тапе ничего не происходило, так как contentIntent не задавался.
            if (targetActivity != null) {
                val openIntent = Intent(context, targetActivity).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    if (intentExtras != null) putExtras(intentExtras)
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, id, openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.setContentIntent(pendingIntent)
            }
            val notification = builder.build()
            androidx.core.app.NotificationManagerCompat.from(context).apply {
                try {
                    notify(id, notification)
                } catch (e: SecurityException) {
                    // Разрешение отозвано между проверкой и вызовом — просто пропускаем.
                }
            }
        }

        /** Планирует проверку лимитов/сроков. Интервал — 1 час (не 24), потому что
         *  критические оповещения (превышен лимит VAT/kasy) теперь могут повторяться
         *  до N раз в день (см. notifyRepeatableStatic, частота задаётся пользователем
         *  в Ustawieniach) — при проверке раз в сутки повторы были бы невозможны.
         *  Обычные мягкие предупреждения (notifyOnce) по-прежнему показываются не
         *  чаще одного раза в день независимо от того, как часто отрабатывает воркер. */
        fun schedule(context: Context) {
            createChannel(context)
            val request = PeriodicWorkRequestBuilder<LimitsNotificationWorker>(1, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }
    }
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar
import java.util.Locale

class MineFragment : Fragment() {
    private lateinit var db: AppDatabase
    private lateinit var recentEntriesAdapter: EntryAdapter

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* результат не критичен для UI */ }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_mine, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        // Update: setContentView/BottomNavBar.attach убраны — этот экран теперь фрагмент
        // внутри MainActivity, у которого нав-бар и рекламный баннер уже созданы один раз
        // на уровне Activity (см. MainActivity.kt), а не пересоздаются здесь.
        db = AppDatabase.getInstance(requireContext())

        // Единая кнопка добавления: выбор дохода/расхода происходит уже внутри
        // AddEntryActivity (переключатель с подсветкой выбранного варианта).
        // По умолчанию открываем на "доход", это чаще нужное действие.
        requireView().findViewById<Button>(R.id.btn_add_entry).setOnClickListener {
            startActivity(Intent(requireContext(), AddEntryActivity::class.java).putExtra("isIncome", true))
        }
        requireView().findViewById<Button>(R.id.btn_settings).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsActivity::class.java))
        }
        requireView().findViewById<View>(R.id.iv_notifications).setOnClickListener {
            startActivity(Intent(requireContext(), NotificationsActivity::class.java))
        }
        requireView().findViewById<Button>(R.id.btn_reports).setOnClickListener {
            // Update: раньше открывал ReportActivity отдельным экраном (пересоздавая
            // баннер/нав-бар); теперь и Mine, и Report — фрагменты внутри одного
            // MainActivity, поэтому просто переключаем вкладку — мгновенно, без мигания.
            (activity as? MainActivity)?.openTab(BottomNavBar.Tab.REPORTS)
        }
        requireView().findViewById<Button>(R.id.btn_history).setOnClickListener {
            startActivity(Intent(requireContext(), HistoryActivity::class.java))
        }
        requireView().findViewById<Button>(R.id.btn_invoices).setOnClickListener {
            if (BillingManager.isPro(requireContext())) {
                startActivity(Intent(requireContext(), AddInvoiceActivity::class.java))
            } else {
                androidx.appcompat.app.AlertDialog.Builder(requireContext())
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.invoice_pro_locked_message))
                    .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                        startActivity(Intent(requireContext(), SettingsActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        // Update: przycisk "Magazyn" przeniesiony do dolnej nawigacji (patrz
        // bottom_nav_bar.xml) — nie jest juz na karcie Start.

        // Karta "Limity" -> pelnoekranowy podglad (dokladnie wedlug makietu).
        requireView().findViewById<View>(R.id.card_limits).setOnClickListener {
            startActivity(Intent(requireContext(), LimitsActivity::class.java))
        }
        // "Edytuj" -> edycja formy dzialalnosci/stawek w ustawieniach podatkowych.
        requireView().findViewById<TextView>(R.id.tv_edit_limits).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsTaxActivity::class.java))
        }

        // "Zobacz wszystkie" nad lista ostatnich transakcji -> pelna historia.
        requireView().findViewById<TextView>(R.id.tv_view_all_entries).setOnClickListener {
            startActivity(Intent(requireContext(), HistoryActivity::class.java))
        }

        recentEntriesAdapter = EntryAdapter { entry ->
            startActivity(
                Intent(requireContext(), AddEntryActivity::class.java)
                    .putExtra("entryId", entry.id)
                    .putExtra("isIncome", entry.isIncome)
            )
        }
        requireView().findViewById<RecyclerView>(R.id.rv_recent_entries).apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = recentEntriesAdapter
        }

        setupHiddenDevCodeGesture()
        requestNotificationPermissionIfNeeded()
        LimitsNotificationWorker.schedule(requireContext())
        InvoiceReminderWorker.schedule(requireContext())
        RecurringEntryWorker.schedule(requireContext())
        StockNotificationWorker.schedule(requireContext())
    }

    /** На Android 13+ уведомления требуют явного разрешения — запрашиваем один раз при первом запуске экрана. */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    /**
     * Скрытый вход для разработчика: удержание пальца на логотипе 10 секунд открывает
     * диалог ввода кода. Никакой видимой кнопки/подсказки в UI нет — это сделано умышленно,
     * чтобы обычный пользователь не наткнулся на неё случайно.
     */
    private fun setupHiddenDevCodeGesture() {
        val handler = Handler(Looper.getMainLooper())
        val holdDurationMs = 10_000L
        var triggered = false

        val showCodeDialog = Runnable {
            if (triggered) return@Runnable
            triggered = true
            val input = EditText(requireContext())
            input.hint = getString(R.string.enter_code_hint)
            AlertDialog.Builder(requireContext())
                .setTitle(getString(R.string.enter_code_title))
                .setView(input)
                .setPositiveButton(getString(R.string.enter_code_apply)) { _, _ ->
                    val ok = BillingManager.tryUnlockWithDevCode(requireContext(), input.text.toString())
                    Toast.makeText(
                        requireContext(),
                        getString(if (ok) R.string.enter_code_success else R.string.enter_code_wrong),
                        Toast.LENGTH_SHORT
                    ).show()
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }

        requireView().findViewById<ImageView>(R.id.iv_logo).setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    triggered = false
                    handler.postDelayed(showCodeDialog, holdDurationMs)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(showCodeDialog)
                    true
                }
                else -> false
            }
        }
    }

    override fun onResume() {
        super.onResume()
        loadData()
        loadLimits()
        loadRecentEntries()
        loadMonthlySummaryChart()
        applyBusinessKindUi()
        updateNotificationBadge()
    }

    // Update: Magazyn jest teraz stalym elementem dolnej nawigacji, wiec ta
    // funkcja (dawniej pokazujaca/ukrywajaca przycisk "Magazyn" na Start wedlug
    // BusinessKind) nie jest juz potrzebna — zostawiona pusta na wypadek,
    // gdyby cos jeszcze jej uzywalo w applyBusinessKindUi() z innego miejsca.
    private fun applyBusinessKindUi() {}

    /** Licznik na dzwonku (iv_notifications) — liczba wpisow w historii powiadomien.
     *  Rosnie przy kazdym nowym powiadomieniu (NotificationLog.add), maleje przy
     *  usunieciu/wyczyszczeniu w NotificationsActivity — zawsze zsynchronizowany,
     *  bo oba ekrany czytaja ten sam magazyn (NotificationLog), a nie osobny licznik. */
    private fun updateNotificationBadge() {
        val count = NotificationLog.count(requireContext())
        val badge = requireView().findViewById<TextView>(R.id.tv_notif_badge)
        if (count <= 0) {
            badge.visibility = View.GONE
        } else {
            badge.visibility = View.VISIBLE
            badge.text = if (count > 99) "99+" else count.toString()
        }
    }

    private fun loadData() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            // Баланс/статистика/налог — только за текущий календарный год,
            // так как лимит 30 000 zł годовой (см. TaxHelper).
            val year = TaxHelper.currentYear()
            val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
            val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)

            val income = yearEntries.filter { it.isIncome }.sumOf { it.amount }
            val expense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense

            val prefs = requireContext().getSharedPreferences("settings", Context.MODE_PRIVATE)
            val otherIncome = TaxHelper.getOtherIncome(prefs, year)
            val activityType = ActivityTypeHelper.get(prefs)
            val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
            val taxResult = when (activityType) {
                ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(profit, otherIncome)
                ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(profit)
                ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczaltByCategory(yearEntries.filter { it.isIncome }, ryczaltRate)
            }
            val taxLabelRes = when (activityType) {
                ActivityType.JDG_LINIOWY -> R.string.tax_label_liniowy
                ActivityType.JDG_RYCZALT -> R.string.tax_label_ryczalt
                else -> TaxHelper.taxLabelResId(profit)
            }

            withContext(Dispatchers.Main) {
                requireView().findViewById<TextView>(R.id.tv_balance).text = formatMoney(profit) + " zł"
                requireView().findViewById<TextView>(R.id.tv_stat_income).text = formatMoney(income)
                requireView().findViewById<TextView>(R.id.tv_stat_expense).text = formatMoney(expense)
                requireView().findViewById<TextView>(R.id.tv_stat_profit).text = formatMoney(profit)
                // Динамическая подпись налога: "0% — необлагаемый минимум" / "12%" /
                // "Прогрессивная шкала 12%/32%" для skali, либо своя подпись для
                // liniowy/ryczałt — вместо одной фиксированной формулировки.
                requireView().findViewById<TextView>(R.id.tv_stat_tax_label).text = getString(taxLabelRes)
                requireView().findViewById<TextView>(R.id.tv_stat_tax).text = formatMoney(taxResult.tax)
                // Чистая прибыль = прибыль минус налог по выбранной форме налогообложения.
                requireView().findViewById<TextView>(R.id.tv_stat_net_profit).text = formatMoney(profit - taxResult.tax)
            }

            // Trend "vs poprzedni miesiac": porownanie zysku (przychod - wydatek) biezacego
            // miesiaca kalendarzowego z poprzednim. Czysto informacyjny wskaznik na karcie
            // Bilans - nie wplywa na zadne wyliczenia podatkowe powyzej.
            val cal = Calendar.getInstance()
            cal.set(Calendar.DAY_OF_MONTH, 1); cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            val curMonthStart = cal.timeInMillis
            val now = System.currentTimeMillis()
            cal.add(Calendar.MONTH, -1)
            val prevMonthStart = cal.timeInMillis
            val prevMonthEnd = curMonthStart - 1

            val curMonthEntries = db.entryDao().getBetween(curMonthStart, now)
            val prevMonthEntries = db.entryDao().getBetween(prevMonthStart, prevMonthEnd)
            val curMonthProfit = curMonthEntries.filter { it.isIncome }.sumOf { it.amount } -
                curMonthEntries.filter { !it.isIncome }.sumOf { it.amount }
            val prevMonthProfit = prevMonthEntries.filter { it.isIncome }.sumOf { it.amount } -
                prevMonthEntries.filter { !it.isIncome }.sumOf { it.amount }

            withContext(Dispatchers.Main) {
                val trendView = requireView().findViewById<TextView>(R.id.tv_balance_trend)
                if (prevMonthProfit == 0.0) {
                    trendView.visibility = View.GONE
                } else {
                    val changePercent = ((curMonthProfit - prevMonthProfit) / kotlin.math.abs(prevMonthProfit)) * 100
                    val up = changePercent >= 0
                    val arrow = if (up) "\u2191" else "\u2193"
                    trendView.text = String.format(Locale.getDefault(), "%s %.1f%%", arrow, kotlin.math.abs(changePercent))
                    trendView.setBackgroundResource(if (up) R.drawable.icon_badge_green_bg else R.drawable.icon_badge_red_bg)
                    trendView.setTextColor(
                        ContextCompat.getColor(requireContext(), if (up) R.color.badge_percent_green else R.color.badge_percent_red)
                    )
                    trendView.visibility = View.VISIBLE
                }
            }
        }
    }

    /** Laduje 5 najnowszych operacji (dochod/wydatek) do karty "Ostatnie transakcje" na glownym ekranie. */
    private fun loadRecentEntries() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val recent = db.entryDao().getAll().take(5)
            withContext(Dispatchers.Main) {
                recentEntriesAdapter.submitList(recent)
                requireView().findViewById<View>(R.id.tv_no_recent_entries).visibility =
                    if (recent.isEmpty()) View.VISIBLE else View.GONE
                requireView().findViewById<View>(R.id.rv_recent_entries).visibility =
                    if (recent.isEmpty()) View.GONE else View.VISIBLE
            }
        }
    }

    /**
     * Karta "Podsumowanie miesiaca": dzieli biezacy miesiac kalendarzowy na 5 przedzialow
     * (dni 1-7 / 8-14 / 15-21 / 22-28 / 29-31) i sumuje w nich przychod/wydatek - lekka
     * wizualizacja trendu bez pisania od zera osobnego wykresu liniowego.
     */
    private fun loadMonthlySummaryChart() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val cal = Calendar.getInstance()
            cal.set(Calendar.DAY_OF_MONTH, 1); cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0); cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            val monthStart = cal.timeInMillis
            val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
            val monthEnd = cal.apply { set(Calendar.DAY_OF_MONTH, daysInMonth) }.timeInMillis + (24L * 60 * 60 * 1000 - 1)

            val entries = db.entryDao().getBetween(monthStart, monthEnd)
            val bucketStarts = listOf(1, 8, 15, 22, 29)
            val points = bucketStarts.mapIndexed { i, dayStart ->
                val dayEnd = if (i + 1 < bucketStarts.size) bucketStarts[i + 1] - 1 else daysInMonth
                val bucketCal = Calendar.getInstance()
                bucketCal.timeInMillis = monthStart
                bucketCal.set(Calendar.DAY_OF_MONTH, dayStart.coerceAtMost(daysInMonth))
                bucketCal.set(Calendar.HOUR_OF_DAY, 0); bucketCal.set(Calendar.MINUTE, 0)
                bucketCal.set(Calendar.SECOND, 0); bucketCal.set(Calendar.MILLISECOND, 0)
                val from = bucketCal.timeInMillis
                bucketCal.set(Calendar.DAY_OF_MONTH, dayEnd.coerceAtMost(daysInMonth))
                bucketCal.set(Calendar.HOUR_OF_DAY, 23); bucketCal.set(Calendar.MINUTE, 59)
                bucketCal.set(Calendar.SECOND, 59)
                val to = bucketCal.timeInMillis
                val inBucket = entries.filter { it.dateMillis in from..to }
                MonthlyBarChartView.MonthPoint(
                    if (i == bucketStarts.lastIndex) daysInMonth.toString() else dayStart.toString(),
                    inBucket.filter { it.isIncome }.sumOf { it.amount },
                    inBucket.filter { !it.isIncome }.sumOf { it.amount }
                )
            }
            withContext(Dispatchers.Main) {
                requireView().findViewById<DualLineChartView>(R.id.chart_monthly_summary).submitData(
                    points.map { DualLineChartView.Point(it.label, it.income, it.expense) }
                )
            }
        }
    }

    /** Обновляет три гейджа лимитов и красный баннер превышения лимита niezarejestrowanej działalności. */
    private fun loadLimits() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val limits = LimitsHelper.compute(requireContext())
            withContext(Dispatchers.Main) {
                // Лимит "Działalność nierejestrowana, ten miesiąc" актуален ТОЛЬКО для
                // niezarejestrowanej — для любой Zarejestrowana JDG (skala/liniowy/ryczałt)
                // его вообще не существует, поэтому он скрыт.
                requireView().findViewById<View>(R.id.layout_limit_monthly).visibility =
                    if (limits.activityType == ActivityType.NIEZAREJESTROWANA) View.VISIBLE else View.GONE
                // Порог 120 000 zł/rok (12% -> 32%) актуален только для niezarejestrowanej
                // и dla skali (JDG_SKALA) — dla liniowy i ryczałt taki próg nie istnieje
                // (inna konstrukcja podatku), поэтому скрыт для них.
                requireView().findViewById<View>(R.id.layout_limit_bracket).visibility =
                    if (limits.activityType == ActivityType.NIEZAREJESTROWANA || limits.activityType == ActivityType.JDG_SKALA)
                        View.VISIBLE else View.GONE
                // Limit zwolnienia z VAT dotyczy wszystkich form działalności — widoczny zawsze.

                requireView().findViewById<TextView>(R.id.tv_limit_monthly_label).text =
                    "${formatMoney(limits.monthly.current)} zł / ${formatMoney(limits.monthly.limit)} zł"
                requireView().findViewById<ProgressBar>(R.id.pb_limit_monthly).progress = limits.monthly.percent.coerceAtMost(100)
                requireView().findViewById<TextView>(R.id.tv_limit_monthly_percent).text = "${limits.monthly.percent.coerceAtMost(100)}%"

                // Update: dwuetapowa szkala progu podatkowego zamiast jednej mylącej
                // "Pierwszy próg (120 000 zł)" — zob. LimitsHelper.BracketStageStatus.
                val stage = limits.bracketStage
                requireView().findViewById<TextView>(R.id.tv_limit_bracket_title).text = when (stage.stage) {
                    LimitsHelper.BracketStage.TAX_FREE -> getString(R.string.limit_bracket_title_tax_free)
                    LimitsHelper.BracketStage.RATE_12 -> getString(R.string.limit_bracket_title_rate12)
                    LimitsHelper.BracketStage.RATE_32 -> getString(R.string.limit_bracket_title_rate32)
                }
                requireView().findViewById<TextView>(R.id.tv_limit_bracket_label).text =
                    "${formatMoney(stage.barCurrent)} zł / ${formatMoney(stage.barLimit)} zł"
                requireView().findViewById<ProgressBar>(R.id.pb_limit_bracket).progress = stage.percent
                requireView().findViewById<TextView>(R.id.tv_limit_bracket_percent).text = "${stage.percent.coerceAtMost(100)}%"

                requireView().findViewById<TextView>(R.id.tv_limit_vat_label).text =
                    getString(
                        R.string.limit_vat_label,
                        formatMoney(limits.vat.current), formatMoney(limits.vat.limit)
                    )
                requireView().findViewById<ProgressBar>(R.id.pb_limit_vat).progress = limits.vat.percent.coerceAtMost(100)

                val warning = requireView().findViewById<TextView>(R.id.tv_limit_warning)
                if (limits.activityType == ActivityType.NIEZAREJESTROWANA && limits.monthly.exceeded) {
                    warning.text = getString(R.string.limit_exceeded_warning)
                    warning.visibility = View.VISIBLE
                } else {
                    warning.visibility = View.GONE
                }
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import java.security.MessageDigest

/**
 * Фасад над SubscriptionService (RevenueCat), сохраняющий исторические имена методов
 * (isPro/connect/restorePurchases/querySubscriptionPlans/launchPurchase), которые уже
 * вызываются из MainActivity/MineFragment/ReportFragment, SettingsActivity, SettingsProActivity и
 * AdsManager. Экраны, которые пользуются BillingManager, менять не пришлось — реальный
 * биллинг теперь идёт через RevenueCat (Google Play Billing ИЛИ Samsung IAP — в
 * зависимости от того, откуда установлено приложение, см. StoreDetector.kt), а не
 * напрямую через com.android.billingclient.
 *
 * Update: миграция с прямого Google Play BillingClient на RevenueCat, с поддержкой
 * единого Pro-доступа для Google Play и Samsung Galaxy Store.
 */
object BillingManager {

    // Исторические ID продуктов из старой (прямой) интеграции с Google Play Billing.
    // Сейчас используются только как публичные константы для UI (SettingsProActivity
    // хранит "какой план выбран" через них) — реальная покупка идёт по RevenueCat
    // package identifier (см. planIdToRcPackage()).
    const val PRO_MONTHLY_PRODUCT_ID = "pro_monthly"
    const val PRO_YEARLY_PRODUCT_ID = "pro_yearly"

    private const val PREFS_NAME = "settings"

    // "Выданный вручную" доступ (промокод разработчика) — независим от RevenueCat.
    // isPro() = ИЛИ(RevenueCat entitlement активен, промокод введён). Это важно: обновления
    // статуса из RevenueCat НЕ должны затирать промокод разработчика, и наоборот.
    private const val KEY_IS_PRO_PROMO = "isProPromo"

    // Код разработчика/тестировщика хранится как SHA-256 хэш, а не открытым текстом,
    // чтобы он не был виден при поверхностном просмотре декомпилированного APK.
    private const val DEV_CODE_SHA256 = "1edc850201cfdf17a41d59873127825355e7a03a3f8c0ab3e550099291844a55"

    private fun planIdToRcPackage(productId: String): String = when (productId) {
        PRO_YEARLY_PRODUCT_ID -> SubscriptionService.PACKAGE_YEARLY
        else -> SubscriptionService.PACKAGE_MONTHLY
    }

    /** Быстрая локальная проверка (кэш) — используйте её для скрытия/показа Pro-функций в UI. */
    fun isPro(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return SubscriptionService.isProActive(context) || prefs.getBoolean(KEY_IS_PRO_PROMO, false)
    }

    /**
     * Ввод кода разработчика/тестировщика — выдаёт Pro локально, без реальной покупки
     * (не связано с RevenueCat).
     * @return true, если код верный и Pro выдан.
     */
    fun tryUnlockWithDevCode(context: Context, code: String): Boolean {
        val hash = sha256(code.trim())
        val ok = hash.equals(DEV_CODE_SHA256, ignoreCase = true)
        if (ok) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_IS_PRO_PROMO, true).apply()
        }
        return ok
    }

    private fun sha256(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Инициализирует RevenueCat (если ещё не было сделано в FaApp.onCreate — на всякий
     * случай, это безопасно вызывать повторно) и подгружает Offering "default", чтобы
     * дальше можно было запросить цены/триал через querySubscriptionPlans().
     * errorMessage заполнен, если оффер не загрузился — полезно для диагностики
     * (можно показать пользователю/залогировать).
     */
    fun connect(context: Context, onReady: (connected: Boolean, errorMessage: String?) -> Unit) {
        SubscriptionService.init(context)
        SubscriptionService.fetchOfferings { offering, errorMessage ->
            onReady(offering != null, errorMessage)
        }
    }

    /** Подтягивает цену и длину пробного периода обоих планов подписки из RevenueCat. */
    fun querySubscriptionPlans(callback: (monthly: SubscriptionService.PlanInfo?, yearly: SubscriptionService.PlanInfo?, errorMessage: String?) -> Unit) {
        SubscriptionService.fetchOfferings { _, errorMessage ->
            val monthly = SubscriptionService.planInfoFor(SubscriptionService.PACKAGE_MONTHLY)
            val yearly = SubscriptionService.planInfoFor(SubscriptionService.PACKAGE_YEARLY)
            callback(monthly, yearly, errorMessage)
        }
    }

    /**
     * Запускает окно оплаты для выбранного плана (месяц/год). RevenueCat сам определяет,
     * через какой магазин проводить покупку — тот, из которого установлено приложение
     * (Google Play или Samsung Galaxy Store), см. StoreDetector/SubscriptionService.
     *
     * @param onResult success=true, если покупка прошла и Pro активирован; errorMessage
     * заполнен при реальной ошибке (не при отмене пользователем — тогда userCancelled=true
     * и errorMessage=null, чтобы не показывать тост "ошибка" на обычную отмену).
     */
    fun launchPurchase(
        activity: Activity,
        productId: String,
        onResult: (success: Boolean, errorMessage: String?, userCancelled: Boolean) -> Unit = { _, _, _ -> }
    ) {
        SubscriptionService.purchase(activity, planIdToRcPackage(productId), onResult)
    }

    /**
     * Сверяет с сервером RevenueCat, активна ли подписка, и обновляет локальный кэш.
     * Вызывать: при старте экрана Pro и сразу после возврата из окна оплаты.
     */
    fun restorePurchases(context: Context, onResult: (isPro: Boolean) -> Unit) {
        SubscriptionService.restorePurchases(context, onResult)
    }
}
FINARS_EOF

echo "Writing app/src/main/res/layout/fragment_report.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_report.xml")"
cat > "app/src/main/res/layout/fragment_report.xml" << 'FINARS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="170dp">

        <!-- ===================== Header: tytul + wybor okresu ===================== -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/reports_title"
            android:textColor="@color/text_primary"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="14dp"/>

        <LinearLayout
            android:id="@+id/btn_period"
            android:layout_width="wrap_content"
            android:layout_height="38dp"
            android:layout_gravity="center_horizontal"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:background="@drawable/input_field_bg"
            android:paddingStart="14dp"
            android:paddingEnd="10dp"
            android:layout_marginBottom="20dp"
            android:clickable="true" android:focusable="true">
            <TextView android:id="@+id/tv_period" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="@string/period_this_month" android:textColor="@color/text_primary" android:textSize="13sp"/>
            <ImageView android:layout_width="16dp" android:layout_height="16dp" android:layout_marginStart="6dp"
                android:src="@drawable/ic_chevron_down"/>
        </LinearLayout>

        <!-- ===================== Karta: Podsumowanie ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/report_summary"
                android:textColor="@color/text_primary"
                android:textSize="15sp"
                android:textStyle="bold"
                android:layout_marginBottom="16dp"/>

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical">

                <com.example.fa_ksiegowy.DonutChartView
                    android:id="@+id/donut_chart"
                    android:layout_width="128dp"
                    android:layout_height="128dp"/>

                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:orientation="vertical"
                    android:layout_marginStart="20dp">

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="10dp">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_income"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_income" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="10dp">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_expense"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_expense" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_tax"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_tax" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                </LinearLayout>

            </LinearLayout>

        </LinearLayout>

        <!-- ===================== Karta: rozklad procentowy ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <!-- Przychod -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/legend_income" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_income" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_income" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_income_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp" android:layout_marginBottom="14dp"/>

            <!-- Wydatki -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/legend_expense" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_expense" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_expense" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_expense_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp" android:layout_marginBottom="14dp"/>

            <!-- Podatek -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:id="@+id/tv_breakdown_tax_label" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_tax" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_tax" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_tax_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp"/>

        </LinearLayout>

        <!-- ===================== Karta: Trend (6 miesiecy) ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/trend_title"
                android:textColor="@color/text_primary"
                android:textSize="15sp"
                android:textStyle="bold"
                android:layout_marginBottom="14dp"/>

            <com.example.fa_ksiegowy.TrendLineChartView
                android:id="@+id/trend_chart"
                android:layout_width="match_parent"
                android:layout_height="140dp"/>

        </LinearLayout>

        <!-- ===================== Eksport raportu (funkcja zachowana z poprzedniej wersji ekranu — makieta jej nie pokazuje) ===================== -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/report_export_section"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:layout_marginBottom="10dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="3" android:baselineAligned="false">

            <Button android:id="@+id/btn_report_month" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/month" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
                android:layout_marginEnd="6dp" android:minWidth="0dp"/>

            <Button android:id="@+id/btn_report_year" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/year" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
                android:layout_marginEnd="6dp" android:minWidth="0dp"/>

            <Button android:id="@+id/btn_report_custom" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/custom_range" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
                android:minWidth="0dp"/>

        </LinearLayout>

    </LinearLayout>
    </ScrollView>

    <!-- Рекламный баннер и нижняя навигация теперь в MainActivity (общий,
         фиксированный контейнер поверх этого фрагмента) — не здесь. -->

</FrameLayout>
FINARS_EOF

echo "Writing app/src/main/AndroidManifest.xml"
mkdir -p "$(dirname "app/src/main/AndroidManifest.xml")"
cat > "app/src/main/AndroidManifest.xml" << 'FINARS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />

    <application
        android:name=".FaApp"
        android:allowBackup="true"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.FA">

        <!-- ЗАМЕНИТЬ на реальный AdMob App ID из консоли AdMob (Apps -> Ваше приложение -> App settings) -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-9218963926031039~6835956339" />

        <activity android:name=".TermsActivity" android:exported="false" />
        <activity android:name=".SettingsActivity" android:exported="false" />
        <activity android:name=".SettingsProActivity" android:exported="false" />
        <activity android:name=".SettingsBackupActivity" android:exported="false" />
        <activity android:name=".SettingsLanguageActivity" android:exported="false" />
        <activity android:name=".SettingsTaxActivity" android:exported="false" />
        <activity android:name=".LimitsActivity" android:exported="false" />
        <activity android:name=".NotificationsActivity" android:exported="false" />
        <activity android:name=".AboutActivity" android:exported="false" />
        <activity android:name=".PrivacyPolicyActivity" android:exported="false" />
        <activity android:name=".SettingsSecurityActivity" android:exported="false" />
        <activity android:name=".LockActivity" android:exported="false"
            android:launchMode="singleTask" android:excludeFromRecents="true" />
        <activity android:name=".PitDataActivity" android:exported="false" />
        <activity android:name=".Pit36Activity" android:exported="false" />
        <activity android:name=".AddEntryActivity" android:exported="false" />
        <activity android:name=".AddInvoiceActivity" android:exported="false" />
        <activity android:name=".AddInvoiceCorrectionActivity" android:exported="false" />
        <activity android:name=".InvoiceHistoryActivity" android:exported="false" />
        <activity android:name=".HistoryActivity" android:exported="false" />
        <activity android:name=".InventoryActivity" android:exported="false" />
        <activity android:name=".InventoryHistoryActivity" android:exported="false" />
        <activity android:name=".AddEditProductActivity" android:exported="false" />
        <activity android:name=".SelectProductsActivity" android:exported="false" />
        <activity android:name=".MainActivity" android:exported="true"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
</manifest>

FINARS_EOF

echo ""
echo "--- Removing files replaced by ReportFragment ---"
if [ -f "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt" ]; then
    rm "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt"
    echo "Removed app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt"
fi
if [ -f "app/src/main/res/layout/activity_report.xml" ]; then
    rm "app/src/main/res/layout/activity_report.xml"
    echo "Removed app/src/main/res/layout/activity_report.xml"
fi


echo ""
echo "--- Проверка баланса скобок (Kotlin) ---"
CHECK_FAILED=0
for f in "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt"; do
    if python3 - "$f" << 'PYCHECK_EOF'
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()
stack = []
pairs = {')': '(', ']': '[', '}': '{'}
in_string = False
str_char = ''
i = 0
line = 1
while i < len(s):
    c = s[i]
    if c == '\n':
        line += 1
    if in_string:
        if c == '\\\\':
            i += 2
            continue
        if c == str_char:
            in_string = False
        i += 1
        continue
    if c in ('"', "'"):
        in_string = True
        str_char = c
        i += 1
        continue
    if c == '/' and i + 1 < len(s) and s[i + 1] == '/':
        j = s.find('\n', i)
        i = j if j != -1 else len(s)
        continue
    if c in '([{':
        stack.append((c, line))
    elif c in ')]}':
        if not stack or pairs[c] != stack[-1][0]:
            print(f"{path}: MISMATCH at line {line}")
            sys.exit(1)
        stack.pop()
    i += 1
if stack:
    print(f"{path}: UNCLOSED {stack}")
    sys.exit(1)
print(f"{path}: OK")
PYCHECK_EOF
    then
        :
    else
        CHECK_FAILED=1
    fi
done
if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "ERROR: синтаксическая проблема в Kotlin-файлах — остановка без коммита."
    exit 1
fi

echo ""
echo "--- Проверка XML-файлов ---"
python3 - << 'PYXML_EOF'
import xml.etree.ElementTree as ET
files = [
    "app/src/main/res/layout/fragment_report.xml",
    "app/src/main/AndroidManifest.xml",
]
for f in files:
    try:
        ET.parse(f)
        print(f, "OK")
    except Exception as e:
        print(f, "ERROR", e)
        raise SystemExit(1)
PYXML_EOF

echo ""
echo "--- Проверка отсутствия остаточных ссылок на ReportActivity ---"
if grep -rn "ReportActivity::class" app/src/main/java --include=*.kt 2>/dev/null; then
    echo "ERROR: остались ссылки на ReportActivity::class — остановка без коммита."
    exit 1
fi
echo "OK: остаточных ссылок нет"

echo ""
echo "--- Все проверки пройдены ---"
echo ""
echo "Изменённые/новые/удалённые файлы:"
git status --short

echo ""
echo "--- git add / commit / push ---"
git add -A "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" "app/src/main/res/layout/fragment_report.xml" "app/src/main/AndroidManifest.xml" \
  "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt" "app/src/main/res/layout/activity_report.xml"
if git diff --cached --quiet; then
    echo "Нет изменений для коммита."
else
    git commit -m "Stage 3: ReportFragment in single-Activity host + fix stale-closure bug that blocked tab switching after first switch"
    git push origin main
    echo ""
    echo "Готово. Пуш выполнен — сборка APK запустится в GitHub Actions."
fi
