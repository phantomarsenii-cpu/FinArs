#!/data/data/com.termux/files/usr/bin/bash
# Update 65: pelny ekran edge-to-edge + realne rozmycie (blur) tla pod
# paskiem statusu i pod dolnym paskiem nawigacji systemowej — tak jak w
# Revolut (patrz zrzuty ekranu w zadaniu).
#
# Zmiany:
#  1) BaseActivity + nowy EdgeToEdge.kt: WindowCompat.setDecorFitsSystemWindows
#     (tresc rysuje sie az po fizyczne krawedzie ekranu), paski systemowe
#     transparentne, realne rozmycie (biblioteka BlurView) tego, co scrolluje
#     sie pod paskiem statusu i pod dolnym paskiem nawigacji/gestow.
#     Podpiete RAZ centralnie w BaseActivity — dziala automatycznie na
#     WSZYSTKICH ekranach aplikacji.
#  2) 26 layoutow (activity_*.xml / fragment_*.xml) — tresc kazdego ekranu
#     opakowana w <eightbitlab.com.blurview.BlurTarget android:id="@+id/blur_target">,
#     zeby EdgeToEdge.kt mial co rozmywac. Tlo (AnimatedMeshBackgroundView)
#     i reszta ukladu bez zmian — to czysto mechaniczne opakowanie.
#     (activity_lock.xml — ekran blokady PIN — i activity_main.xml — hostuje
#     fragmenty, ktore maja to opakowanie u siebie — celowo pominiete.)
#  3) settings.gradle: dodane repo Jitpack (zrodlo biblioteki BlurView).
#  4) app/build.gradle: dodana zaleznosc com.github.Dimezis:BlurView.
#  5) themes.xml: statusBarColor/navigationBarColor -> transparent,
#     windowLayoutInDisplayCutoutMode=shortEdges (tresc siega tez pod notch/
#     wcięcie na aparat, jesli telefon je ma).
#
# Uruchamiac z korzenia repo (tam gdzie folder app/ i .git/), np.:
#   cd ~/FA_ksiegowy
#   bash update_project-65-fullscreen-edge-to-edge-blur.sh

set -e

TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".update65_backup_${TS}"

echo "=== Update 65: pelny ekran + rozmycie pod paskami systemowymi ==="
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
  echo "BLAD: nie widze settings.gradle lub app/src/main/java/com/example/fa_ksiegowy - uruchom skrypt z korzenia repo."
  exit 1
fi

if [ -f "app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt" ]; then
  echo "!!! Wyglada na to, ze update_project-65 zostal juz zastosowany (EdgeToEdge.kt juz istnieje)."
  exit 1
fi

mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt" \
    "app/src/main/res/values/themes.xml" \
    "settings.gradle" \
    "app/build.gradle" \
    "app/src/main/res/layout/activity_about.xml" \
    "app/src/main/res/layout/activity_add_edit_product.xml" \
    "app/src/main/res/layout/activity_add_entry.xml" \
    "app/src/main/res/layout/activity_add_invoice.xml" \
    "app/src/main/res/layout/activity_add_invoice_correction.xml" \
    "app/src/main/res/layout/activity_history.xml" \
    "app/src/main/res/layout/activity_inventory.xml" \
    "app/src/main/res/layout/activity_inventory_history.xml" \
    "app/src/main/res/layout/activity_invoice_history.xml" \
    "app/src/main/res/layout/activity_limits.xml" \
    "app/src/main/res/layout/activity_notifications.xml" \
    "app/src/main/res/layout/activity_pit36.xml" \
    "app/src/main/res/layout/activity_pit_data.xml" \
    "app/src/main/res/layout/activity_privacy_policy.xml" \
    "app/src/main/res/layout/activity_select_contractor.xml" \
    "app/src/main/res/layout/activity_select_products.xml" \
    "app/src/main/res/layout/activity_settings_backup.xml" \
    "app/src/main/res/layout/activity_settings_language.xml" \
    "app/src/main/res/layout/activity_settings_pro.xml" \
    "app/src/main/res/layout/activity_settings_security.xml" \
    "app/src/main/res/layout/activity_settings_tax.xml" \
    "app/src/main/res/layout/activity_terms.xml" \
    "app/src/main/res/layout/fragment_magazin.xml" \
    "app/src/main/res/layout/fragment_mine.xml" \
    "app/src/main/res/layout/fragment_report.xml" \
    "app/src/main/res/layout/fragment_settings.xml"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "Kopia zapasowa (plikow modyfikowanych) zapisana w: $BACKUP_DIR"
echo ""
echo "-> krok: nowy plik app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt" << 'FILEEOF'
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
FILEEOF

echo "-> krok: nowy plik app/src/main/res/values/ids_edge_to_edge.xml"
mkdir -p "$(dirname "app/src/main/res/values/ids_edge_to_edge.xml")"
cat > "app/src/main/res/values/ids_edge_to_edge.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<!--
    Pomocnicze id uzywane WYLACZNIE jako klucze View.setTag(id, ...) przez
    EdgeToEdge.kt — zeby bezpiecznie odroznic "juz obsluzone" widoki od
    nowych, bez kolizji z tagami innych bibliotek (np. BlurView), ktore
    uzywaja jednoargumentowego setTag(Object).
-->
<resources>
    <item name="tag_edge_to_edge_padding" type="id"/>
    <item name="tag_edge_to_edge_margin_done" type="id"/>
    <item name="tag_edge_to_edge_blur_done" type="id"/>
</resources>
FILEEOF

echo "-> krok: nadpisanie app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt"
mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/BaseActivity.kt" << 'FILEEOF'
package com.example.fa_ksiegowy

import android.content.Context
import android.content.Intent
import androidx.appcompat.app.AppCompatActivity

open class BaseActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.applyLocale(newBase))
    }

    // Update: pelny ekran "jak w Revolut" — tresc pod paskiem statusu i pod
    // dolnym paskiem nawigacji systemowej, z realnym rozmyciem tego, co tam
    // wjezdza (patrz EdgeToEdge.kt). onContentChanged() wywoluje sie
    // automatycznie zaraz PO kazdym setContentView() — dzieki temu dziala to
    // na KAZDYM ekranie apki (kazda Activity dziedziczy z BaseActivity),
    // bez potrzeby wywolywania czegokolwiek recznie w kazdej z osobna.
    override fun onContentChanged() {
        super.onContentChanged()
        EdgeToEdge.apply(this)
    }

    // Ladny fade+scale zamiast domyslnego "slajdu" systemowego przy przejsciu
    // miedzy ekranami — dotyczy KAZDEGO startActivity() w calej aplikacji,
    // bo wszystkie ekrany dziedzicza z BaseActivity.
    override fun startActivity(intent: Intent) {
        super.startActivity(intent)
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    override fun startActivity(intent: Intent, options: android.os.Bundle?) {
        super.startActivity(intent, options)
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(R.anim.screen_enter, R.anim.screen_exit)
    }

    /** Показываем экран блокировки поверх любого экрана приложения, если
     *  AppLockState считает, что приложение только что вернулось из фона
     *  и PIN установлен. Сам LockActivity этот код у себя не выполняет
     *  (иначе он бесконечно запускал бы сам себя).
     *
     *  Перед этим проверяем, принято ли пользовательское соглашение —
     *  если нет, перехватываем навигацию и открываем TermsActivity
     *  (кроме самого TermsActivity, чтобы не зациклиться). */
    override fun onResume() {
        super.onResume()
        if (this !is TermsActivity && !TermsActivity.isAccepted(this)) {
            startActivity(Intent(this, TermsActivity::class.java))
            return
        }
        if (this !is LockActivity && AppLockState.isLocked) {
            startActivity(Intent(this, LockActivity::class.java))
        }
    }
}
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/values/themes.xml"
mkdir -p "$(dirname "app/src/main/res/values/themes.xml")"
cat > "app/src/main/res/values/themes.xml" << 'FILEEOF'
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.FA" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/accent_blue_light</item>
        <item name="colorPrimaryVariant">@color/accent_blue_dark</item>
        <item name="colorOnPrimary">@color/text_primary</item>
        <item name="colorSecondary">@color/accent_cyan</item>
        <item name="colorSecondaryVariant">@color/accent_blue_dark</item>
        <item name="colorOnSecondary">@color/text_primary</item>
        <item name="colorAccent">@color/accent_blue_light</item>
        <item name="colorControlActivated">@color/accent_blue_light</item>
        <!-- Update: pelny ekran "jak w Revolut" — paski systemowe transparentne,
             tresc rysuje sie az po fizyczne krawedzie ekranu (patrz
             EdgeToEdge.kt / BaseActivity.onContentChanged, ktore ustawiaja
             to samo programowo, zeby dzialalo tez na starszym Androidzie —
             te dwa wpisy w motywie to tylko zabezpieczenie przed
             mignieciem starego koloru w pierwszej klatce startu Activity). -->
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowBackground">@drawable/bg_gradient</item>
        <item name="android:textColorPrimary">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
        <item name="android:buttonStyle">@style/Widget.FA.Button</item>
        <item name="android:switchStyle">@style/Widget.FA.Switch</item>
        <item name="android:progressBarStyleHorizontal">@style/Widget.FA.ProgressBar</item>
        <!-- Update: kazdy AlertDialog.Builder(context) w calej aplikacji (PIN,
             "O aplikacji", blokady funkcji Pro itd.) uzywal domyslnego
             systemowego (jasnoszarego) wygladu, bo Theme.MaterialComponents
             nie mial wlasnego motywu dialogu. Podpiecie go tutaj naprawia
             WSZYSTKIE dialogi w aplikacji jednym miejscem, bez zmiany kazdego
             wywolania z osobna. -->
        <item name="alertDialogTheme">@style/ThemeOverlay.FA.Dialog</item>
        <item name="android:alertDialogTheme">@style/ThemeOverlay.FA.Dialog</item>
    </style>

    <style name="ThemeOverlay.FA.Dialog" parent="ThemeOverlay.MaterialComponents.MaterialAlertDialog">
        <item name="colorSurface">@color/card_bg_light</item>
        <item name="colorOnSurface">@color/text_primary</item>
        <item name="colorPrimary">@color/accent_blue_light</item>
        <item name="colorAccent">@color/accent_blue_light</item>
        <item name="android:textColorPrimary">@color/text_primary</item>
        <item name="android:textColorSecondary">@color/text_secondary</item>
        <item name="android:background">@color/card_bg_light</item>
        <item name="materialAlertDialogTitleTextStyle">@style/FA.Dialog.Title</item>
        <item name="buttonBarPositiveButtonStyle">@style/FA.Dialog.Button</item>
        <item name="buttonBarNegativeButtonStyle">@style/FA.Dialog.Button</item>
        <item name="buttonBarNeutralButtonStyle">@style/FA.Dialog.Button</item>
        <item name="android:windowBackground">@drawable/dialog_bg</item>
    </style>

    <style name="FA.Dialog.Title" parent="MaterialAlertDialog.MaterialComponents.Title.Text">
        <item name="android:textColor">@color/text_primary</item>
        <item name="android:textStyle">bold</item>
    </style>

    <style name="FA.Dialog.Button" parent="Widget.MaterialComponents.Button.TextButton.Dialog">
        <item name="android:textColor">@color/accent_blue_light</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <!-- Applied app-wide to every plain <Button>: adds a ripple + a soft
         press/release scale bounce. Buttons keep their own inline
         android:background / size, only the touch-feedback layer is added
         here so nothing else needs to change per screen. -->
    <style name="Widget.FA.Button" parent="Widget.AppCompat.Button">
        <item name="android:stateListAnimator">@animator/btn_press_scale</item>
        <item name="android:foreground">?attr/selectableItemBackground</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <style name="Widget.FA.Switch" parent="android:Widget.Material.CompoundButton.Switch">
        <item name="android:thumbTint">@color/switch_thumb_selector</item>
        <item name="android:trackTint">@color/switch_track_selector</item>
    </style>

    <style name="Widget.FA.ProgressBar" parent="android:Widget.ProgressBar.Horizontal">
        <item name="android:progressDrawable">@drawable/progress_bar_bg</item>
        <item name="android:minHeight">8dp</item>
        <item name="android:maxHeight">8dp</item>
    </style>

    <style name="InvoiceInput">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">56dp</item>
        <item name="android:layout_marginBottom">14dp</item>
        <item name="android:background">@drawable/input_field_bg</item>
        <item name="android:paddingStart">18dp</item>
        <item name="android:paddingEnd">18dp</item>
        <item name="android:textColor">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
    </style>

    <style name="InvoiceInputHalfStart" parent="InvoiceInput">
        <item name="android:layout_width">0dp</item>
        <item name="android:layout_weight">1</item>
        <item name="android:layout_marginEnd">7dp</item>
    </style>

    <style name="InvoiceInputHalfEnd" parent="InvoiceInput">
        <item name="android:layout_width">0dp</item>
        <item name="android:layout_weight">1</item>
        <item name="android:layout_marginStart">7dp</item>
    </style>
</resources>
FILEEOF

echo "-> krok: nadpisanie settings.gradle"
mkdir -p "$(dirname "settings.gradle")"
cat > "settings.gradle" << 'FILEEOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Update: BlurView (realne rozmycie tla pod paskiem statusu/nawigacji,
        // patrz app/build.gradle i EdgeToEdge.kt) jest publikowany przez Jitpack.
        maven { url 'https://jitpack.io' }
    }
}
rootProject.name = 'FA_ksiegowy'
include ':app'
FILEEOF

