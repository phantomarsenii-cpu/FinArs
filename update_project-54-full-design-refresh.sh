#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 54: pelny redesign UI wg makiety (dolny pasek nawigacji + animowane tlo + karty/przyciski/switche) ==="
echo "Co sie zmienia:"
echo " 1) Nowa paleta kolorow (colors.xml) blizsza makiecie - te same nazwy kolorow,"
echo "    wiec zmiana dziala automatycznie na >30 ekranach ktore juz z nich korzystaja."
echo " 2) Karty (card_bg), przyciski (btn_pill_primary/outline), pole tekstowe"
echo "    (input_field_bg) i pasek postepu limitow - odswiezone, wieksze zaokraglenia,"
echo "    cienka ramka, jak na makiecie."
echo " 3) KAZDY zwykly <Button> w calej aplikacji dostaje automatycznie (przez motyw,"
echo "    android:buttonStyle) delikatna animacje wcisniecia (scale 0.96) + ripple -"
echo "    bez zmiany choc jednego istniejacego layoutu przyciskow."
echo " 4) Switch (np. 'Powtarzaj co miesiac', PIN/biometria) dostaje kolory motywu -"
echo "    natywna animacja przelaczania Androida juz jest plynna, tylko przefarbowana."
echo " 5) Nowy AnimatedMeshBackgroundView - lekkie, wlasne (bez zadnych zasobow z"
echo "    zewnatrz) animowane tlo z 'siecia' swiecacych sie kropek, w kolorach appki -"
echo "    odpowiednik tla z drugiego zdjecia makiety, dodane na 4 glownych ekranach."
echo " 6) Nowy stale widoczny dolny pasek nawigacji (Start / Transakcje / [+] / Raporty /"
echo "    Ustawienia) - jak na makiecie - dodany do 4 glownych ekranow (MineActivity,"
echo "    HistoryActivity, ReportActivity, SettingsActivity), srodkowy przycisk [+]"
echo "    otwiera AddEntryActivity."
echo " 7) Zeby uniknac PODWOJNYCH przyciskow nawigacji (ten sam cel dostepny z dwoch"
echo "    miejsc na tym samym ekranie), przyciski 'Historia' / 'Ustawienia' / 'Raporty' /"
echo "    'Dodaj wpis' na ekranie startowym zostaly ukryte (visibility=gone) - ich"
echo "    funkcje przejal dolny pasek. Same ID i kod w MineActivity.kt NIE zostaly"
echo "    ruszone, wiec nic sie nie wywali."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Uruchom skrypt z korzenia projektu (tam, gdzie jest settings.gradle)"
    exit 1
fi

if [ -f "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt" ]; then
    echo "!!! Wyglada na to, ze update_project-54 zostal juz zastosowany (BottomNavBar.kt juz istnieje)"
    exit 1
fi

BACKUP_DIR=".update54_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/res/values/colors.xml" \
    "app/src/main/res/values/themes.xml" \
    "app/src/main/res/drawable/card_bg.xml" \
    "app/src/main/res/drawable/btn_pill_primary.xml" \
    "app/src/main/res/drawable/btn_pill_outline.xml" \
    "app/src/main/res/drawable/input_field_bg.xml" \
    "app/src/main/res/layout/activity_mine.xml" \
    "app/src/main/res/layout/activity_history.xml" \
    "app/src/main/res/layout/activity_report.xml" \
    "app/src/main/res/layout/activity_settings.xml" \
    "app/src/main/res/values/strings.xml" \
    "app/src/main/res/values-pl/strings.xml" \
    "app/src/main/res/values-ru/strings.xml" \
    "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/HistoryActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Backup zmienianych plikow zapisany w $BACKUP_DIR ---"

mkdir -p "$(dirname "app/src/main/res/values/colors.xml")"
cat > app/src/main/res/values/colors.xml << 'EOF_APP_SRC_MAIN_RES_VALUES_COLORS_XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bg_top">#060A1A</color>
    <color name="bg_glow">#1E3A8A</color>
    <color name="bg_bottom">#080C20</color>

    <color name="accent_cyan">#38BDF8</color>
    <color name="accent_blue_light">#3B82F6</color>
    <color name="accent_blue_dark">#1D4ED8</color>
    <color name="accent_purple">#8B7CF6</color>

    <color name="card_bg">#141B36</color>
    <color name="card_bg_light">#141B36</color>
    <color name="card_border">#232D57</color>
    <color name="nav_bar_bg">#0E1430</color>

    <color name="text_primary">#FFFFFF</color>
    <color name="text_secondary">#94A3C4</color>
    <color name="text_hint">#5B6690</color>

    <color name="income_green">#34D399</color>
    <color name="expense_red">#F87171</color>
