#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 30: исправление ошибки рекламы 'Required XML attribute adSize was missing' ==="
echo "Баннер AdView раньше объявлялся прямо в XML без атрибута adSize —"
echo "из-за этого текущая версия Google Mobile Ads SDK показывала эту ошибку"
echo "вместо самой рекламы. Теперь AdView создаётся программно в коде и"
echo "кладётся в пустой FrameLayout-контейнер — это официально рекомендуемый"
echo "способ, гонки между инфлейтом XML и setAdSize()/adUnitId() больше нет."
echo ""

if [ ! -f "settings.gradle" ] || [ ! -d "app/src/main/java/com/example/fa_ksiegowy" ]; then
    echo "!!! Запусти скрипт из корня проекта FA_ksiegowy-main (там, где settings.gradle)"
    exit 1
fi

if [ ! -f "app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt" ]; then
    echo "!!! Не найден AdsManager.kt — сначала примени предыдущие обновления с рекламой"
    exit 1
fi

BACKUP_DIR=".update30_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
for f in \
    "app/src/main/res/layout/activity_mine.xml" \
    "app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt" \
    "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt"
do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
    fi
done
echo "--- Бэкап изменяемых файлов сохранён в $BACKUP_DIR ---"

echo ""
echo "--- Записываю обновлённые файлы ---"

mkdir -p "$(dirname "app/src/main/res/layout/activity_mine.xml")"
cat > app/src/main/res/layout/activity_mine.xml << 'EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MINE_XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:fillViewport="true">

<LinearLayout
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:paddingStart="24dp"
    android:paddingEnd="24dp"
    android:paddingTop="36dp"
    android:paddingBottom="16dp">

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
            android:background="#2A2E60" android:layout_marginTop="6dp" android:layout_marginBottom="10dp"/>

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

        <TextView android:id="@+id/tv_limit_monthly_label" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
        <ProgressBar android:id="@+id/pb_limit_monthly" style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
            android:layout_marginBottom="14dp"/>

        <TextView android:id="@+id/tv_limit_bracket_label" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
        <ProgressBar android:id="@+id/pb_limit_bracket" style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent" android:layout_height="8dp" android:max="100"
            android:layout_marginBottom="14dp"/>

        <TextView android:id="@+id/tv_limit_vat_label" android:layout_width="match_parent" android:layout_height="wrap_content"
            android:textColor="@color/text_primary" android:textSize="13sp" android:layout_marginBottom="4dp"/>
        <ProgressBar android:id="@+id/pb_limit_vat" style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent" android:layout_height="8dp" android:max="100"/>

    </LinearLayout>

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
        android:elevation="4dp"/>

    <Button
        android:id="@+id/btn_history"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="14dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/transaction_history"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>

    <Button
        android:id="@+id/btn_invoices"
        android:layout_width="match_parent"
        android:layout_height="56dp"
        android:layout_marginBottom="20dp"
        android:background="@drawable/btn_pill_outline"
        android:text="@string/nav_invoices"
        android:textAllCaps="false"
        android:textColor="@color/text_primary"
        android:textSize="16sp"/>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginTop="12dp"
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
EOF_APP_SRC_MAIN_RES_LAYOUT_ACTIVITY_MINE_XML
echo "OK: app/src/main/res/layout/activity_mine.xml"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADSMANAGER_KT'
package com.example.fa_ksiegowy

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

/**
 * Показ баннера только для пользователей без Pro.
 *
 * AdView создаётся программно (а не через XML-тег) и добавляется в
 * пустой FrameLayout-контейнер из разметки. Это осознанное решение: при
 * инфлейте `<com.google.android.gms.ads.AdView>` напрямую из XML без
 * атрибута adSize текущая версия Google Mobile Ads SDK показывает вместо
 * рекламы ошибку "Required XML attribute "adSize" was missing." —
 * потому что setAdSize()/adUnitId() в коде вызываются уже ПОСЛЕ инфлейта,
 * а SDK ожидает их либо в XML, либо до первого добавления View в иерархию.
 * Создание AdView(activity) в коде и его addView() в контейнер полностью
 * убирает эту гонку и является официально рекомендуемым способом.
 *
 * ВРЕМЕННО (для диагностики): каждый шаг пишет свой статус в debugView —
 * маленькую серую строку под баннером на главном экране. Это позволяет
 * увидеть причину, по которой реклама не показывается, прямо на экране
 * телефона, без logcat/adb. Когда реклама заработает стабильно — эту
 * строку и вызовы setDebugStatus можно убрать.
 */
