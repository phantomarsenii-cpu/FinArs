#!/usr/bin/env bash
# Update 70: обучающий тур (onboarding / spotlight-tutorial) при первом запуске.
#  - затемнение экрана + подсветка нужного элемента + карточка "Пропустить / Назад / Далее" со счётчиком шагов;
#  - 14 шагов: приветствие, баланс, лимиты, график, уведомления, кнопка "+", история, Склад, Отчёты,
#    Налоги, Резервная копия, Pro, Язык, финал (шаги сами переключают вкладки и прокручивают экран);
#  - запускается на главном экране ПОСЛЕ принятия условий (TermsActivity) и согласий (UMP), один раз;
#  - тексты на 4 языках (en / pl / ru / uk) в strings.xml (ключи tour_*);
#  - в Настройках новый пункт "Обучение / Samouczek / Tutorial" — повторный запуск тура.
# Запускать из КОРНЯ репозитория.
set -euo pipefail

M=app/src/main
J=$M/java/com/example/fa_ksiegowy
for f in "$J/MainActivity.kt" "$J/SettingsFragment.kt" "$M/res/layout/fragment_mine.xml" "$M/res/layout/fragment_settings.xml"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

BK=".update70_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
for f in "$J/MainActivity.kt" "$J/SettingsFragment.kt" \
         "$M/res/layout/fragment_mine.xml" "$M/res/layout/fragment_settings.xml" \
         "$M/res/values/strings.xml" "$M/res/values-pl/strings.xml" \
         "$M/res/values-ru/strings.xml" "$M/res/values-uk/strings.xml"; do
  cp "$f" "$BK/$(echo "$f" | tr '/' '_')"
done

# ---------------------------------------------------------------- новые Kotlin-файлы
cat > "$J/TourOverlayView.kt" <<'KT_OVERLAY'
package com.example.fa_ksiegowy

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.max
import kotlin.math.min

/**
 * Полноэкранный оверлей обучающего тура: затемнение + "дырка" (spotlight) вокруг
 * нужного элемента + карточка с заголовком, текстом, счётчиком шагов и кнопками
 * "Пропустить / Назад / Далее". Сам ничего не знает о шагах — рисует то, что ему
 * передал OnboardingTour через showStep().
 */
class TourOverlayView(context: Context) : FrameLayout(context) {

    interface Listener {
        fun onNext()
        fun onBack()
        fun onSkip()
    }

    var listener: Listener? = null

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density
    private fun dpi(v: Int) = (v * density).toInt()