echo "-> krok: nadpisanie app/build.gradle"
mkdir -p "$(dirname "app/build.gradle")"
cat > "app/build.gradle" << 'FILEEOF'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
    id 'com.google.devtools.ksp'
}

// Update: numer wersji byl oparty o date/godzine builda (nieczytelny, nie
// rosnie w prosty sposob). Teraz numer wersji to zwykly licznik zapisany w
// pliku version.txt w korzeniu repo: 1.0, 1.1, 1.2, ... Plik jest odczytywany
// tutaj (versionCode/versionName), a incrementowany i commitowany z powrotem
// do repo automatycznie przez GitHub Actions PO kazdym udanym buildzie (patrz
// .github/workflows/build.yml, krok "Bump build version number") — dzieki
// czemu kolejny build automatycznie dostaje kolejny numer, bez recznej pracy.
def versionFile = file("$rootDir/version.txt")
def buildNumber = versionFile.exists() ? versionFile.text.trim().toInteger() : 0
def buildDateStamp = "${buildNumber}"

android {
    signingConfigs {
        debug {
            storeFile file("debug.keystore")
            storePassword "fa_ksiegowy_debug"
            keyAlias "fa_ksiegowy_debug"
            keyPassword "fa_ksiegowy_debug"
        }
    }

    namespace "com.example.fa_ksiegowy"
    compileSdk 34

    defaultConfig {
        applicationId "com.finars.app"
        minSdk 26
        targetSdk 34
        versionCode buildNumber + 1
        versionName "1.${buildDateStamp}"
        multiDexEnabled true
    }

    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = '17' }

    // pdfbox-android (добавлена для заполнения официального PIT-36) и Apache POI оба
    // тянут META-INF файлы с одинаковыми именами — без этого блока сборка падает
    // с "More than one file was found with OS independent path 'META-INF/...'".
    packagingOptions {
        resources {
            excludes += [
                'META-INF/DEPENDENCIES',
                'META-INF/LICENSE',
                'META-INF/LICENSE.txt',
                'META-INF/LICENSE.md',
                'META-INF/NOTICE',
                'META-INF/NOTICE.txt',
                'META-INF/NOTICE.md',
                'META-INF/*.kotlin_module'
            ]
        }
    }

    // Domyslnie AGP nazywa plik wyjsciowy wg nazwy modulu ("app-debug.apk"),
    // niezaleznie od android:label aplikacji. Nadpisujemy nazwe pliku
    // wyjsciowego na prosta, stala nazwe "FinArs.apk" (bez wersji/wariantu
    // w nazwie — sama wersja jest widoczna w samej aplikacji po instalacji).
    applicationVariants.all { variant ->
        variant.outputs.all { output ->
            outputFileName = "FinArs.apk"
        }
    }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib:1.9.0"
    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
    implementation "androidx.core:core-ktx:1.10.1"
    implementation "androidx.appcompat:appcompat:1.6.1"
    // Update: нужны для перехода MineActivity -> MineFragment (единый MainActivity-хост
    // с постоянным баннером/нав-баром) — Fragment.viewLifecycleOwner.lifecycleScope
    // безопасно останавливает фоновые корутины при уничтожении view фрагмента.
    implementation "androidx.fragment:fragment-ktx:1.6.2"
    implementation "androidx.lifecycle:lifecycle-runtime-ktx:2.7.0"
    implementation "androidx.activity:activity-ktx:1.7.2"
    implementation "com.google.android.material:material:1.9.0"
    implementation "androidx.constraintlayout:constraintlayout:2.1.4"
    implementation "androidx.recyclerview:recyclerview:1.2.1"
    implementation "androidx.room:room-runtime:2.5.0"
    ksp "androidx.room:room-compiler:2.5.0"
    implementation "androidx.room:room-ktx:2.5.0"
    implementation "org.apache.poi:poi-ooxml:5.2.3"
    implementation "androidx.multidex:multidex:2.0.1"
    // Update: прямой com.android.billingclient:billing-ktx убран — реальный биллинг
    // теперь идёт через RevenueCat (см. SubscriptionService.kt), который тянет свой
    // billing client сам; отдельная зависимость только создавала риск конфликта версий.
    implementation "com.google.android.gms:play-services-ads:23.6.0"
    implementation "com.google.android.ump:user-messaging-platform:3.1.0"
    implementation "androidx.biometric:biometric:1.1.0"
    implementation "androidx.work:work-runtime-ktx:2.9.0"
    implementation "com.tom-roush:pdfbox-android:2.0.27.0"

    // RevenueCat: единый Pro-доступ (Monthly/Yearly) поверх Google Play Billing И
    // Samsung IAP (Galaxy Store) — см. SubscriptionService.kt / StoreDetector.kt.
    // "purchases" по умолчанию поддерживает Google Play; "purchases-store-galaxy"
    // добавляет поддержку Samsung Galaxy Store (используется runtime-конфигурацией
    // GalaxyConfiguration, выбирается автоматически в зависимости от того, откуда
    // установлено приложение — см. StoreDetector.kt).
    implementation "com.revenuecat.purchases:purchases:10.15.1"
    implementation "com.revenuecat.purchases:purchases-store-galaxy:10.15.1"

    // Update 41: OCR чеков (ML Kit, работает на устройстве, без интернета).
    // Примечание: у Google ML Kit нет on-device модели для кириллицы, поэтому
    // используется только латинский распознаватель (он же нормально читает цифры).
    implementation "com.google.mlkit:text-recognition:16.0.0"

    // Update 41: сканирование штрихкодов для склада (ZXing, без OpenCV)
    implementation "com.journeyapps:zxing-android-embedded:4.3.0"

    // Update 65: pelny ekran + realne rozmycie tla pod paskiem statusu i pod
    // dolnym paskiem nawigacji (jak w Revolut) — patrz EdgeToEdge.kt.
    implementation "com.github.Dimezis:BlurView:version-3.2.0"
}
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_about.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_about.xml")"
cat > "app/src/main/res/layout/activity_about.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="24dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="18dp">

            <ImageView
                android:id="@+id/iv_back"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:src="@drawable/ic_back"
                android:clickable="true"
                android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>

            <TextView
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="wrap_content"
                android:layout_marginStart="12dp"
                android:text="@string/about_app"
                android:textColor="@color/text_primary"
                android:textSize="18sp"
                android:textStyle="bold"/>

        </LinearLayout>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="16dp">

            <ImageView
                android:layout_width="48dp"
                android:layout_height="48dp"
                android:src="@drawable/logo"/>

            <LinearLayout
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="wrap_content"
                android:orientation="vertical"
                android:layout_marginStart="12dp">
                <TextView
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:text="@string/app_subtitle"
                    android:textColor="@color/text_primary"
                    android:textSize="16sp"
                    android:textStyle="bold"/>
                <TextView
                    android:id="@+id/tv_about_version"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginTop="2dp"
                    android:textColor="@color/text_secondary"
                    android:textSize="12sp"/>
            </LinearLayout>

        </LinearLayout>

        <ScrollView
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:layout_marginBottom="16dp"
            android:clipToPadding="false">

            <LinearLayout
                android:id="@+id/ll_about_container"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical"/>

        </ScrollView>

        <Button
            android:id="@+id/btn_about_write"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:text="@string/dialog_write"
            android:textAllCaps="false"
            android:textSize="15sp"
            android:textColor="@color/text_primary"
            android:background="@drawable/btn_pill_primary"/>

    </LinearLayout>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_add_edit_product.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_add_edit_product.xml")"
cat > "app/src/main/res/layout/activity_add_edit_product.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="20dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/magazin_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <EditText android:id="@+id/et_name" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="14dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_name"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="14dp" android:gravity="center_vertical">
        <EditText android:id="@+id/et_barcode" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_barcode" android:textColorHint="@color/text_hint"
            android:textColor="@color/text_primary" android:inputType="number"/>
        <Button android:id="@+id/btn_scan_barcode_form" android:layout_width="56dp" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/btn_pill_outline"
            android:text="@string/scan_short" android:textAllCaps="false" android:textColor="@color/accent_cyan" android:textSize="11sp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:layout_marginEnd="8dp" android:text="@string/product_quantity" android:textColor="@color/text_secondary" android:textSize="12sp"/>
        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
            android:layout_marginStart="8dp" android:text="@string/product_unit" android:textColor="@color/text_secondary" android:textSize="12sp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginTop="4dp" android:layout_marginBottom="14dp" android:weightSum="2" android:baselineAligned="false">
        <EditText android:id="@+id/et_quantity" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginEnd="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_quantity" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>
        <EditText android:id="@+id/et_unit" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_unit" android:text="szt." android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="text"/>
    </LinearLayout>

    <EditText android:id="@+id/et_low_stock" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="14dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_low_stock"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>

    <EditText android:id="@+id/et_price" android:layout_width="match_parent" android:layout_height="56dp"
        android:layout_marginBottom="14dp" android:background="@drawable/input_field_bg"
        android:paddingStart="18dp" android:paddingEnd="18dp" android:hint="@string/product_price"
        android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="8dp" android:weightSum="2" android:baselineAligned="false">
        <EditText android:id="@+id/et_price_sell" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginEnd="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_price_sell" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal"/>
        <EditText android:id="@+id/et_margin" android:layout_width="0dp" android:layout_weight="1" android:layout_height="56dp"
            android:layout_marginStart="8dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:hint="@string/product_margin" android:textColorHint="@color/text_hint" android:textColor="@color/text_primary" android:inputType="numberDecimal|numberSigned"/>
    </LinearLayout>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginBottom="28dp" android:text="@string/product_margin_hint"
        android:textColor="@color/text_secondary" android:textSize="11sp"/>

    <Button android:id="@+id/btn_delete_product" android:layout_width="match_parent" android:layout_height="52dp"
        android:layout_marginBottom="12dp" android:background="@drawable/btn_pill_danger"
        android:text="@string/delete_entry" android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="15sp"
        android:visibility="gone"/>

    <Button android:id="@+id/btn_save_product" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary" android:text="@string/save" android:textAllCaps="false"
        android:textColor="@color/text_primary" android:textSize="17sp" android:textStyle="bold"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_add_entry.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_add_entry.xml")"
