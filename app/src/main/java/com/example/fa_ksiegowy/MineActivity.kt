package com.example.fa_ksiegowy

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.gms.ads.AdView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Calendar
import java.util.Locale

class MineActivity : BaseActivity() {
    private lateinit var db: AppDatabase
    private lateinit var recentEntriesAdapter: EntryAdapter
    private var bannerAdView: AdView? = null

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* результат не критичен для UI */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_mine)
        BottomNavBar.attach(this, BottomNavBar.Tab.START)
        db = AppDatabase.getInstance(this)

        // Единая кнопка добавления: выбор дохода/расхода происходит уже внутри
        // AddEntryActivity (переключатель с подсветкой выбранного варианта).
        // По умолчанию открываем на "доход", это чаще нужное действие.
        findViewById<Button>(R.id.btn_add_entry).setOnClickListener {
            startActivity(Intent(this, AddEntryActivity::class.java).putExtra("isIncome", true))
        }
        findViewById<Button>(R.id.btn_settings).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        findViewById<View>(R.id.iv_notifications).setOnClickListener {
            startActivity(Intent(this, NotificationsActivity::class.java))
        }
        findViewById<Button>(R.id.btn_reports).setOnClickListener {
            startActivity(Intent(this, ReportActivity::class.java))
        }
        findViewById<Button>(R.id.btn_history).setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
        }
        findViewById<Button>(R.id.btn_invoices).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, AddInvoiceActivity::class.java))
            } else {
                androidx.appcompat.app.AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.invoice_pro_locked_message))
                    .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                        startActivity(Intent(this, SettingsActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        // Update: przycisk "Magazyn" przeniesiony do dolnej nawigacji (patrz
        // bottom_nav_bar.xml) — nie jest juz na karcie Start.

        // Karta "Limity" -> pelnoekranowy podglad (dokladnie wedlug makietu).
        findViewById<View>(R.id.card_limits).setOnClickListener {
            startActivity(Intent(this, LimitsActivity::class.java))
        }
        // "Edytuj" -> edycja formy dzialalnosci/stawek w ustawieniach podatkowych.
        findViewById<TextView>(R.id.tv_edit_limits).setOnClickListener {
            startActivity(Intent(this, SettingsTaxActivity::class.java))
        }

        // "Zobacz wszystkie" nad lista ostatnich transakcji -> pelna historia.
        findViewById<TextView>(R.id.tv_view_all_entries).setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
        }

        recentEntriesAdapter = EntryAdapter { entry ->
            startActivity(
                Intent(this, AddEntryActivity::class.java)
                    .putExtra("entryId", entry.id)
                    .putExtra("isIncome", entry.isIncome)
            )
        }
        findViewById<RecyclerView>(R.id.rv_recent_entries).apply {
            layoutManager = LinearLayoutManager(this@MineActivity)
            adapter = recentEntriesAdapter
        }

        bannerAdView = AdsManager.setupAndLoadBanner(
            this,
            findViewById<FrameLayout>(R.id.ad_container),
            findViewById(R.id.tv_ad_debug)
        )
        setupHiddenDevCodeGesture()
        requestNotificationPermissionIfNeeded()
        LimitsNotificationWorker.schedule(this)
        InvoiceReminderWorker.schedule(this)
        RecurringEntryWorker.schedule(this)
        StockNotificationWorker.schedule(this)
    }

    /** На Android 13+ уведомления требуют явного разрешения — запрашиваем один раз при первом запуске экрана. */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
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
            val input = EditText(this)
            input.hint = getString(R.string.enter_code_hint)
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.enter_code_title))
                .setView(input)
                .setPositiveButton(getString(R.string.enter_code_apply)) { _, _ ->
                    val ok = BillingManager.tryUnlockWithDevCode(this, input.text.toString())
                    Toast.makeText(
                        this,
                        getString(if (ok) R.string.enter_code_success else R.string.enter_code_wrong),
                        Toast.LENGTH_SHORT
                    ).show()
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }

        findViewById<ImageView>(R.id.iv_logo).setOnTouchListener { _, event ->
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

    override fun onDestroy() {
        bannerAdView?.destroy()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        loadData()
        loadLimits()
        loadRecentEntries()
        loadMonthlySummaryChart()
        applyBusinessKindUi()
        if (BillingManager.isPro(this)) {
            bannerAdView?.let { AdsManager.hideBanner(findViewById(R.id.ad_container), it) }
        }
    }

    // Update: Magazyn jest teraz stalym elementem dolnej nawigacji, wiec ta
    // funkcja (dawniej pokazujaca/ukrywajaca przycisk "Magazyn" na Start wedlug
    // BusinessKind) nie jest juz potrzebna — zostawiona pusta na wypadek,
    // gdyby cos jeszcze jej uzywalo w applyBusinessKindUi() z innego miejsca.
    private fun applyBusinessKindUi() {}

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            // Баланс/статистика/налог — только за текущий календарный год,
            // так как лимит 30 000 zł годовой (см. TaxHelper).
            val year = TaxHelper.currentYear()
            val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
            val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)

            val income = yearEntries.filter { it.isIncome }.sumOf { it.amount }
            val expense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense

            val prefs = getSharedPreferences("settings", MODE_PRIVATE)
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
                findViewById<TextView>(R.id.tv_balance).text = formatMoney(profit) + " zł"
                findViewById<TextView>(R.id.tv_stat_income).text = formatMoney(income)
                findViewById<TextView>(R.id.tv_stat_expense).text = formatMoney(expense)
                findViewById<TextView>(R.id.tv_stat_profit).text = formatMoney(profit)
                // Динамическая подпись налога: "0% — необлагаемый минимум" / "12%" /
                // "Прогрессивная шкала 12%/32%" для skali, либо своя подпись для
                // liniowy/ryczałt — вместо одной фиксированной формулировки.
                findViewById<TextView>(R.id.tv_stat_tax_label).text = getString(taxLabelRes)
                findViewById<TextView>(R.id.tv_stat_tax).text = formatMoney(taxResult.tax)
                // Чистая прибыль = прибыль минус налог по выбранной форме налогообложения.
                findViewById<TextView>(R.id.tv_stat_net_profit).text = formatMoney(profit - taxResult.tax)
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
                val trendView = findViewById<TextView>(R.id.tv_balance_trend)
                if (prevMonthProfit == 0.0) {
                    trendView.visibility = View.GONE
                } else {
                    val changePercent = ((curMonthProfit - prevMonthProfit) / kotlin.math.abs(prevMonthProfit)) * 100
                    val up = changePercent >= 0
                    val arrow = if (up) "\u2191" else "\u2193"
                    trendView.text = String.format(Locale.getDefault(), "%s %.1f%%", arrow, kotlin.math.abs(changePercent))
                    trendView.setBackgroundResource(if (up) R.drawable.icon_badge_green_bg else R.drawable.icon_badge_red_bg)
                    trendView.setTextColor(
                        ContextCompat.getColor(this@MineActivity, if (up) R.color.badge_percent_green else R.color.badge_percent_red)
                    )
                    trendView.visibility = View.VISIBLE
                }
            }
        }
    }

    /** Laduje 5 najnowszych operacji (dochod/wydatek) do karty "Ostatnie transakcje" na glownym ekranie. */
    private fun loadRecentEntries() {
        CoroutineScope(Dispatchers.IO).launch {
            val recent = db.entryDao().getAll().take(5)
            withContext(Dispatchers.Main) {
                recentEntriesAdapter.submitList(recent)
                findViewById<View>(R.id.tv_no_recent_entries).visibility =
                    if (recent.isEmpty()) View.VISIBLE else View.GONE
                findViewById<View>(R.id.rv_recent_entries).visibility =
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
        CoroutineScope(Dispatchers.IO).launch {
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
                findViewById<DualLineChartView>(R.id.chart_monthly_summary).submitData(
                    points.map { DualLineChartView.Point(it.label, it.income, it.expense) }
                )
            }
        }
    }

    /** Обновляет три гейджа лимитов и красный баннер превышения лимита niezarejestrowanej działalności. */
    private fun loadLimits() {
        CoroutineScope(Dispatchers.IO).launch {
            val limits = LimitsHelper.compute(this@MineActivity)
            withContext(Dispatchers.Main) {
                // Лимит "Działalność nierejestrowana, ten miesiąc" актуален ТОЛЬКО для
                // niezarejestrowanej — для любой Zarejestrowana JDG (skala/liniowy/ryczałt)
                // его вообще не существует, поэтому он скрыт.
                findViewById<View>(R.id.layout_limit_monthly).visibility =
                    if (limits.activityType == ActivityType.NIEZAREJESTROWANA) View.VISIBLE else View.GONE
                // Порог 120 000 zł/rok (12% -> 32%) актуален только для niezarejestrowanej
                // и dla skali (JDG_SKALA) — dla liniowy i ryczałt taki próg nie istnieje
                // (inna konstrukcja podatku), поэтому скрыт для них.
                findViewById<View>(R.id.layout_limit_bracket).visibility =
                    if (limits.activityType == ActivityType.NIEZAREJESTROWANA || limits.activityType == ActivityType.JDG_SKALA)
                        View.VISIBLE else View.GONE
                // Limit zwolnienia z VAT dotyczy wszystkich form działalności — widoczny zawsze.

                findViewById<TextView>(R.id.tv_limit_monthly_label).text =
                    "${formatMoney(limits.monthly.current)} zł / ${formatMoney(limits.monthly.limit)} zł"
                findViewById<ProgressBar>(R.id.pb_limit_monthly).progress = limits.monthly.percent.coerceAtMost(100)
                findViewById<TextView>(R.id.tv_limit_monthly_percent).text = "${limits.monthly.percent.coerceAtMost(100)}%"

                // Update: dwuetapowa szkala progu podatkowego zamiast jednej mylącej
                // "Pierwszy próg (120 000 zł)" — zob. LimitsHelper.BracketStageStatus.
                val stage = limits.bracketStage
                findViewById<TextView>(R.id.tv_limit_bracket_title).text = when (stage.stage) {
                    LimitsHelper.BracketStage.TAX_FREE -> getString(R.string.limit_bracket_title_tax_free)
                    LimitsHelper.BracketStage.RATE_12 -> getString(R.string.limit_bracket_title_rate12)
                    LimitsHelper.BracketStage.RATE_32 -> getString(R.string.limit_bracket_title_rate32)
                }
                findViewById<TextView>(R.id.tv_limit_bracket_label).text =
                    "${formatMoney(stage.barCurrent)} zł / ${formatMoney(stage.barLimit)} zł"
                findViewById<ProgressBar>(R.id.pb_limit_bracket).progress = stage.percent
                findViewById<TextView>(R.id.tv_limit_bracket_percent).text = "${stage.percent.coerceAtMost(100)}%"

                findViewById<TextView>(R.id.tv_limit_vat_label).text =
                    getString(
                        R.string.limit_vat_label,
                        formatMoney(limits.vat.current), formatMoney(limits.vat.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_vat).progress = limits.vat.percent.coerceAtMost(100)

                val warning = findViewById<TextView>(R.id.tv_limit_warning)
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