</resources>
EOF_APP_SRC_MAIN_RES_VALUES_COLORS_XML

mkdir -p "$(dirname "app/src/main/res/values/themes.xml")"
cat > app/src/main/res/values/themes.xml << 'EOF_APP_SRC_MAIN_RES_VALUES_THEMES_XML'
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
        <item name="android:statusBarColor">@color/bg_top</item>
        <item name="android:navigationBarColor">@color/nav_bar_bg</item>
        <item name="android:windowBackground">@drawable/bg_gradient</item>
        <item name="android:textColorPrimary">@color/text_primary</item>
        <item name="android:textColorHint">@color/text_hint</item>
        <item name="android:buttonStyle">@style/Widget.FA.Button</item>
        <item name="android:switchStyle">@style/Widget.FA.Switch</item>
        <item name="android:progressBarStyleHorizontal">@style/Widget.FA.ProgressBar</item>
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
EOF_APP_SRC_MAIN_RES_VALUES_THEMES_XML

mkdir -p "$(dirname "app/src/main/res/color/switch_thumb_selector.xml")"
cat > app/src/main/res/color/switch_thumb_selector.xml << 'EOF_APP_SRC_MAIN_RES_COLOR_SWITCH_THUMB_SELECTOR_XML'
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_checked="true" android:color="@color/accent_blue_light"/>
    <item android:color="@color/text_secondary"/>
</selector>
EOF_APP_SRC_MAIN_RES_COLOR_SWITCH_THUMB_SELECTOR_XML

mkdir -p "$(dirname "app/src/main/res/color/switch_track_selector.xml")"
cat > app/src/main/res/color/switch_track_selector.xml << 'EOF_APP_SRC_MAIN_RES_COLOR_SWITCH_TRACK_SELECTOR_XML'
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_checked="true" android:color="@color/accent_blue_dark" android:alpha="0.7"/>
    <item android:color="@color/card_border" android:alpha="0.9"/>
</selector>
EOF_APP_SRC_MAIN_RES_COLOR_SWITCH_TRACK_SELECTOR_XML

mkdir -p "$(dirname "app/src/main/res/animator/btn_press_scale.xml")"
cat > app/src/main/res/animator/btn_press_scale.xml << 'EOF_APP_SRC_MAIN_RES_ANIMATOR_BTN_PRESS_SCALE_XML'
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_pressed="true">
        <set>
            <objectAnimator android:propertyName="scaleX" android:valueTo="0.96" android:valueType="floatType" android:duration="90"/>
            <objectAnimator android:propertyName="scaleY" android:valueTo="0.96" android:valueType="floatType" android:duration="90"/>
        </set>
    </item>
    <item>
        <set>
            <objectAnimator android:propertyName="scaleX" android:valueTo="1.0" android:valueType="floatType" android:duration="140"/>
            <objectAnimator android:propertyName="scaleY" android:valueTo="1.0" android:valueType="floatType" android:duration="140"/>
        </set>
    </item>
</selector>
EOF_APP_SRC_MAIN_RES_ANIMATOR_BTN_PRESS_SCALE_XML

mkdir -p "$(dirname "app/src/main/res/drawable/card_bg.xml")"
cat > app/src/main/res/drawable/card_bg.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_CARD_BG_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="20dp" />
    <solid android:color="@color/card_bg_light" />
    <stroke android:width="1dp" android:color="@color/card_border" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_CARD_BG_XML

mkdir -p "$(dirname "app/src/main/res/drawable/btn_pill_primary.xml")"
cat > app/src/main/res/drawable/btn_pill_primary.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PRIMARY_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="18dp" />
    <gradient
        android:angle="90"
        android:startColor="@color/accent_blue_light"
        android:endColor="@color/accent_blue_dark" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_PRIMARY_XML

mkdir -p "$(dirname "app/src/main/res/drawable/btn_pill_outline.xml")"
cat > app/src/main/res/drawable/btn_pill_outline.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_OUTLINE_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="18dp" />
    <solid android:color="@color/card_bg_light" />
    <stroke android:width="1dp" android:color="@color/card_border" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_BTN_PILL_OUTLINE_XML

mkdir -p "$(dirname "app/src/main/res/drawable/input_field_bg.xml")"
cat > app/src/main/res/drawable/input_field_bg.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_INPUT_FIELD_BG_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="16dp" />
    <solid android:color="@color/card_bg" />
    <stroke android:width="1dp" android:color="@color/card_border" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_INPUT_FIELD_BG_XML

