#!/data/data/com.termux/files/usr/bin/bash
# FinArs — update_project-43-single-activity-stage2-magazin-fragment.sh
#
# ЭТАП 2 миграции на единый MainActivity-хост:
#
#   - MagazinActivity УДАЛЁН, заменён на MagazinFragment внутри MainActivity.
#   - MainActivity теперь переключает Start<->Magazyn через show/hide (без
#     recreate) — баннер и нав-бар НЕ пересоздаются при переходе между ними.
#   - BottomNavBar: 'Start'/'Magazyn' из оставшихся экранов-Activity
#     (Raporty/Ustawienia) теперь ведут в MainActivity с нужной вкладкой,
#     а не в удалённый MagazinActivity.
#   - Уведомление 'низкий остаток товара' (StockNotificationWorker) теперь
#     открывает MainActivity на вкладке Magazyn (через Intent-экстра), а не
#     удалённый MagazinActivity. MainActivity: launchMode=singleTask, обработка
#     onNewIntent — тап по уведомлению при уже запущенном приложении просто
#     переключает вкладку, а не пересоздаёт Activity.
#
# ВАЖНО: Raporty/Ustawienia ПОКА ОСТАЮТСЯ отдельными Activity — баннер/нав-бар
# на них по-прежнему пересоздаются при переходе. Переключение Start<->Magazyn
# внутри MainActivity теперь МГНОВЕННОЕ и без мигания баннера.
set -euo pipefail

echo "=== FinArs: единый Activity-хост, этап 2 (MagazinFragment) ==="

REPO_ROOT="$HOME/FA_ksiegowy"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)

if [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "ERROR: не похоже на корень репозитория FinArs."
    exit 1
fi

echo "--- Backing up files that will be modified or deleted ---"
[ -f "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/fragment_magazin.xml" ] && cp "app/src/main/res/layout/fragment_magazin.xml" "app/src/main/res/layout/fragment_magazin.xml.bak_${TS}" || true
[ -f "app/src/main/AndroidManifest.xml" ] && cp "app/src/main/AndroidManifest.xml" "app/src/main/AndroidManifest.xml.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/activity_magazin.xml" ] && cp "app/src/main/res/layout/activity_magazin.xml" "app/src/main/res/layout/activity_magazin.xml.bak_${TS}" || true

echo "Writing app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import androidx.fragment.app.Fragment