cat > "app/src/main/res/layout/activity_add_entry.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="26dp"
        android:paddingBottom="32dp">

        <!-- ===================== Header: X + tytul ===================== -->
        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="20dp">

            <ImageView
                android:id="@+id/btn_close"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center_vertical|start"
                android:src="@drawable/ic_close"
                android:clickable="true"
                android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>

            <TextView
                android:id="@+id/tv_add_title"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:text="@string/add_entry_title"
                android:textColor="@color/text_primary"
                android:textSize="18sp"
                android:textStyle="bold"/>

        </FrameLayout>

        <!-- ===================== Zakladki: Przychod / Wydatek / Faktura ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:orientation="horizontal"
            android:background="@drawable/input_field_bg"
            android:padding="4dp"
            android:layout_marginBottom="18dp"
            android:weightSum="3" android:baselineAligned="false">

            <Button
                android:id="@+id/btn_type_income"
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:background="@drawable/btn_pill_payment_selected"
                android:text="@string/type_income"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="13sp"
                android:minWidth="0dp" android:minHeight="0dp"/>

            <Button
                android:id="@+id/btn_type_expense"
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:layout_marginStart="4dp"
                android:background="@drawable/btn_pill_payment_unselected"
                android:text="@string/type_expense"
                android:textAllCaps="false"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"
                android:minWidth="0dp" android:minHeight="0dp"/>

            <Button
                android:id="@+id/btn_type_invoice"
                android:layout_width="0dp"
                android:layout_height="match_parent"
                android:layout_weight="1"
                android:layout_marginStart="4dp"
                android:background="@drawable/btn_pill_payment_unselected"
                android:text="@string/tab_invoice"
                android:textAllCaps="false"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"
                android:minWidth="0dp" android:minHeight="0dp"/>

        </LinearLayout>

        <!-- ===================== Kwota — duzy, wysrodkowany odczyt ===================== -->
        <EditText
            android:id="@+id/et_amount"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="22dp"
            android:background="@null"
            android:gravity="center"
            android:hint="@string/enter_amount"
            android:textColorHint="@color/text_hint"
            android:textColor="@color/text_primary"
            android:textSize="46sp"
            android:textStyle="bold"
            android:inputType="numberDecimal"/>

        <!-- ===================== Karta wierszy: Data / Kategoria / Komentarz / Paragon / Powtarzaj ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:layout_marginBottom="16dp">

            <!-- Data transakcji -->
            <LinearLayout
                android:id="@+id/btn_date"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:padding="16dp"
                android:clickable="true" android:focusable="true">
                <ImageView android:layout_width="20dp" android:layout_height="20dp" android:src="@drawable/ic_calendar"/>
                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical" android:layout_marginStart="14dp">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/entry_date_label" android:textColor="@color/text_secondary" android:textSize="12sp"/>
                    <TextView android:id="@+id/tv_date_value" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:textColor="@color/text_primary" android:textSize="14sp" android:layout_marginTop="2dp"/>
                </LinearLayout>
                <ImageView android:layout_width="16dp" android:layout_height="16dp" android:src="@drawable/ic_chevron_right"/>
            </LinearLayout>

            <View android:layout_width="match_parent" android:layout_height="1dp" android:background="@color/card_border"
                android:layout_marginStart="16dp" android:layout_marginEnd="16dp"/>

            <!-- Kategoria -->
            <LinearLayout
                android:id="@+id/btn_category"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:padding="16dp"
                android:clickable="true" android:focusable="true">
                <ImageView android:layout_width="20dp" android:layout_height="20dp" android:src="@drawable/ic_tag"/>
                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical" android:layout_marginStart="14dp">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/category_label" android:textColor="@color/text_secondary" android:textSize="12sp"/>
                    <TextView android:id="@+id/tv_category_value" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/category_choose" android:textColor="@color/text_primary" android:textSize="14sp" android:layout_marginTop="2dp"/>
                </LinearLayout>
                <ImageView android:layout_width="16dp" android:layout_height="16dp" android:src="@drawable/ic_chevron_right"/>
            </LinearLayout>

            <View android:layout_width="match_parent" android:layout_height="1dp" android:background="@color/card_border"
                android:layout_marginStart="16dp" android:layout_marginEnd="16dp"/>

            <!-- Komentarz -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:padding="16dp">
                <ImageView android:layout_width="20dp" android:layout_height="20dp" android:src="@drawable/ic_comment"/>
                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical" android:layout_marginStart="14dp">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/enter_comment" android:textColor="@color/text_secondary" android:textSize="12sp"/>
                    <EditText
                        android:id="@+id/et_comment"
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:layout_marginTop="2dp"
                        android:background="@null"
                        android:minHeight="0dp"
                        android:padding="0dp"
                        android:hint="@string/add_comment_hint"
                        android:textColorHint="@color/text_hint"
                        android:textColor="@color/text_primary"
                        android:textSize="14sp"
                        android:inputType="text"/>
                </LinearLayout>
            </LinearLayout>

            <View android:layout_width="match_parent" android:layout_height="1dp" android:background="@color/card_border"
                android:layout_marginStart="16dp" android:layout_marginEnd="16dp"/>

            <!-- Dodaj paragon / zdjecie -->
            <LinearLayout
                android:id="@+id/btn_attach"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:padding="16dp"
                android:clickable="true" android:focusable="true">
                <ImageView android:layout_width="20dp" android:layout_height="20dp" android:src="@drawable/ic_camera"/>
                <TextView android:id="@+id/tv_attach_label" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/attach_receipt_row" android:textColor="@color/text_primary" android:textSize="14sp"
                    android:layout_marginStart="14dp"/>
                <ImageView android:layout_width="16dp" android:layout_height="16dp" android:src="@drawable/ic_chevron_right"/>
            </LinearLayout>

            <View android:id="@+id/divider_recurring" android:layout_width="match_parent" android:layout_height="1dp" android:background="@color/card_border"
                android:layout_marginStart="16dp" android:layout_marginEnd="16dp"/>

            <!-- Powtarzaj co miesiac -->
            <LinearLayout
                android:id="@+id/row_recurring"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:padding="16dp">
                <ImageView android:layout_width="20dp" android:layout_height="20dp" android:src="@drawable/ic_repeat"/>
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/recurring_switch_label" android:textColor="@color/text_primary" android:textSize="14sp"
                    android:layout_marginStart="14dp"/>
                <Switch
                    android:id="@+id/sw_recurring"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:checked="false"/>
            </LinearLayout>

        </LinearLayout>

        <!-- ===================== Dodatkowe akcje: kategoria ryczaltu ===================== -->
        <!-- Update: przyciski "Skanuj paragon (autouzupelnianie)" i "Skanuj
             paragon z galerii" usuniete z interfejsu na wyrazna prosbe
             uzytkownika — pozostaje tylko recznie zalaczony paragon (wiersz
             "Dodaj paragon / zdjecie" powyzej). Metody OCR w Kotlinie
             (launchReceiptScan, pickOcrImage) zostaly bez wywolan z UI. -->
        <Button
            android:id="@+id/btn_ryczalt_category"
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:layout_marginBottom="20dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/ryczalt_category_choose"
            android:textAllCaps="false"
            android:textColor="@color/accent_cyan"
            android:textSize="14sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"
            android:visibility="gone"/>

        <Button
            android:id="@+id/btn_delete"
            android:layout_width="match_parent"
            android:layout_height="52dp"
            android:layout_marginBottom="12dp"
            android:background="@drawable/btn_pill_danger"
            android:text="@string/delete_entry"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:visibility="gone"/>

        <Button
            android:id="@+id/btn_save"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/save"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="17sp"
            android:textStyle="bold"/>

    </LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_add_invoice.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_add_invoice.xml")"
cat > "app/src/main/res/layout/activity_add_invoice.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/invoice_form_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <Button
        android:id="@+id/btn_invoice_history"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:layout_marginBottom="16dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/invoice_history_title"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="14sp"/>

    <!-- Sprzedawca -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_seller_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_seller_name" style="@style/InvoiceInput" android:hint="@string/seller_name" android:inputType="textPersonName"/>
        <EditText android:id="@+id/et_seller_nip" style="@style/InvoiceInput" android:hint="@string/seller_nip" android:inputType="number"/>
        <EditText android:id="@+id/et_seller_street" style="@style/InvoiceInput" android:hint="@string/seller_address_street" android:inputType="textPostalAddress"/>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
            <EditText android:id="@+id/et_seller_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/seller_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_seller_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/seller_address_city" android:inputType="text"/>
        </LinearLayout>
        <EditText android:id="@+id/et_seller_bank_account" style="@style/InvoiceInput" android:hint="@string/seller_bank_account" android:inputType="text"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginTop="12dp">

            <ImageView
                android:id="@+id/iv_seller_logo_preview"
                android:layout_width="40dp"
                android:layout_height="40dp"
                android:scaleType="centerInside"
                android:background="@drawable/card_bg"
                android:contentDescription="@string/upload_logo_button" />

            <Button
                android:id="@+id/btn_upload_logo"
                android:layout_width="0dp"
                android:layout_height="40dp"
                android:layout_weight="1"
                android:layout_marginStart="10dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/upload_logo_button"
                android:textAllCaps="false"
                android:textSize="12sp"
                android:textColor="@color/text_primary" />
        </LinearLayout>

    </LinearLayout>

    <!-- Nabywca -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_buyer_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <Button
            android:id="@+id/btn_select_contractor"
            android:layout_width="match_parent"
            android:layout_height="40dp"
            android:layout_marginBottom="12dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/select_contractor_button"
            android:textAllCaps="false"
            android:textSize="13sp"
            android:textColor="@color/text_primary"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_physical_person"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:checked="true"/>
            <TextView
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="10dp"
                android:text="@string/buyer_physical_person_switch"
                android:textColor="@color/text_primary"
                android:textSize="14sp"/>
        </LinearLayout>

        <EditText android:id="@+id/et_buyer_name" style="@style/InvoiceInput" android:hint="@string/buyer_name" android:inputType="textPersonName"/>
        <EditText android:id="@+id/et_buyer_nip" style="@style/InvoiceInput" android:hint="@string/buyer_nip" android:inputType="number" android:visibility="gone"/>
        <EditText android:id="@+id/et_buyer_street" style="@style/InvoiceInput" android:hint="@string/buyer_address_street" android:inputType="textPostalAddress"/>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:weightSum="2" android:baselineAligned="false">
            <EditText android:id="@+id/et_buyer_postal" style="@style/InvoiceInputHalfStart" android:hint="@string/buyer_address_postal" android:inputType="text"/>
            <EditText android:id="@+id/et_buyer_city" style="@style/InvoiceInputHalfEnd" android:hint="@string/buyer_address_city" android:inputType="text"/>
        </LinearLayout>

        <Button
            android:id="@+id/btn_save_contractor"
            android:layout_width="match_parent"
            android:layout_height="40dp"
            android:layout_marginTop="12dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/save_contractor_button"
            android:textAllCaps="false"
            android:textSize="13sp"
            android:textColor="@color/text_primary"/>

    </LinearLayout>

    <!-- Usługa / towar -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/invoice_service_section"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="12dp"/>

        <!-- Позиции фактуры (до 20 шт., товар или услуга) — заполняются динамически,
             см. AddInvoiceActivity.addItemRow/item_invoice_line.xml. Кнопка "Dodaj
             towary z magazynu" добавляет позиции сюда же, а не отдельным полем. -->
        <LinearLayout
            android:id="@+id/ll_invoice_items"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"/>

        <Button
            android:id="@+id/btn_add_item_row"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginBottom="10dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/add_invoice_item_row"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

        <TextView
            android:id="@+id/tv_invoice_total"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textColor="@color/accent_cyan"
            android:textSize="15sp"
            android:textStyle="bold"
            android:gravity="end"
            android:layout_marginBottom="10dp"/>

        <Button
            android:id="@+id/btn_add_warehouse_items"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginTop="4dp"
            android:layout_marginBottom="10dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/add_from_warehouse"
            android:textAllCaps="false"
            android:textColor="@color/accent_cyan"
            android:textSize="13sp"/>

        <Button
            android:id="@+id/btn_service_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/service_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"/>

        <Button
            android:id="@+id/btn_payment_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/payment_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="14dp">
            <Switch
                android:id="@+id/sw_invoice_paid"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:checked="true"
                android:text="@string/invoice_paid_switch_label"
                android:textColor="@color/text_primary"/>
        </LinearLayout>

        <Button
            android:id="@+id/btn_due_date"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/input_field_bg"
            android:text="@string/invoice_due_date_label"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="15sp"
            android:gravity="start|center_vertical"
            android:paddingStart="18dp"
            android:paddingEnd="18dp"
            android:visibility="gone"/>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/payment_method_label"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:layout_marginBottom="8dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="3" android:baselineAligned="false">

            <Button
                android:id="@+id/btn_payment_cash"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginEnd="6dp"
                android:background="@drawable/btn_pill_payment_selected"
                android:text="@string/payment_method_cash"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_transfer"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="3dp" android:layout_marginEnd="3dp"
                android:background="@drawable/btn_pill_payment_unselected"
                android:text="@string/payment_method_transfer"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_payment_blik"
                android:layout_width="0dp" android:layout_height="46dp" android:layout_weight="1"
                android:layout_marginStart="6dp"
                android:background="@drawable/btn_pill_payment_unselected"
                android:text="@string/payment_method_blik"
                android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="13sp"/>

        </LinearLayout>

    </LinearLayout>

    <!-- Limit gotówki -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:background="@drawable/card_bg"
        android:padding="16dp"
        android:layout_marginBottom="20dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/cash_limit_title"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            android:textStyle="bold"
            android:letterSpacing="0.08"
            android:layout_marginBottom="10dp"/>

        <TextView android:id="@+id/tv_cash_limit_label" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
        <ProgressBar android:id="@+id/pb_cash_limit" style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>

        <TextView
            android:id="@+id/tv_cash_limit_warning"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:textColor="#FF6B6B"
            android:textSize="12sp"
            android:visibility="gone"/>

    </LinearLayout>

    <!-- Blokada wystawiania faktur: pokazywana, gdy przekroczono limit VAT (240 000 zł)
         lub limit gotówki dla osób fizycznych (20 000 zł), a odpowiednie potwierdzenie
         nie zostało jeszcze złożone w Ustawieniach (zob. VatComplianceHelper). -->
    <TextView
        android:id="@+id/tv_compliance_block_banner"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:background="@drawable/card_bg"
        android:backgroundTint="#33FF3B30"
        android:padding="14dp"
        android:layout_marginBottom="14dp"
        android:textColor="#FF3B30"
        android:textSize="13sp"
        android:textStyle="bold"
        android:visibility="gone"/>

    <!-- Update 63: stawka VAT jest teraz wybierana OSOBNO na każdej pozycji poniżej
         (zob. item_invoice_line.xml/btn_item_vat_rate) — ta podpowiedź tylko informuje o
         tym, widoczna gdy sprzedawca jest już zarejestrowanym podatnikiem VAT. -->
    <TextView
        android:id="@+id/tv_vat_rate_info"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="10dp"
        android:text="@string/vat_rate_per_item_info"
        android:textColor="@color/text_secondary"
        android:textSize="12sp"
        android:visibility="gone"/>

    <!-- "Do paragonu" — widoczne tylko po potwierdzeniu posiadania kasy fiskalnej. -->
    <LinearLayout
        android:id="@+id/row_is_receipt"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="14dp"
        android:visibility="gone">

        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="@string/invoice_is_receipt_label"
            android:textColor="@color/text_primary"
            android:textSize="14sp"/>

        <Switch
            android:id="@+id/sw_is_receipt"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"/>

    </LinearLayout>

    <Button
        android:id="@+id/btn_generate"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/generate_invoice_button"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

    <LinearLayout
        android:id="@+id/row_after_generate"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:weightSum="2"
        android:baselineAligned="false"
        android:layout_marginBottom="14dp"
        android:visibility="gone">

        <Button
            android:id="@+id/btn_open_pdf"
            android:layout_width="0dp" android:layout_height="52dp" android:layout_weight="1"
            android:layout_marginEnd="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/open_pdf_button"
            android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="14sp"/>

        <Button
            android:id="@+id/btn_share"
            android:layout_width="0dp" android:layout_height="52dp" android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/share_invoice_button"
            android:textAllCaps="false" android:textColor="@color/text_primary" android:textSize="14sp"/>

    </LinearLayout>

    <Button
        android:id="@+id/btn_open_folder"
        android:layout_width="match_parent"
        android:layout_height="52dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/open_invoices_folder_button"
        android:textAllCaps="false"
        android:textColor="@color/accent_cyan"
        android:textSize="14sp"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_add_invoice_correction.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_add_invoice_correction.xml")"
