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
