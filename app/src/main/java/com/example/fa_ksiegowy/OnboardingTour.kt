package com.example.fa_ksiegowy

import android.content.Context
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import androidx.activity.OnBackPressedCallback
import kotlin.math.abs
import kotlin.math.max

/**
 * Обучающий тур при первом запуске: затемнение + подсветка элементов + карточка с
 * пояснением. Запускается из MainActivity ПОСЛЕ принятия условий (TermsActivity) и
 * согласий (UMP), то есть когда пользователь уже на главном экране.
 *
 * Шаги сами переключают вкладки (Start -> Magazyn -> Raporty -> Ustawienia -> Start),
 * прокручивают экран к нужному элементу и пропускают шаг, если элемента нет на экране
 * (например, карточка лимитов скрыта для выбранной формы деятельности).
 *
 * Все тексты — в strings.xml (tour_*), поэтому тур автоматически идёт на языке приложения
 * (en/pl/ru/uk). Прогресс и признак "пройдено" хранятся в SharedPreferences("settings").
 */
class OnboardingTour(private val activity: MainActivity) {

    private class Step(
        val targetId: Int?,
        val title: Int,
        val text: Int,
        val tab: BottomNavBar.Tab
    )

    private val steps = listOf(
        Step(null, R.string.tour_welcome_title, R.string.tour_welcome_text, BottomNavBar.Tab.START),
        Step(R.id.card_balance, R.string.tour_balance_title, R.string.tour_balance_text, BottomNavBar.Tab.START),
        Step(R.id.card_limits, R.string.tour_limits_title, R.string.tour_limits_text, BottomNavBar.Tab.START),
        Step(R.id.card_monthly_summary, R.string.tour_chart_title, R.string.tour_chart_text, BottomNavBar.Tab.START),
        Step(R.id.iv_notifications, R.string.tour_bell_title, R.string.tour_bell_text, BottomNavBar.Tab.START),
        Step(R.id.nav_add, R.string.tour_add_title, R.string.tour_add_text, BottomNavBar.Tab.START),
        Step(R.id.tv_view_all_entries, R.string.tour_history_title, R.string.tour_history_text, BottomNavBar.Tab.START),
        Step(R.id.nav_magazin, R.string.tour_magazin_title, R.string.tour_magazin_text, BottomNavBar.Tab.MAGAZIN),
        Step(R.id.donut_chart, R.string.tour_reports_title, R.string.tour_reports_text, BottomNavBar.Tab.REPORTS),
        Step(R.id.btn_menu_tax, R.string.tour_tax_title, R.string.tour_tax_text, BottomNavBar.Tab.SETTINGS),
        Step(R.id.btn_menu_backup, R.string.tour_backup_title, R.string.tour_backup_text, BottomNavBar.Tab.SETTINGS),
        Step(R.id.btn_menu_pro, R.string.tour_pro_title, R.string.tour_pro_text, BottomNavBar.Tab.SETTINGS),
        Step(R.id.btn_menu_language, R.string.tour_language_title, R.string.tour_language_text, BottomNavBar.Tab.SETTINGS),
        Step(null, R.string.tour_final_title, R.string.tour_final_text, BottomNavBar.Tab.START)
    )

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: TourOverlayView? = null
    private var backCallback: OnBackPressedCallback? = null
    private var index = 0
    /** true, пока идёт переход между шагами (смена вкладки/скролл) — кнопки в это время игнорируются. */
    private var busy = false

    val isRunning: Boolean get() = overlay != null

    fun start(fromBeginning: Boolean = false) {
        if (overlay != null) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return

        val ov = TourOverlayView(activity)
        ov.elevation = 64f * activity.resources.displayMetrics.density
        ov.alpha = 0f
        ov.listener = object : TourOverlayView.Listener {
            override fun onNext() { if (!busy) goTo(index + 1, +1) }
            override fun onBack() { if (!busy) goTo(index - 1, -1) }
            override fun onSkip() { if (!busy) finish() }
        }
        root.addView(ov, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        overlay = ov
        ov.animate().alpha(1f).setDuration(250).start()

        // Системная кнопка "Назад" во время тура = предыдущий шаг (на первом — выход из тура).
        val cb = object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (busy) return
                if (index <= 0) finish() else goTo(index - 1, -1)
            }
        }
        activity.onBackPressedDispatcher.addCallback(activity, cb)
        backCallback = cb