mkdir -p "$(dirname "app/src/main/res/drawable/progress_bar_bg.xml")"
cat > app/src/main/res/drawable/progress_bar_bg.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_PROGRESS_BAR_BG_XML'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:id="@android:id/background">
        <shape android:shape="rectangle">
            <corners android:radius="8dp" />
            <solid android:color="@color/card_border" />
        </shape>
    </item>
    <item android:id="@android:id/progress">
        <clip>
            <shape android:shape="rectangle">
                <corners android:radius="8dp" />
                <gradient
                    android:angle="0"
                    android:startColor="@color/accent_blue_light"
                    android:endColor="@color/accent_cyan" />
            </shape>
        </clip>
    </item>
</layer-list>
EOF_APP_SRC_MAIN_RES_DRAWABLE_PROGRESS_BAR_BG_XML

mkdir -p "$(dirname "app/src/main/res/drawable/nav_bar_bg.xml")"
cat > app/src/main/res/drawable/nav_bar_bg.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_NAV_BAR_BG_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:topLeftRadius="24dp" android:topRightRadius="24dp" />
    <solid android:color="@color/nav_bar_bg" />
    <stroke android:width="1dp" android:color="@color/card_border" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_NAV_BAR_BG_XML

mkdir -p "$(dirname "app/src/main/res/drawable/fab_add_bg.xml")"
cat > app/src/main/res/drawable/fab_add_bg.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_FAB_ADD_BG_XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <gradient
        android:angle="90"
        android:startColor="@color/accent_blue_light"
        android:endColor="@color/accent_blue_dark" />
</shape>
EOF_APP_SRC_MAIN_RES_DRAWABLE_FAB_ADD_BG_XML

mkdir -p "$(dirname "app/src/main/res/drawable/ic_nav_home.xml")"
cat > app/src/main/res/drawable/ic_nav_home.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_HOME_XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M10,20v-6h4v6h5v-8h3L12,3 2,12h3v8z"/>
</vector>
EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_HOME_XML

mkdir -p "$(dirname "app/src/main/res/drawable/ic_nav_list.xml")"
cat > app/src/main/res/drawable/ic_nav_list.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_LIST_XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M3,13h2v-2H3V13zM3,17h2v-2H3V17zM3,9h2V7H3V9zM7,13h14v-2H7V13zM7,17h14v-2H7V17zM7,7v2h14V7H7z"/>
</vector>
EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_LIST_XML

mkdir -p "$(dirname "app/src/main/res/drawable/ic_nav_chart.xml")"
cat > app/src/main/res/drawable/ic_nav_chart.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_CHART_XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M5,9.2h3V19H5V9.2zM10.6,5h2.8v14h-2.8V5zM16.2,13H19v6h-2.8V13z"/>
</vector>
EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_CHART_XML

mkdir -p "$(dirname "app/src/main/res/drawable/ic_nav_settings.xml")"
cat > app/src/main/res/drawable/ic_nav_settings.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_SETTINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M3,17v2h6v-2H3zM3,5v2h10V5H3zM13,21v-2h8v-2h-8v-2h-2v6h2zM7,9v2H3v2h4v2h2V9H7zM21,13v-2H11v2h10zM15,9h2V7h4V5h-4V3h-2V9z"/>
</vector>
EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_SETTINGS_XML

mkdir -p "$(dirname "app/src/main/res/drawable/ic_nav_add.xml")"
cat > app/src/main/res/drawable/ic_nav_add.xml << 'EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_ADD_XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="26dp" android:height="26dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:pathData="M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/>
</vector>
EOF_APP_SRC_MAIN_RES_DRAWABLE_IC_NAV_ADD_XML

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AnimatedMeshBackgroundView.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AnimatedMeshBackgroundView.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ANIMATEDMESHBACKGROUNDVIEW_KT'
package com.example.fa_ksiegowy

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.sin
import kotlin.random.Random

/**
 * Lightweight animated "plexus" background (glowing dots slowly drifting,
 * connected by thin lines when close enough) — same visual family as the
 * design mockup's background image, but drawn natively so it costs no
 * extra assets and matches the app's own blue palette.
 *
 * Usage: put as the first child of a FrameLayout, full match_parent, with
 * the real screen content drawn on top of it.
 */
