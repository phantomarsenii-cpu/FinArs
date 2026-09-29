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