    // ---------- рисование затемнения и подсветки ----------
    private val dimPaint = Paint().apply { color = Color.argb(0xD2, 0x04, 0x07, 0x14) }
    private val holePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
        color = ContextCompat.getColor(context, R.color.accent_cyan)
    }
    private val hole = RectF()
    private var hasHole = false
    private var holeRadius = dp(16f)
    private var pulse = 0f
    private var holeAnimator: ValueAnimator? = null
    private var pulseAnimator: ValueAnimator? = null

    // ---------- карточка ----------
    private val card = LinearLayout(context)
    private val titleView = TextView(context)
    private val counterView = TextView(context)
    private val textView = TextView(context)
    private val progressView = ProgressLine(context)
    private val skipView = TextView(context)
    private val backView = TextView(context)
    private val nextView = TextView(context)

    init {
        setWillNotDraw(false)
        // Слой нужен, чтобы PorterDuff.CLEAR "пробил" затемнение, а не залил дырку чёрным.
        setLayerType(LAYER_TYPE_HARDWARE, null)
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES

        buildCard()
        val lp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.START
            marginStart = dpi(CARD_MARGIN_DP)
            marginEnd = dpi(CARD_MARGIN_DP)
        }
        addView(card, lp)
    }

    private fun buildCard() {
        card.orientation = LinearLayout.VERTICAL
        card.background = ContextCompat.getDrawable(context, R.drawable.card_bg)
        card.setPadding(dpi(20), dpi(18), dpi(20), dpi(14))
        card.elevation = dp(12f)

        // заголовок + счётчик
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        titleView.apply {
            setTextColor(ContextCompat.getColor(context, R.color.text_primary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            setTypeface(typeface, Typeface.BOLD)
        }
        counterView.apply {
            setTextColor(ContextCompat.getColor(context, R.color.text_hint))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dpi(12), 0, 0, 0)
        }
        head.addView(titleView, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        head.addView(counterView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        card.addView(head)

        // тонкая полоса прогресса
        card.addView(progressView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dpi(4)).apply {
            topMargin = dpi(10)
            bottomMargin = dpi(12)
        })

        textView.apply {
            setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setLineSpacing(0f, 1.15f)
        }
        card.addView(textView)

        // кнопки
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        styleTextButton(skipView, R.color.text_secondary)
        styleTextButton(backView, R.color.text_primary)
        nextView.apply {
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dpi(24), 0, dpi(24), 0)
            minHeight = dpi(44)
            background = ContextCompat.getDrawable(context, R.drawable.btn_pill_primary)
            foreground = ripple(dp(18f))
            isClickable = true
            isFocusable = true
            setOnClickListener { listener?.onNext() }
        }
        skipView.setOnClickListener { listener?.onSkip() }
        backView.setOnClickListener { listener?.onBack() }

        row.addView(skipView)
        row.addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
        row.addView(backView)
        row.addView(nextView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            marginStart = dpi(6)
        })
        card.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dpi(14)
        })
    }

    private fun styleTextButton(tv: TextView, colorRes: Int) {
        tv.apply {
            gravity = Gravity.CENTER
            setTextColor(ContextCompat.getColor(context, colorRes))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(dpi(12), 0, dpi(12), 0)
            minHeight = dpi(44)
            foreground = ripple(dp(12f))
            isClickable = true
            isFocusable = true
        }
    }

    private fun ripple(radius: Float): RippleDrawable {
        val mask = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(Color.WHITE)
        }
        return RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), null, mask)
    }

    // ---------- публичное API ----------

    /**
     * @param target прямоугольник подсвечиваемого элемента в координатах ЭТОГО оверлея,
     *               либо null — тогда экран просто затемнён, а карточка по центру.
     */
    fun showStep(
        title: String,
        text: String,
        counter: String,
        skipLabel: String,
        backLabel: String,
        nextLabel: String,
        index: Int,
        total: Int,
        showBack: Boolean,
        target: RectF?
    ) {
        titleView.text = title
        textView.text = text
        counterView.text = counter
        skipView.text = skipLabel
        backView.text = backLabel
        nextView.text = nextLabel
        backView.visibility = if (showBack) View.VISIBLE else View.GONE
        // на последнем шаге "Пропустить" не нужен
        skipView.visibility = if (index >= total - 1) View.INVISIBLE else View.VISIBLE
        progressView.setProgress((index + 1).toFloat() / total.toFloat())

        animateHoleTo(target)
        placeCard(target)
    }

    private fun placeCard(target: RectF?) {
        val w = width
        val h = height
        if (w == 0 || h == 0) return
        val cardW = w - 2 * dpi(CARD_MARGIN_DP)
        card.measure(
            MeasureSpec.makeMeasureSpec(cardW, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val cardH = card.measuredHeight

        val insets = ViewCompat.getRootWindowInsets(this)
            ?.getInsets(WindowInsetsCompat.Type.systemBars())
        val topInset = insets?.top ?: 0
        val botInset = insets?.bottom ?: 0
        val gap = dpi(16)
        val minTop = topInset + dpi(12)
        val maxTop = max(minTop, h - botInset - dpi(12) - cardH)

        val top: Int = if (target == null) {
            (h - cardH) / 2
        } else {
            val spaceBelow = h - botInset - target.bottom
            val spaceAbove = target.top - topInset
            if (spaceBelow >= cardH + gap || spaceBelow >= spaceAbove) {
                (target.bottom + gap).toInt()
            } else {
                (target.top - gap - cardH).toInt()
            }
        }.coerceIn(minTop, maxTop)

        (card.layoutParams as LayoutParams).topMargin = top
        card.requestLayout()

        card.animate().cancel()
        card.alpha = 0f
        card.translationY = dp(14f)
        card.animate().alpha(1f).translationY(0f).setDuration(240)
            .setInterpolator(DecelerateInterpolator()).start()
    }

    // ---------- анимация подсветки ----------

    private fun animateHoleTo(target: RectF?) {
        holeAnimator?.cancel()
        if (target == null) {
            if (!hasHole) { invalidate(); return }
            val cx = hole.centerX()
            val cy = hole.centerY()
            runHoleAnimation(RectF(hole), RectF(cx, cy, cx, cy)) { hasHole = false; invalidate() }
        } else {
            val start = if (hasHole) RectF(hole)
            else RectF(target.centerX(), target.centerY(), target.centerX(), target.centerY())
            hasHole = true
            // Круглые/квадратные цели (кнопка "+") — подсвечиваем кругом, остальные — скруглённым прямоугольником.
            val half = min(target.width(), target.height()) / 2f
            val squarish = kotlin.math.abs(target.width() - target.height()) < dp(8f) && target.width() < dp(90f)
            holeRadius = if (squarish) half else min(dp(16f), half)
            runHoleAnimation(start, RectF(target), null)
        }
    }

    private fun runHoleAnimation(from: RectF, to: RectF, onEnd: (() -> Unit)?) {
        hole.set(from)
        holeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 300
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                hole.set(
                    from.left + (to.left - from.left) * t,
                    from.top + (to.top - from.top) * t,
                    from.right + (to.right - from.right) * t,
                    from.bottom + (to.bottom - from.bottom) * t
                )
                invalidate()
            }
            if (onEnd != null) {
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    private var cancelled = false
                    override fun onAnimationCancel(animation: android.animation.Animator) { cancelled = true }
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        if (!cancelled) onEnd()
                    }
                })
            }
            start()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dimPaint)
        if (hasHole) {
            canvas.drawRoundRect(hole, holeRadius, holeRadius, holePaint)
            ringPaint.alpha = (140 + 115 * pulse).toInt()
            canvas.drawRoundRect(hole, holeRadius, holeRadius, ringPaint)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 900
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener {
                pulse = it.animatedValue as Float
                if (hasHole) invalidate()
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        pulseAnimator?.cancel()
        holeAnimator?.cancel()
        card.animate().cancel()
        super.onDetachedFromWindow()
    }

    // Оверлей полностью перехватывает касания — приложение под ним во время тура не кликается.
    override fun onTouchEvent(event: MotionEvent): Boolean = true

    /** Тонкая полоса прогресса тура. */
    private class ProgressLine(context: Context) : View(context) {
        private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.card_border)
        }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.accent_cyan)
        }
        private var fraction = 0f
        private var animator: ValueAnimator? = null

        fun setProgress(target: Float) {
            animator?.cancel()
            animator = ValueAnimator.ofFloat(fraction, target).apply {
                duration = 300
                addUpdateListener { fraction = it.animatedValue as Float; invalidate() }
                start()
            }
        }

        override fun onDraw(canvas: Canvas) {
            val r = height / 2f
            canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), r, r, track)
            canvas.drawRoundRect(0f, 0f, width * fraction, height.toFloat(), r, r, fill)
        }

        override fun onDetachedFromWindow() {
            animator?.cancel()
            super.onDetachedFromWindow()
        }
    }

    companion object {
        private const val CARD_MARGIN_DP = 16
    }
}
KT_OVERLAY
echo "создан: $J/TourOverlayView.kt"

