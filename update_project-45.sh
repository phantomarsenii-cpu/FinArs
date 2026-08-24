#!/data/data/com.termux/files/usr/bin/bash
# FinArs — update_project-45-single-activity-stage4-settings-fragment-final.sh
#
# ЭТАП 4 (ФИНАЛЬНЫЙ) миграции на единый MainActivity-хост + ИСПРАВЛЕНИЕ БАГА
# 'кнопка Start на экране Limits не работает':
#
#   БАГ (исправлен): bindToMainActivityTab() пропускал навигацию, если нажатая
#   вкладка совпадала с 'текущей' (current) — это верно для переключения ВНУТРИ
#   MainActivity, но НЕВЕРНО для отдельных экранов-детализаций (LimitsActivity,
#   HistoryActivity), которые тоже показывают нав-бар с подсвеченной вкладкой,
#   но сами не являются этой вкладкой — из-за этого кнопка 'Start' на экране
#   Limits (где Start тоже подсвечен) ничего не делала. Теперь такие экраны
#   ВСЕГДА переходят в MainActivity по тапу, независимо от подсветки.
#
#   - SettingsActivity УДАЛЁН, заменён на SettingsFragment внутри MainActivity.
#   - Все 4 вкладки (Start/Magazyn/Raporty/Ustawienia) теперь фрагменты —
#     переключение между ЛЮБЫМИ из них мгновенное, БЕЗ пересоздания баннера
#     или нижней навигации. Миграция завершена.
#   - Кнопка 'Ustawienia' на дашборде Start и диалоги 'функция Pro' теперь
#     тоже мгновенно переключают вкладку вместо запуска отдельного экрана.
set -euo pipefail

echo "=== FinArs: единый Activity-хост, этап 4/4 (SettingsFragment) + фикс кнопки Start в Limits ==="

REPO_ROOT="$HOME/FA_ksiegowy"
cd "$REPO_ROOT"

TS=$(date +%Y%m%d_%H%M%S)

if [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "ERROR: не похоже на корень репозитория FinArs."
    exit 1
fi

echo "--- Backing up files that will be modified or deleted ---"
[ -f "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt" "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/fragment_settings.xml" ] && cp "app/src/main/res/layout/fragment_settings.xml" "app/src/main/res/layout/fragment_settings.xml.bak_${TS}" || true
[ -f "app/src/main/AndroidManifest.xml" ] && cp "app/src/main/AndroidManifest.xml" "app/src/main/AndroidManifest.xml.bak_${TS}" || true
[ -f "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" ] && cp "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt.bak_${TS}" || true
[ -f "app/src/main/res/layout/activity_settings.xml" ] && cp "app/src/main/res/layout/activity_settings.xml" "app/src/main/res/layout/activity_settings.xml.bak_${TS}" || true

echo "Writing app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.content.Intent
import android.os.Bundle
import androidx.fragment.app.Fragment

/**
 * Постоянный хост для всех главных вкладок. Заменяет собой бывшие MineActivity/
 * MagazinActivity/ReportActivity/SettingsActivity — все прежние ссылки на них теперь
 * указывают сюда.
 *
 * Update: миграция на единый Activity-хост с фрагментами завершена (этап 4) — нижняя
 * навигация и рекламный баннер создаются ОДИН РАЗ за всё время жизни этой Activity и
 * никогда не пересоздаются ни при каком переключении вкладок. Переключение идёт через
 * show/hide (а не replace) — у каждой вкладки сохраняется состояние (скролл, загруженные
 * данные) между переключениями, а не пересоздаётся с нуля.
 *
 * Все 4 вкладки — Start (MineFragment), Magazyn (MagazinFragment), Raporty (ReportFragment),
 * Ustawienia (SettingsFragment) — теперь фрагменты внутри этой Activity. Отдельные Activity
 * остаются только у экранов ВНЕ нижней навигации (AddEntryActivity, LimitsActivity,
 * HistoryActivity и т.д. — они по-прежнему показывают нав-бар как удобство через
 * BottomNavBar.attach(), но не входят в этот фрагмент-хост).
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
            TAB_SETTINGS -> BottomNavBar.Tab.SETTINGS
            TAB_START -> BottomNavBar.Tab.START
            else -> null
        }

    private fun setupNav() {
        BottomNavBar.attachHost(this, currentTab) { tab -> switchTo(tab) }
    }

    /** Публичный вход для фрагментов (например, кнопка "Raporty" на дашборде
     * MineFragment) — переключает вкладку мгновенно, тем же механизмом, что и
     * нижняя навигация, без пересоздания Activity/баннера. */
    fun openTab(tab: BottomNavBar.Tab) = switchTo(tab)

    /** Переключение вкладки — все 4 вкладки теперь фрагменты внутри этой же Activity
     * (show/hide, без recreate — баннер и нав-бар не трогаются). */
    private fun switchTo(tab: BottomNavBar.Tab) {
        if (tab == currentTab) return

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
        BottomNavBar.Tab.REPORTS -> ReportFragment()
        BottomNavBar.Tab.SETTINGS -> SettingsFragment()
        else -> MineFragment()
    }

    companion object {
        private const val KEY_CURRENT_TAB = "current_tab"

        /** Публичные константы для Intent-экстра "какую вкладку открыть" — используются
         * воркерами уведомлений (StockNotificationWorker, LimitsNotificationWorker) и
         * экранами-детализациями (HistoryActivity, LimitsActivity) через BottomNavBar. */
        const val EXTRA_OPEN_TAB = "open_tab"
        const val TAB_MAGAZIN = "MAGAZIN"
        const val TAB_REPORTS = "REPORTS"
        const val TAB_SETTINGS = "SETTINGS"
        const val TAB_START = "START"
    }
}
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment

