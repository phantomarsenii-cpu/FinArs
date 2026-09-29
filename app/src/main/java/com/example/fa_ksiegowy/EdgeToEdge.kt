package com.example.fa_ksiegowy

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import androidx.core.view.OnApplyWindowInsetsListener
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import eightbitlab.com.blurview.BlurTarget
import eightbitlab.com.blurview.BlurView

/**
 * Prawdziwy pelny ekran (jak w Revolut): tresc rysuje sie az po fizyczne
 * krawedzie ekranu — POD pasek statusu i POD dolny pasek nawigacji — a to,
 * co tam wjezdza podczas scrollowania, PLYNNIE, bez zadnej widocznej linii,
 * rozmywa sie (BlurView + gradientowa maska alfa, patrz [FadeBlurStrip]).
 *
 * Update 66: poprzednia wersja dawala BlurView o stalej, twardej wysokosci
 * (dokladnie insets.top / insets.bottom) — granica miedzy "rozmyte" i
 * "ostre" byla widoczna jako linia. Teraz kazdy pasek jest:
 *  1) WYZSZY niz sam inset (tresc wjezdza w niego stopniowo podczas
 *     scrolla, zanim dotrze do prawdziwej krawedzi),
 *  2) zamaskowany gradientem alfa (w pelni rozmyty/widoczny dokladnie przy
 *     krawedzi ekranu, plynnie zanikajacy do zera w glab tresci) —
 *     zero twardej linii.
 * Dolny pasek jest dodatkowo znacznie wyzszy (BOTTOM_EXTRA_DP), bo ma
 * obejmowac tez obszar POD plywajacym paskiem nawigacji aplikacji (Start/
 * Magazyn/Raporty/Ustawienia), a nie tylko waski systemowy inset — user
 * chcial zeby rozmycie zaczynalo sie juz od gory tego paska.
 *
 * Podpiete RAZ, centralnie, w BaseActivity.onContentChanged() — dziala wiec
 * automatycznie na kazdym ekranie w calej aplikacji. Warunek: root danego
 * layoutu (activity_*.xml / fragment_*.xml) opakowuje swoja tresc w
 * <eightbitlab.com.blurview.BlurTarget android:id="@+id/blur_target">.
 */
object EdgeToEdge {

    private const val BLUR_RADIUS = 25f

    /** Gorny pasek: ile razy wyzszy niz sam inset paska statusu — daje
     * miejsce na plynne wygaszanie rozmycia zamiast twardej linii. */
    private const val TOP_FADE_MULTIPLIER = 2.4f

    /** Dolny pasek: stala dodatkowa wysokosc (w dp) doklejana do insetu
     * systemowego, tak zeby strefa rozmycia siegala az pod gorna krawedz
     * plywajacego paska nawigacji aplikacji (Start/Magazyn/...), a nie
     * tylko pod sam systemowy gesture-bar. */
    private const val BOTTOM_EXTRA_DP = 130f

    /** Update 68: dolny pasek — mocniejsze rozmycie niz gora, zeby napisy pod
     * systemowymi przyciskami nawigacji nie mylily sie z ikonami przyciskow. */
    private const val BOTTOM_BLUR_RADIUS = 45f

    /** Strefa PELNEGO rozmycia: inset systemowy + tyle dp nad nim. */
    private const val BOTTOM_SOLID_EXTRA_DP = 20f

    /** Ciemny ton (kolor tla aplikacji, ~70%) kladziony na rozmycie u dolu. */
    private val BOTTOM_TINT = Color.argb(0xB3, 0x08, 0x0C, 0x20)

