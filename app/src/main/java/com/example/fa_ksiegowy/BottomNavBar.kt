package com.example.fa_ksiegowy

import android.content.Intent
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Wires up the persistent bottom navigation bar included (via
 * @layout/bottom_nav_bar) at the bottom of the 4 main tab screens
 * (Start / Transakcje / Raporty / Ustawienia) plus the central "+" button.
 *
 * Call once, right after setContentView(), from each of those 4 activities:
 *     BottomNavBar.attach(this, BottomNavBar.Tab.START)
 */
object BottomNavBar {

    enum class Tab { START, TRANSACTIONS, REPORTS, SETTINGS }

    fun attach(activity: AppCompatActivity, current: Tab) {
        bind(activity, R.id.nav_start, Tab.START, current, MineActivity::class.java)
        bind(activity, R.id.nav_transactions, Tab.TRANSACTIONS, current, HistoryActivity::class.java)
        bind(activity, R.id.nav_reports, Tab.REPORTS, current, ReportActivity::class.java)
        bind(activity, R.id.nav_settings, Tab.SETTINGS, current, SettingsActivity::class.java)

        activity.findViewById<View>(R.id.nav_add)?.setOnClickListener {
            activity.startActivity(Intent(activity, AddEntryActivity::class.java))
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
        val icon = (group as? android.view.ViewGroup)?.getChildAt(0) as? ImageView
        val label = (group as? android.view.ViewGroup)?.getChildAt(1) as? TextView

        val active = tab == current
        val color = if (active) {
            androidx.core.content.ContextCompat.getColor(activity, R.color.accent_blue_light)
        } else {
            androidx.core.content.ContextCompat.getColor(activity, R.color.text_secondary)
        }
        icon?.setColorFilter(color)
        label?.setTextColor(color)

        group.setOnClickListener {
            if (!active) {
                activity.startActivity(Intent(activity, target))
                activity.finish()
            }
        }
    }
}
