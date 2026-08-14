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
