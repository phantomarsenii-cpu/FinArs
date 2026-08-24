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