cat > "app/src/main/res/layout/activity_add_invoice_correction.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
    android:paddingTop="28dp" android:paddingBottom="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="20dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/correction_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <LinearLayout
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg"
        android:padding="16dp" android:layout_marginBottom="18dp">
        <TextView android:id="@+id/tv_original_invoice_info" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="14sp" android:layout_marginBottom="8dp"/>
        <TextView android:id="@+id/tv_original_amount" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_secondary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Update 62: wybór WIELU pozycji do korekty naraz — widoczny tylko gdy oryginalna
         faktura ma więcej niż 1 pozycję (dla faktur z jedną pozycją zachowanie jest jak
         dotychczas: kwota po korekcie odnosi się do całej faktury, pole et_corrected_amount
         poniżej). Przycisk btn_pick_items otwiera dialog w stylu aplikacji
         (AppDialog.showMultiCheckboxPicker) zamiast standardowego systemowego Spinnera. -->
    <LinearLayout android:id="@+id/ll_item_picker" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:visibility="gone" android:layout_marginBottom="14dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/correction_item_picker_hint" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
        <Button android:id="@+id/btn_pick_items" android:layout_width="match_parent" android:layout_height="52dp"
            android:text="@string/correction_pick_items_button" android:textAllCaps="false" android:textSize="14sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
        <TextView android:id="@+id/tv_no_items_selected" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/correction_no_items_selected_hint" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginTop="10dp"/>
        <LinearLayout android:id="@+id/ll_selected_items_amounts" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_corrected_amount_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_corrected_amount_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
    <EditText android:id="@+id/et_corrected_amount" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="14dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_reason_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
    <EditText android:id="@+id/et_reason" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:minLines="2" android:gravity="top|start"
        android:background="@drawable/input_field_bg" android:padding="18dp"
        android:textColor="@color/text_primary" android:inputType="textMultiLine"
        android:layout_marginBottom="16dp"/>

    <CheckBox android:id="@+id/cb_apply_to_income" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/correction_apply_to_income_label" android:textColor="@color/text_primary"
        android:textSize="13sp" android:checked="true" android:layout_marginBottom="24dp"/>

    <Button android:id="@+id/btn_save_correction" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/correction_save_button" android:textAllCaps="false" android:textSize="16sp"
        android:textStyle="bold" android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_history.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_history.xml")"
cat > "app/src/main/res/layout/activity_history.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="96dp">

        <!-- ===================== Header: tytul ===================== -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/transaction_history"
            android:textColor="@color/text_primary"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="20dp"/>

        <!-- ===================== Wyszukiwarka + filtr ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="16dp">

            <FrameLayout
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="46dp"
                android:background="@drawable/input_field_bg">

                <ImageView
                    android:layout_width="16dp"
                    android:layout_height="16dp"
                    android:layout_gravity="center_vertical|start"
                    android:layout_marginStart="14dp"
                    android:src="@drawable/ic_search"/>

                <EditText
                    android:id="@+id/et_search"
                    android:layout_width="match_parent"
                    android:layout_height="match_parent"
                    android:background="@null"
                    android:paddingStart="40dp"
                    android:paddingEnd="14dp"
                    android:hint="@string/history_search_hint"
                    android:textColorHint="@color/text_hint"
                    android:textColor="@color/text_primary"
                    android:textSize="13sp"
                    android:singleLine="true"
                    android:imeOptions="actionSearch"
                    android:inputType="text"/>
            </FrameLayout>

            <FrameLayout
                android:id="@+id/btn_filter_date"
                android:layout_width="46dp"
                android:layout_height="46dp"
                android:layout_marginStart="10dp"
                android:background="@drawable/input_field_bg"
                android:clickable="true"
                android:focusable="true">
                <ImageView
                    android:layout_width="18dp"
                    android:layout_height="18dp"
                    android:layout_gravity="center"
                    android:src="@drawable/ic_filter"/>
            </FrameLayout>

        </LinearLayout>

        <TextView
            android:id="@+id/btn_clear_search"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="end"
            android:padding="4dp"
            android:layout_marginBottom="4dp"
            android:text="✕"
            android:textColor="@color/text_secondary"
            android:textSize="14sp"
            android:textStyle="bold"
            android:clickable="true"
            android:focusable="true"
            android:visibility="gone"/>

        <TextView
            android:id="@+id/btn_filter_clear"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="end"
            android:padding="4dp"
            android:text="@string/filter_clear"
            android:textColor="@color/accent_cyan"
            android:textSize="12sp"
            android:clickable="true"
            android:focusable="true"
            android:visibility="gone"/>

        <!-- ===================== Zakladki: Wszystkie / Przychody / Wydatki ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:layout_marginBottom="14dp">

            <LinearLayout android:id="@+id/tab_all" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:orientation="vertical" android:gravity="center"
                android:clickable="true" android:focusable="true">
                <TextView android:id="@+id/tv_tab_all" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:text="@string/tx_all" android:textColor="@color/text_primary" android:textSize="14sp"
                    android:textStyle="bold" android:paddingBottom="8dp"/>
                <View android:id="@+id/indicator_all" android:layout_width="match_parent" android:layout_height="2dp"
                    android:background="@color/accent_blue_light"/>
            </LinearLayout>

            <LinearLayout android:id="@+id/tab_income" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:orientation="vertical" android:gravity="center"
                android:clickable="true" android:focusable="true">
                <TextView android:id="@+id/tv_tab_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:text="@string/tx_income" android:textColor="@color/text_secondary" android:textSize="14sp"
                    android:paddingBottom="8dp"/>
                <View android:id="@+id/indicator_income" android:layout_width="match_parent" android:layout_height="2dp"
                    android:background="@android:color/transparent"/>
            </LinearLayout>

            <LinearLayout android:id="@+id/tab_expense" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:orientation="vertical" android:gravity="center"
                android:clickable="true" android:focusable="true">
                <TextView android:id="@+id/tv_tab_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:text="@string/tx_expense" android:textColor="@color/text_secondary" android:textSize="14sp"
                    android:paddingBottom="8dp"/>
                <View android:id="@+id/indicator_expense" android:layout_width="match_parent" android:layout_height="2dp"
                    android:background="@android:color/transparent"/>
            </LinearLayout>

        </LinearLayout>

        <TextView
            android:id="@+id/tv_no_entries"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/no_entries"
            android:textColor="@color/text_secondary"
            android:textSize="15sp"
            android:visibility="gone"
            android:layout_marginTop="40dp"
            android:gravity="center"/>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/rv_history"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false"/>

    </LinearLayout>

    <include layout="@layout/bottom_nav_bar"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom"/>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_inventory.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_inventory.xml")"
cat > "app/src/main/res/layout/activity_inventory.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/inventory_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/inventory_hint"
        android:textColor="@color/text_secondary"
        android:textSize="13sp"
        android:lineSpacingExtra="2dp"
        android:layout_marginBottom="16dp"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="16dp">

        <Button
            android:id="@+id/btn_scan_inventory"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:layout_marginEnd="6dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/inventory_scan_button"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

        <Button
            android:id="@+id/btn_inventory_history"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:layout_marginStart="6dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/inventory_history_button"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

    </LinearLayout>

    <LinearLayout
        android:id="@+id/ll_inventory_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginBottom="16dp"/>

    <Button
        android:id="@+id/btn_save_inventory"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/inventory_save"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_inventory_history.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_inventory_history.xml")"
cat > "app/src/main/res/layout/activity_inventory_history.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="24dp">

        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="18dp">
            <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
                android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
                android:clickable="true" android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:text="@string/inventory_history_title"
                android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
        </FrameLayout>

        <TextView
            android:id="@+id/tv_inventory_history_empty"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/inventory_history_empty"
            android:textColor="@color/text_secondary"
            android:textSize="14sp"
            android:visibility="gone"
            android:layout_marginTop="24dp"
            android:gravity="center"/>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/rv_inventory_sessions"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false"/>

    </LinearLayout>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_invoice_history.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_invoice_history.xml")"
cat > "app/src/main/res/layout/activity_invoice_history.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="16dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/invoice_history_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <!-- Поисковая строка: номер / клиент / сумма -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="8dp">

        <EditText
            android:id="@+id/et_search"
            android:layout_width="0dp"
            android:layout_height="46dp"
            android:layout_weight="1"
            android:background="@drawable/input_field_bg"
            android:paddingStart="16dp"
            android:paddingEnd="16dp"
            android:hint="@string/invoice_search_hint"
            android:textColorHint="@color/text_hint"
            android:textColor="@color/text_primary"
            android:textSize="13sp"
            android:singleLine="true"
            android:imeOptions="actionSearch"
            android:inputType="text"/>

        <TextView
            android:id="@+id/btn_clear_search"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="8dp"
            android:padding="8dp"
            android:text="✕"
            android:textColor="@color/text_secondary"
            android:textSize="16sp"
            android:textStyle="bold"
            android:clickable="true"
            android:focusable="true"
            android:visibility="gone"/>
    </LinearLayout>

    <!-- Фильтр по диапазону дат -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="14dp">

        <Button
            android:id="@+id/btn_filter_date"
            android:layout_width="0dp"
            android:layout_height="38dp"
            android:layout_weight="1"
            android:layout_marginEnd="8dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/filter_date_range"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="12sp"
            android:minWidth="0dp"
            android:minHeight="0dp"
            android:paddingStart="10dp"
            android:paddingEnd="10dp"/>

        <Button
            android:id="@+id/btn_filter_clear"
            android:layout_width="wrap_content"
            android:layout_height="38dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/filter_clear"
            android:textAllCaps="false"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:minWidth="0dp"
            android:minHeight="0dp"
            android:paddingStart="10dp"
            android:paddingEnd="10dp"
            android:visibility="gone"/>
    </LinearLayout>

    <!-- Фильтр по статусу оплаты -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginBottom="14dp">

        <Button
            android:id="@+id/btn_status_all"
            android:layout_width="0dp"
            android:layout_height="38dp"
            android:layout_weight="1"
            android:layout_marginEnd="6dp"
            android:background="@drawable/btn_pill_payment_selected"
            android:text="@string/invoice_status_filter_all"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="12sp"
            android:minWidth="0dp"
            android:minHeight="0dp"/>

        <Button
            android:id="@+id/btn_status_paid"
            android:layout_width="0dp"
            android:layout_height="38dp"
            android:layout_weight="1"
            android:layout_marginEnd="6dp"
            android:background="@drawable/btn_pill_payment_unselected"
            android:text="@string/invoice_status_paid"
            android:textAllCaps="false"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:minWidth="0dp"
            android:minHeight="0dp"/>

        <Button
            android:id="@+id/btn_status_pending"
            android:layout_width="0dp"
            android:layout_height="38dp"
            android:layout_weight="1"
            android:background="@drawable/btn_pill_payment_unselected"
            android:text="@string/invoice_status_pending"
            android:textAllCaps="false"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:minWidth="0dp"
            android:minHeight="0dp"/>
    </LinearLayout>

    <TextView
        android:id="@+id/tv_no_invoices"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/no_invoices"
        android:textColor="@color/text_secondary"
        android:textSize="15sp"
        android:visibility="gone"
        android:layout_marginTop="40dp"
        android:gravity="center"/>

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rv_invoices"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:clipToPadding="false"/>

