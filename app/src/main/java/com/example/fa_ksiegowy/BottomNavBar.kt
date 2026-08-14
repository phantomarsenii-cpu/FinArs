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
 * @layout/bottom_nav_bar) at the bottom of the 4 main tab screens
 * (Start / Transakcje / Raporty / Ustawienia) plus the central "+" button.
 *
 * Update: этап миграции на единый MainActivity-хост (фрагменты вместо отдельных
 * Activity — чтобы нижняя навигация и рекламный баннер не пересоздавались при
 * переключении вкладок). Пока переведён только "Start" (MineFragment внутри
 * MainActivity) — attachHost() используется MainActivity. Остальные 3 вкладки
 * (Magazyn/Raporty/Ustawienia) пока ещё отдельные Activity — используют старый
 * attach(), как и раньше; будут переведены на следующих этапах.
 */
object BottomNavBar {

    // Update: "Transakcje" zostalo zastapione przez "Magazyn" w dolnej nawigacji
    // (pelna lista transakcji jest nadal dostepna przez "Zobacz wszystkie" na
    // Start — bylo to postrzegane jako duplikat, Magazyn jest teraz bardziej
    // przydatny w stalym miejscu). TRANSACTIONS zostaje w enumie (uzywane przez
    // HistoryActivity), po prostu nie odpowiada juz zadnej ikonie w tym pasku.
    enum class Tab { START, TRANSACTIONS, MAGAZIN, REPORTS, SETTINGS }

    /** Для 3 оставшихся экранов-Activity (Magazyn/Raporty/Ustawienia) — "Start" ведёт
     * в MainActivity (единый фрагмент-хост), а не в бывший MineActivity. */
    fun attach(activity: AppCompatActivity, current: Tab) {
        bind(activity, R.id.nav_start, Tab.START, current, MainActivity::class.java)
        bind(activity, R.id.nav_magazin, Tab.MAGAZIN, current, MagazinActivity::class.java)
        bind(activity, R.id.nav_reports, Tab.REPORTS, current, ReportActivity::class.java)
        bind(activity, R.id.nav_settings, Tab.SETTINGS, current, SettingsActivity::class.java)
        attachAddButton(activity)
        attachAdBanner(activity)
    }

    /**
     * Для MainActivity (фрагмент-хост): "Start" переключает фрагмент на месте —
     * Activity, нав-бар и рекламный баннер НЕ пересоздаются. Остальные 3 вкладки
     * пока ещё отдельные Activity (следующие этапы миграции) — ведут себя как раньше.
     */
    fun attachHost(mainActivity: AppCompatActivity, current: Tab, onStartSelected: () -> Unit) {
        val startGroup = mainActivity.findViewById<View>(R.id.nav_start)
        if (startGroup != null) {
            applyVisual(mainActivity, startGroup, current == Tab.START)
            startGroup.setOnClickListener {
                if (current != Tab.START) onStartSelected()
            }
        }
        bind(mainActivity, R.id.nav_magazin, Tab.MAGAZIN, current, MagazinActivity::class.java)
        bind(mainActivity, R.id.nav_reports, Tab.REPORTS, current, ReportActivity::class.java)
        bind(mainActivity, R.id.nav_settings, Tab.SETTINGS, current, SettingsActivity::class.java)
        attachAddButton(mainActivity)
        attachAdBanner(mainActivity)
    }

    private fun attachAddButton(activity: AppCompatActivity) {
        activity.findViewById<View>(R.id.nav_add)?.setOnClickListener {
            activity.startActivity(Intent(activity, AddEntryActivity::class.java))
        }
    }

    /**
     * Единый рекламный баннер, зафиксированный над нижней навигацией. На MainActivity
     * (Start) он создаётся ОДИН РАЗ за всё время жизни Activity и никогда не
     * пересоздаётся при переключении вкладок фрагментов. На остальных 3 экранах-Activity
     * (Magazyn/Raporty/Ustawienia) он пока пересоздаётся при каждом переходе — это
     * уйдёт после того, как и они станут фрагментами внутри MainActivity.
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