cat > "$J/OnboardingTour.kt" <<'KT_TOUR'
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
KT_TOUR
echo "создан: $J/OnboardingTour.kt"

# ---------------------------------------------------------------- правки существующих файлов
python3 - <<'PY'
import re
M = "app/src/main"
J = M + "/java/com/example/fa_ksiegowy"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден фрагмент (" + what + ")"
    return s.replace(old, new)

# ---- 1) fragment_mine.xml: id для карточек "Bilans" и "Podsumowanie miesiaca" ----
p = M + "/res/layout/fragment_mine.xml"
s = read(p)
def add_id(s, marker, new_id):
    if "@+id/" + new_id in s:
        return s
    pat = re.compile(r"(" + re.escape(marker) + r"\s*-->\s*<LinearLayout)(\s)")
    assert len(pat.findall(s)) == 1, "не найден маркер " + marker
    return pat.sub(lambda m: m.group(1) + '\n            android:id="@+id/' + new_id + '"' + m.group(2), s, count=1)
s = add_id(s, "<!-- ===================== Karta Bilans =====================", "card_balance")
s = add_id(s, "<!-- ===================== Karta Podsumowanie miesiaca =====================", "card_monthly_summary")
write(p, s)

# ---- 2) fragment_settings.xml: пункт "Обучение" (после "Язык") ----
p = M + "/res/layout/fragment_settings.xml"
s = read(p)
if "btn_menu_tutorial" not in s:
    row = (
        '        <!-- Samouczek (powtorzenie wycieczki po aplikacji) -->\n'
        '        <LinearLayout android:id="@+id/btn_menu_tutorial" style="@style/SettingsRow">\n'
        '            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">\n'
        '                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_info"/>\n'
        '            </FrameLayout>\n'
        '            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_tutorial"/>\n'
        '            <ImageView style="@style/SettingsRowChevron"/>\n'
        '        </LinearLayout>\n\n'
    )
    s = rep(s, "        <!-- Wersja Pro -->\n", row + "        <!-- Wersja Pro -->\n", "settings: Wersja Pro marker")
    write(p, s)