</LinearLayout>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_limits.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_limits.xml")"
cat > "app/src/main/res/layout/activity_limits.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="110dp">

        <!-- ===================== Header: strzalka wstecz + tytul ===================== -->
        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="20dp">

            <ImageView
                android:id="@+id/iv_back"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center_vertical|start"
                android:src="@drawable/ic_back"
                android:clickable="true"
                android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"
                android:contentDescription="@string/back"/>

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:text="@string/limits_title"
                android:textColor="@color/text_primary"
                android:textSize="18sp"
                android:textStyle="bold"/>

        </FrameLayout>

        <!-- ===================== Karta: Dzialalnosc nierejestrowana ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="16dp">

                <FrameLayout android:layout_width="40dp" android:layout_height="40dp"
                    android:background="@drawable/icon_badge_blue_bg">
                    <ImageView android:layout_width="18dp" android:layout_height="18dp"
                        android:layout_gravity="center" android:src="@drawable/ic_nav_list"/>
                </FrameLayout>

                <TextView
                    android:id="@+id/tv_monthly_title"
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="12dp"
                    android:text="@string/activity_type_niezarejestrowana"
                    android:textColor="@color/text_primary"
                    android:textSize="15sp"
                    android:textStyle="bold"/>

                <TextView
                    android:id="@+id/tv_monthly_percent"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:textColor="@color/badge_percent_blue"
                    android:textSize="18sp"
                    android:textStyle="bold"/>

            </LinearLayout>

            <TextView
                android:id="@+id/tv_monthly_amounts"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"
                android:layout_marginBottom="8dp"/>

            <ProgressBar android:id="@+id/pb_monthly" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
                android:layout_marginBottom="14dp"/>

            <TextView
                android:id="@+id/tv_monthly_remaining"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_primary"
                android:textSize="14sp"
                android:textStyle="bold"
                android:layout_marginBottom="2dp"/>

            <TextView
                android:id="@+id/tv_monthly_limit"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"/>

        </LinearLayout>

        <!-- ===================== Karta: Prog podatkowy ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="16dp">

                <FrameLayout android:layout_width="40dp" android:layout_height="40dp"
                    android:background="@drawable/icon_badge_green_bg">
                    <ImageView android:layout_width="18dp" android:layout_height="18dp"
                        android:layout_gravity="center" android:src="@drawable/ic_nav_chart"/>
                </FrameLayout>

                <TextView
                    android:id="@+id/tv_bracket_title"
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="12dp"
                    android:textColor="@color/text_primary"
                    android:textSize="15sp"
                    android:textStyle="bold"/>

                <TextView
                    android:id="@+id/tv_bracket_percent"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:textColor="@color/badge_percent_green"
                    android:textSize="18sp"
                    android:textStyle="bold"/>

            </LinearLayout>

            <TextView
                android:id="@+id/tv_bracket_amounts"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"
                android:layout_marginBottom="8dp"/>

            <ProgressBar android:id="@+id/pb_bracket" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
                android:layout_marginBottom="14dp"/>

            <TextView
                android:id="@+id/tv_bracket_remaining"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_primary"
                android:textSize="14sp"
                android:textStyle="bold"
                android:layout_marginBottom="2dp"/>

            <TextView
                android:id="@+id/tv_bracket_limit"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"/>

        </LinearLayout>

        <!-- ===================== Karta: O limitach ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:background="@drawable/card_bg"
            android:padding="18dp">

            <FrameLayout android:layout_width="34dp" android:layout_height="34dp"
                android:background="@drawable/icon_badge_blue_bg">
                <ImageView android:layout_width="18dp" android:layout_height="18dp"
                    android:layout_gravity="center" android:src="@drawable/ic_info"/>
            </FrameLayout>

            <LinearLayout
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="wrap_content"
                android:orientation="vertical"
                android:layout_marginStart="12dp">

                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="@string/limits_about_title"
                    android:textColor="@color/text_primary"
                    android:textSize="14sp"
                    android:textStyle="bold"
                    android:layout_marginBottom="4dp"/>

                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="@string/limits_about_desc"
                    android:textColor="@color/text_secondary"
                    android:textSize="13sp"
                    android:lineSpacingExtra="2dp"/>

            </LinearLayout>

        </LinearLayout>

    </LinearLayout>

    </ScrollView>

    <include layout="@layout/bottom_nav_bar"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom"/>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_notifications.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_notifications.xml")"
cat > "app/src/main/res/layout/activity_notifications.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="24dp">

        <!-- ===================== Header: strzalka wstecz + tytul + wyczysc ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="20dp">

            <ImageView
                android:id="@+id/iv_back"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:src="@drawable/ic_back"
                android:clickable="true"
                android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>

            <TextView
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="wrap_content"
                android:layout_marginStart="12dp"
                android:text="@string/notifications_title"
                android:textColor="@color/text_primary"
                android:textSize="18sp"
                android:textStyle="bold"/>

            <TextView
                android:id="@+id/tv_clear_all"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/notifications_clear_all"
                android:textColor="@color/accent_cyan"
                android:textSize="13sp"
                android:maxLines="1"
                android:clickable="true"
                android:focusable="true"
                android:padding="4dp"/>

        </LinearLayout>

        <TextView
            android:id="@+id/tv_no_notifications"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/notifications_empty"
            android:textColor="@color/text_secondary"
            android:textSize="15sp"
            android:gravity="center"
            android:layout_marginTop="60dp"
            android:visibility="gone"/>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/rv_notifications"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false"/>

    </LinearLayout>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_pit36.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_pit36.xml")"
cat > "app/src/main/res/layout/activity_pit36.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:paddingStart="20dp" android:paddingEnd="20dp"
        android:paddingTop="28dp" android:paddingBottom="24dp">

        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="18dp">
            <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
                android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
                android:clickable="true" android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:text="@string/settings_menu_pit36"
                android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
        </FrameLayout>

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/pit36_hint" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:lineSpacingExtra="2dp" android:layout_marginBottom="20dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="20dp">
        <Button android:id="@+id/btn_year_prev" android:layout_width="48dp" android:layout_height="48dp"
            android:text="−" android:textAllCaps="false" android:textSize="18sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
        <TextView android:id="@+id/tv_pit_year" android:layout_width="0dp" android:layout_weight="1"
            android:layout_height="wrap_content" android:gravity="center" android:textSize="20sp"
            android:textStyle="bold" android:textColor="@color/text_primary"/>
        <Button android:id="@+id/btn_year_next" android:layout_width="48dp" android:layout_height="48dp"
            android:text="+" android:textAllCaps="false" android:textSize="18sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_pit_form_code" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:textSize="13sp" android:textStyle="bold"
        android:textColor="@color/accent_cyan" android:layout_marginBottom="12dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="16dp"
        android:layout_marginBottom="20dp">

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_przychod" android:textColor="@color/text_secondary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_przychod" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/income_green" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_koszty" android:textColor="@color/text_secondary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_koszty" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/expense_red" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="10dp">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_dochod" android:textColor="@color/text_primary" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_dochod" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/text_primary" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal">
            <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                android:text="@string/pit_row_tax" android:textColor="@color/accent_cyan" android:textSize="14sp"/>
            <TextView android:id="@+id/tv_pit_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:textColor="@color/accent_cyan" android:textSize="14sp" android:textStyle="bold"/>
        </LinearLayout>

    </LinearLayout>

    <TextView android:id="@+id/tv_pit_data_status" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_data_status_missing" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_edit_pit_data" android:layout_width="match_parent" android:layout_height="52dp"
        android:text="@string/pit_edit_data_button" android:textAllCaps="false" android:textSize="15sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_generate_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/pit36_generate_button" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
        android:layout_marginBottom="10dp"/>

    <Button android:id="@+id/btn_generate_official_pit36" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/pit36_generate_official_button" android:textAllCaps="false" android:textSize="15sp"
        android:textColor="@color/accent_cyan" android:background="@drawable/btn_pill_outline"
        android:layout_marginBottom="8dp"/>

    <TextView android:id="@+id/tv_pit36_official_hint" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:textSize="11sp"
        android:textColor="@color/text_hint" android:layout_marginBottom="14dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit36_disclaimer" android:textSize="11sp"
        android:textColor="@color/text_hint"/>

    </LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_pit_data.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_pit_data.xml")"
cat > "app/src/main/res/layout/activity_pit_data.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
    android:paddingTop="28dp" android:paddingBottom="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="16dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/pit_data_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_data_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="18dp"/>

    <EditText android:id="@+id/et_first_name" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_first_name"/>
    <EditText android:id="@+id/et_last_name" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_last_name"/>
    <EditText android:id="@+id/et_pesel" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_pesel"
        android:inputType="number" android:maxLength="11"/>
    <EditText android:id="@+id/et_street" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_street"/>
    <EditText android:id="@+id/et_house_number" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_house_number"/>
    <EditText android:id="@+id/et_apartment_number" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_apartment_number"/>
    <EditText android:id="@+id/et_voivodeship" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_voivodeship"/>
    <EditText android:id="@+id/et_county" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_county"/>
    <EditText android:id="@+id/et_commune" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_commune"/>
    <EditText android:id="@+id/et_postal_code" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_postal_code"/>
    <EditText android:id="@+id/et_city" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_city"/>
    <EditText android:id="@+id/et_tax_office" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_tax_office"/>

    <View android:layout_width="match_parent" android:layout_height="1dp"
        android:background="#2A2E60" android:layout_marginTop="6dp" android:layout_marginBottom="18dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_reliefs_title" android:textSize="15sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="12dp"/>

    <EditText android:id="@+id/et_children_count" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_children_count"
        android:inputType="number"/>
    <EditText android:id="@+id/et_internet_relief" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_internet_relief"
        android:inputType="numberDecimal"/>
    <EditText android:id="@+id/et_ikze" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_ikze"
        android:inputType="numberDecimal"/>
    <EditText android:id="@+id/et_donations" android:layout_width="match_parent" android:layout_height="56dp" android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp" android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:layout_marginBottom="12dp" android:hint="@string/pit_donations"
        android:inputType="numberDecimal"/>

    <CheckBox android:id="@+id/cb_joint_spouse" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/pit_joint_spouse" android:textColor="@color/text_primary"
        android:layout_marginBottom="12dp"/>

    <!-- Блок полей супруга(и) — виден только если отмечено "Rozliczenie wspólnie z małżonkiem" -->
    <LinearLayout android:id="@+id/layout_spouse_block" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:visibility="gone" android:background="@drawable/card_bg"
        android:padding="16dp" android:layout_marginBottom="20dp">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/pit_spouse_data_title" android:textSize="14sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:layout_marginBottom="12dp"/>

        <!-- Переключатель NIP/PESEL для супруга(и) -->
        <RadioGroup android:id="@+id/rg_spouse_id_type" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="horizontal" android:layout_marginBottom="12dp">
            <RadioButton android:id="@+id/rb_spouse_nip" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:text="NIP" android:textColor="@color/text_primary" android:textSize="12sp" android:checked="true"/>
            <RadioButton android:id="@+id/rb_spouse_pesel" android:layout_width="0dp" android:layout_weight="1"
                android:layout_height="wrap_content" android:text="PESEL" android:textColor="@color/text_primary" android:textSize="12sp"/>
        </RadioGroup>

        <EditText android:id="@+id/et_spouse_id" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:hint="@string/pit_spouse_id_hint"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_spouse_first_name" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:hint="@string/pit_spouse_first_name_hint"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_spouse_last_name" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:hint="@string/pit_spouse_last_name_hint"
            android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_spouse_birth_date" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:hint="@string/pit_spouse_birth_date_hint"
            android:inputType="date" android:layout_marginBottom="12dp"/>

        <EditText android:id="@+id/et_spouse_income" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:textColorHint="@color/text_hint" android:hint="@string/pit_spouse_income_hint"
            android:inputType="numberDecimal"/>

    </LinearLayout>

    <Button android:id="@+id/btn_save_pit_data" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/save" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_privacy_policy.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_privacy_policy.xml")"
cat > "app/src/main/res/layout/activity_privacy_policy.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="24dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:layout_marginBottom="6dp">

            <ImageView
                android:id="@+id/iv_back"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:src="@drawable/ic_back"
                android:clickable="true"
                android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>

            <TextView
                android:layout_width="0dp"
                android:layout_weight="1"
                android:layout_height="wrap_content"
                android:layout_marginStart="12dp"
                android:text="@string/settings_menu_privacy"
                android:textColor="@color/text_primary"
                android:textSize="18sp"
                android:textStyle="bold"/>

        </LinearLayout>

        <TextView
            android:id="@+id/tv_privacy_updated"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="16dp"
            android:textColor="@color/text_hint"
            android:textSize="12sp"/>

        <ScrollView
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false">

            <LinearLayout
                android:id="@+id/ll_privacy_container"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical"/>

        </ScrollView>

    </LinearLayout>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_select_contractor.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_select_contractor.xml")"
cat > "app/src/main/res/layout/activity_select_contractor.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/select_contractor_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <TextView
        android:id="@+id/tv_contractors_empty"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="@string/contractors_empty"
        android:textColor="@color/text_secondary"
        android:textSize="14sp"
        android:visibility="gone"/>

    <LinearLayout
        android:id="@+id/ll_contractors_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_select_products.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_select_products.xml")"
cat > "app/src/main/res/layout/activity_select_products.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/select_products_title"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <LinearLayout
        android:id="@+id/ll_products_container"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginBottom="16dp"/>

    <Button
        android:id="@+id/btn_confirm_selection"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/save"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="17sp"
        android:textStyle="bold"/>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_settings_backup.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_backup.xml")"
cat > "app/src/main/res/layout/activity_settings_backup.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:paddingStart="20dp" android:paddingEnd="20dp"
        android:paddingTop="28dp" android:paddingBottom="24dp">

        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="20dp">
            <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
                android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
                android:clickable="true" android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:text="@string/settings_menu_backup"
                android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
        </FrameLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical" android:background="@drawable/card_bg" android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
                android:text="@string/backup_hint" android:textSize="13sp"
                android:textColor="@color/text_secondary" android:lineSpacingExtra="2dp"
                android:layout_marginBottom="14dp"/>

            <TextView android:id="@+id/tv_last_backup" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:text="@string/backup_never" android:textSize="12sp"
                android:textColor="@color/text_hint"/>

        </LinearLayout>

        <Button android:id="@+id/btn_backup_now" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/backup_create" android:textAllCaps="false" android:textSize="15sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
            android:layout_marginBottom="12dp"/>

        <Button android:id="@+id/btn_restore_now" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/backup_restore" android:textAllCaps="false" android:textSize="15sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="24dp"/>

        <Button android:id="@+id/btn_clear_all" android:layout_width="match_parent" android:layout_height="52dp"
            android:text="@string/clear_all_button" android:textAllCaps="false" android:textColor="@color/text_primary"
            android:background="@drawable/btn_pill_danger"/>

    </LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_settings_language.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_language.xml")"
