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