object AdsManager {

    private var sdkInitialized = false
    private const val TEST_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"
    private const val PROD_BANNER_UNIT_ID = "ca-app-pub-9218963926031039/4293553475"

    private fun setDebugStatus(debugView: TextView?, text: String) {
        Log.i("AdsManager", "STATUS: $text")
        debugView?.text = "Ad status: $text"
    }

    /**
     * Создаёт AdView программно, кладёт его в [container] и запускает загрузку.
     * Возвращает созданный AdView — вызывающая Activity должна сохранить его
     * (например, в поле класса), чтобы вызвать destroy()/pause() в своём
     * жизненном цикле.
     */
    fun setupAndLoadBanner(activity: Activity, container: ViewGroup, debugView: TextView? = null): AdView {
        val adView = AdView(activity)
        container.removeAllViews()
        container.addView(adView)

        if (BillingManager.isPro(activity)) {
            container.visibility = View.GONE
            setDebugStatus(debugView, "hidden (Pro active)")
            return adView
        }

        setDebugStatus(debugView, "starting…")

        try {
            adView.setAdSize(AdSize.BANNER)

            val isDebuggable = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            adView.adUnitId = if (isDebuggable) TEST_BANNER_UNIT_ID else PROD_BANNER_UNIT_ID
            setDebugStatus(debugView, "isDebuggable=$isDebuggable, unit=${adView.adUnitId}")

            if (isDebuggable) {
                // Тестовый блок Google не требует согласия пользователя —
                // грузим его сразу, без UMP.
                initAndLoad(activity, container, adView, debugView)
                return adView
            }

            val consentInformation = UserMessagingPlatform.getConsentInformation(activity)
            val params = ConsentRequestParameters.Builder().build()

            consentInformation.requestConsentInfoUpdate(
                activity,
                params,
                {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { formError ->
                        if (formError != null) {
                            setDebugStatus(debugView, "consent form error: ${formError.message}")
                        }
                        if (consentInformation.canRequestAds()) {
                            initAndLoad(activity, container, adView, debugView)
                        } else {
                            setDebugStatus(debugView, "blocked — canRequestAds()=false (нужно опубликовать Privacy & messaging в AdMob)")
                        }
                    }
                },
                { requestError ->
                    setDebugStatus(debugView, "consent info update error: ${requestError.message}")
                }
            )

            if (consentInformation.canRequestAds() && !sdkInitialized) {
                initAndLoad(activity, container, adView, debugView)
            }
        } catch (e: Exception) {
            // Ловим вообще любое исключение на этом пути, чтобы оно не терялось молча —
            // выводим текст ошибки прямо на экран.
            setDebugStatus(debugView, "EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
        }

        return adView
    }

    private fun initAndLoad(activity: Activity, container: ViewGroup, adView: AdView, debugView: TextView?) {
        setDebugStatus(debugView, "initializing SDK…")
        if (!sdkInitialized) {
            sdkInitialized = true
            MobileAds.initialize(activity) {
                setDebugStatus(debugView, "SDK initialized, loading ad…")
            }
        }
        container.visibility = View.VISIBLE
        adView.adListener = object : AdListener() {
            override fun onAdLoaded() {
                setDebugStatus(debugView, "loaded OK ✅")
            }
            override fun onAdFailedToLoad(error: LoadAdError) {
                // errorCode 3 = ERROR_CODE_NO_FILL — самая частая причина для новых
                // рекламных блоков: у Google пока нет рекламы для показа именно вам.
                setDebugStatus(debugView, "FAILED code=${error.code} domain=${error.domain} msg=${error.message}")
            }
        }
        setDebugStatus(debugView, "loadAd() called…")
        adView.loadAd(AdRequest.Builder().build())
    }

    /** Вызывать сразу после успешной покупки Pro, чтобы мгновенно убрать баннер без перезапуска экрана. */
    fun hideBanner(container: ViewGroup, adView: AdView) {
        container.visibility = View.GONE
        adView.pause()
    }
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_ADSMANAGER_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt")"
cat > app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt << 'EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_MINEACTIVITY_KT'
package com.example.fa_ksiegowy

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.gms.ads.AdView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

class MineActivity : BaseActivity() {
    private lateinit var db: AppDatabase
    private var bannerAdView: AdView? = null

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* результат не критичен для UI */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_mine)
        db = AppDatabase.getInstance(this)

        // Единая кнопка добавления: выбор дохода/расхода происходит уже внутри
        // AddEntryActivity (переключатель с подсветкой выбранного варианта).
        // По умолчанию открываем на "доход", это чаще нужное действие.
        findViewById<Button>(R.id.btn_add_entry).setOnClickListener {
            startActivity(Intent(this, AddEntryActivity::class.java).putExtra("isIncome", true))
        }
        findViewById<Button>(R.id.btn_settings).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
        findViewById<Button>(R.id.btn_reports).setOnClickListener {
            startActivity(Intent(this, ReportActivity::class.java))
        }
        findViewById<Button>(R.id.btn_history).setOnClickListener {
            startActivity(Intent(this, HistoryActivity::class.java))
        }
        findViewById<Button>(R.id.btn_invoices).setOnClickListener {
            startActivity(Intent(this, AddInvoiceActivity::class.java))
        }


        bannerAdView = AdsManager.setupAndLoadBanner(
            this,
            findViewById<FrameLayout>(R.id.ad_container),
            findViewById(R.id.tv_ad_debug)
        )
        setupHiddenDevCodeGesture()
        requestNotificationPermissionIfNeeded()
        LimitsNotificationWorker.schedule(this)
    }