cat > "app/src/main/res/layout/activity_settings_language.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:paddingStart="20dp" android:paddingEnd="20dp"
        android:paddingTop="28dp" android:paddingBottom="24dp">

        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="24dp">
            <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
                android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
                android:clickable="true" android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:text="@string/settings_menu_language"
                android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
        </FrameLayout>

        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical" android:background="@drawable/card_bg" android:padding="8dp">

            <Button android:id="@+id/btn_lang_en" android:layout_width="match_parent" android:layout_height="52dp"
                android:text="English" android:textAllCaps="false" android:textColor="@color/text_primary"
                android:background="@drawable/btn_pill_primary" android:layout_margin="6dp"/>
            <Button android:id="@+id/btn_lang_ru" android:layout_width="match_parent" android:layout_height="52dp"
                android:text="Русский" android:textAllCaps="false" android:textColor="@color/text_primary"
                android:background="@drawable/btn_pill_outline" android:layout_margin="6dp"/>
            <Button android:id="@+id/btn_lang_pl" android:layout_width="match_parent" android:layout_height="52dp"
                android:text="Polski" android:textAllCaps="false" android:textColor="@color/text_primary"
                android:background="@drawable/btn_pill_outline" android:layout_margin="6dp"/>

        </LinearLayout>

    </LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_settings_pro.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_pro.xml")"
cat > "app/src/main/res/layout/activity_settings_pro.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
        android:paddingTop="20dp" android:paddingBottom="28dp"
        android:layout_width="match_parent" android:layout_height="wrap_content">

        <!-- Header: back arrow + title -->
        <FrameLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="18dp">
            <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
                android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
                android:clickable="true" android:focusable="true"
                android:background="?attr/selectableItemBackgroundBorderless"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:text="@string/settings_menu_pro"
                android:textColor="@color/text_primary" android:textSize="20sp" android:textStyle="bold"/>
        </FrameLayout>

        <!-- Crown -->
        <ImageView
            android:layout_width="72dp" android:layout_height="72dp"
            android:layout_gravity="center_horizontal"
            android:layout_marginTop="8dp"
            android:src="@drawable/ic_crown_pro"/>

        <!-- Title -->
        <TextView android:id="@+id/tv_paywall_header"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginTop="18dp"
            android:gravity="center" android:textSize="24sp" android:textStyle="bold"/>

        <!-- Subtitle -->
        <TextView
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:gravity="center" android:text="@string/paywall_subtitle"
            android:textColor="@color/text_secondary" android:textSize="14sp" android:lineSpacingExtra="3dp"/>

        <!-- Feature list -->
        <LinearLayout
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical" android:layout_marginTop="26dp">

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="16dp">
                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_1"
                    android:textColor="@color/text_primary" android:textSize="15sp"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="16dp">
                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_2"
                    android:textColor="@color/text_primary" android:textSize="15sp"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="16dp">
                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_3"
                    android:textColor="@color/text_primary" android:textSize="15sp"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="16dp">
                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_4"
                    android:textColor="@color/text_primary" android:textSize="15sp"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical">
                <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_check_circle_green"/>
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:layout_marginStart="14dp" android:text="@string/paywall_feature_5"
                    android:textColor="@color/text_primary" android:textSize="15sp"/>
            </LinearLayout>
        </LinearLayout>

        <!-- Yearly plan card (selected / highlighted) -->
        <FrameLayout android:id="@+id/card_yearly"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:background="@drawable/card_plan_selected"
            android:padding="18dp"
            android:layout_marginTop="26dp"
            android:clickable="true" android:focusable="true">

            <LinearLayout
                android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical">

                <TextView android:id="@+id/tv_badge_yearly"
                    android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:background="@drawable/badge_pill_bg"
                    android:paddingStart="12dp" android:paddingEnd="12dp"
                    android:paddingTop="6dp" android:paddingBottom="6dp"
                    android:drawableStart="@drawable/ic_star_small" android:drawablePadding="6dp"
                    android:text="@string/paywall_badge"
                    android:textColor="@color/accent_cyan" android:textSize="11sp" android:textStyle="bold"
                    android:layout_marginBottom="14dp"/>

                <FrameLayout
                    android:layout_width="match_parent" android:layout_height="wrap_content">
                    <TextView
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_gravity="center_vertical|start"
                        android:text="@string/paywall_plan_yearly_title"
                        android:textColor="@color/text_primary" android:textSize="19sp" android:textStyle="bold"/>
                    <ImageView android:id="@+id/radio_yearly"
                        android:layout_width="24dp" android:layout_height="24dp"
                        android:layout_gravity="center_vertical|end"
                        android:src="@drawable/ic_radio_selected"/>
                </FrameLayout>

                <LinearLayout
                    android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="bottom"
                    android:layout_marginTop="10dp">
                    <TextView android:id="@+id/tv_price_yearly"
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/paywall_price_yearly_default"
                        android:textColor="@color/text_primary" android:textSize="28sp" android:textStyle="bold"/>
                    <TextView
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_marginStart="4dp" android:layout_marginBottom="3dp"
                        android:text="@string/paywall_per_year"
                        android:textColor="@color/text_secondary" android:textSize="15sp"/>
                </LinearLayout>

                <TextView android:id="@+id/tv_trial_yearly"
                    android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:layout_marginTop="8dp"
                    android:textColor="@color/income_green" android:textSize="13sp"/>

                <LinearLayout
                    android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="center_vertical"
                    android:layout_marginTop="8dp">
                    <ImageView android:layout_width="14dp" android:layout_height="14dp" android:src="@drawable/ic_tag_small"/>
                    <TextView
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_marginStart="6dp" android:text="@string/paywall_per_month_note"
                        android:textColor="@color/accent_blue_light" android:textSize="13sp"/>
                </LinearLayout>
            </LinearLayout>
        </FrameLayout>

        <!-- Monthly plan card -->
        <FrameLayout android:id="@+id/card_monthly"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:background="@drawable/card_plan_unselected"
            android:padding="18dp"
            android:layout_marginTop="14dp"
            android:clickable="true" android:focusable="true">

            <LinearLayout
                android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical">

                <FrameLayout
                    android:layout_width="match_parent" android:layout_height="wrap_content">
                    <TextView
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_gravity="center_vertical|start"
                        android:text="@string/paywall_plan_monthly_title"
                        android:textColor="@color/text_primary" android:textSize="19sp" android:textStyle="bold"/>
                    <ImageView android:id="@+id/radio_monthly"
                        android:layout_width="24dp" android:layout_height="24dp"
                        android:layout_gravity="center_vertical|end"
                        android:src="@drawable/ic_radio_unselected"/>
                </FrameLayout>

                <LinearLayout
                    android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="bottom"
                    android:layout_marginTop="10dp">
                    <TextView android:id="@+id/tv_price_monthly"
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/paywall_price_monthly_default"
                        android:textColor="@color/text_primary" android:textSize="28sp" android:textStyle="bold"/>
                    <TextView
                        android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_marginStart="4dp" android:layout_marginBottom="3dp"
                        android:text="@string/paywall_per_month"
                        android:textColor="@color/text_secondary" android:textSize="15sp"/>
                </LinearLayout>

                <TextView android:id="@+id/tv_trial_monthly"
                    android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:layout_marginTop="8dp"
                    android:textColor="@color/income_green" android:textSize="13sp"/>
            </LinearLayout>
        </FrameLayout>

        <!-- Status text (hidden unless already Pro / loading) -->
        <TextView android:id="@+id/tv_pro_status"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginTop="14dp"
            android:gravity="center" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:visibility="gone"/>

        <!-- CTA -->
        <FrameLayout android:id="@+id/btn_cta"
            android:layout_width="match_parent" android:layout_height="58dp"
            android:background="@drawable/btn_pill_cta"
            android:layout_marginTop="22dp"
            android:clickable="true" android:focusable="true">
            <LinearLayout
                android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_gravity="center" android:orientation="horizontal" android:gravity="center_vertical">
                <FrameLayout
                    android:layout_width="26dp" android:layout_height="26dp"
                    android:background="@drawable/circle_translucent_white">
                    <ImageView
                        android:layout_width="15dp" android:layout_height="15dp"
                        android:layout_gravity="center" android:src="@drawable/ic_crown_small"/>
                </FrameLayout>
                <TextView android:id="@+id/tv_cta"
                    android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:layout_marginStart="10dp" android:text="@string/paywall_cta"
                    android:textColor="@color/text_primary" android:textSize="17sp" android:textStyle="bold"/>
            </LinearLayout>
        </FrameLayout>

        <!-- Restore purchases -->
        <TextView android:id="@+id/tv_restore_purchases"
            android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center_horizontal"
            android:layout_marginTop="16dp"
            android:padding="8dp"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"
            android:text="@string/paywall_restore_purchases"
            android:textColor="@color/accent_blue_light" android:textSize="13sp" android:textStyle="bold"/>

        <!-- Footer -->
        <TextView android:id="@+id/tv_footer_cancel_anytime"
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginTop="18dp"
            android:gravity="center" android:text="@string/paywall_footer_1"
            android:textColor="@color/text_secondary" android:textSize="12sp" android:lineSpacingExtra="3dp"/>

        <LinearLayout
            android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center_horizontal"
            android:orientation="horizontal" android:gravity="center_vertical"
            android:layout_marginTop="10dp">
            <ImageView android:layout_width="14dp" android:layout_height="14dp" android:src="@drawable/ic_shield_check"/>
            <TextView
                android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginStart="6dp" android:text="@string/paywall_data_safe"
                android:textColor="@color/accent_blue_light" android:textSize="13sp"/>
        </LinearLayout>

        <TextView
            android:layout_width="match_parent" android:layout_height="wrap_content"
            android:layout_marginTop="12dp"
            android:gravity="center" android:text="@string/paywall_footer_2"
            android:textColor="@color/text_hint" android:textSize="11sp" android:lineSpacingExtra="3dp"/>

    </LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_settings_security.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_security.xml")"
cat > "app/src/main/res/layout/activity_settings_security.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
    android:paddingTop="28dp" android:paddingBottom="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/settings_menu_security"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/security_hint" android:textSize="13sp"
        android:textColor="@color/text_secondary" android:layout_marginBottom="20dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical"
        android:background="@drawable/card_bg" android:padding="16dp" android:layout_marginBottom="12dp">
        <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:text="@string/security_pin_switch" android:textSize="15sp" android:textColor="@color/text_primary"/>
        <Switch android:id="@+id/switch_pin" android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_change_pin" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/security_change_pin" android:textSize="14sp" android:textColor="@color/accent_cyan"
        android:padding="8dp" android:layout_marginBottom="12dp"/>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical"
        android:background="@drawable/card_bg" android:padding="16dp" android:layout_marginBottom="12dp">
        <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:text="@string/security_biometric_switch" android:textSize="15sp" android:textColor="@color/text_primary"/>
        <Switch android:id="@+id/switch_biometric" android:layout_width="wrap_content" android:layout_height="wrap_content"/>
    </LinearLayout>

</LinearLayout>
    </ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_settings_tax.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_tax.xml")"
cat > "app/src/main/res/layout/activity_settings_tax.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:fillViewport="true">