else:
    print("fragment_settings: уже применено")

# ---- 3) SettingsFragment.kt: клик по пункту ----
p = J + "/SettingsFragment.kt"
s = read(p)
if "btn_menu_tutorial" not in s:
    old = "        requireView().findViewById<View>(R.id.btn_menu_about).setOnClickListener {\n"
    new = (
        "        // Update 70: повторный запуск обучающего тура.\n"
        "        requireView().findViewById<View>(R.id.btn_menu_tutorial).setOnClickListener {\n"
        "            (activity as? MainActivity)?.startTutorial()\n"
        "        }\n"
    ) + old
    s = rep(s, old, new, "SettingsFragment about listener")
    write(p, s)
else:
    print("SettingsFragment: уже применено")

# ---- 4) MainActivity.kt: автозапуск тура + startTutorial() ----
p = J + "/MainActivity.kt"
s = read(p)
if "OnboardingTour" not in s:
    s = rep(s, "import android.os.Bundle\n",
            "import android.os.Bundle\nimport android.os.Handler\nimport android.os.Looper\n", "imports")
    code = """    // ===================== Update 70: обучающий тур =====================
    private var tour: OnboardingTour? = null
    private val tourHandler = Handler(Looper.getMainLooper())

    override fun onResume() {
        super.onResume()
        scheduleTourIfNeeded()
    }

    // Пока поверх открыта форма согласия (UMP) или другой диалог, окно теряет фокус —
    // тур стартует, как только фокус вернулся.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) scheduleTourIfNeeded()
    }

    override fun onDestroy() {
        tourHandler.removeCallbacksAndMessages(null)
        tour?.dismiss(false)
        tour = null
        super.onDestroy()
    }

    private fun canShowTourNow(): Boolean =
        !isFinishing && !isDestroyed && hasWindowFocus() &&
            TermsActivity.isAccepted(this) && !AppLockState.isLocked

    private fun scheduleTourIfNeeded() {
        if (tour?.isRunning == true) return
        if (!TermsActivity.isAccepted(this) || AppLockState.isLocked) return
        if (!OnboardingTour.shouldAutoStart(this)) return
        tourHandler.removeCallbacksAndMessages(null)
        tourHandler.postDelayed({
            if (!canShowTourNow()) return@postDelayed
            if (tour?.isRunning == true) return@postDelayed
            val t = tour ?: OnboardingTour(this).also { tour = it }
            t.start()
        }, 900)
    }

    /** Повторный запуск тура из Настроек. */
    fun startTutorial() {
        tourHandler.removeCallbacksAndMessages(null)
        tour?.dismiss(false)
        OnboardingTour.reset(this)
        val t = OnboardingTour(this)
        tour = t
        t.start(fromBeginning = true)
    }

"""
    s = rep(s, "    companion object {\n        private const val KEY_CURRENT_TAB",
            code + "    companion object {\n        private const val KEY_CURRENT_TAB", "MainActivity companion")
    write(p, s)
