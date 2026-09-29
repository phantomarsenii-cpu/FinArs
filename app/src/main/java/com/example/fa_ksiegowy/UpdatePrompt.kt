package com.example.fa_ksiegowy

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability

/**
 * Плашка "Доступно обновление" снизу главного экрана.
 *
 * Как работает:
 *  - раз за запуск (и не чаще, чем разрешает "Позже") спрашивает у Google Play, есть ли более
 *    новая версия приложения (Play Core, AppUpdateManager);
 *  - если есть — плавно выезжает карточка с кнопками "Обновить" / "Позже";
 *  - "Обновить" открывает страницу FinArs в Google Play, "Позже" прячет плашку на несколько дней.
 *
 * Работает только для установок из Google Play (у APK из Termux/adb Play не знает о версии).
 * Не показывается поверх обучающего тура и пока тур не пройден.
 */
class UpdatePrompt(private val activity: MainActivity) {

    private val handler = Handler(Looper.getMainLooper())
    private var card: View? = null
    private var checking = false

    fun schedule() {
        if (checkedThisProcess || checking || card != null) return
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ tryCheck() }, 2500)
    }

    fun dismiss(animated: Boolean = false) {
        handler.removeCallbacksAndMessages(null)
        val c = card ?: return
        card = null
        if (animated) {
            c.animate().alpha(0f).translationY(c.height * 0.4f).setDuration(220)
                .withEndAction { (c.parent as? ViewGroup)?.removeView(c) }.start()
        } else {
            c.animate().cancel()
            (c.parent as? ViewGroup)?.removeView(c)
        }
    }

    private fun canShowNow(): Boolean =
        !activity.isFinishing && !activity.isDestroyed && activity.hasWindowFocus() &&
            TermsActivity.isAccepted(activity) && !AppLockState.isLocked &&
            OnboardingTour.isDone(activity) && !isSnoozed(activity)

    private fun tryCheck() {
        if (!canShowNow()) return   // повторим при следующем onResume
        if (StoreDetector.detect(activity) != StoreSource.GOOGLE_PLAY) {
            checkedThisProcess = true
            return
        }
        checking = true
        try {
            AppUpdateManagerFactory.create(activity.applicationContext)
                .appUpdateInfo
                .addOnSuccessListener { info ->
                    checking = false
                    checkedThisProcess = true
                    if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE && canShowNow()) {
                        show()
                    }
                }
                .addOnFailureListener {
                    checking = false
                    checkedThisProcess = true
                }
        } catch (e: Exception) {
            checking = false
            checkedThisProcess = true
        }
    }

    // ------------------------------------------------------------------ UI

    private fun show() {
        if (card != null) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val density = activity.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val c = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = ContextCompat.getDrawable(activity, R.drawable.card_bg)
            setPadding(dp(18), dp(16), dp(18), dp(10))
            elevation = 24f * density
        }
        val title = TextView(activity).apply {
            text = activity.getString(R.string.update_available_title)
            setTextColor(ContextCompat.getColor(activity, R.color.text_primary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTypeface(typeface, Typeface.BOLD)
        }
        val bodyView = TextView(activity).apply {
            text = activity.getString(R.string.update_available_text)
            setTextColor(ContextCompat.getColor(activity, R.color.text_secondary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setPadding(0, dp(6), 0, 0)
        }
        val later = TextView(activity).apply {
            text = activity.getString(R.string.update_later)
            gravity = Gravity.CENTER
            setTextColor(ContextCompat.getColor(activity, R.color.text_secondary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(dp(14), 0, dp(14), 0)
            minHeight = dp(44)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                snooze(activity)
                dismiss(true)
            }
        }
        val update = TextView(activity).apply {
            text = activity.getString(R.string.update_now)
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(24), 0, dp(24), 0)
            minHeight = dp(44)
            background = ContextCompat.getDrawable(activity, R.drawable.btn_pill_primary)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                openStore()
                snooze(activity)   // вернулся из Play без обновления — не донимаем сразу же
                dismiss(true)
            }
        }
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            addView(later)
            addView(update, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginStart = dp(6) })
        }
        c.addView(title)
        c.addView(bodyView)
        c.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(10) })

        // Над плавающей нижней навигацией (если она уже отрисована), иначе — с запасом снизу.
        var bottom = dp(110)
        val nav = root.findViewById<View>(R.id.nav_start)
        if (nav != null && nav.height > 0 && root.height > 0) {
            val a = IntArray(2); val b = IntArray(2)
            nav.getLocationInWindow(a); root.getLocationInWindow(b)
            bottom = (root.height - (a[1] - b[1])) + dp(18)
        }
        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM
            marginStart = dp(16); marginEnd = dp(16); bottomMargin = bottom
        }
        c.alpha = 0f
        root.addView(c, lp)
        card = c
        c.post {
            c.translationY = c.height * 0.5f
            c.animate().alpha(1f).translationY(0f).setDuration(320)
                .setInterpolator(PathInterpolator(0.4f, 0f, 0.2f, 1f)).start()
        }
    }

    private fun openStore() {
        val pkg = activity.packageName
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                .apply { setPackage("com.android.vending") })
        } catch (e: ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$pkg")))
            } catch (e2: Exception) {
                // нет ни Play, ни браузера — молча ничего не делаем
            }
        }
    }

    companion object {
        private const val PREFS = "settings"
        private const val KEY_SNOOZE_UNTIL = "update_prompt_snooze_until"
        private const val SNOOZE_MS = 3L * 24 * 60 * 60 * 1000

        @Volatile private var checkedThisProcess = false

        private fun isSnoozed(context: Context): Boolean =
            System.currentTimeMillis() <
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_SNOOZE_UNTIL, 0L)

        private fun snooze(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_SNOOZE_UNTIL, System.currentTimeMillis() + SNOOZE_MS).apply()
        }
    }
}