class AnimatedMeshBackgroundView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private data class Node(var x: Float, var y: Float, var vx: Float, var vy: Float, var r: Float)

    private val nodes = mutableListOf<Node>()
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#5B9CFF")
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#3B82F6")
        strokeWidth = 1.2f
    }
    private val maxLinkDist = 260f
    private var animator: ValueAnimator? = null
    private var seeded = false

    private fun seed(w: Int, h: Int) {
        if (seeded || w <= 0 || h <= 0) return
        seeded = true
        val count = ((w * h) / 42000f).toInt().coerceIn(14, 34)
        val rnd = Random(System.currentTimeMillis())
        repeat(count) {
            nodes.add(
                Node(
                    x = rnd.nextFloat() * w,
                    y = rnd.nextFloat() * h,
                    vx = (rnd.nextFloat() - 0.5f) * 0.35f,
                    vy = (rnd.nextFloat() - 0.5f) * 0.35f,
                    r = rnd.nextFloat() * 2.2f + 1.4f
                )
            )
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        seed(w, h)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        seed(width, height)
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 16
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                step()
                invalidate()
            }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }

    private fun step() {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        val t = System.currentTimeMillis() * 0.0002
        for (n in nodes) {
            n.x += n.vx + sin(t + n.y * 0.01).toFloat() * 0.06f
            n.y += n.vy
            if (n.x < -20 || n.x > w + 20) n.vx = -n.vx
            if (n.y < -20 || n.y > h + 20) n.vy = -n.vy
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val n = nodes
        for (i in n.indices) {
            for (j in i + 1 until n.size) {
                val a = n[i]; val b = n[j]
                val dx = a.x - b.x; val dy = a.y - b.y
                val dist = kotlin.math.sqrt(dx * dx + dy * dy)
                if (dist < maxLinkDist) {
                    linePaint.alpha = (60 * (1f - dist / maxLinkDist)).toInt().coerceIn(0, 60)
                    canvas.drawLine(a.x, a.y, b.x, b.y, linePaint)
                }
            }
        }
        for (node in n) {
            dotPaint.alpha = 130
            canvas.drawCircle(node.x, node.y, node.r, dotPaint)
        }
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ANIMATEDMESHBACKGROUNDVIEW_KT

mkdir -p "$(dirname "app/src/main/res/layout/bottom_nav_bar.xml")"
cat > app/src/main/res/layout/bottom_nav_bar.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_BOTTOM_NAV_BAR_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content">

    <LinearLayout
        android:id="@+id/nav_bar_bg"
        android:layout_width="match_parent"
        android:layout_height="72dp"
        android:layout_gravity="bottom"
        android:background="@drawable/nav_bar_bg"
        android:elevation="12dp"
        android:orientation="horizontal"
        android:gravity="center_vertical">

        <LinearLayout android:id="@+id/nav_start" android:layout_width="0dp" android:layout_height="match_parent"
            android:layout_weight="1" android:orientation="vertical" android:gravity="center"
            android:clickable="true" android:focusable="true" android:background="?attr/selectableItemBackgroundBorderless">
            <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_nav_home"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginTop="3dp" android:text="@string/nav_start" android:textSize="10sp"
                android:textColor="@color/text_secondary"/>
        </LinearLayout>

        <LinearLayout android:id="@+id/nav_transactions" android:layout_width="0dp" android:layout_height="match_parent"
            android:layout_weight="1" android:orientation="vertical" android:gravity="center"
            android:clickable="true" android:focusable="true" android:background="?attr/selectableItemBackgroundBorderless">
            <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_nav_list"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginTop="3dp" android:text="@string/nav_transactions" android:textSize="10sp"
                android:textColor="@color/text_secondary"/>
        </LinearLayout>

        <View android:layout_width="0dp" android:layout_height="match_parent" android:layout_weight="1"/>

        <LinearLayout android:id="@+id/nav_reports" android:layout_width="0dp" android:layout_height="match_parent"
            android:layout_weight="1" android:orientation="vertical" android:gravity="center"
            android:clickable="true" android:focusable="true" android:background="?attr/selectableItemBackgroundBorderless">
            <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_nav_chart"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginTop="3dp" android:text="@string/nav_reports" android:textSize="10sp"
                android:textColor="@color/text_secondary"/>
        </LinearLayout>

        <LinearLayout android:id="@+id/nav_settings" android:layout_width="0dp" android:layout_height="match_parent"
            android:layout_weight="1" android:orientation="vertical" android:gravity="center"
            android:clickable="true" android:focusable="true" android:background="?attr/selectableItemBackgroundBorderless">
            <ImageView android:layout_width="22dp" android:layout_height="22dp" android:src="@drawable/ic_nav_settings"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginTop="3dp" android:text="@string/nav_settings" android:textSize="10sp"
                android:textColor="@color/text_secondary"/>
        </LinearLayout>

    </LinearLayout>

    <ImageButton
        android:id="@+id/nav_add"
        android:layout_width="56dp"
        android:layout_height="56dp"
        android:layout_gravity="center_horizontal|bottom"
        android:layout_marginBottom="44dp"
        android:background="@drawable/fab_add_bg"
        android:src="@drawable/ic_nav_add"
        android:scaleType="center"
        android:elevation="14dp"
        android:stateListAnimator="@animator/btn_press_scale"
        android:contentDescription="@string/add_entry"/>

</FrameLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_BOTTOM_NAV_BAR_XML

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/BottomNavBar.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_BOTTOMNAVBAR_KT'
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
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_BOTTOMNAVBAR_KT

mkdir -p "$(dirname "app/src/main/res/layout/activity_mine.xml")"
cat > app/src/main/res/layout/activity_mine.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MINE_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
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
        android:paddingStart="24dp"
        android:paddingEnd="24dp"
        android:paddingTop="36dp"
        android:paddingBottom="110dp">

        <ImageView
                android:id="@+id/iv_logo"
                android:layout_width="120dp"
                android:layout_height="120dp"
                android:layout_gravity="center_horizontal"
                android:layout_marginBottom="4dp"
                android:adjustViewBounds="true"
                android:src="@drawable/logo"
                android:contentDescription="@string/app_name"/>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="center_horizontal"
            android:layout_marginTop="2dp"
            android:layout_marginBottom="20dp"
            android:text="@string/app_subtitle"
            android:textColor="@color/text_primary"
            android:textSize="24sp"
            android:textStyle="bold"/>

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="center_horizontal"
            android:text="@string/balance"
            android:textColor="@color/text_secondary"
            android:textSize="13sp"
            android:letterSpacing="0.1"/>

        <TextView
            android:id="@+id/tv_balance"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_gravity="center_horizontal"
            android:layout_marginBottom="16dp"
            android:text="0.00"
            android:textColor="@color/text_primary"
            android:textSize="34sp"
            android:textStyle="bold"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="16dp"
            android:layout_marginBottom="18dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/statistics"
                android:textColor="@color/text_secondary"
                android:textSize="11sp"
                android:textStyle="bold"
                android:letterSpacing="0.12"
                android:layout_marginBottom="10dp"/>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:layout_marginBottom="8dp">
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:text="@string/stat_income" android:textColor="@color/text_primary" android:textSize="15sp"/>
                <TextView android:id="@+id/tv_stat_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/income_green" android:textSize="15sp" android:textStyle="bold"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:layout_marginBottom="8dp">
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:text="@string/stat_expense" android:textColor="@color/text_primary" android:textSize="15sp"/>
                <TextView android:id="@+id/tv_stat_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/expense_red" android:textSize="15sp" android:textStyle="bold"/>
            </LinearLayout>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal" android:layout_marginBottom="8dp">
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:text="@string/stat_profit" android:textColor="@color/text_primary" android:textSize="15sp"/>
                <TextView android:id="@+id/tv_stat_profit" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/accent_cyan" android:textSize="15sp" android:textStyle="bold"/>
            </LinearLayout>

            <!-- Вертикальная раскладка (вместо строки "лейбл | сумма") специально для налога:
                 подпись может быть длинной ("прогрессивная шкала…"), и при переносе строки
                 в горизонтальной раскладке сумма визуально "влезала" внутрь текста подписи. -->
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:layout_marginBottom="8dp">
                <TextView android:id="@+id/tv_stat_tax_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:textColor="@color/text_secondary" android:textSize="15sp"/>
                <TextView android:id="@+id/tv_stat_tax" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:gravity="end" android:textColor="@color/text_secondary" android:textSize="15sp" android:textStyle="bold"/>
            </LinearLayout>

            <View android:layout_width="match_parent" android:layout_height="1dp"
                android:background="@color/card_border" android:layout_marginTop="6dp" android:layout_marginBottom="10dp"/>

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="horizontal">
                <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                    android:text="@string/stat_net_profit" android:textColor="@color/text_primary" android:textSize="16sp" android:textStyle="bold"/>
                <TextView android:id="@+id/tv_stat_net_profit" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/accent_cyan" android:textSize="16sp" android:textStyle="bold"/>
            </LinearLayout>

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

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="16dp"
            android:layout_marginBottom="18dp">

            <TextView
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:text="@string/limits_title"
                android:textColor="@color/text_secondary"
                android:textSize="11sp"
                android:textStyle="bold"
                android:letterSpacing="0.12"
                android:layout_marginBottom="12dp"/>

            <LinearLayout android:id="@+id/layout_limit_monthly" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical">
                <TextView android:id="@+id/tv_limit_monthly_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
                <ProgressBar android:id="@+id/pb_limit_monthly" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
                    android:layout_marginBottom="14dp"/>
            </LinearLayout>

            <LinearLayout android:id="@+id/layout_limit_bracket" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical">
                <TextView android:id="@+id/tv_limit_bracket_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
                <ProgressBar android:id="@+id/pb_limit_bracket" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
                    android:layout_marginBottom="14dp"/>
            </LinearLayout>

            <!-- Update: шкала лимита zwolnienia z VAT (240 000 zł) убрана с главного
                 экрана по просьбе пользователя — сама проверка лимита и уведомления
                 остаются рабочими (LimitsHelper/LimitsNotificationWorker), убран
                 только визуальный прогресс-бар здесь. -->
            <LinearLayout android:id="@+id/layout_limit_vat" android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:visibility="gone">
                <TextView android:id="@+id/tv_limit_vat_label" android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
                <ProgressBar android:id="@+id/pb_limit_vat" style="?android:attr/progressBarStyleHorizontal"
                    android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>
            </LinearLayout>

        </LinearLayout>

        <!-- Update (design refresh): "Dodaj wpis" / "Historia" / "Ustawienia" / "Raporty"
             na tym ekranie zostały ukryte (visibility=gone), bo te same akcje są teraz
             dostępne z poziomu dolnego paska nawigacji na każdym ekranie — usuwa to
             powielone przyciski widoczne na tym samym ekranie. Same widoki i ich ID
             zostają w layoucie, żeby istniejący kod w MineActivity.kt (findViewById /
             setOnClickListener) nie wymagał zmian i się nie wywalił. -->
        <Button
            android:id="@+id/btn_add_entry"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="20dp"
            android:background="@drawable/btn_pill_primary"
            android:text="@string/add_entry"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="17sp"
            android:textStyle="bold"
            android:elevation="4dp"
            android:visibility="gone"/>

        <Button
            android:id="@+id/btn_history"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="14dp"
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
            android:background="@drawable/btn_pill_outline"
            android:text="@string/nav_invoices"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="16sp"/>

        <Button
            android:id="@+id/btn_magazin"
            android:layout_width="match_parent"
            android:layout_height="56dp"
            android:layout_marginBottom="20dp"
            android:background="@drawable/btn_pill_outline"
            android:text="@string/nav_magazin"
            android:textAllCaps="false"
            android:textColor="@color/text_primary"
            android:textSize="16sp"
            android:visibility="gone"/>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:layout_marginTop="12dp"
            android:visibility="gone"
            android:weightSum="2" android:baselineAligned="false">

            <Button
                android:id="@+id/btn_settings"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:minHeight="56dp"
                android:layout_weight="1"
                android:layout_marginEnd="8dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/settings"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="12sp"
                android:maxLines="2"
                android:includeFontPadding="false"
                android:paddingTop="8dp"
                android:paddingBottom="8dp"
                android:paddingStart="6dp"
                android:paddingEnd="6dp"/>

            <Button
                android:id="@+id/btn_reports"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:minHeight="56dp"
                android:layout_weight="1"
                android:layout_marginStart="8dp"
                android:background="@drawable/btn_pill_outline"
                android:text="@string/generate_report"
                android:textAllCaps="false"
                android:textColor="@color/text_primary"
                android:textSize="12sp"
                android:maxLines="2"
                android:includeFontPadding="false"
                android:paddingTop="8dp"
                android:paddingBottom="8dp"
                android:paddingStart="6dp"
                android:paddingEnd="6dp"/>

        </LinearLayout>

        <FrameLayout
            android:id="@+id/ad_container"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="10dp"
            android:visibility="gone"
            />

        <TextView
            android:id="@+id/tv_ad_debug"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="6dp"
            android:text="Ad status: —"
            android:textColor="@color/text_secondary"
            android:textSize="11sp"
            />

    </LinearLayout>
    </ScrollView>

    <include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>

</FrameLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MINE_XML

mkdir -p "$(dirname "app/src/main/res/layout/activity_history.xml")"
cat > app/src/main/res/layout/activity_history.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_HISTORY_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:paddingStart="24dp"
        android:paddingEnd="24dp"
        android:paddingTop="36dp"
        android:paddingBottom="96dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/transaction_history"
            android:textSize="22sp"
            android:textStyle="bold"
            android:textColor="@color/accent_cyan"
            android:layout_marginBottom="14dp"/>

        <!-- Поисковая строка: комментарий / категория / сумма -->
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
                android:hint="@string/history_search_hint"
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

        <!-- Заголовок таблицы: Дата | Категория/Описание | Чек | Сумма -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:paddingStart="12dp"
            android:paddingEnd="12dp"
            android:paddingBottom="6dp">
            <TextView android:layout_width="72dp" android:layout_height="wrap_content"
                android:text="@string/report_col_date" android:textColor="@color/text_secondary"
                android:textSize="11sp" android:textStyle="bold" android:letterSpacing="0.06"/>
            <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
                android:layout_marginStart="8dp"
                android:text="@string/report_col_comment" android:textColor="@color/text_secondary"
                android:textSize="11sp" android:textStyle="bold" android:letterSpacing="0.06"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:layout_marginEnd="6dp"
                android:text="@string/history_col_receipt" android:textColor="@color/text_secondary"
                android:textSize="11sp" android:textStyle="bold"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:minWidth="72dp" android:gravity="end"
                android:text="@string/history_col_amount" android:textColor="@color/text_secondary"
                android:textSize="11sp" android:textStyle="bold" android:letterSpacing="0.06"/>
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

        <!-- Итоговая строка (SUMA / ИТОГО) -->
        <LinearLayout
            android:id="@+id/layout_totals"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:background="@drawable/card_bg"
            android:padding="14dp"
            android:layout_marginTop="10dp">

            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="4dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/report_total_income" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_totals_income" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/income_green" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="4dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/report_total_expense" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_totals_expense" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/expense_red" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:layout_marginBottom="4dp">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/report_total_tax" android:textColor="@color/text_secondary" android:textSize="13sp"/>
                <TextView android:id="@+id/tv_totals_tax" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/text_secondary" android:textSize="13sp" android:textStyle="bold"/>
            </LinearLayout>
            <View android:layout_width="match_parent" android:layout_height="1dp"
                android:background="@color/card_border" android:layout_marginTop="4dp" android:layout_marginBottom="6dp"/>
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal">
                <TextView android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content"
                    android:text="@string/report_total_net_profit" android:textColor="@color/text_primary" android:textSize="14sp" android:textStyle="bold"/>
                <TextView android:id="@+id/tv_totals_net_profit" android:layout_width="wrap_content" android:layout_height="wrap_content"
                    android:textColor="@color/accent_cyan" android:textSize="14sp" android:textStyle="bold"/>
            </LinearLayout>
        </LinearLayout>

    </LinearLayout>

    <include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>

</FrameLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_HISTORY_XML

mkdir -p "$(dirname "app/src/main/res/layout/activity_report.xml")"
cat > app/src/main/res/layout/activity_report.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_REPORT_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <com.example.fa_ksiegowy.AnimatedMeshBackgroundView
        android:layout_width="match_parent"
        android:layout_height="match_parent"/>

    <LinearLayout
        android:orientation="vertical" android:padding="24dp"
        android:paddingBottom="96dp"
        android:layout_width="match_parent" android:layout_height="match_parent">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/select_period" android:textSize="22sp" android:textStyle="bold"
            android:textColor="@color/accent_cyan" android:layout_marginBottom="24dp"/>

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/chart_title" android:textSize="14sp"
            android:textColor="@color/text_secondary" android:layout_marginBottom="8dp"/>

        <com.example.fa_ksiegowy.MonthlyBarChartView
            android:id="@+id/chart_monthly"
            android:layout_width="match_parent"
            android:layout_height="160dp"
            android:layout_marginBottom="24dp"/>

        <Button android:id="@+id/btn_report_month" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/month" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_report_year" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/year" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_report_custom" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/custom_range" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>

    </LinearLayout>

    <include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>

</FrameLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_REPORT_XML

mkdir -p "$(dirname "app/src/main/res/layout/activity_settings.xml")"
cat > app/src/main/res/layout/activity_settings.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_SETTINGS_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
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
        android:orientation="vertical" android:padding="24dp"
        android:paddingBottom="110dp"
        android:layout_width="match_parent" android:layout_height="wrap_content">

        <TextView android:layout_width="match_parent" android:layout_height="wrap_content"
            android:text="@string/settings" android:textSize="22sp" android:textStyle="bold"
            android:textColor="@color/accent_cyan" android:layout_marginBottom="24dp"/>

        <Button android:id="@+id/btn_menu_business" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_business" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_tax" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_tax" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <!-- Update: пункт меню "Безопасность" был потерян в одном из прошлых
             обновлений (сам экран SettingsSecurityActivity и вся логика PIN/Biometrics
             остались рабочими, но зайти в них было неоткуда) — возвращаем кнопку. -->
        <Button android:id="@+id/btn_menu_security" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_security" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_pit36" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_pit36" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_language" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_language" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_backup" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_backup" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_pro" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_pro" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_primary"
            android:layout_marginBottom="14dp"/>

        <Button android:id="@+id/btn_menu_terms" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/settings_menu_terms" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"
            android:layout_marginBottom="14dp"/>

        <View android:layout_width="match_parent" android:layout_height="1dp"
            android:background="@color/card_border" android:layout_marginTop="10dp" android:layout_marginBottom="24dp"/>

        <Button android:id="@+id/btn_menu_about" android:layout_width="match_parent" android:layout_height="56dp"
            android:text="@string/about_app" android:textAllCaps="false" android:textSize="16sp"
            android:textColor="@color/text_primary" android:background="@drawable/btn_pill_outline"/>

    </LinearLayout>
    </ScrollView>

    <include layout="@layout/bottom_nav_bar" android:layout_gravity="bottom"/>

</FrameLayout>
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_SETTINGS_XML

# --- Podpiecie dolnego paska nawigacji w 4 glownych ekranach (jedna linia po setContentView) ---
sed -i 's|setContentView(R.layout.activity_mine)|setContentView(R.layout.activity_mine)\n        BottomNavBar.attach(this, BottomNavBar.Tab.START)|' \
    "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt"

sed -i 's|setContentView(R.layout.activity_history)|setContentView(R.layout.activity_history)\n        BottomNavBar.attach(this, BottomNavBar.Tab.TRANSACTIONS)|' \
    "app/src/main/java/com/example/fa_ksiegowy/HistoryActivity.kt"

sed -i 's|setContentView(R.layout.activity_report)|setContentView(R.layout.activity_report)\n        BottomNavBar.attach(this, BottomNavBar.Tab.REPORTS)|' \
    "app/src/main/java/com/example/fa_ksiegowy/ReportActivity.kt"

sed -i 's|setContentView(R.layout.activity_settings)|setContentView(R.layout.activity_settings)\n        BottomNavBar.attach(this, BottomNavBar.Tab.SETTINGS)|' \
    "app/src/main/java/com/example/fa_ksiegowy/SettingsActivity.kt"

echo "--- Dopisano BottomNavBar.attach(...) w 4 activity ---"

# --- Nowe stringi etykiet dolnego paska (EN / PL / RU) ---
if [ -f "app/src/main/res/values/strings.xml" ] && ! grep -q "nav_start" "app/src/main/res/values/strings.xml"; then
    sed -i 's|</resources>|    <string name="nav_start">Start</string>\n    <string name="nav_transactions">Transactions</string>\n    <string name="nav_reports">Reports</string>\n    <string name="nav_settings">Settings</string>\n</resources>|' \
        "app/src/main/res/values/strings.xml"
fi
if [ -f "app/src/main/res/values-pl/strings.xml" ] && ! grep -q "nav_start" "app/src/main/res/values-pl/strings.xml"; then
    sed -i 's|</resources>|    <string name="nav_start">Start</string>\n    <string name="nav_transactions">Transakcje</string>\n    <string name="nav_reports">Raporty</string>\n    <string name="nav_settings">Ustawienia</string>\n</resources>|' \
        "app/src/main/res/values-pl/strings.xml"
fi
if [ -f "app/src/main/res/values-ru/strings.xml" ] && ! grep -q "nav_start" "app/src/main/res/values-ru/strings.xml"; then
    sed -i 's|</resources>|    <string name="nav_start">Старт</string>\n    <string name="nav_transactions">Транзакции</string>\n    <string name="nav_reports">Отчёты</string>\n    <string name="nav_settings">Настройки</string>\n</resources>|' \
        "app/src/main/res/values-ru/strings.xml"
fi
echo "--- Dopisano stringi nav_* (values / values-pl / values-ru) ---"

echo ""
echo "=== Gotowe. Co dalej: ==="
echo " 1) Sprawdz w Android Studio / przez 'git diff', czy wszystko wyglada ok."
echo " 2) Zbuduj APK jak zwykle (./gradlew assembleDebug lub przez GitHub Actions)."
echo " 3) git add -A && git commit -m 'update54: pelny redesign UI wg makiety' && git push"
echo ""
echo "Backup oryginalnych plikow: $BACKUP_DIR"