<LinearLayout
    android:orientation="vertical" android:paddingStart="20dp" android:paddingEnd="20dp"
    android:paddingTop="28dp" android:paddingBottom="24dp"
    android:layout_width="match_parent" android:layout_height="wrap_content">

    <FrameLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp">
        <ImageView android:id="@+id/iv_back" android:layout_width="24dp" android:layout_height="24dp"
            android:layout_gravity="center_vertical|start" android:src="@drawable/ic_back"
            android:clickable="true" android:focusable="true"
            android:background="?attr/selectableItemBackgroundBorderless"/>
        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
            android:layout_gravity="center" android:text="@string/settings_menu_tax"
            android:textColor="@color/text_primary" android:textSize="18sp" android:textStyle="bold"/>
    </FrameLayout>

    <!-- Форма деятельности -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_title" android:textSize="16sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/activity_type_hint" android:textSize="12sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <RadioGroup android:id="@+id/rg_activity_type" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="12dp"
        android:layout_marginBottom="16dp">

        <RadioButton android:id="@+id/rb_niezarejestrowana" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_niezarejestrowana_desc" android:textSize="12sp"
            android:textColor="#9AA0C0" android:paddingStart="32dp" android:paddingBottom="14dp"/>

        <!-- Update: приложение сфокусировано ИСКЛЮЧИТЕЛЬНО на Działalność
             Nierejestrowana — варианты Zarejestrowana JDG (skala/liniowy/ryczałt)
             скрыты из UI (visibility="gone"), поэтому пользователь физически не
             может их выбрать и rb_niezarejestrowana остаётся отмеченным всегда
             (это значение и так уже используется по умолчанию — см.
             ActivityTypeHelper.get()). Сами классы/RadioButton'ы намеренно
             оставлены в коде/разметке (не удалены), чтобы ничего не сломать в
             SettingsTaxActivity.kt (idFor map/rg.check и т.д.), если в будущем
             понадобится вернуть выбор формы деятельности. -->
        <RadioButton android:id="@+id/rb_jdg_skala" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_skala" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp" android:visibility="gone"/>

        <RadioButton android:id="@+id/rb_jdg_liniowy" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_liniowy" android:textColor="@color/text_primary" android:textSize="14sp"
            android:paddingBottom="10dp" android:visibility="gone"/>

        <RadioButton android:id="@+id/rb_jdg_ryczalt" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/activity_type_jdg_ryczalt" android:textColor="@color/text_primary" android:textSize="14sp"
            android:visibility="gone"/>

    </RadioGroup>

    <!-- Ставка ryczałtu больше не задаётся здесь одной общей цифрой — теперь она
         выбирается для каждой операции отдельно (доход / позиция фактуры), так как
         один человек может продавать товары и оказывать услуги с разными ставками. -->
    <LinearLayout android:id="@+id/layout_ryczalt_rate_hint" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/ryczalt_rate_moved_title" android:textSize="13sp" android:textStyle="bold"
            android:textColor="@color/accent_cyan" android:layout_marginBottom="4dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/ryczalt_rate_moved_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary"/>
    </LinearLayout>

    <!-- Минимальное вознаграждение (для лимита 75%) — актуально ТОЛЬКО для
         niezarejestrowana, для любого Zarejestrowana JDG блок скрыт целиком. -->
    <LinearLayout android:id="@+id/layout_min_wage" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/min_wage_label" android:textSize="13sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>
        <EditText android:id="@+id/et_min_wage" android:layout_width="match_parent" android:layout_height="56dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:inputType="numberDecimal"
            android:layout_marginBottom="8dp"/>
        <TextView android:id="@+id/tv_monthly_limit_preview" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textSize="12sp" android:textColor="#9AA0C0" android:layout_marginBottom="20dp"/>
    </LinearLayout>

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="16dp"
        android:layout_marginBottom="24dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:layout_marginBottom="8dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/tax_scale_description" android:textSize="13sp"
            android:textColor="@color/text_secondary"/>
    </LinearLayout>

    <!-- VAT: pole z galką pojawia się dopiero po przekroczeniu limitu 240 000 zł
         (widoczne też po już złożonym potwierdzeniu — jako informacja bez możliwości edycji). -->
    <LinearLayout android:id="@+id/layout_vat_compliance" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/vat_compliance_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="#FF3B30" android:layout_marginBottom="6dp"/>
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/vat_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_vat_registered" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/cb_vat_registered_label" android:textColor="@color/text_primary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Kasa fiskalna: analogiczne pole z galką po przekroczeniu limitu 20 000 zł gotówki. -->
    <LinearLayout android:id="@+id/layout_kasa_compliance" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="vertical" android:background="@drawable/card_bg" android:padding="14dp"
        android:visibility="gone" android:layout_marginBottom="16dp">
        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_title" android:textSize="15sp" android:textStyle="bold"
            android:textColor="#FF3B30" android:layout_marginBottom="6dp"/>
        <TextView android:id="@+id/tv_kasa_compliance_hint" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/kasa_compliance_hint" android:textSize="12sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="10dp"/>
        <CheckBox android:id="@+id/cb_kasa_fiskalna" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/cb_kasa_label" android:textColor="@color/text_primary" android:textSize="13sp"/>
    </LinearLayout>

    <!-- Częstotliwość powiadomień push — ile razy dziennie mogą przychodzić alerty
         o przekroczonych limitach i zaległych fakturach. -->
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/push_frequency_title" android:textSize="16sp" android:textStyle="bold"
        android:textColor="@color/text_primary" android:layout_marginBottom="4dp"/>
    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/push_frequency_hint" android:textSize="12sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginBottom="24dp">
        <EditText android:id="@+id/et_push_frequency" android:layout_width="0dp" android:layout_height="56dp"
            android:layout_weight="1" android:layout_marginEnd="10dp"
            android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
            android:textColor="@color/text_primary" android:inputType="number" android:maxLength="2"/>
        <Button android:id="@+id/btn_save_push_frequency" android:layout_width="wrap_content" android:layout_height="56dp"
            android:text="@string/save" android:textAllCaps="false" android:textSize="14sp"
            android:paddingStart="20dp" android:paddingEnd="20dp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>
    </LinearLayout>

    <TextView android:id="@+id/tv_other_income_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_title" android:textSize="18sp"
        android:textColor="@color/text_primary" android:layout_marginBottom="6dp"/>

    <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
        android:text="@string/other_income_hint" android:textSize="13sp"
        android:textColor="#9AA0C0" android:layout_marginBottom="10dp"/>

    <EditText android:id="@+id/et_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:background="@drawable/input_field_bg" android:paddingStart="18dp" android:paddingEnd="18dp"
        android:textColor="@color/text_primary" android:inputType="numberDecimal"
        android:layout_marginBottom="14dp"/>

    <Button android:id="@+id/btn_save_other_income" android:layout_width="match_parent" android:layout_height="56dp"
        android:text="@string/save" android:textAllCaps="false" android:textSize="16sp"
        android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"/>

</LinearLayout>
</ScrollView>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>

FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/activity_terms.xml"
mkdir -p "$(dirname "app/src/main/res/layout/activity_terms.xml")"
cat > "app/src/main/res/layout/activity_terms.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:paddingStart="20dp"
    android:paddingEnd="20dp"
    android:paddingTop="28dp"
    android:paddingBottom="24dp">

    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="18dp"
        android:gravity="center"
        android:text="@string/terms_title"
        android:textColor="@color/text_primary"
        android:textSize="18sp"
        android:textStyle="bold"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginBottom="16dp">

        <TextView
            android:id="@+id/tv_terms_body"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@drawable/card_bg"
            android:padding="16dp"
            android:textColor="@color/text_primary"
            android:textSize="14sp"
            android:lineSpacingExtra="4dp"/>

    </ScrollView>

    <TextView
        android:id="@+id/tv_terms_status"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="12dp"
        android:padding="12dp"
        android:background="@drawable/input_field_bg"
        android:textColor="@color/accent_cyan"
        android:textSize="13sp"
        android:visibility="gone"/>

    <CheckBox
        android:id="@+id/cb_terms_accept"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="14dp"
        android:text="@string/terms_checkbox_label"
        android:textColor="@color/text_primary"/>

    <Button
        android:id="@+id/btn_terms_accept"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_primary"
        android:text="@string/terms_accept_button"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:textStyle="bold"/>

    <Button
        android:id="@+id/btn_terms_close"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/dialog_close"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"
        android:visibility="gone"/>

</LinearLayout>

    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/fragment_magazin.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_magazin.xml")"