    /** На Android 13+ уведомления требуют явного разрешения — запрашиваем один раз при первом запуске экрана. */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    /**
     * Скрытый вход для разработчика: удержание пальца на логотипе 10 секунд открывает
     * диалог ввода кода. Никакой видимой кнопки/подсказки в UI нет — это сделано умышленно,
     * чтобы обычный пользователь не наткнулся на неё случайно.
     */
    private fun setupHiddenDevCodeGesture() {
        val handler = Handler(Looper.getMainLooper())
        val holdDurationMs = 10_000L
        var triggered = false

        val showCodeDialog = Runnable {
            if (triggered) return@Runnable
            triggered = true
            val input = EditText(this)
            input.hint = getString(R.string.enter_code_hint)
            AlertDialog.Builder(this)
                .setTitle(getString(R.string.enter_code_title))
                .setView(input)
                .setPositiveButton(getString(R.string.enter_code_apply)) { _, _ ->
                    val ok = BillingManager.tryUnlockWithDevCode(this, input.text.toString())
                    Toast.makeText(
                        this,
                        getString(if (ok) R.string.enter_code_success else R.string.enter_code_wrong),
                        Toast.LENGTH_SHORT
                    ).show()
                }
                .setNegativeButton(getString(R.string.dialog_close), null)
                .show()
        }

        findViewById<ImageView>(R.id.iv_logo).setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    triggered = false
                    handler.postDelayed(showCodeDialog, holdDurationMs)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(showCodeDialog)
                    true
                }
                else -> false
            }
        }
    }

    override fun onDestroy() {
        bannerAdView?.destroy()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        loadData()
        loadLimits()
        if (BillingManager.isPro(this)) {
            bannerAdView?.let { AdsManager.hideBanner(findViewById(R.id.ad_container), it) }
        }
    }

    private fun loadData() {
        CoroutineScope(Dispatchers.IO).launch {
            // Баланс/статистика/налог — только за текущий календарный год,
            // так как лимит 30 000 zł годовой (см. TaxHelper).
            val year = TaxHelper.currentYear()
            val (yearStart, yearEndExclusive) = TaxHelper.yearRange(year)
            val yearEntries = db.entryDao().getBetween(yearStart, yearEndExclusive - 1)

            val income = yearEntries.filter { it.isIncome }.sumOf { it.amount }
            val expense = yearEntries.filter { !it.isIncome }.sumOf { it.amount }
            val profit = income - expense

            val prefs = getSharedPreferences("settings", MODE_PRIVATE)
            val otherIncome = TaxHelper.getOtherIncome(prefs, year)
            val activityType = ActivityTypeHelper.get(prefs)
            val ryczaltRate = ActivityTypeHelper.getRyczaltRate(prefs)
            val taxResult = when (activityType) {
                ActivityType.NIEZAREJESTROWANA, ActivityType.JDG_SKALA -> TaxHelper.calc(profit, otherIncome)
                ActivityType.JDG_LINIOWY -> TaxHelper.calcLiniowy(profit)
                ActivityType.JDG_RYCZALT -> TaxHelper.calcRyczalt(income, ryczaltRate)
            }
            val taxLabelRes = when (activityType) {
                ActivityType.JDG_LINIOWY -> R.string.tax_label_liniowy
                ActivityType.JDG_RYCZALT -> R.string.tax_label_ryczalt
                else -> TaxHelper.taxLabelResId(profit)
            }

            withContext(Dispatchers.Main) {
                findViewById<TextView>(R.id.tv_balance).text = formatMoney(profit)
                findViewById<TextView>(R.id.tv_stat_income).text = formatMoney(income)
                findViewById<TextView>(R.id.tv_stat_expense).text = formatMoney(expense)
                findViewById<TextView>(R.id.tv_stat_profit).text = formatMoney(profit)
                // Динамическая подпись налога: "0% — необлагаемый минимум" / "12%" /
                // "Прогрессивная шкала 12%/32%" для skali, либо своя подпись для
                // liniowy/ryczałt — вместо одной фиксированной формулировки.
                findViewById<TextView>(R.id.tv_stat_tax_label).text = getString(taxLabelRes)
                findViewById<TextView>(R.id.tv_stat_tax).text = formatMoney(taxResult.tax)
                // Чистая прибыль = прибыль минус налог по выбранной форме налогообложения.
                findViewById<TextView>(R.id.tv_stat_net_profit).text = formatMoney(profit - taxResult.tax)
            }
        }
    }

    /** Обновляет три гейджа лимитов и красный баннер превышения лимита niezarejestrowanej działalności. */
    private fun loadLimits() {
        CoroutineScope(Dispatchers.IO).launch {
            val limits = LimitsHelper.compute(this@MineActivity)
            withContext(Dispatchers.Main) {
                findViewById<TextView>(R.id.tv_limit_monthly_label).text =
                    getString(
                        R.string.limit_monthly_label,
                        formatMoney(limits.monthly.current), formatMoney(limits.monthly.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_monthly).progress = limits.monthly.percent.coerceAtMost(100)

                findViewById<TextView>(R.id.tv_limit_bracket_label).text =
                    getString(
                        R.string.limit_bracket_label,
                        formatMoney(limits.bracket.current), formatMoney(limits.bracket.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_bracket).progress = limits.bracket.percent.coerceAtMost(100)

                findViewById<TextView>(R.id.tv_limit_vat_label).text =
                    getString(
                        R.string.limit_vat_label,
                        formatMoney(limits.vat.current), formatMoney(limits.vat.limit)
                    )
                findViewById<ProgressBar>(R.id.pb_limit_vat).progress = limits.vat.percent.coerceAtMost(100)

                val warning = findViewById<TextView>(R.id.tv_limit_warning)
                if (limits.activityType == ActivityType.NIEZAREJESTROWANA && limits.monthly.exceeded) {
                    warning.text = getString(R.string.limit_exceeded_warning)
                    warning.visibility = View.VISIBLE
                } else {
                    warning.visibility = View.GONE
                }
            }
        }
    }

    private fun formatMoney(v: Double): String = String.format(Locale.getDefault(), "%.2f", v)
}
EOF_APP_SRC_MAIN_JAVA_COM_EXAMPLE_FA_KSIEGOWY_MINEACTIVITY_KT
echo "OK: app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt"

echo ""
echo "=== Готово. Дальше вручную: ==="
echo "1) Пересобери APK:  ./gradlew assembleDebug"
echo "2) Проверь на главном экране:"
echo "   - под кнопками появился баннер без ошибки 'Required XML attribute adSize was missing'"
echo "   - в debug-строке 'Ad status: ...' в итоге видно 'loaded OK' или 'FAILED code=... (No fill — это нормально для новых блоков)'"
echo "   - для Pro-аккаунта баннер по-прежнему скрыт"
echo "3) Если всё ок:"
echo "   git add -A"
echo "   git commit -m 'Fix AdMob banner: create AdView programmatically instead of XML to fix missing adSize error'"
echo "   git push"
echo ""
echo "Бэкап изменённых файлов лежит в: $BACKUP_DIR — можно удалить после проверки."