else:
    print("MainActivity: уже применено")

# ---- 5) strings.xml (en / pl / ru / uk) ----
STR = {
    'values': '\n    <!-- ===== Update 70: обучающий тур (onboarding) ===== -->\n    <string name="tour_skip">Skip</string>\n    <string name="tour_back">Back</string>\n    <string name="tour_next">Next</string>\n    <string name="tour_done">Got it</string>\n    <string name="tour_counter">%1$d / %2$d</string>\n    <string name="settings_menu_tutorial">Tutorial</string>\n    <string name="tour_welcome_title">Welcome to FinArs</string>\n    <string name="tour_welcome_text">A short tour will show you where everything is and how to keep your records in order. It takes about a minute. You can skip it at any time and replay it later in Settings.</string>\n    <string name="tour_balance_title">Your balance</string>\n    <string name="tour_balance_text">Income, expenses and estimated tax at a glance. Everything updates instantly after each entry.</string>\n    <string name="tour_limits_title">Limits and thresholds</string>\n    <string name="tour_limits_text">FinArs tracks your monthly and yearly limits and warns you before you get close to them. Tap the card for details, or “Edit” to change your business type.</string>\n    <string name="tour_chart_title">Income and expenses</string>\n    <string name="tour_chart_text">Two lines show how your income and expenses change over time, so trends are easy to spot.</string>\n    <string name="tour_bell_title">Notifications</string>\n    <string name="tour_bell_text">Reminders about limits, tax advance payments, low stock and unpaid invoices appear here.</string>\n    <string name="tour_add_title">Add an entry</string>\n    <string name="tour_add_text">Tap + to record income or an expense: amount, date, comment, payment method and a photo of the receipt.</string>\n    <string name="tour_history_title">All transactions</string>\n    <string name="tour_history_text">Your latest entries are listed here. Open the full history to search and filter entries by date.</string>\n    <string name="tour_magazin_title">Warehouse</string>\n    <string name="tour_magazin_text">Manage products and stock: add items by hand or with the barcode scanner, run an inventory count and get low-stock alerts.</string>\n    <string name="tour_reports_title">Reports</string>\n    <string name="tour_reports_text">Pick a period to see how income, expenses and tax are split. You can also export a report or the sales register (Ewidencja) as a PDF.</string>\n    <string name="tour_tax_title">Tax settings</string>\n    <string name="tour_tax_text">Set your business type, rates and other income first. FinArs uses this to calculate your tax and limits correctly.</string>\n    <string name="tour_backup_title">Backup</string>\n    <string name="tour_backup_text">Save all your data to a file, including receipt photos, and restore it after losing your phone or reinstalling. Do it regularly.</string>\n    <string name="tour_pro_title">FinArs Pro</string>\n    <string name="tour_pro_text">Unlock extra features such as invoices and backup, and remove ads.</string>\n    <string name="tour_language_title">Language</string>\n    <string name="tour_language_text">Switch the app language at any time: English, Polski, Русский or Українська.</string>\n    <string name="tour_final_title">You’re all set!</string>\n    <string name="tour_final_text">Start by adding your first entry with the + button. You can replay this tutorial any time in Settings.</string>\n',
    'values-pl': '\n    <!-- ===== Update 70: обучающий тур (onboarding) ===== -->\n    <string name="tour_skip">Pomiń</string>\n    <string name="tour_back">Wstecz</string>\n    <string name="tour_next">Dalej</string>\n    <string name="tour_done">Zaczynamy</string>\n    <string name="tour_counter">%1$d / %2$d</string>\n    <string name="settings_menu_tutorial">Samouczek</string>\n    <string name="tour_welcome_title">Witaj w FinArs</string>\n    <string name="tour_welcome_text">Krótki przewodnik pokaże, gdzie co jest i jak prowadzić ewidencję. Zajmie około minuty. Możesz go pominąć w każdej chwili i powtórzyć później w Ustawieniach.</string>\n    <string name="tour_balance_title">Twoje saldo</string>\n    <string name="tour_balance_text">Przychody, wydatki i szacowany podatek w jednym miejscu. Wszystko odświeża się od razu po dodaniu wpisu.</string>\n    <string name="tour_limits_title">Limity i progi</string>\n    <string name="tour_limits_text">FinArs pilnuje Twoich miesięcznych i rocznych limitów i ostrzega, zanim się do nich zbliżysz. Dotknij karty, aby zobaczyć szczegóły, lub „Edytuj”, aby zmienić formę działalności.</string>\n    <string name="tour_chart_title">Przychody i wydatki</string>\n    <string name="tour_chart_text">Dwie linie pokazują, jak zmieniają się Twoje przychody i wydatki w czasie — trendy widać od razu.</string>\n    <string name="tour_bell_title">Powiadomienia</string>\n    <string name="tour_bell_text">Tutaj pojawiają się przypomnienia o limitach, zaliczkach na podatek, niskim stanie magazynu i nieopłaconych fakturach.</string>\n    <string name="tour_add_title">Dodaj wpis</string>\n    <string name="tour_add_text">Dotknij +, aby zapisać przychód lub wydatek: kwotę, datę, komentarz, metodę płatności i zdjęcie paragonu.</string>\n    <string name="tour_history_title">Wszystkie transakcje</string>\n    <string name="tour_history_text">Tu widać ostatnie wpisy. Pełna historia pozwala wyszukiwać i filtrować wpisy według daty.</string>\n    <string name="tour_magazin_title">Magazyn</string>\n    <string name="tour_magazin_text">Zarządzaj produktami i stanami: dodawaj towary ręcznie lub skanerem kodów kreskowych, rób inwentaryzację i otrzymuj alerty o niskim stanie.</string>\n    <string name="tour_reports_title">Raporty</string>\n    <string name="tour_reports_text">Wybierz okres, aby zobaczyć podział przychodów, wydatków i podatku. Możesz też wyeksportować raport lub ewidencję sprzedaży do PDF.</string>\n    <string name="tour_tax_title">Ustawienia podatkowe</string>\n    <string name="tour_tax_text">Na początku ustaw formę działalności, stawki i inne dochody. Na tej podstawie FinArs poprawnie liczy podatek i limity.</string>\n    <string name="tour_backup_title">Kopia zapasowa</string>\n    <string name="tour_backup_text">Zapisz wszystkie dane do pliku, także zdjęcia paragonów, i przywróć je po utracie telefonu lub reinstalacji. Rób to regularnie.</string>\n    <string name="tour_pro_title">FinArs Pro</string>\n    <string name="tour_pro_text">Odblokuj dodatkowe funkcje, takie jak faktury i kopia zapasowa, oraz usuń reklamy.</string>\n    <string name="tour_language_title">Język</string>\n    <string name="tour_language_text">Zmieniaj język aplikacji w dowolnej chwili: English, Polski, Русский lub Українська.</string>\n    <string name="tour_final_title">Wszystko gotowe!</string>\n    <string name="tour_final_text">Zacznij od dodania pierwszego wpisu przyciskiem +. Ten samouczek możesz powtórzyć w Ustawieniach.</string>\n',
    'values-ru': '\n    <!-- ===== Update 70: обучающий тур (onboarding) ===== -->\n    <string name="tour_skip">Пропустить</string>\n    <string name="tour_back">Назад</string>\n    <string name="tour_next">Далее</string>\n    <string name="tour_done">Начать</string>\n    <string name="tour_counter">%1$d / %2$d</string>\n    <string name="settings_menu_tutorial">Обучение</string>\n    <string name="tour_welcome_title">Добро пожаловать в FinArs</string>\n    <string name="tour_welcome_text">Короткое обучение покажет, где что находится и как вести учёт. Это займёт около минуты. Его можно пропустить в любой момент и пройти снова в Настройках.</string>\n    <string name="tour_balance_title">Ваш баланс</string>\n    <string name="tour_balance_text">Доходы, расходы и примерный налог — всё в одном месте. Данные обновляются сразу после каждой записи.</string>\n    <string name="tour_limits_title">Лимиты и пороги</string>\n    <string name="tour_limits_text">FinArs следит за месячными и годовыми лимитами и предупреждает, прежде чем вы к ним приблизитесь. Нажмите на карточку, чтобы увидеть подробности, или «Изменить», чтобы поменять форму деятельности.</string>\n    <string name="tour_chart_title">Доходы и расходы</string>\n    <string name="tour_chart_text">Две линии показывают, как меняются ваши доходы и расходы со временем, — тренды видны сразу.</string>\n    <string name="tour_bell_title">Уведомления</string>\n    <string name="tour_bell_text">Здесь появляются напоминания о лимитах, авансовых платежах по налогу, низких остатках на складе и неоплаченных счетах.</string>\n    <string name="tour_add_title">Добавить запись</string>\n    <string name="tour_add_text">Нажмите +, чтобы записать доход или расход: сумму, дату, комментарий, способ оплаты и фото чека.</string>\n    <string name="tour_history_title">Все операции</string>\n    <string name="tour_history_text">Здесь видны последние записи. В полной истории можно искать и фильтровать записи по дате.</string>\n    <string name="tour_magazin_title">Склад</string>\n    <string name="tour_magazin_text">Управляйте товарами и остатками: добавляйте позиции вручную или сканером штрихкодов, проводите инвентаризацию и получайте уведомления о низком остатке.</string>\n    <string name="tour_reports_title">Отчёты</string>\n    <string name="tour_reports_text">Выберите период, чтобы увидеть распределение доходов, расходов и налога. Отчёт или книгу продаж (Ewidencja) можно выгрузить в PDF.</string>\n    <string name="tour_tax_title">Налоговые настройки</string>\n    <string name="tour_tax_text">Сначала укажите форму деятельности, ставки и прочие доходы. На этом основании FinArs правильно считает налог и лимиты.</string>\n    <string name="tour_backup_title">Резервная копия</string>\n    <string name="tour_backup_text">Сохраните все данные в файл, включая фото чеков, и восстановите их при потере телефона или переустановке. Делайте это регулярно.</string>\n    <string name="tour_pro_title">FinArs Pro</string>\n    <string name="tour_pro_text">Откройте дополнительные функции, такие как счета и резервное копирование, и уберите рекламу.</string>\n    <string name="tour_language_title">Язык</string>\n    <string name="tour_language_text">Язык приложения можно сменить в любой момент: English, Polski, Русский или Українська.</string>\n    <string name="tour_final_title">Всё готово!</string>\n    <string name="tour_final_text">Начните с первой записи — кнопка +. Это обучение можно пройти снова в Настройках.</string>\n',
    'values-uk': '\n    <!-- ===== Update 70: обучающий тур (onboarding) ===== -->\n    <string name="tour_skip">Пропустити</string>\n    <string name="tour_back">Назад</string>\n    <string name="tour_next">Далі</string>\n    <string name="tour_done">Почати</string>\n    <string name="tour_counter">%1$d / %2$d</string>\n    <string name="settings_menu_tutorial">Навчання</string>\n    <string name="tour_welcome_title">Ласкаво просимо до FinArs</string>\n    <string name="tour_welcome_text">Коротке навчання покаже, де що знаходиться і як вести облік. Це займе близько хвилини. Його можна пропустити будь-коли й пройти знову в Налаштуваннях.</string>\n    <string name="tour_balance_title">Ваш баланс</string>\n    <string name="tour_balance_text">Доходи, витрати та орієнтовний податок — усе в одному місці. Дані оновлюються одразу після кожного запису.</string>\n    <string name="tour_limits_title">Ліміти та пороги</string>\n    <string name="tour_limits_text">FinArs стежить за місячними й річними лімітами та попереджає, поки ви до них не наблизилися. Натисніть на картку, щоб побачити подробиці, або «Редагувати», щоб змінити форму діяльності.</string>\n    <string name="tour_chart_title">Доходи та витрати</string>\n    <string name="tour_chart_text">Дві лінії показують, як змінюються ваші доходи й витрати з часом, — тенденції видно одразу.</string>\n    <string name="tour_bell_title">Сповіщення</string>\n    <string name="tour_bell_text">Тут з’являються нагадування про ліміти, авансові платежі з податку, низькі залишки на складі та неоплачені рахунки.</string>\n    <string name="tour_add_title">Додати запис</string>\n    <string name="tour_add_text">Натисніть +, щоб записати дохід або витрату: суму, дату, коментар, спосіб оплати та фото чека.</string>\n    <string name="tour_history_title">Усі операції</string>\n    <string name="tour_history_text">Тут видно останні записи. У повній історії можна шукати й фільтрувати записи за датою.</string>\n    <string name="tour_magazin_title">Склад</string>\n    <string name="tour_magazin_text">Керуйте товарами та залишками: додавайте позиції вручну або сканером штрихкодів, проводьте інвентаризацію й отримуйте сповіщення про низький залишок.</string>\n    <string name="tour_reports_title">Звіти</string>\n    <string name="tour_reports_text">Оберіть період, щоб побачити розподіл доходів, витрат і податку. Звіт або книгу продажів (Ewidencja) можна вивантажити в PDF.</string>\n    <string name="tour_tax_title">Податкові налаштування</string>\n    <string name="tour_tax_text">Спочатку вкажіть форму діяльності, ставки та інші доходи. На цій основі FinArs правильно рахує податок і ліміти.</string>\n    <string name="tour_backup_title">Резервна копія</string>\n    <string name="tour_backup_text">Збережіть усі дані у файл, зокрема фото чеків, і відновіть їх після втрати телефона чи перевстановлення. Робіть це регулярно.</string>\n    <string name="tour_pro_title">FinArs Pro</string>\n    <string name="tour_pro_text">Відкрийте додаткові функції, як-от рахунки та резервне копіювання, і приберіть рекламу.</string>\n    <string name="tour_language_title">Мова</string>\n    <string name="tour_language_text">Мову застосунку можна змінити будь-коли: English, Polski, Русский або Українська.</string>\n    <string name="tour_final_title">Усе готово!</string>\n    <string name="tour_final_text">Почніть із першого запису — кнопка +. Це навчання можна пройти знову в Налаштуваннях.</string>\n',
}

for d, blk in STR.items():
    p = M + "/res/" + d + "/strings.xml"
    s = read(p)
    if "tour_welcome_title" in s:
        print(d + ": строки уже добавлены")
        continue
    assert s.rstrip().endswith("</resources>"), d + ": нет </resources>"
    idx = s.rfind("</resources>")
    s = s[:idx].rstrip("\n") + "\n" + blk + "</resources>\n"
    write(p, s)
PY

echo
echo "Готово. Обучение появится на главном экране после принятия условий (один раз)."
echo "Повторный запуск: Настройки -> Обучение / Samouczek / Tutorial."
echo "Резервные копии изменённых файлов: $BK"
