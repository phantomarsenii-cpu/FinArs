#!/usr/bin/env bash
# Update 72: обучающий тур — плавная анимация + исправление текстов.
#  - анимация: затемнение рисуется одним Path (без аппаратного offscreen-слоя и PorterDuff.CLEAR),
#    подсветка плавно переезжает к новой цели, карточка мягко гаснет/появляется со сдвигом,
#    при смене вкладки экран под оверлеем перестраивается за ровным затемнением (нет рывков);
#  - тексты приведены в соответствие с приложением: квартальный лимит (не месячный), нет выбора
#    вида деятельности, в "Налог и лимиты" — ввод прочих доходов из других источников,
#    отчёты Excel/PDF, что входит в Pro, что в резервной копии и т. д.
# Запускать из КОРНЯ репозитория.
set -euo pipefail

M=app/src/main
J=$M/java/com/example/fa_ksiegowy
for f in "$J/TourOverlayView.kt" "$J/OnboardingTour.kt" "$M/res/values/strings.xml"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

cat > "$J/TourOverlayView.kt" <<'KT_OVERLAY'
package com.example.fa_ksiegowy

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.animation.PathInterpolator
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
    // Затемнение рисуем ОДНИМ путём (прямоугольник экрана минус скруглённая "дырка", EVEN_ODD) —
    // без PorterDuff.CLEAR и без аппаратного offscreen-слоя, поэтому анимация не подтормаживает.
    private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(0xD2, 0x04, 0x07, 0x14) }
    private val dimPath = Path().apply { fillType = Path.FillType.EVEN_ODD }
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
    private val smooth = PathInterpolator(0.4f, 0f, 0.2f, 1f)   // fast-out-slow-in

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
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES

        buildCard()
        card.alpha = 0f
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
     * Перед сменой вкладки / прокруткой: карточка гаснет, подсветка "схлопывается" в точку.
     * Пока экран под оверлеем перестраивается, пользователь видит только ровное затемнение —
     * поэтому переключение вкладок выглядит плавным, а не рваным.
     */
    fun beginTransition() {
        card.animate().cancel()
        card.animate().alpha(0f).setDuration(120).setInterpolator(smooth).start()
        animateHoleTo(null)
    }

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
        // Подсветка плавно "переезжает" к новой цели (или раскрывается из точки).
        animateHoleTo(target)
        progressView.setProgress((index + 1).toFloat() / total.toFloat())

        val bind = {
            titleView.text = title
            textView.text = text
            counterView.text = counter
            skipView.text = skipLabel
            backView.text = backLabel
            nextView.text = nextLabel
            backView.visibility = if (showBack) View.VISIBLE else View.GONE
            // на последнем шаге "Пропустить" не нужен
            skipView.visibility = if (index >= total - 1) View.INVISIBLE else View.VISIBLE
            val top = computeCardTop(target)
            card.translationY = top + dp(16f)
            card.animate().cancel()
            card.animate()
                .alpha(1f)
                .translationY(top)
                .setDuration(300)
                .setInterpolator(smooth)
                .start()
        }

        card.animate().cancel()
        if (card.alpha > 0.05f) {
            // Карточка уже на экране: сначала быстро гасим старый текст, затем показываем новый.
            card.animate().alpha(0f).setDuration(110).setInterpolator(smooth)
                .withEndAction { bind() }.start()
        } else {
            bind()
        }
    }

    /** Вертикальная позиция карточки (translationY при topMargin = 0). */
    private fun computeCardTop(target: RectF?): Float {
        val w = width
        val h = height
        if (w == 0 || h == 0) return 0f
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
        return top.toFloat()
    }

    // ---------- анимация подсветки ----------

    private fun animateHoleTo(target: RectF?) {
        holeAnimator?.cancel()
        if (target == null) {
            if (!hasHole) { invalidate(); return }
            val cx = hole.centerX()
            val cy = hole.centerY()
            runHoleAnimation(RectF(hole), RectF(cx, cy, cx, cy), holeRadius, 0f, 200L) {
                hasHole = false
                invalidate()
            }
        } else {
            val start = if (hasHole) RectF(hole)
            else RectF(target.centerX(), target.centerY(), target.centerX(), target.centerY())
            val startRadius = if (hasHole) holeRadius else 0f
            hasHole = true
            // Круглые/квадратные цели (кнопка "+") — подсвечиваем кругом, остальные — скруглённым прямоугольником.
            val half = min(target.width(), target.height()) / 2f
            val squarish = kotlin.math.abs(target.width() - target.height()) < dp(8f) && target.width() < dp(90f)
            val endRadius = if (squarish) half else min(dp(16f), half)
            runHoleAnimation(start, RectF(target), startRadius, endRadius, 340L, null)
        }
    }

    private fun runHoleAnimation(
        from: RectF, to: RectF, r0: Float, r1: Float, durationMs: Long, onEnd: (() -> Unit)?
    ) {
        hole.set(from)
        holeRadius = r0
        holeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            interpolator = smooth
            addUpdateListener {
                val t = it.animatedValue as Float
                hole.set(
                    from.left + (to.left - from.left) * t,
                    from.top + (to.top - from.top) * t,
                    from.right + (to.right - from.right) * t,
                    from.bottom + (to.bottom - from.bottom) * t
                )
                holeRadius = r0 + (r1 - r0) * t
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
        dimPath.reset()
        dimPath.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
        if (hasHole) {
            val r = holeRadius.coerceAtMost(min(hole.width(), hole.height()) / 2f).coerceAtLeast(0f)
            dimPath.addRoundRect(hole, r, r, Path.Direction.CW)
        }
        canvas.drawPath(dimPath, dimPaint)
        if (hasHole && hole.width() > 1f) {
            ringPaint.alpha = (140 + 115 * pulse).toInt()
            val r = holeRadius.coerceAtMost(min(hole.width(), hole.height()) / 2f).coerceAtLeast(0f)
            canvas.drawRoundRect(hole, r, r, ringPaint)
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
echo "обновлён: $J/TourOverlayView.kt"

python3 - <<'PY'
import re
M = "app/src/main"
J = M + "/java/com/example/fa_ksiegowy"
def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)

# --- OnboardingTour.kt: перед сменой шага "схлопываем" подсветку и гасим карточку ---
p = J + "/OnboardingTour.kt"
s = read(p)
if "ov.beginTransition()" not in s:
    old = "        val step = steps[i]\n\n"
    assert s.count(old) == 1, "не найден фрагмент в OnboardingTour.goTo"
    s = s.replace(old, "        val step = steps[i]\n        ov.beginTransition()\n\n")
    write(p, s)
else:
    print("OnboardingTour: уже применено")

# --- тексты ---
U = {'tour_balance_text': {'values': 'Your balance, income and expenses for the current period. Everything updates instantly after each entry.', 'values-pl': 'Saldo, przychody i wydatki za bieżący okres. Wszystko odświeża się od razu po dodaniu wpisu.', 'values-ru': 'Баланс, доходы и расходы за текущий период. Данные обновляются сразу после каждой записи.', 'values-uk': 'Баланс, доходи й витрати за поточний період. Дані оновлюються одразу після кожного запису.'}, 'tour_limits_title': {'values': 'Quarterly limit', 'values-pl': 'Limit kwartalny', 'values-ru': 'Квартальный лимит', 'values-uk': 'Квартальний ліміт'}, 'tour_limits_text': {'values': 'FinArs tracks the quarterly income limit for unregistered activity and the yearly tax thresholds, and warns you at 80%, 95% and 100%. Tap the card for details.', 'values-pl': 'FinArs pilnuje kwartalnego limitu przychodu dla działalności nierejestrowanej oraz rocznych progów podatkowych i ostrzega przy 80%, 95% i 100%. Dotknij karty, aby zobaczyć szczegóły.', 'values-ru': 'FinArs следит за квартальным лимитом дохода незарегистрированной деятельности и годовыми налоговыми порогами и предупреждает при 80%, 95% и 100%. Нажмите на карточку, чтобы увидеть подробности.', 'values-uk': 'FinArs стежить за квартальним лімітом доходу незареєстрованої діяльності та річними податковими порогами й попереджає при 80%, 95% і 100%. Натисніть на картку, щоб побачити подробиці.'}, 'tour_chart_text': {'values': 'Two lines show how your income and expenses change during the month, so trends are easy to spot.', 'values-pl': 'Dwie linie pokazują, jak w ciągu miesiąca zmieniają się Twoje przychody i wydatki — trendy widać od razu.', 'values-ru': 'Две линии показывают, как в течение месяца меняются ваши доходы и расходы, — тренды видны сразу.', 'values-uk': 'Дві лінії показують, як протягом місяця змінюються ваші доходи й витрати, — тенденції видно одразу.'}, 'tour_bell_text': {'values': 'Reminders about limits, tax advance payments, the annual return deadline, low stock and invoice due dates appear here.', 'values-pl': 'Tutaj pojawiają się przypomnienia o limitach, zaliczkach na podatek, terminie rocznego zeznania, niskim stanie magazynu i terminach płatności faktur.', 'values-ru': 'Здесь появляются напоминания о лимитах, авансовых платежах по налогу, сроке подачи годовой декларации, низких остатках на складе и сроках оплаты фактур.', 'values-uk': 'Тут з’являються нагадування про ліміти, авансові платежі з податку, строк подання річної декларації, низькі залишки на складі та строки оплати фактур.'}, 'tour_add_text': {'values': 'Tap + to add income or an expense: amount, date, category, comment and an attachment such as a receipt photo. You can also make an entry recurring.', 'values-pl': 'Dotknij +, aby dodać przychód lub wydatek: kwotę, datę, kategorię, komentarz i załącznik, np. zdjęcie paragonu. Wpis możesz też ustawić jako cykliczny.', 'values-ru': 'Нажмите +, чтобы добавить доход или расход: сумму, дату, категорию, комментарий и вложение, например фото чека. Запись можно сделать повторяющейся.', 'values-uk': 'Натисніть +, щоб додати дохід або витрату: суму, дату, категорію, коментар і вкладення, наприклад фото чека. Запис можна зробити повторюваним.'}, 'tour_history_text': {'values': 'Your latest entries are listed here. Open the full history to search, filter by date, and switch between All, Income and Expenses.', 'values-pl': 'Tu widać ostatnie wpisy. W pełnej historii możesz wyszukiwać, filtrować według daty i przełączać Wszystkie, Przychody i Wydatki.', 'values-ru': 'Здесь видны последние записи. В полной истории можно искать, фильтровать по дате и переключаться между «Все», «Доходы» и «Расходы».', 'values-uk': 'Тут видно останні записи. У повній історії можна шукати, фільтрувати за датою та перемикатися між «Усі», «Доходи» і «Витрати».'}, 'tour_reports_text': {'values': 'Pick a period to see how income, expenses and tax are split. Reports for a month, a year or any period export to Excel, and the sales register (Ewidencja) to PDF. Yearly and custom reports are Pro.', 'values-pl': 'Wybierz okres, aby zobaczyć podział przychodów, wydatków i podatku. Raporty za miesiąc, rok lub dowolny okres eksportujesz do Excela, a ewidencję sprzedaży do PDF. Raport roczny i dowolny okres to funkcje Pro.', 'values-ru': 'Выберите период, чтобы увидеть распределение доходов, расходов и налога. Отчёты за месяц, год или любой период выгружаются в Excel, а книга продаж (Ewidencja) — в PDF. Годовой и произвольный отчёты — функции Pro.', 'values-uk': 'Оберіть період, щоб побачити розподіл доходів, витрат і податку. Звіти за місяць, рік або будь-який період вивантажуються в Excel, а книга продажів (Ewidencja) — у PDF. Річний і довільний звіти — функції Pro.'}, 'tour_tax_title': {'values': 'Tax and limits', 'values-pl': 'Podatek i limity', 'values-ru': 'Налог и лимиты', 'values-uk': 'Податки та ліміти'}, 'tour_tax_text': {'values': 'Important: enter your other income for the year here (employment, another business and so on), if you have any. It is added to the income from this app when FinArs calculates your tax and checks the 30,000 zł tax-free amount.', 'values-pl': 'Ważne: wpisz tutaj swoje inne przychody z tego roku (etat, inna działalność itp.), jeśli je masz. Są one doliczane do przychodów z aplikacji, gdy FinArs liczy podatek i sprawdza kwotę wolną 30 000 zł.', 'values-ru': 'Важно: укажите здесь свои прочие доходы за год из других источников (работа по найму, другая деятельность и т. п.), если они есть. Они прибавляются к доходу из приложения, когда FinArs считает налог и проверяет необлагаемый минимум 30 000 zł.', 'values-uk': 'Важливо: вкажіть тут свої інші доходи за рік з інших джерел (робота за наймом, інша діяльність тощо), якщо вони є. Вони додаються до доходу із застосунку, коли FinArs рахує податок і перевіряє неоподатковуваний мінімум 30 000 zł.'}, 'tour_backup_text': {'values': 'Save your entries, including receipt photos, to a file and restore them after losing your phone or reinstalling. This is a Pro feature. Do it regularly.', 'values-pl': 'Zapisz wpisy, także zdjęcia paragonów, do pliku i przywróć je po utracie telefonu lub reinstalacji. To funkcja Pro. Rób to regularnie.', 'values-ru': 'Сохраните записи, включая фото чеков, в файл и восстановите их при потере телефона или переустановке. Это функция Pro. Делайте это регулярно.', 'values-uk': 'Збережіть записи, зокрема фото чеків, у файл і відновіть їх після втрати телефона чи перевстановлення. Це функція Pro. Робіть це регулярно.'}, 'tour_pro_text': {'values': 'Pro unlocks invoices (PDF), yearly and custom-period reports in Excel, PIT-36 return, backup and restore, and removes ads. It starts with a 7-day free trial.', 'values-pl': 'Pro odblokowuje faktury (PDF), raporty roczne i za dowolny okres w Excelu, deklarację PIT-36, kopię zapasową i przywracanie oraz usuwa reklamy. Na start jest 7 dni za darmo.', 'values-ru': 'Pro открывает счета и фактуры (PDF), годовой и произвольный отчёты в Excel, декларацию PIT-36, резервное копирование и восстановление и убирает рекламу. Начинается с 7 дней бесплатно.', 'values-uk': 'Pro відкриває рахунки та фактури (PDF), річний і довільний звіти в Excel, декларацію PIT-36, резервне копіювання й відновлення та прибирає рекламу. Починається з 7 днів безкоштовно.'}}

for d, items in {}.items():
    pass
langs = ["values", "values-pl", "values-ru", "values-uk"]
for d in langs:
    p = M + "/res/" + d + "/strings.xml"
    s = read(p)
    for key, per in U.items():
        pat = re.compile(r'(<string name="' + re.escape(key) + r'"[^>]*>)(.*?)(</string>)', re.S)
        assert len(pat.findall(s)) == 1, d + ": не найден ключ " + key
        s = pat.sub(lambda m: m.group(1) + per[d] + m.group(3), s, count=1)
    write(p, s)
PY

echo
echo "Готово: анимация тура сглажена, тексты исправлены."
