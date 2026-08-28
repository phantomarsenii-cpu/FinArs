package com.example.fa_ksiegowy

import android.app.Activity
import android.graphics.Color
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
 * krawedzie ekranu — POD pasek statusu i POD dolny (gestowy/systemowy) pasek
 * nawigacji — a to, co tam "wjezdza" podczas scrollowania, jest realnie
 * rozmywane (BlurView, prawdziwy Gaussian blur), zamiast byc zwyczajnie
 * zaslaniane jednolitym kolorem.
 *
 * Podpiete RAZ, centralnie, w BaseActivity.onContentChanged() — dziala wiec
 * automatycznie na kazdym ekranie w calej aplikacji, bez zmian w kazdej
 * Activity/Fragmencie z osobna. Warunek: root danego layoutu (activity_*.xml
 * / fragment_*.xml) opakowuje swoja tresc w
 * <eightbitlab.com.blurview.BlurTarget android:id="@+id/blur_target">
 * (patrz dowolny activity_*.xml — ksztalt jest zawsze ten sam: BlurTarget
 * zawiera [tlo AnimatedMeshBackgroundView, wlasciwa tresc, opcjonalnie
 * <include bottom_nav_bar>]). Ekrany bez tego id (np. activity_lock.xml)
 * i tak dostaja pelny ekran (transparentne paski systemowe), po prostu bez
 * nakladki rozmycia.
 *
 * Co dokladnie sie dzieje dla kazdego takiego ekranu:
 *  - tlo (AnimatedMeshBackgroundView) zostaje bez zmian — ma wypelniac caly
 *    ekran, tez pod paskami systemowymi;
 *  - wlasciwa tresc (bezposrednie rodzenstwo tla w BlurTarget) dostaje
 *    dodatkowy padding gorny/dolny = wysokosc paska statusu/nawigacji, zeby
 *    naglowek czy przyciski nie ladowaly sie doslownie pod zegarkiem/
 *    przyciskami systemowymi;
 *  - kontener plywajacego dolnego paska nawigacji aplikacji (ten z
 *    ic_nav_home itd., rozpoznawany po tym, ze zawiera widok o id
 *    nav_start) dostaje dodatkowy dolny margines, zeby "uniosl sie" ponad
 *    gestowy pasek systemowy — dokladnie jak w Revolut. Dziala to zarowno
 *    gdy ten kontener jest bezposrednio w BlurTarget (np. activity_history),
 *    jak i gdy jest poza nim, obok fragment_containera (activity_main).
 */
object EdgeToEdge {

    private const val BLUR_RADIUS = 22f

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
        // PO tym, jak insets zostaly juz raz dostarczone do Activity — kazda
        // kolejna zmiana w drzewie widokow (np. pokazanie nowego fragmentu)
        // musi wiec ponownie przejsc drzewo, zeby ten nowy fragment tez
        // dostal swoj pasek rozmycia i padding.
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
                    // ponad systemowy pasek/gesty, nic wiecej tu nie trzeba robic.
                    bumpBottomMargin(child, bars.bottom)
                }
                else -> walkChildren(child, insets)
            }
        }
    }

    /** Dziala na BEZPOSREDNICH dzieciach BlurTarget — ksztalt layoutu jest
     * zawsze ten sam (patrz komentarz u gory pliku), wiec nie trzeba
     * zgadywac typu widoku (ScrollView, RecyclerView, LinearLayout...). */
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

    /** Dodaje dwa BlurView (gora/dol) jako RODZENSTWO BlurTarget (tak wymaga
     * biblioteka) — czyli jako kolejne dzieci wspolnego rodzica (root
     * layoutu ekranu), narysowane NAD BlurTarget. Kazdy ma wysokosc dokladnie
     * insetu paska systemowego i rozmywa to, co w danym momencie scrolluje
     * sie pod nim wewnatrz BlurTarget. */
    private fun addBlurStrips(target: BlurTarget, topInset: Int, bottomInset: Int) {
        val parent = target.parent as? ViewGroup ?: return

        if (target.getTag(R.id.tag_edge_to_edge_blur_done) == true) {
            resizeStrip(parent, Gravity.TOP, topInset)
            resizeStrip(parent, Gravity.BOTTOM, bottomInset)
            return
        }
        if (topInset > 0) parent.addView(buildBlurStrip(target, Gravity.TOP, topInset))
        if (bottomInset > 0) parent.addView(buildBlurStrip(target, Gravity.BOTTOM, bottomInset))
        target.setTag(R.id.tag_edge_to_edge_blur_done, true)
    }

    private fun buildBlurStrip(target: BlurTarget, gravity: Int, height: Int): BlurView {
        val strip = BlurView(target.context)
        strip.tag = stripTag(gravity)
        strip.layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height).apply {
            this.gravity = gravity
        }
        strip.setupWith(target).setBlurRadius(BLUR_RADIUS)
        return strip
    }

    private fun resizeStrip(parent: ViewGroup, gravity: Int, height: Int) {
        val strip = parent.findViewWithTag<View>(stripTag(gravity)) ?: return
        val lp = strip.layoutParams ?: return
        if (lp.height != height) {
            lp.height = height
            strip.layoutParams = lp
        }
    }

    private fun stripTag(gravity: Int) =
        if (gravity == Gravity.TOP) "edge_to_edge_blur_top" else "edge_to_edge_blur_bottom"
}