/** Главное меню настроек — теперь просто категории, сами экраны вынесены
 *  в отдельные Activity, чтобы список не занимал весь экран и было место
 *  под будущие разделы. */
class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_settings, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        // Update: setContentView/BottomNavBar.attach убраны — этот экран теперь фрагмент
        // внутри MainActivity, у которого нав-бар и рекламный баннер уже созданы один раз
        // на уровне Activity (см. MainActivity.kt), а не пересоздаются здесь.

        requireView().findViewById<View>(R.id.btn_menu_tax).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsTaxActivity::class.java))
        }
        // Update: пункт меню "Безопасность (PIN/Biometrics)" был потерян в одном
        // из прошлых обновлений — сама логика (SecurityHelper/LockActivity/
        // AppLockState) всё это время оставалась рабочей, но экран настроек был
        // недостижим, поэтому PIN никто не мог задать и блокировка ни разу не
        // срабатывала. Возвращаем переход на экран.
        requireView().findViewById<View>(R.id.btn_menu_security).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsSecurityActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(requireContext())) {
                startActivity(Intent(requireContext(), Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(requireContext())
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(requireContext(), SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        requireView().findViewById<View>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsLanguageActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_backup).setOnClickListener {
            if (BillingManager.isPro(requireContext())) {
                startActivity(Intent(requireContext(), SettingsBackupActivity::class.java))
            } else {
                AlertDialog.Builder(requireContext())
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.backup_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(requireContext(), SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        requireView().findViewById<View>(R.id.btn_menu_pro).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsProActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_terms).setOnClickListener {
            val i = Intent(requireContext(), TermsActivity::class.java)
            i.putExtra(TermsActivity.EXTRA_READ_ONLY, true)
            startActivity(i)
        }
        requireView().findViewById<View>(R.id.btn_menu_privacy).setOnClickListener {
            startActivity(Intent(requireContext(), PrivacyPolicyActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_about).setOnClickListener {
            startActivity(Intent(requireContext(), AboutActivity::class.java))
        }
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

    /** Для оставшихся экранов-Activity, которые показывают нижнюю навигацию как
     * удобство (не являются одной из 4 главных вкладок) — HistoryActivity, LimitsActivity. */
    fun attach(activity: AppCompatActivity, current: Tab) {
        bindToMainActivityTab(activity, R.id.nav_start, Tab.START, current)
        bindToMainActivityTab(activity, R.id.nav_magazin, Tab.MAGAZIN, current)
        bindToMainActivityTab(activity, R.id.nav_reports, Tab.REPORTS, current)
        bindToMainActivityTab(activity, R.id.nav_settings, Tab.SETTINGS, current)
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
    /** "Start"/"Magazyn"/"Raporty"/"Ustawienia" с отдельных экранов-детализации
     * (HistoryActivity, LimitsActivity — показывают нижнюю навигацию для удобства, но
     * сами не являются одной из вкладок MainActivity) всегда ведут в MainActivity,
     * даже если визуально "своя" вкладка уже подсвечена активной. Это НЕ то же самое,
     * что переключение вкладок внутри самого MainActivity (там повторный тап по уже
     * активной вкладке действительно должен быть no-op — см. attachHost/switchTo).
     * Update: раньше здесь ошибочно стоял `if (!active)`, из-за чего, например, кнопка
     * "Start" на экране Limits (который тоже подсвечивает Start) вообще не реагировала —
     * пользователь не мог вернуться на главный экран отсюда одним тапом. */
    private fun bindToMainActivityTab(activity: AppCompatActivity, viewId: Int, tab: Tab, current: Tab) {
        val group = activity.findViewById<View>(viewId) ?: return
        applyVisual(activity, group, tab == current)

        group.setOnClickListener {
            val intent = Intent(activity, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
                when (tab) {
                    Tab.MAGAZIN -> putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_MAGAZIN)
                    Tab.REPORTS -> putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_REPORTS)
                    Tab.SETTINGS -> putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_SETTINGS)
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
            // Update: раньше открывал SettingsActivity отдельным экраном (пересоздавая
            // баннер/нав-бар); теперь оба — фрагменты внутри одного MainActivity,
            // поэтому просто переключаем вкладку — мгновенно, без мигания.
            (activity as? MainActivity)?.openTab(BottomNavBar.Tab.SETTINGS)
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
                        (activity as? MainActivity)?.openTab(BottomNavBar.Tab.SETTINGS)
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
FINARS_EOF

echo "Writing app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Экран добавления ИЛИ редактирования операции.
 * Если в intent передан "entryId" (id существующей записи) — режим редактирования:
 * поля предзаполняются, появляется кнопка удаления, а сохранение обновляет запись
 * вместо создания новой. Без "entryId" работает как раньше — создание новой записи.
 *
 * Update: сканирование чека (распознавание суммы/даты/позиций по фото, ML Kit OCR —
 * "Skanuj paragon" и "Skanuj paragon z galerii") возвращено — работает офлайн, на
 * устройстве, поверх обычного прикрепления фото чека (btn_attach), доступно только
 * для расходов (см. updateTypeToggleUi/runOcr).
 *
 * Для приходов, когда в настройках выбрана форма ActivityType.JDG_RYCZALT,
 * появляется обязательный выбор категории ryczałtu (см. RyczaltCategory) — ставка
 * (3%/5,5%/8,5%/12%/14%/17%) теперь привязана к конкретной операции, а не к одной
 * общей настройке, так как один человек может одновременно продавать товары и
 * оказывать разные услуги.
 */
class AddEntryActivity : BaseActivity() {
    private var selectedImagePath: String? = null
    private var editingEntry: Entry? = null
    private var currentIsIncome: Boolean = true
    // Дата транзакции (Data sprzedaży / Data transakcji) — по умолчанию сегодня,
    // но пользователь может выбрать любую дату через DatePickerDialog. Это важно,
    // так как лимиты działalność nierejestrowana считаются строго по месяцам/кварталам,
    // и запись должна попадать в правильный период, а не всегда в "сейчас".
    private var selectedDateMillis: Long = System.currentTimeMillis()
    // Повтор доступен только при создании новой записи (не при редактировании
    // существующей) — иначе неясно, что должно произойти с уже созданными
    // на основе шаблона транзакциями.
    private var wantsRecurring: Boolean = false

    // Категория ryczałtu для этого дохода — актуальна только когда currentIsIncome==true
    // и в настройках выбран ActivityType.JDG_RYCZALT (см. updateTypeToggleUi/RyczaltCategory).
    private var selectedRyczaltCategory: String? = null

    // Косметическая категория операции (Kategoria z makiety) — НЕ отдельное поле в БД,
    // хранится как читаемый префикс в Entry.comment (см. TransactionCategory), чтобы не
    // требовать миграции Room. Null, если пользователь не выбрал категорию.
    private var selectedCategoryLabel: String? = null
    private val activityType: ActivityType by lazy {
        ActivityTypeHelper.get(getSharedPreferences("settings", MODE_PRIVATE))
    }

    // Update: фото для распознавания чека (ML Kit OCR) — пишется в полном разрешении
    // через системную камеру (FileProvider), затем прогоняется через ReceiptOcrHelper.
    private var ocrPhotoFile: File? = null

    private val takeOcrPhoto = registerForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (success) runOcr()
    }

    // Сканирование чека по фото ИЗ ГАЛЕРЕИ (в отличие от btn_attach, который просто
    // прикладывает файл без распознавания) — копируем выбранную картинку во временный
    // файл и прогоняем через тот же runOcr(), что и снимок с камеры.
    private val pickOcrImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri == null) return@registerForActivityResult
        try {
            val input = contentResolver.openInputStream(uri)
            if (input == null) {
                Toast.makeText(this, getString(R.string.receipt_scan_no_text), Toast.LENGTH_SHORT).show()
                return@registerForActivityResult
            }
            val file = File(getExternalFilesDir(null), "ocr_tmp_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { fos -> input.copyTo(fos) }
            input.close()
            ocrPhotoFile = file
            runOcr()
        } catch (e: Exception) {
            Toast.makeText(this, "Ошибка при загрузке чека: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_add_entry)

        val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
            if (uri == null) return@registerForActivityResult
            try {
                val input = contentResolver.openInputStream(uri)
                if (input == null) {
                    Toast.makeText(this, "Не удалось открыть файл", Toast.LENGTH_SHORT).show()
                    return@registerForActivityResult
                }
                // Временное имя: окончательное стандартизированное имя
                // (YYYY-MM-DD_TYPE_AMOUNT_ID.jpg) присваивается при сохранении записи,
                // когда известны дата операции, сумма, тип и id (см. renameReceiptToStandardName).
                val out = File(getExternalFilesDir(null), "receipt_tmp_${System.currentTimeMillis()}.jpg")
                FileOutputStream(out).use { fos -> input.copyTo(fos) }
                input.close()
                selectedImagePath = out.absolutePath
                findViewById<TextView>(R.id.tv_attach_label).text = getString(R.string.attach_receipt) + " ✓"
                Toast.makeText(this, "Чек добавлен", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Ошибка при добавлении чека: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }

        val entryId = intent.getLongExtra("entryId", -1L)
        currentIsIncome = intent.getBooleanExtra("isIncome", true)

        setupTypeToggle()
        findViewById<View>(R.id.btn_close).setOnClickListener { finish() }
        findViewById<View>(R.id.btn_attach).setOnClickListener { pickImage.launch("image/*") }
        findViewById<View>(R.id.btn_category).setOnClickListener { showCategoryPicker() }
        findViewById<Button>(R.id.btn_delete).setOnClickListener { confirmDelete() }
        findViewById<View>(R.id.btn_date).setOnClickListener { showDatePicker() }
        findViewById<Button>(R.id.btn_ryczalt_category).setOnClickListener { showRyczaltCategoryPicker() }
        findViewById<android.widget.Switch>(R.id.sw_recurring).setOnCheckedChangeListener { _, checked ->
            wantsRecurring = checked
        }

        updateTypeToggleUi()
        updateTitle()
        updateDateButtonText()
        updateCategoryButtonText()
        updateRyczaltCategoryButtonText()

        if (entryId != -1L) {
            findViewById<Button>(R.id.btn_delete).visibility = View.VISIBLE
            findViewById<View>(R.id.row_recurring).visibility = View.GONE
            findViewById<View>(R.id.divider_recurring).visibility = View.GONE
            CoroutineScope(Dispatchers.IO).launch {
                val entry = AppDatabase.getInstance(applicationContext).entryDao().getById(entryId)
                withContext(Dispatchers.Main) {
                    if (entry == null) {
                        Toast.makeText(this@AddEntryActivity, "Запись не найдена", Toast.LENGTH_SHORT).show()
                        finish()
                        return@withContext
                    }
                    editingEntry = entry
                    currentIsIncome = entry.isIncome
                    findViewById<EditText>(R.id.et_amount).setText(formatAmount(entry.amount))
                    val (cat, restComment) = TransactionCategory.splitComment(this@AddEntryActivity, entry.comment, entry.isIncome)
                    selectedCategoryLabel = cat?.let { getString(it.labelRes) }
                    findViewById<EditText>(R.id.et_comment).setText(restComment)
                    updateCategoryButtonText()
                    selectedImagePath = entry.receiptPath
                    selectedDateMillis = entry.dateMillis
                    selectedRyczaltCategory = entry.ryczaltCategory
                    if (entry.receiptPath != null) {
                        findViewById<TextView>(R.id.tv_attach_label).text = getString(R.string.attach_receipt) + " ✓"
                    }
                    updateTypeToggleUi()
                    updateTitle()
                    updateDateButtonText()
                    updateRyczaltCategoryButtonText()
                }
            }
        }

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            val amt = findViewById<EditText>(R.id.et_amount).text.toString().toDoubleOrNull()
            if (amt == null || amt <= 0.0) {
                Toast.makeText(this, "Введите корректную сумму", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT && selectedRyczaltCategory == null) {
                Toast.makeText(this, getString(R.string.income_ryczalt_category_required_error), Toast.LENGTH_LONG).show()
                return@setOnClickListener
            }
            val comment = buildFinalComment(findViewById<EditText>(R.id.et_comment).text.toString())
            findViewById<Button>(R.id.btn_save).isEnabled = false

            // Категория ryczałtu имеет смысл только для приходов при форме ryczałt —
            // для расходов и других форм налогообложения запись сохраняем с null.
            val categoryToSave = if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT) selectedRyczaltCategory else null

            val existing = editingEntry
            CoroutineScope(Dispatchers.IO).launch {
                val dao = AppDatabase.getInstance(applicationContext).entryDao()
                val finalReceiptPath = renameReceiptToStandardName(
                    selectedImagePath, selectedDateMillis, currentIsIncome, amt, existing?.id
                )
                if (existing != null) {
                    dao.update(
                        existing.copy(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath,
                            ryczaltCategory = categoryToSave
                        )
                    )
                } else {
                    val newId = dao.insert(
                        Entry(
                            amount = amt,
                            isIncome = currentIsIncome,
                            comment = comment,
                            dateMillis = selectedDateMillis,
                            receiptPath = finalReceiptPath,
                            ryczaltCategory = categoryToSave
                        )
                    )
                    // Имя файла чека включает id записи — при создании id известен только
                    // после insert, поэтому для новых записей переименовываем повторно.
                    val renamedAgain = renameReceiptToStandardName(
                        finalReceiptPath, selectedDateMillis, currentIsIncome, amt, newId
                    )
                    if (renamedAgain != finalReceiptPath) {
                        dao.update(
                            Entry(
                                id = newId, amount = amt, isIncome = currentIsIncome,
                                comment = comment, dateMillis = selectedDateMillis, receiptPath = renamedAgain,
                                ryczaltCategory = categoryToSave
                            )
                        )
                    }
                    if (wantsRecurring) {
                        val cal = java.util.Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
                        val dayOfMonth = cal.get(java.util.Calendar.DAY_OF_MONTH).coerceIn(1, 28)
                        cal.add(java.util.Calendar.MONTH, 1)
                        cal.set(java.util.Calendar.DAY_OF_MONTH, dayOfMonth)
                        AppDatabase.getInstance(applicationContext).recurringEntryDao().insert(
                            RecurringEntry(
                                amount = amt,
                                isIncome = currentIsIncome,
                                comment = comment,
                                dayOfMonth = dayOfMonth,
                                nextRunMillis = cal.timeInMillis
                            )
                        )
                    }
                }
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@AddEntryActivity,
                        getString(if (existing != null) R.string.entry_updated else R.string.saved),
                        Toast.LENGTH_SHORT
                    ).show()
                    finish()
                }
            }
        }
    }

    private fun setupTypeToggle() {
        findViewById<Button>(R.id.btn_type_income).setOnClickListener {
            currentIsIncome = true
            selectedCategoryLabel = null
            updateTypeToggleUi()
            updateTitle()
            updateCategoryButtonText()
        }
        findViewById<Button>(R.id.btn_type_expense).setOnClickListener {
            currentIsIncome = false
            selectedCategoryLabel = null
            updateTypeToggleUi()
            updateTitle()
            updateCategoryButtonText()
        }
        // "Faktura" nie jest trzecim stanem tej samej operacji — to osobny przeplyw
        // (patrz AddInvoiceActivity), wiec od razu nawigujemy i zamykamy ten ekran.
        // Update: ta sciezka pomijala sprawdzenie Pro (w przeciwienstwie do analogicznego
        // przycisku na ekranie glownym) — kazdy mogl wystawiac faktury bez subskrypcji.
        findViewById<Button>(R.id.btn_type_invoice).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, AddInvoiceActivity::class.java))
                finish()
            } else {
                androidx.appcompat.app.AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.invoice_pro_locked_message))
                    .setPositiveButton(getString(R.string.pro_feature_locked_go_settings)) { _, _ ->
                        // Update: SettingsActivity удалён — теперь MainActivity (единый
                        // фрагмент-хост), с флагом, какую вкладку открыть.
                        startActivity(Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra(MainActivity.EXTRA_OPEN_TAB, MainActivity.TAB_SETTINGS)
                        })
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
    }

    private fun updateTypeToggleUi() {
        val income = findViewById<Button>(R.id.btn_type_income)
        val expense = findViewById<Button>(R.id.btn_type_expense)
        // Явное выделение выбранного варианта — тот же приём, что и для способа оплаты
        // на экране фактуры: яркий фон + белый текст против приглушённого фона и
        // серого текста у невыбранного варианта.
        income.setBackgroundResource(if (currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        expense.setBackgroundResource(if (!currentIsIncome) R.drawable.btn_pill_payment_selected else R.drawable.btn_pill_payment_unselected)
        income.setTextColor(resources.getColor(if (currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        expense.setTextColor(resources.getColor(if (!currentIsIncome) R.color.text_primary else R.color.text_secondary, theme))
        income.alpha = if (currentIsIncome) 1.0f else 0.75f
        expense.alpha = if (!currentIsIncome) 1.0f else 0.75f
        // Прикладывать/сканировать чек имеет смысл только для расходов (чек подтверждает
        // трату) — для приходов эти кнопки только путают.
        findViewById<View>(R.id.btn_attach).visibility = if (currentIsIncome) View.GONE else View.VISIBLE
        // Update: przyciski skanowania paragonu usuniete z UI — nie ma juz
        // czego pokazywac/ukrywac tutaj wg typu operacji.
        // Категория ryczałtu, наоборот, актуальна только для ПРИХОДОВ и только при
        // форме налогообложения ryczałt — во всех остальных случаях скрыта.
        findViewById<Button>(R.id.btn_ryczalt_category).visibility =
            if (currentIsIncome && activityType == ActivityType.JDG_RYCZALT) View.VISIBLE else View.GONE
    }

    private fun updateTitle() {
        val isEditing = editingEntry != null
        findViewById<TextView>(R.id.tv_add_title).text =
            getString(if (isEditing) R.string.edit_entry_title else R.string.add_entry_title)
    }

    /** Небольшое стилизованное вертикальное меню (см. AppDialog) для выбора категории
     *  ryczałtu этого прихода — от неё зависит применяемая ставка налога. */
    private fun showRyczaltCategoryPicker() {
        AppDialog.showOptionPicker(
            context = this,
            title = getString(R.string.ryczalt_category_picker_title),
            options = RyczaltCategory.entries.map { it.name to getString(it.labelRes) }
        ) { selected ->
            selectedRyczaltCategory = selected
            updateRyczaltCategoryButtonText()
        }
    }

    private fun updateRyczaltCategoryButtonText() {
        val btn = findViewById<Button>(R.id.btn_ryczalt_category)
        val cat = RyczaltCategory.fromStorageKeyOrNull(selectedRyczaltCategory)
        btn.text = if (cat != null) getString(R.string.ryczalt_category_selected, getString(cat.labelRes))
        else getString(R.string.ryczalt_category_choose)
    }

    /** Wiersz "Kategoria" (z makiety) — kosmetyczny wybor, zapisywany jako czytelny
     *  prefiks Entry.comment (patrz TransactionCategory i buildFinalComment()). */
    private fun showCategoryPicker() {
        val defs = if (currentIsIncome) TransactionCategory.incomeCategories(this) else TransactionCategory.expenseCategories(this)
        AppDialog.showOptionPicker(
            context = this,
            title = getString(R.string.category_label),
            options = defs.map { it.id to getString(it.labelRes) }
        ) { selectedId ->
            val def = defs.firstOrNull { it.id == selectedId }
            selectedCategoryLabel = def?.let { getString(it.labelRes) }
            updateCategoryButtonText()
        }
    }

    private fun updateCategoryButtonText() {
        findViewById<TextView>(R.id.tv_category_value).text =
            selectedCategoryLabel ?: getString(R.string.category_choose)
    }

    /** Laczy kategorie (jesli wybrana) z wolnym komentarzem w jeden tekst do zapisu w bazie
     *  — patrz TransactionCategory.splitComment po stronie odczytu (lista transakcji). */
    private fun buildFinalComment(freeComment: String): String {
        val cat = selectedCategoryLabel
        return when {
            cat != null && freeComment.isNotBlank() -> "$cat — $freeComment"
            cat != null -> cat
            else -> freeComment
        }
    }

    private fun confirmDelete() {
        val entry = editingEntry ?: return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.delete_confirm_title))
            .setMessage(getString(R.string.delete_confirm_message))
            .setPositiveButton(getString(R.string.delete_confirm_yes)) { _, _ ->
                CoroutineScope(Dispatchers.IO).launch {
                    AppDatabase.getInstance(applicationContext).entryDao().delete(entry)
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@AddEntryActivity, getString(R.string.entry_deleted), Toast.LENGTH_SHORT).show()
                        finish()
                    }
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }

    /** Без лишних нулей для целых сумм (100, а не 100.0), но с сохранением копеек, если они есть. */
    private fun formatAmount(v: Double): String =
        if (v == v.toLong().toDouble()) v.toLong().toString() else v.toString()

    /** Запускает системную камеру для фото чека и сохраняет полноразмерный файл через FileProvider. */
    private fun launchReceiptScan() {
        val file = File(getExternalFilesDir(null), "ocr_tmp_${System.currentTimeMillis()}.jpg")
        ocrPhotoFile = file
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        takeOcrPhoto.launch(uri)
    }

    /** Прогоняет сделанное фото через ML Kit и подставляет распознанные сумму/дату/продавца. */
    private fun runOcr() {
        val file = ocrPhotoFile ?: return
        Toast.makeText(this, getString(R.string.receipt_scan_processing), Toast.LENGTH_SHORT).show()
        CoroutineScope(Dispatchers.IO).launch {
            val bmp = try {
                BitmapFactory.decodeFile(file.absolutePath)
            } catch (e: Exception) {
                null
            }
            if (bmp == null) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_SHORT).show()
                }
                return@launch
            }
            val result = try {
                ReceiptOcrHelper.recognize(bmp)
            } catch (e: Exception) {
                null
            }
            withContext(Dispatchers.Main) {
                if (result == null) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_LONG).show()
                    return@withContext
                }
                if (result.amount != null) {
                    findViewById<EditText>(R.id.et_amount).setText(formatAmount(result.amount))
                }
                if (result.dateMillis != null) {
                    selectedDateMillis = result.dateMillis
                    updateDateButtonText()
                }
                // Комментарий заполняем позициями покупки с чека (название + цена
                // каждого товара/услуги), а не просто именем продавца — это то, ради
                // чего вообще нужно сканирование, чтобы не вводить список вручную.
                // Не трогаем поле, если пользователь уже что-то в него вписал.
                if (result.items.isNotEmpty() || !result.sellerName.isNullOrBlank()) {
                    val commentField = findViewById<EditText>(R.id.et_comment)
                    if (commentField.text.toString().isBlank()) {
                        commentField.setText(buildReceiptComment(result))
                    }
                }
                selectedImagePath = file.absolutePath
                findViewById<TextView>(R.id.tv_attach_label).text = getString(R.string.attach_receipt) + " ✓"
                if (result.amount == null && result.dateMillis == null) {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_no_text), Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(this@AddEntryActivity, getString(R.string.receipt_scan_done), Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun buildReceiptComment(result: ReceiptOcrResult): String {
        if (result.items.isNotEmpty()) {
            val builder = StringBuilder()
            for (item in result.items) {
                builder.append("• ").append(item.name)
                if (item.price != null) {
                    builder.append(" — ").append(formatAmount(item.price)).append(" zł")
                }
                builder.append("\n")
            }
            return builder.toString().trim()
        }
        return result.sellerName?.trim().orEmpty()
    }

    /** Открывает системный DatePickerDialog, предзаполненный текущей выбранной датой. */
    private fun showDatePicker() {
        val cal = Calendar.getInstance().apply { timeInMillis = selectedDateMillis }
        DatePickerDialog(
            this,
            { _, year, month, dayOfMonth ->
                val picked = Calendar.getInstance().apply {
                    set(year, month, dayOfMonth, 12, 0, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                selectedDateMillis = picked.timeInMillis
                updateDateButtonText()
            },
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH),
            cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    /**
     * Переименовывает файл чека (если он есть) в стандартизированный формат
     * `YYYY-MM-DD_TYPE_AMOUNT_ID.jpg` (см. FileNaming) для удобной сортировки
     * и архивации перед подачей в налоговую. Если id ещё не известен
     * (новая запись до insert), используется 0 — сразу после insert
     * файл переименовывается ещё раз с настоящим id.
     */
    private fun renameReceiptToStandardName(
        path: String?, dateMillis: Long, isIncome: Boolean, amount: Double, entryId: Long?
    ): String? {
        if (path == null) return null
        val current = File(path)
        if (!current.exists()) return path
        val ext = current.extension.ifBlank { "jpg" }
        val newName = FileNaming.receiptFileName(dateMillis, isIncome, amount, entryId ?: 0L, ext)
        val newFile = File(current.parentFile, newName)
        if (newFile.absolutePath == current.absolutePath) return path
        return try {
            if (current.renameTo(newFile)) newFile.absolutePath else path
        } catch (e: Exception) {
            path
        }
    }

    /** Обновляет текст значения даты в формате dd.MM.yyyy (польский/общеевропейский формат). */
    private fun updateDateButtonText() {
        val sdf = SimpleDateFormat("dd.MM.yyyy", Locale.getDefault())
        findViewById<TextView>(R.id.tv_date_value).text = sdf.format(selectedDateMillis)
    }
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
 * вызываются из MainActivity/MineFragment/ReportFragment/SettingsFragment, SettingsProActivity и
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

echo "Writing app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt" << 'FINARS_EOF'
package com.example.fa_ksiegowy

import android.net.Uri
import android.os.Bundle
import android.view.View
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
 * Экран генерации PIT (PRO): выбор года, предпросмотр Przychód/Koszty/Dochód/podatek,
 * ссылка на форму личных данных и кнопка генерации PDF-отчёта (см. Pit36PdfGenerator).
 * Доступен только пользователям с Pro (проверка — в SettingsFragment перед стартом).
 *
 * Какая декларация нужна (PIT-36 / PIT-36L / PIT-28) определяется автоматически
 * по выбранному в настройках виду деятельности (см. ActivityTypeHelper.formCode) —
 * экран и его заголовок не привязаны к одной конкретной декларации.
 *
 * Данные супруга(и) для совместного rozliczenia редактируются на экране личных
 * данных (PitDataActivity), а не здесь — см. cb_joint_spouse и layout_spouse_block.
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

        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
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

        // Официальный (готовый к подаче) бланк сейчас доступен только для PIT-36 —
        // для PIT-36L/PIT-28 показываем только вспомогательный информационный PDF.
        val officialSupported = Pit36FormFiller.isSupported(r.activityType)
        findViewById<Button>(R.id.btn_generate_official_pit36).visibility =
            if (officialSupported) View.VISIBLE else View.GONE
        findViewById<TextView>(R.id.tv_pit36_official_hint).apply {
            visibility = if (officialSupported) View.VISIBLE else View.GONE
            if (officialSupported) text = getString(R.string.pit36_official_hint, r.activityType.formCode)
        }

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
FINARS_EOF

echo "Writing app/src/main/res/layout/fragment_settings.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_settings.xml")"
cat > "app/src/main/res/layout/fragment_settings.xml" << 'FINARS_EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="170dp">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/settings" android:textSize="18sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:gravity="center" android:layout_marginBottom="20dp"/>

        <!-- Podatek i limity -->
        <LinearLayout android:id="@+id/btn_menu_tax" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_tax"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_tax"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Bezpieczenstwo -->
        <LinearLayout android:id="@+id/btn_menu_security" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_purple_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_security"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_security"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Kopia zapasowa (Pro) -->
        <LinearLayout android:id="@+id/btn_menu_backup" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_backup"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_backup"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Generuj PIT (Pro) -->
        <LinearLayout android:id="@+id/btn_menu_pit36" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_green_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_pit"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_pit36"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Jezyk -->
        <LinearLayout android:id="@+id/btn_menu_language" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_language"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_language"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Wersja Pro -->
        <LinearLayout android:id="@+id/btn_menu_pro" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_orange_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_pro"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_pro"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- O aplikacji -->
        <LinearLayout android:id="@+id/btn_menu_about" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_info"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/about_app"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Polityka prywatnosci (wymagana do publikacji w Google Play) -->
        <LinearLayout android:id="@+id/btn_menu_privacy" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_green_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_privacy"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_privacy"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Warunki korzystania -->
        <LinearLayout android:id="@+id/btn_menu_terms" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_terms"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_terms"/>
            <ImageView style="@style/SettingsRowChevron"/>
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
echo "--- Removing files replaced by SettingsFragment ---"
if [ -f "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" ]; then
    rm "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt"
    echo "Removed app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt"
fi
if [ -f "app/src/main/res/layout/activity_settings.xml" ]; then
    rm "app/src/main/res/layout/activity_settings.xml"
    echo "Removed app/src/main/res/layout/activity_settings.xml"
fi


echo ""
echo "--- Проверка баланса скобок (Kotlin) ---"
CHECK_FAILED=0
for f in "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt"; do
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
    "app/src/main/res/layout/fragment_settings.xml",
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
echo "--- Проверка отсутствия остаточных ссылок на SettingsActivity ---"
if grep -rn "SettingsActivity::class" app/src/main/java --include=*.kt 2>/dev/null; then
    echo "ERROR: остались ссылки на SettingsActivity::class — остановка без коммита."
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
git add -A "app/src/main/java/com/example/fa_ksiegowy/MainActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/SettingsFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" "app/src/main/java/com/example/fa_ksiegowy/MineFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/ReportFragment.kt" "app/src/main/java/com/example/fa_ksiegowy/AddEntryActivity.kt" "app/src/main/java/com/example/fa_ksiegowy/BillingManager.kt" "app/src/main/java/com/example/fa_ksiegowy/Pit36Activity.kt" "app/src/main/res/layout/fragment_settings.xml" "app/src/main/AndroidManifest.xml" \
  "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt" "app/src/main/res/layout/activity_settings.xml"
if git diff --cached --quiet; then
    echo "Нет изменений для коммита."
else
    git commit -m "Stage 4 (final): SettingsFragment completes single-Activity migration + fix Start button not working from LimitsActivity"
    git push origin main
    echo ""
    echo "Готово. Пуш выполнен — сборка APK запустится в GitHub Actions."
fi