        index = if (fromBeginning) 0 else savedStep(activity).coerceIn(0, steps.size - 1)
        busy = true
        ov.post { goTo(index, +1) }
    }

    /** Убрать оверлей. animated = false — при уничтожении Activity. */
    fun dismiss(animated: Boolean = true) {
        handler.removeCallbacksAndMessages(null)
        backCallback?.remove()
        backCallback = null
        val ov = overlay ?: return
        overlay = null
        busy = false
        if (animated) {
            ov.animate().alpha(0f).setDuration(220).withEndAction {
                (ov.parent as? ViewGroup)?.removeView(ov)
            }.start()
        } else {
            ov.animate().cancel()
            (ov.parent as? ViewGroup)?.removeView(ov)
        }
    }

    // ------------------------------------------------------------------

    private fun goTo(i: Int, dir: Int) {
        val ov = overlay ?: return
        if (i >= steps.size) { finish(); return }
        if (i < 0) { goTo(0, +1); return }

        busy = true
        index = i
        saveStep(activity, i)
        val step = steps[i]

        // Показываем вкладку, к которой относится шаг (openTab сам ничего не делает, если она уже открыта).
        activity.openTab(step.tab)

        val targetId = step.targetId
        if (targetId == null) {
            handler.postDelayed({ if (overlay != null) render(step, null) }, 120)
            return
        }
        resolveTarget(targetId, 0) { view ->
            if (overlay == null) return@resolveTarget
            if (view == null) {
                // Элемента нет на экране — пропускаем шаг в текущем направлении.
                goTo(i + dir, dir)
            } else {
                scrollIntoView(view) { render(step, rectOf(view, ov)) }
            }
        }
    }

    private fun render(step: Step, rect: RectF?) {
        val ov = overlay ?: return
        ov.showStep(
            title = activity.getString(step.title),
            text = activity.getString(step.text),
            counter = activity.getString(R.string.tour_counter, index + 1, steps.size),
            skipLabel = activity.getString(R.string.tour_skip),
            backLabel = activity.getString(R.string.tour_back),
            nextLabel = activity.getString(
                if (index >= steps.size - 1) R.string.tour_done else R.string.tour_next),
            index = index,
            total = steps.size,
            showBack = index > 0,
            target = rect
        )
        busy = false
    }

    /** Ждём, пока целевой view появится и получит размер (вкладка ещё может создаваться). */
    private fun resolveTarget(id: Int, attempt: Int, cb: (View?) -> Unit) {
        val v = activity.findViewById<View>(id)
        if (v != null && v.isShown && v.width > 0 && v.height > 0) {
            cb(v)
            return
        }
        if (attempt >= 12) {
            cb(null)
            return
        }
        handler.postDelayed({ if (overlay != null) resolveTarget(id, attempt + 1, cb) }, 100)
    }

    /** Если элемент внутри ScrollView — плавно докручиваем так, чтобы он оказался по центру. */
    private fun scrollIntoView(v: View, done: () -> Unit) {
        var p = v.parent
        var sv: ScrollView? = null
        while (p is View) {
            if (p is ScrollView) { sv = p; break }
            p = p.parent
        }
        if (sv == null) { done(); return }

        val r = Rect()
        v.getDrawingRect(r)
        sv.offsetDescendantRectToMyCoords(v, r)
        val wanted = max(0, r.centerY() - sv.height / 2)
        val needsScroll = abs(wanted - sv.scrollY) > 4
        if (needsScroll) sv.smoothScrollTo(0, wanted)
        handler.postDelayed({ if (overlay != null) done() }, if (needsScroll) 450L else 40L)
    }

    private fun rectOf(view: View, ov: View): RectF {
        val a = IntArray(2)
        val b = IntArray(2)
        view.getLocationInWindow(a)
        ov.getLocationInWindow(b)
        val pad = 6f * activity.resources.displayMetrics.density
        val left = (a[0] - b[0]).toFloat() - pad
        val top = (a[1] - b[1]).toFloat() - pad
        val right = (a[0] - b[0] + view.width).toFloat() + pad
        val bottom = (a[1] - b[1] + view.height).toFloat() + pad
        return RectF(
            max(0f, left), max(0f, top),
            minOf(ov.width.toFloat(), right), minOf(ov.height.toFloat(), bottom)
        )
    }

    private fun finish() {
        markDone(activity)
        dismiss(true)
        activity.openTab(BottomNavBar.Tab.START)
    }

    // ------------------------------------------------------------------

    companion object {
        private const val PREFS = TermsActivity.PREFS_NAME
        private const val KEY_DONE = "onboarding_tour_done"
        private const val KEY_STEP = "onboarding_tour_step"

        /**
         * true  — тур увидят ВСЕ, у кого он ещё не пройден (в том числе после обновления
         *         приложения);
         * false — только новые установки; после обновления существующие пользователи
         *         тур автоматически не увидят (повторить можно из Настроек).
         */
        private const val SHOW_TO_UPDATED_INSTALLS = true

        fun isDone(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_DONE, false)

        fun markDone(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_DONE, true).remove(KEY_STEP).apply()
        }

        fun reset(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .remove(KEY_DONE).remove(KEY_STEP).apply()
        }

        private fun savedStep(context: Context): Int =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getInt(KEY_STEP, 0)

        private fun saveStep(context: Context, step: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putInt(KEY_STEP, step).apply()
        }

        /** Нужно ли автоматически показать тур прямо сейчас (по флагам; сама проверка
         *  "согласия приняты / нет блокировки" делается в MainActivity). */
        fun shouldAutoStart(context: Context): Boolean {
            if (isDone(context)) return false
            if (!SHOW_TO_UPDATED_INSTALLS) {
                try {
                    val pi = context.packageManager.getPackageInfo(context.packageName, 0)
                    if (pi.lastUpdateTime > pi.firstInstallTime + 60_000L) {
                        markDone(context)
                        return false
                    }
                } catch (e: Exception) {
                    // не смогли определить — показываем тур как обычно
                }
            }
            return true
        }
    }
}