    fun apply(activity: Activity) {
        val window = activity.window
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        val contentParent = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val root = contentParent.getChildAt(0) ?: return

        var latestInsets: WindowInsetsCompat? = null

        val listener = OnApplyWindowInsetsListener { _, insets ->
            latestInsets = insets
            root.post { latestInsets?.let { walkChildren(root, it) } }
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(root, listener)

        // Fragmenty (Start/Magazyn/Raporty/Ustawienia) dokladaja swoje widoki
        // PO tym, jak insets zostaly juz raz dostarczone — kazda kolejna
        // zmiana w drzewie widokow musi wiec ponownie przejsc drzewo.
        root.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                latestInsets?.let { insets -> root.post { walkChildren(root, insets) } }
            }
        })

        ViewCompat.requestApplyInsets(root)
    }

    private fun walkChildren(view: View, insets: WindowInsetsCompat) {
        if (view !is ViewGroup) return
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
        for (i in 0 until view.childCount) {
            val child = view.getChildAt(i)
            when {
                child is BlurTarget && child.id == R.id.blur_target -> {
                    setupBlurTarget(child, bars.top, bars.bottom)
                    walkChildren(child, insets)
                }
                child is ViewGroup && child.findViewById<View>(R.id.nav_start) != null -> {
                    // Plywajacy dolny pasek nawigacji aplikacji — podnies go
                    // ponad systemowy pasek/gesty.
                    bumpBottomMargin(child, bars.bottom)
                }
                else -> walkChildren(child, insets)
            }
        }
    }

    private fun setupBlurTarget(target: BlurTarget, topInset: Int, bottomInset: Int) {
        for (i in 0 until target.childCount) {
            val child = target.getChildAt(i)
            if (child is AnimatedMeshBackgroundView) continue
            if (child is ViewGroup && child.findViewById<View>(R.id.nav_start) != null) continue
            bumpPadding(child, topInset, bottomInset)
        }
        addBlurStrips(target, topInset, bottomInset)
    }

    private fun bumpPadding(view: View, topInset: Int, bottomInset: Int) {
        val original = view.getTag(R.id.tag_edge_to_edge_padding) as? IntArray
            ?: intArrayOf(view.paddingLeft, view.paddingTop, view.paddingRight, view.paddingBottom)
                .also { view.setTag(R.id.tag_edge_to_edge_padding, it) }
        val newTop = original[1] + topInset
        val newBottom = original[3] + bottomInset
        if (view.paddingTop != newTop || view.paddingBottom != newBottom) {
            view.setPadding(original[0], newTop, original[2], newBottom)
        }
    }

    private fun bumpBottomMargin(view: View, bottomInset: Int) {
        if (view.getTag(R.id.tag_edge_to_edge_margin_done) == true) return
        (view.layoutParams as? ViewGroup.MarginLayoutParams)?.let { lp ->
            lp.bottomMargin += bottomInset
            view.layoutParams = lp
        }
        view.setTag(R.id.tag_edge_to_edge_margin_done, true)
    }

    /** Dodaje dwa [FadeBlurStrip] (gora/dol) jako RODZENSTWO BlurTarget (tak
     * wymaga biblioteka BlurView) — kolejne dzieci wspolnego rodzica (root
     * layoutu ekranu), narysowane NAD BlurTarget. */
    private fun addBlurStrips(target: BlurTarget, topInset: Int, bottomInset: Int) {
        val parent = target.parent as? ViewGroup ?: return
        val density = target.resources.displayMetrics.density
        val topHeight = (topInset * TOP_FADE_MULTIPLIER).toInt()
        val bottomHeight = bottomInset + (BOTTOM_EXTRA_DP * density).toInt()
        val bottomSolid = bottomInset + (BOTTOM_SOLID_EXTRA_DP * density).toInt()

        if (target.getTag(R.id.tag_edge_to_edge_blur_done) == true) {
            resizeStrip(parent, Gravity.TOP, topHeight, 0)
            resizeStrip(parent, Gravity.BOTTOM, bottomHeight, bottomSolid)
            return
        }
        if (topInset > 0) parent.addView(buildBlurStrip(target, Gravity.TOP, topHeight, 0))
        if (bottomInset > 0) parent.addView(buildBlurStrip(target, Gravity.BOTTOM, bottomHeight, bottomSolid))
        target.setTag(R.id.tag_edge_to_edge_blur_done, true)
    }

    private fun buildBlurStrip(target: BlurTarget, gravity: Int, height: Int, solidPx: Int): FadeBlurStrip {
        val strip = FadeBlurStrip(target.context, fadeFromEdge = gravity)
        val isBottom = gravity == Gravity.BOTTOM
        strip.solidPx = solidPx
        strip.tintColor = if (isBottom) BOTTOM_TINT else Color.TRANSPARENT
        strip.tag = stripTag(gravity)
        strip.layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height).apply {
            this.gravity = gravity
        }
        strip.blurView.setupWith(target)
            .setBlurRadius(if (isBottom) BOTTOM_BLUR_RADIUS else BLUR_RADIUS)
        return strip
    }

    private fun resizeStrip(parent: ViewGroup, gravity: Int, height: Int, solidPx: Int) {
        val strip = parent.findViewWithTag<View>(stripTag(gravity)) ?: return
        (strip as? FadeBlurStrip)?.solidPx = solidPx
        val lp = strip.layoutParams ?: return
        if (lp.height != height) {
            lp.height = height
            strip.layoutParams = lp
        }
    }

    private fun stripTag(gravity: Int) =
        if (gravity == Gravity.TOP) "edge_to_edge_blur_top" else "edge_to_edge_blur_bottom"

    /**
     * Kontener na BlurView, ktory maskuje go pionowym gradientem alfa —
     * pelne rozmycie dokladnie przy krawedzi ekranu (fadeFromEdge), plynnie
     * zanikajace do zera w strone tresci. Dzieki temu nie ma zadnej
     * widocznej linii miedzy "rozmyte" i "ostre" (jak w Revolut).
     */
    private class FadeBlurStrip(context: Context, private val fadeFromEdge: Int) : FrameLayout(context) {
        val blurView = BlurView(context)

        private val maskPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }

        /** Wysokosc (px) od krawedzi ekranu, w ktorej rozmycie jest w 100% nieprzezroczyste. */
        var solidPx: Int = 0
            set(value) {
                if (field != value) { field = value; rebuildMask() }
            }

        /** Ciemny ton kladziony na rozmycie (przed maska). */
        var tintColor: Int = Color.TRANSPARENT

        // Update 73: на слабых устройствах (PerformanceMode.MINIMAL) вместо размытия — простой
        // градиент-затемнение: без BlurView и без saveLayer на каждый кадр.
        private var blurOn = true
        private val scrimPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val levelListener: (Int) -> Unit = { applyLevel(it) }

        init {
            setWillNotDraw(false)
            addView(blurView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            applyLevel(PerformanceMode.level(context))
        }

        private fun applyLevel(level: Int) {
            val on = level < PerformanceMode.MINIMAL
            if (on == blurOn && blurView.visibility == (if (on) VISIBLE else GONE)) return
            blurOn = on
            blurView.visibility = if (on) VISIBLE else GONE
            invalidate()
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            PerformanceMode.addListener(levelListener)
            applyLevel(PerformanceMode.level(context))
        }

        override fun onDetachedFromWindow() {
            PerformanceMode.removeListener(levelListener)
            super.onDetachedFromWindow()
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            rebuildMask()
        }

        private fun rebuildMask() {
            val h = height
            if (width <= 0 || h <= 0) return
            maskPaint.shader = if (fadeFromEdge == Gravity.TOP) {
                // gora nieprzezroczysta -> dol przezroczysty
                LinearGradient(
                    0f, 0f, 0f, h.toFloat(),
                    Color.BLACK, Color.TRANSPARENT,
                    Shader.TileMode.CLAMP
                )
            } else {
                // gora przezroczysta -> plynnie -> 100% w strefie solidPx przy dolnej krawedzi
                val solid = solidPx.coerceIn(0, h - 1)
                val frac = (h - solid).toFloat() / h
                LinearGradient(
                    0f, 0f, 0f, h.toFloat(),
                    intArrayOf(Color.TRANSPARENT, Color.BLACK, Color.BLACK),
                    floatArrayOf(0f, frac, 1f),
                    Shader.TileMode.CLAMP
                )
            }
            // тот же градиент, но цветом затемнения — для режима без размытия
            val scrim = Color.argb(215, 5, 9, 24)
            val scrimClear = Color.argb(0, 5, 9, 24)
            scrimPaint.shader = if (fadeFromEdge == Gravity.TOP) {
                LinearGradient(0f, 0f, 0f, h.toFloat(), scrim, scrimClear, Shader.TileMode.CLAMP)
            } else {
                val solid = solidPx.coerceIn(0, h - 1)
                val frac = (h - solid).toFloat() / h
                LinearGradient(
                    0f, 0f, 0f, h.toFloat(),
                    intArrayOf(scrimClear, scrim, scrim),
                    floatArrayOf(0f, frac, 1f),
                    Shader.TileMode.CLAMP
                )
            }
            invalidate()
        }

        override fun dispatchDraw(canvas: Canvas) {
            if (!blurOn) {
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrimPaint)
                return
            }
            val save = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
            super.dispatchDraw(canvas)
            if (Color.alpha(tintColor) > 0) canvas.drawColor(tintColor)
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), maskPaint)
            canvas.restoreToCount(save)
        }
    }
}