/**
 * Постоянный хост для главных вкладок. Заменяет собой бывший MineActivity/MagazinActivity —
 * все прежние ссылки на них теперь указывают сюда.
 *
 * Update: миграция на единый Activity-хост с фрагментами — нижняя навигация и рекламный
 * баннер создаются ОДИН РАЗ за всё время жизни этой Activity и не пересоздаются при
 * переключении вкладок (раньше каждая вкладка была отдельной Activity, и AdView грузился
 * заново при каждом переходе). Переключение между уже переведёнными на фрагменты вкладками
 * идёт через show/hide (а не replace) — так у каждой вкладки сохраняется состояние
 * (скролл, загруженные данные) между переключениями, а не пересоздаётся с нуля.
 *
 * Этап 2: переведены Start (MineFragment) и Magazyn (MagazinFragment). Raporty/Ustawienia
 * пока ещё отдельные Activity — переключение на них по-старому запускает Activity
 * (см. BottomNavBar.attach на них самих). Будут переведены на следующих этапах.
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
        // Тап по уведомлению (например, "низкий остаток товара") при уже запущенном
        // MainActivity — не пересоздаём Activity, просто переключаемся на нужную вкладку.
        tabFromIntentExtra(intent)?.let { switchTo(it) }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_CURRENT_TAB, currentTab.name)
    }

    private fun tabFromIntentExtra(intent: Intent?): BottomNavBar.Tab? =
        when (intent?.getStringExtra(EXTRA_OPEN_TAB)) {
            TAB_MAGAZIN -> BottomNavBar.Tab.MAGAZIN
            TAB_START -> BottomNavBar.Tab.START
            else -> null
        }

    private fun setupNav() {
        BottomNavBar.attachHost(this, currentTab) { tab -> switchTo(tab) }
    }

    /**
     * Переключение вкладки. Start/Magazyn — фрагменты внутри этой же Activity (show/hide,
     * без recreate — баннер и нав-бар не трогаются). Raporty/Ustawienia пока отдельные
     * Activity — обычный startActivity, как было раньше (следующие этапы миграции).
     */
    private fun switchTo(tab: BottomNavBar.Tab) {
        if (tab == currentTab) return

        if (tab != BottomNavBar.Tab.START && tab != BottomNavBar.Tab.MAGAZIN) {
            val target = when (tab) {
                BottomNavBar.Tab.REPORTS -> ReportActivity::class.java
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

    private fun tagFor(tab: BottomNavBar.Tab) = "tab_${tab.name}"

    private fun createFragment(tab: BottomNavBar.Tab): Fragment = when (tab) {
        BottomNavBar.Tab.MAGAZIN -> MagazinFragment()
        else -> MineFragment()
    }

    companion object {
        private const val KEY_CURRENT_TAB = "current_tab"

        /** Публичные константы для Intent-экстра "какую вкладку открыть" — используются
         * воркерами уведомлений (см. StockNotificationWorker) при тапе по push-уведомлению. */
        const val EXTRA_OPEN_TAB = "open_tab"
        const val TAB_MAGAZIN = "MAGAZIN"
        const val TAB_START = "START"
    }
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Склад: список товаров, добавление вручную или сканированием штрихкода, удаление. */
class MagazinFragment : Fragment() {
    private lateinit var adapter: ProductAdapter

    private val scanLauncher = registerForActivityResult(ScanContract()) { result ->
        val barcode = result.contents
        if (barcode != null) handleScannedBarcode(barcode)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_magazin, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        adapter = ProductAdapter(
            onClick = { p ->
                startActivity(Intent(requireContext(), AddEditProductActivity::class.java).putExtra("productId", p.id))
            },
            onLongClick = { p -> confirmDelete(p); true }
        )
        requireView().findViewById<RecyclerView>(R.id.rv_products).apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@MagazinFragment.adapter
        }

        requireView().findViewById<Button>(R.id.btn_add_product_manual).setOnClickListener {
            startActivity(Intent(requireContext(), AddEditProductActivity::class.java))
        }
        requireView().findViewById<Button>(R.id.btn_scan_barcode).setOnClickListener {
            scanLauncher.launch(
                ScanOptions()
                    .setDesiredBarcodeFormats(ScanOptions.ALL_CODE_TYPES)
                    .setPrompt(getString(R.string.scan_barcode_prompt))
                    .setBeepEnabled(true)
                    .setOrientationLocked(true)
            )
        }
        requireView().findViewById<Button>(R.id.btn_inventory).setOnClickListener {
            startActivity(Intent(requireContext(), InventoryActivity::class.java))
        }
    }

    override fun onResume() {
        super.onResume()
        loadProducts()
    }

    private fun loadProducts() {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val all = AppDatabase.getInstance(requireContext().applicationContext).productDao().getAll()
            withContext(Dispatchers.Main) {
                adapter.submitList(all)
                val low = all.filter { it.isLowStock }
                val banner = requireView().findViewById<TextView>(R.id.tv_low_stock_banner)
                if (low.isNotEmpty()) {
                    banner.text = getString(R.string.low_stock_banner, low.size)
                    banner.visibility = View.VISIBLE
                } else {
                    banner.visibility = View.GONE
                }
            }
        }
    }

    /** Штрихкод отсканирован: если товар уже есть — открываем на редактирование (пополнение),
     *  иначе пробуем найти название в Open Food Facts, а если не нашли — открываем ручной ввод
     *  с уже подставленным штрихкодом. */
    private fun handleScannedBarcode(barcode: String) {
        viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
            val existing = AppDatabase.getInstance(requireContext().applicationContext).productDao().getByBarcode(barcode)
            if (existing != null) {
                withContext(Dispatchers.Main) {
                    startActivity(Intent(requireContext(), AddEditProductActivity::class.java).putExtra("productId", existing.id))
                }
                return@launch
            }
            withContext(Dispatchers.Main) {
                Toast.makeText(requireContext(), getString(R.string.looking_up_product), Toast.LENGTH_SHORT).show()
            }
            val name = ProductLookupService.lookupName(barcode)
            withContext(Dispatchers.Main) {
                val i = Intent(requireContext(), AddEditProductActivity::class.java)
                i.putExtra("barcode", barcode)
                if (name != null) i.putExtra("prefillName", name)
                startActivity(i)
            }
        }
    }

    private fun confirmDelete(p: Product) {
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
                    AppDatabase.getInstance(requireContext().applicationContext).productDao().delete(p)
                    withContext(Dispatchers.Main) { loadProducts() }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
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
 * Этап 2: Start (MineFragment) и Magazyn (MagazinFragment) переведены на фрагменты внутри
 * MainActivity — attachHost()/updateVisual() используются MainActivity. Raporty/Ustawienia
 * пока ещё отдельные Activity — используют старый attach(), как и раньше; "Start" и
 * "Magazyn" из НИХ теперь ведут в MainActivity (с нужной вкладкой через Intent-экстра),
 * а не в удалённые MineActivity/MagazinActivity.
 */
object BottomNavBar {

    enum class Tab { START, TRANSACTIONS, MAGAZIN, REPORTS, SETTINGS }

    /** Для оставшихся экранов-Activity (Raporty/Ustawienia). */
    fun attach(activity: AppCompatActivity, current: Tab) {
        bindToMainActivityTab(activity, R.id.nav_start, Tab.START, current)
        bindToMainActivityTab(activity, R.id.nav_magazin, Tab.MAGAZIN, current)
        bind(activity, R.id.nav_reports, Tab.REPORTS, current, ReportActivity::class.java)
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
            mainActivity.findViewById<View>(viewId)?.setOnClickListener {
                if (tab != current) onTabSelected(tab)
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

    /** "Start"/"Magazyn" с оставшихся экранов-Activity (Raporty/Ustawienia) ведут в
     * MainActivity (единый фрагмент-хост), а не в удалённые MineActivity/MagazinActivity.
     * FLAG_ACTIVITY_CLEAR_TOP переиспользует уже существующий (singleTask) экземпляр
     * MainActivity вместо создания нового поверх стека. */
    private fun bindToMainActivityTab(activity: AppCompatActivity, viewId: Int, tab: Tab, current: Tab) {
        val group = activity.findViewById<View>(viewId) ?: return
        val active = tab == current
        applyVisual(activity, group, active)

        group.setOnClickListener {
            if (!active) {
                val intent = Intent(activity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
                    if (tab == Tab.MAGAZIN) putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_MAGAZIN)
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

echo "Writing app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.content.Context
import android.content.SharedPreferences
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/** Ежедневная проверка остатков на складе — уведомление раз в день на товар, если остаток низкий. */
class StockNotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            // Уведомления должны быть на языке, выбранном В ПРИЛОЖЕНИИ (LocaleHelper),
            // а не на системном языке телефона — раньше ctx.getString(...)
            // брал системную локаль напрямую, из-за чего уведомления могли отличаться
            // от языка интерфейса приложения.
            val ctx = LocaleHelper.applyLocale(applicationContext)
            val prefs = applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)
            if (!BusinessKindHelper.get(prefs).showsMagazin) return Result.success()
            val dao = AppDatabase.getInstance(applicationContext).productDao()
            val today = SDF_DAY.format(Date())
            for (p in dao.getLowStock()) {
                notifyOnce(
                    prefs, "stock_low_${p.id}_$today",
                    ctx.getString(R.string.notif_low_stock_title),
                    ctx.getString(
                        R.string.notif_low_stock_text,
                        p.name,
                        String.format(Locale.getDefault(), "%.1f", p.quantity),
                        p.unit
                    ),
                    // Update: MagazinActivity удалён — теперь MainActivity (единый хост),
                    // с флагом, какую вкладку открыть при тапе по уведомлению.
                    MainActivity::class.java,
                    android.os.Bundle().apply { putString(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_MAGAZIN) }
                )
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun notifyOnce(
        prefs: SharedPreferences, key: String, title: String, text: String,
        targetActivity: Class<*>? = null,
        intentExtras: android.os.Bundle? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        LimitsNotificationWorker.showNotification(applicationContext, key.hashCode(), title, text, targetActivity, intentExtras)
    }

    companion object {
        private val SDF_DAY = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        private const val UNIQUE_WORK_NAME = "fa_stock_low_daily_check"

        fun schedule(context: Context) {
            LimitsNotificationWorker.createChannel(context)
            val request = PeriodicWorkRequestBuilder<StockNotificationWorker>(24, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request
            )
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
                    ReportActivity::class.java
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
        targetActivity: Class<*>? = null
    ) {
        if (prefs.getBoolean("notif_shown_$key", false)) return
        prefs.edit().putBoolean("notif_shown_$key", true).apply()
        showNotification(applicationContext, key.hashCode(), title, text, targetActivity)
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

echo "Writing app/src/main/res/layout/fragment_magazin.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_magazin.xml")"
cat > "app/src/main/res/layout/fragment_magazin.xml" << 'FINARS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="152dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/magazin_title"
            android:textColor="@color/text_primary"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="18dp"/>

        <TextView
            android:id="@+id/tv_low_stock_banner"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@drawable/card_bg"
            android:padding="14dp"
            android:layout_marginBottom="14dp"
            android:textColor="@color/expense_red"
            android:textSize="13sp"
            android:textStyle="bold"
            android:visibility="gone"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="2"
            android:baselineAligned="false"
            android:layout_marginBottom="12dp">

            <Button
                android:id="@+id/btn_add_product_manual"
                android:layout_width="0dp"
                android:layout_height="52dp"
                android:layout_weight="1"
                android:layout_marginEnd="8dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/add_product_manually"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_scan_barcode"
                android:layout_width="0dp"
                android:layout_height="52dp"
                android:layout_weight="1"
                android:layout_marginStart="8dp"
                android:background="@drawable/btn_pill_primary"
                android:text="@string/scan_barcode"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="13sp"/>

        </LinearLayout>

        <Button
            android:id="@+id/btn_inventory"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginBottom="16dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/start_inventory"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/rv_products"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false"/>

    </LinearLayout>

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
        <activity android:name=".ReportActivity" android:exported="false" />
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
echo "--- Removing files replaced by MagazinFragment ---"
if [ -f "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" ]; then
    rm "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt"
    echo "Removed app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt"
fi
if [ -f "app/src/main/res/layout/activity_magazin.xml" ]; then
    rm "app/src/main/res/layout/activity_magazin.xml"
    echo "Removed app/src/main/res/layout/activity_magazin.xml"
fi


echo ""
echo "--- Проверка баланса скобок (Kotlin) ---"
CHECK_FAILED=0
for f in "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt"; do
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
    "app/src/main/res/layout/fragment_magazin.xml",
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
echo "--- Проверка отсутствия остаточных ссылок на MagazinActivity ---"
if grep -rn "MagazinActivity::class" app/src/main/java --include=*.kt 2>/dev/null; then
    echo "ERROR: остались ссылки на MagazinActivity::class — остановка без коммита."
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
git add -A "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MagazinFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/StockNotificationWorker.kt" "app/src/main/java/com/example/fa_ksiegowy/LimitsNotificationWorker.kt" "app/src/main/res/layout/fragment_magazin.xml" "app/src/main/AndroidManifest.xml" \
  "app/src/main/java/com/example/fa_ksiegowy/MagazinActivity.kt" "app/src/main/res/layout/activity_magazin.xml"
if git diff --cached --quiet; then
    echo "Нет изменений для коммита."
else
    git commit -m "Stage 2: MagazinFragment in single-Activity host, instant Start<->Magazin switching without banner/nav recreation, notification deep link updated"
    git push origin main
    echo ""
    echo "Готово. Пуш выполнен — сборка APK запустится в GitHub Actions."
fi