cat > "app/src/main/res/layout/fragment_magazin.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="152dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/magazin_title"
            android:textColor="@color/text_primary"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="18dp"/>

        <TextView
            android:id="@+id/tv_low_stock_banner"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@drawable/card_bg"
            android:padding="14dp"
            android:layout_marginBottom="14dp"
            android:textColor="@color/expense_red"
            android:textSize="13sp"
            android:textStyle="bold"
            android:visibility="gone"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="2"
            android:baselineAligned="false"
            android:layout_marginBottom="12dp">

            <Button
                android:id="@+id/btn_add_product_manual"
                android:layout_width="0dp"
                android:layout_height="52dp"
                android:layout_weight="1"
                android:layout_marginEnd="8dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/add_product_manually"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="13sp"/>

            <Button
                android:id="@+id/btn_scan_barcode"
                android:layout_width="0dp"
                android:layout_height="52dp"
                android:layout_weight="1"
                android:layout_marginStart="8dp"
                android:background="@drawable/btn_pill_primary"
                android:text="@string/scan_barcode"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="13sp"/>

        </LinearLayout>

        <Button
            android:id="@+id/btn_inventory"
            android:layout_width="match_parent"
            android:layout_height="48dp"
            android:layout_marginBottom="16dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/start_inventory"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="13sp"/>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/rv_products"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1"
            android:clipToPadding="false"/>

    </LinearLayout>

    <!-- Рекламный баннер и нижняя навигация теперь в MainActivity (общий,
         фиксированный контейнер поверх этого фрагмента) — не здесь. -->


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/fragment_mine.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_mine.xml")"
cat > "app/src/main/res/layout/fragment_mine.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="170dp">

        <!-- ===================== Header: mala ikona + nazwa + dzwonek ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:clipChildren="false"
            android:clipToPadding="false"
            android:layout_marginBottom="20dp">

            <ImageView
                android:id="@+id/iv_logo"
                android:layout_width="48dp"
                android:layout_height="48dp"
                android:adjustViewBounds="true"
                android:src="@drawable/logo"
                android:contentDescription="@string/app_name"/>

            <TextView
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="10dp"
                android:text="@string/app_subtitle"
                android:textColor="@color/text_primary"
                android:textSize="20sp"
                android:textStyle="bold"/>

            <FrameLayout
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginTop="6dp"
                android:layout_marginEnd="6dp"
                android:clipChildren="false"
                android:clipToPadding="false">

                <ImageView
                    android:id="@+id/iv_notifications"
                    android:layout_width="24dp"
                    android:layout_height="24dp"
                    android:padding="2dp"
                    android:src="@drawable/ic_bell"
                    android:contentDescription="@string/app_name"/>

                <TextView
                    android:id="@+id/tv_notif_badge"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_gravity="top|end"
                    android:layout_marginTop="-8dp"
                    android:layout_marginEnd="-8dp"
                    android:minWidth="18dp"
                    android:minHeight="18dp"
                    android:gravity="center"
                    android:includeFontPadding="false"
                    android:paddingStart="4dp"
                    android:paddingEnd="4dp"
                    android:paddingTop="2dp"
                    android:paddingBottom="2dp"
                    android:background="@drawable/badge_count_bg"
                    android:textColor="#FFFFFF"
                    android:textSize="10sp"
                    android:textStyle="bold"
                    android:visibility="gone"/>

            </FrameLayout>

        </LinearLayout>

        <!-- ===================== Karta Bilans ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg_balance"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/balance"
                android:textColor="@color/text_secondary"
                android:textSize="12sp"
                android:letterSpacing="0.08"/>

            <TextView
                android:id="@+id/tv_balance"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginTop="4dp"
                android:layout_marginBottom="6dp"
                android:text="0.00"
                android:textColor="@color/text_primary"
                android:textSize="32sp"
                android:textStyle="bold"/>

            <!-- Update: napis "vs poprzedni miesiąc" oraz odznaka trendu usunięte
                 na wyraźną prośbę użytkownika — jedyne odstępstwo od makietu. -->
            <TextView
                android:id="@+id/tv_balance_trend"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_marginBottom="16dp"
                android:visibility="gone"/>

            <View android:layout_width="match_parent" android:layout_height="1dp"
                android:background="@color/card_border" android:layout_marginBottom="14dp"/>

            <!-- Trzy kolumny: Przychod / Wydatek / Podatek -->
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:weightSum="3"
                android:baselineAligned="false">

                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/stat_income" android:textColor="@color/text_secondary" android:textSize="12sp"
                        android:layout_marginBottom="3dp"/>
                    <TextView android:id="@+id/tv_stat_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:textColor="@color/income_green" android:textSize="15sp" android:textStyle="bold"/>
                </LinearLayout>

                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/stat_expense" android:textColor="@color/text_secondary" android:textSize="12sp"
                        android:layout_marginBottom="3dp"/>
                    <TextView android:id="@+id/tv_stat_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:textColor="@color/expense_red" android:textSize="15sp" android:textStyle="bold"/>
                </LinearLayout>

                <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:orientation="vertical">
                    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:text="@string/stat_tax_short" android:textColor="@color/text_secondary" android:textSize="12sp"
                        android:layout_marginBottom="3dp"/>
                    <TextView android:id="@+id/tv_stat_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:textColor="@color/text_primary" android:textSize="15sp" android:textStyle="bold"/>
                </LinearLayout>

            </LinearLayout>

            <!-- Zachowane dla kompatybilnosci z MineActivity.kt (findViewById), niewidoczne na tym ekranie -->
            <TextView android:id="@+id/tv_stat_tax_label" android:layout_width="wrap_content" android:layout_height="wrap_content" android:visibility="gone"/>
            <TextView android:id="@+id/tv_stat_profit" android:layout_width="wrap_content" android:layout_height="wrap_content" android:visibility="gone"/>
            <TextView android:id="@+id/tv_stat_net_profit" android:layout_width="wrap_content" android:layout_height="wrap_content" android:visibility="gone"/>

        </LinearLayout>

        <TextView
            android:id="@+id/tv_limit_warning"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:background="@drawable/card_bg"
            android:backgroundTint="#3A1414"
            android:padding="14dp"
            android:layout_marginBottom="16dp"
            android:textColor="#FF6B6B"
            android:textSize="13sp"
            android:textStyle="bold"
            android:visibility="gone"/>

        <!-- ===================== Karta Limity ===================== -->
        <LinearLayout
            android:id="@+id/card_limits"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:clickable="true"
            android:focusable="true"
            android:foreground="?attr/selectableItemBackground"
            android:padding="16dp"
            android:layout_marginBottom="16dp">

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="14dp">
                <TextView
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:text="@string/limits_title"
                    android:textColor="@color/text_primary"
                    android:textSize="15sp"
                    android:textStyle="bold"/>
                <TextView
                    android:id="@+id/tv_edit_limits"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:text="@string/edit_limits"
                    android:textColor="@color/accent_cyan"
                    android:textSize="13sp"
                    android:padding="4dp"/>
            </LinearLayout>

            <LinearLayout android:id="@+id/layout_limit_monthly" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:layout_marginBottom="16dp">
                <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="8dp">
                    <FrameLayout android:layout_width="34dp" android:layout_height="34dp"
                        android:background="@drawable/icon_badge_blue_bg">
                        <ImageView android:layout_width="16dp" android:layout_height="16dp"
                            android:layout_gravity="center" android:src="@drawable/ic_nav_list"/>
                    </FrameLayout>
                    <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                        android:orientation="vertical" android:layout_marginStart="10dp">
                        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:text="@string/activity_type_niezarejestrowana"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                        <TextView android:id="@+id/tv_limit_monthly_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:layout_marginTop="2dp"
                            android:textColor="@color/text_secondary" android:textSize="12sp"/>
                    </LinearLayout>
                    <TextView android:id="@+id/tv_limit_monthly_percent" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_marginStart="8dp"
                        android:textColor="@color/badge_percent_blue" android:textSize="15sp" android:textStyle="bold"/>
                </LinearLayout>
                <ProgressBar android:id="@+id/pb_limit_monthly" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>
            </LinearLayout>

            <LinearLayout android:id="@+id/layout_limit_bracket" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:layout_marginBottom="4dp">
                <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="8dp">
                    <FrameLayout android:layout_width="34dp" android:layout_height="34dp"
                        android:background="@drawable/icon_badge_green_bg">
                        <ImageView android:layout_width="16dp" android:layout_height="16dp"
                            android:layout_gravity="center" android:src="@drawable/ic_nav_chart"/>
                    </FrameLayout>
                    <LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                        android:orientation="vertical" android:layout_marginStart="10dp">
                        <TextView android:id="@+id/tv_limit_bracket_title" android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                        <TextView android:id="@+id/tv_limit_bracket_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:layout_marginTop="2dp"
                            android:textColor="@color/text_secondary" android:textSize="12sp"/>
                    </LinearLayout>
                    <TextView android:id="@+id/tv_limit_bracket_percent" android:layout_width="wrap_content" android:layout_height="wrap_content"
                        android:layout_marginStart="8dp"
                        android:textColor="@color/badge_percent_green" android:textSize="15sp" android:textStyle="bold"/>
                </LinearLayout>
                <ProgressBar android:id="@+id/pb_limit_bracket" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>
            </LinearLayout>

            <!-- Limit zwolnienia z VAT (240 000 zł) - ukryty wizualnie na glownym ekranie na prosbe
                 uzytkownika, sama logika sprawdzania limitu i powiadomienia dzialaja dalej. -->
            <LinearLayout android:id="@+id/layout_limit_vat" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:visibility="gone">
                <TextView android:id="@+id/tv_limit_vat_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
                <ProgressBar android:id="@+id/pb_limit_vat" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>
            </LinearLayout>

        </LinearLayout>

        <!-- ===================== Karta Podsumowanie miesiaca ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="16dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/monthly_summary_title"
                android:textColor="@color/text_primary"
                android:textSize="15sp"
                android:textStyle="bold"
                android:layout_marginBottom="4dp"/>

            <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="8dp">
                <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/legend_dot" android:backgroundTint="@color/income_green"/>
                <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:layout_marginStart="6dp" android:layout_marginEnd="14dp"
                    android:text="@string/stat_income" android:textColor="@color/text_secondary" android:textSize="12sp"/>
                <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/legend_dot" android:backgroundTint="@color/expense_red"/>
                <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:layout_marginStart="6dp"
                    android:text="@string/stat_expense" android:textColor="@color/text_secondary" android:textSize="12sp"/>
            </LinearLayout>

            <com.example.fa_ksiegowy.DualLineChartView
                android:id="@+id/chart_monthly_summary"
                android:layout_width="match_parent"
                android:layout_height="140dp"/>

        </LinearLayout>

        <!-- ===================== Karta Ostatnie transakcje ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:layout_marginBottom="18dp">

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical"
                android:layout_marginBottom="10dp">
                <TextView
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:text="@string/recent_transactions_title"
                    android:textColor="@color/text_primary"
                    android:textSize="15sp"
                    android:textStyle="bold"/>
                <TextView
                    android:id="@+id/tv_view_all_entries"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:text="@string/view_all"
                    android:textColor="@color/accent_cyan"
                    android:textSize="13sp"
                    android:padding="4dp"/>
            </LinearLayout>

            <TextView
                android:id="@+id/tv_no_recent_entries"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/no_recent_transactions"
                android:textColor="@color/text_secondary"
                android:textSize="13sp"
                android:gravity="center"
                android:padding="16dp"
                android:visibility="gone"/>

            <androidx.recyclerview.widget.RecyclerView
                android:id="@+id/rv_recent_entries"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:nestedScrollingEnabled="false"/>

        </LinearLayout>

        <!-- Zachowane dla kompatybilnosci z MineActivity.kt - funkcje tych przyciskow przejal
             dolny pasek nawigacji, wiec sa ukryte, zeby uniknac powielonych przyciskow. -->
        <Button
            android:id="@+id/btn_add_entry"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/add_entry"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="17sp"
            android:textStyle="bold"
            android:visibility="gone"/>

        <Button
            android:id="@+id/btn_history"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/transaction_history"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="16sp"
            android:visibility="gone"/>

        <Button
            android:id="@+id/btn_invoices"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/nav_invoices"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="16sp"
            android:visibility="gone"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:visibility="gone"
            android:weightSum="2" android:baselineAligned="false">

            <Button
                android:id="@+id/btn_settings"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:minHeight="56dp"
                android:layout_weight="1"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/settings"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="12sp"/>

            <Button
                android:id="@+id/btn_reports"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:minHeight="56dp"
                android:layout_weight="1"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/generate_report"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="12sp"/>

        </LinearLayout>

        <!-- Рекламный баннер и нижняя навигация теперь в MainActivity (общий,
             фиксированный контейнер поверх этого фрагмента) — не здесь. -->

    </LinearLayout>
    </ScrollView>


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/fragment_report.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_report.xml")"
cat > "app/src/main/res/layout/fragment_report.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="170dp">

        <!-- ===================== Header: tytul + wybor okresu ===================== -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center"
            android:text="@string/reports_title"
            android:textColor="@color/text_primary"
            android:textSize="18sp"
            android:textStyle="bold"
            android:layout_marginBottom="14dp"/>

        <LinearLayout
            android:id="@+id/btn_period"
            android:layout_width="wrap_content"
            android:layout_height="38dp"
            android:layout_gravity="center_horizontal"
            android:orientation="horizontal"
            android:gravity="center_vertical"
            android:background="@drawable/input_field_bg"
            android:paddingStart="14dp"
            android:paddingEnd="10dp"
            android:layout_marginBottom="20dp"
            android:clickable="true" android:focusable="true">
            <TextView android:id="@+id/tv_period" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="@string/period_this_month" android:textColor="@color/text_primary" android:textSize="13sp"/>
            <ImageView android:layout_width="16dp" android:layout_height="16dp" android:layout_marginStart="6dp"
                android:src="@drawable/ic_chevron_down"/>
        </LinearLayout>

        <!-- ===================== Karta: Podsumowanie ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/report_summary"
                android:textColor="@color/text_primary"
                android:textSize="15sp"
                android:textStyle="bold"
                android:layout_marginBottom="16dp"/>

            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="horizontal"
                android:gravity="center_vertical">

                <com.example.fa_ksiegowy.DonutChartView
                    android:id="@+id/donut_chart"
                    android:layout_width="128dp"
                    android:layout_height="128dp"/>

                <LinearLayout
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="wrap_content"
                    android:orientation="vertical"
                    android:layout_marginStart="20dp">

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="10dp">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_income"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_income" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical" android:layout_marginBottom="10dp">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_expense"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_expense" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="horizontal" android:gravity="center_vertical">
                        <View android:layout_width="9dp" android:layout_height="9dp" android:background="@drawable/dot_tax"/>
                        <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                            android:text="@string/legend_tax" android:textColor="@color/text_secondary" android:textSize="13sp"
                            android:layout_marginStart="8dp"/>
                        <TextView android:id="@+id/tv_legend_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
                    </LinearLayout>

                </LinearLayout>

            </LinearLayout>

        </LinearLayout>

        <!-- ===================== Karta: rozklad procentowy ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <!-- Przychod -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/legend_income" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_income" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_income" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_income_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp" android:layout_marginBottom="14dp"/>

            <!-- Wydatki -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/legend_expense" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_expense" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_expense" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_expense_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp" android:layout_marginBottom="14dp"/>

            <!-- Podatek -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal"
                android:layout_marginBottom="6dp">
                <TextView android:id="@+id/tv_breakdown_tax_label" android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_breakdown_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <ProgressBar android:id="@+id/pb_tax" style="?android:attr/progressBarStyleHorizontal"
                android:layout_width="match_parent" android:layout_height="7dp" android:max="100"
                android:progressDrawable="@drawable/progress_bar_tax" android:layout_marginBottom="4dp"/>
            <TextView android:id="@+id/tv_breakdown_tax_pct" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:gravity="end" android:textColor="@color/text_secondary" android:textSize="11sp"/>

        </LinearLayout>

        <!-- ===================== Karta: Trend (6 miesiecy) ===================== -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="18dp"
            android:layout_marginBottom="16dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/trend_title"
                android:textColor="@color/text_primary"
                android:textSize="15sp"
                android:textStyle="bold"
                android:layout_marginBottom="14dp"/>

            <com.example.fa_ksiegowy.TrendLineChartView
                android:id="@+id/trend_chart"
                android:layout_width="match_parent"
                android:layout_height="140dp"/>

        </LinearLayout>

        <!-- ===================== Eksport raportu (funkcja zachowana z poprzedniej wersji ekranu — makieta jej nie pokazuje) ===================== -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/report_export_section"
            android:textColor="@color/text_secondary"
            android:textSize="12sp"
            android:layout_marginBottom="10dp"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:weightSum="3" android:baselineAligned="false">

            <Button android:id="@+id/btn_report_month" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/month" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
                android:layout_marginEnd="6dp" android:minWidth="0dp"/>

            <Button android:id="@+id/btn_report_year" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/year" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
                android:layout_marginEnd="6dp" android:minWidth="0dp"/>

            <Button android:id="@+id/btn_report_custom" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp"
                android:text="@string/custom_range" android:textAllCaps="false" android:textSize="12sp"
                android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
                android:minWidth="0dp"/>

        </LinearLayout>

    </LinearLayout>
    </ScrollView>

    <!-- Рекламный баннер и нижняя навигация теперь в MainActivity (общий,
         фиксированный контейнер поверх этого фрагмента) — не здесь. -->


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo "-> krok: nadpisanie app/src/main/res/layout/fragment_settings.xml"
mkdir -p "$(dirname "app/src/main/res/layout/fragment_settings.xml")"
cat > "app/src/main/res/layout/fragment_settings.xml" << 'FILEEOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <eightbitlab.com.blurview.BlurTarget
        android:id="@+id/blur_target"
        android:layout_width="match_parent"
        android:layout_height="match_parent">


    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <ScrollView
        android:layout_width="match_parent" android:layout_height="match_parent"
        android:clipToPadding="false"
        android:fillViewport="true">

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent" android:layout_height="wrap_content"
        android:paddingStart="20dp"
        android:paddingEnd="20dp"
        android:paddingTop="28dp"
        android:paddingBottom="170dp">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/settings" android:textSize="18sp" android:textStyle="bold"
            android:textColor="@color/text_primary" android:gravity="center" android:layout_marginBottom="20dp"/>

        <!-- Podatek i limity -->
        <LinearLayout android:id="@+id/btn_menu_tax" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_tax"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_tax"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Bezpieczenstwo -->
        <LinearLayout android:id="@+id/btn_menu_security" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_purple_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_security"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_security"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Kopia zapasowa (Pro) -->
        <LinearLayout android:id="@+id/btn_menu_backup" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_backup"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_backup"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Generuj PIT (Pro) -->
        <LinearLayout android:id="@+id/btn_menu_pit36" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_green_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_pit"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_pit36"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Jezyk -->
        <LinearLayout android:id="@+id/btn_menu_language" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_language"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_language"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Wersja Pro -->
        <LinearLayout android:id="@+id/btn_menu_pro" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_orange_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_pro"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_pro"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- O aplikacji -->
        <LinearLayout android:id="@+id/btn_menu_about" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_info"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/about_app"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Polityka prywatnosci (wymagana do publikacji w Google Play) -->
        <LinearLayout android:id="@+id/btn_menu_privacy" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_green_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_privacy"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_privacy"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

        <!-- Warunki korzystania -->
        <LinearLayout android:id="@+id/btn_menu_terms" style="@style/SettingsRow">
            <FrameLayout style="@style/SettingsRowIconBadge" android:background="@drawable/icon_badge_blue_bg">
                <ImageView style="@style/SettingsRowIcon" android:src="@drawable/ic_settings_terms"/>
            </FrameLayout>
            <TextView style="@style/SettingsRowLabel" android:text="@string/settings_menu_terms"/>
            <ImageView style="@style/SettingsRowChevron"/>
        </LinearLayout>

    </LinearLayout>
    </ScrollView>

    <!-- Рекламный баннер и нижняя навигация теперь в MainActivity (общий,
         фиксированный контейнер поверх этого фрагмента) — не здесь. -->


    </eightbitlab.com.blurview.BlurTarget>

</FrameLayout>
FILEEOF

echo ""
echo "=== Update 65 zastosowany. ==="
echo "Nastepny krok: zacommituj i wypchnij zmiany, np.:"
echo "  git add -A && git commit -m 'Update 65: fullscreen edge-to-edge + blur' && git push"
echo "GitHub Actions zbuduje nowy FinArs.apk automatycznie."
