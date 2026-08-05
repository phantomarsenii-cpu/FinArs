#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "=== Обновление 25: видимая на экране строка статуса рекламы (для диагностики без adb) ==="
echo "Pro выключен, язык — русский, оба этих пункта не при чём. Раз баннер всё равно не"
echo "появляется — добавляем прямо на главный экран маленькую серую строку, которая"
echo "текстом покажет, что происходит с рекламой: грузится / загружена / ошибка (с кодом)."
echo "Так будет видно причину без logcat/adb — просто открыть приложение и прочитать."
echo ""

LAYOUT_MINE="app/src/main/res/layout/activity_mine.xml"
ADS_MANAGER="app/src/main/java/com/example/fa_ksiegowy/AdsManager.kt"
MINE_ACTIVITY="app/src/main/java/com/example/fa_ksiegowy/MineActivity.kt"

for f in "$LAYOUT_MINE" "$ADS_MANAGER" "$MINE_ACTIVITY"; do
    if [ ! -f "$f" ]; then
        echo "!!! Не найден $f"
        exit 1
    fi
done

# --- 1) Добавляем TextView для статуса рекламы в layout, сразу под AdView ---
python3 - "$LAYOUT_MINE" << 'EOF_PY'
import sys, io

path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

marker = '''    <com.google.android.gms.ads.AdView
        android:id="@+id/ad_banner"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="10dp"
        android:visibility="gone"
        />'''

if "tv_ad_debug" in content:
    print("-- tv_ad_debug уже есть в layout, пропускаю")
else:
    if marker not in content:
        print("!!! Не найден блок AdView в ожидаемом виде — не могу вставить debug TextView")
        sys.exit(1)
    replacement = marker + '''

    <TextView
        android:id="@+id/tv_ad_debug"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="6dp"
        android:text="Ad status: —"
        android:textColor="@color/text_secondary"
        android:textSize="11sp"
        />'''
    content = content.replace(marker, replacement, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: tv_ad_debug добавлен в", path)
EOF_PY

# --- 2) AdsManager.kt: пишем статус в этот TextView на каждом шаге ---
cat > "$ADS_MANAGER" << 'EOF_ADS_MANAGER_KT'
package com.example.fa_ksiegowy

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.util.Log
import android.view.View
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

    fun setupAndLoadBanner(activity: Activity, adView: AdView, debugView: TextView? = null) {
        if (BillingManager.isPro(activity)) {
            adView.visibility = View.GONE
            setDebugStatus(debugView, "hidden (Pro active)")
            return
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
                initAndLoad(activity, adView, debugView)
                return
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
                            initAndLoad(activity, adView, debugView)
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
                initAndLoad(activity, adView, debugView)
            }
        } catch (e: Exception) {
            // Ловим вообще любое исключение на этом пути, чтобы оно не терялось молча —
            // выводим текст ошибки прямо на экран.
            setDebugStatus(debugView, "EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun initAndLoad(activity: Activity, adView: AdView, debugView: TextView?) {
        setDebugStatus(debugView, "initializing SDK…")
        if (!sdkInitialized) {
            sdkInitialized = true
            MobileAds.initialize(activity) {
                setDebugStatus(debugView, "SDK initialized, loading ad…")
            }
        }
        adView.visibility = View.VISIBLE
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
    fun hideBanner(adView: AdView) {
        adView.visibility = View.GONE
        adView.pause()
    }
}
EOF_ADS_MANAGER_KT
echo "OK: $ADS_MANAGER — теперь пишет статус каждого шага в debugView"

# --- 3) MineActivity.kt: передаём tv_ad_debug в AdsManager ---
python3 - "$MINE_ACTIVITY" << 'EOF_PY'
import sys, io

path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    content = f.read()

old = "        AdsManager.setupAndLoadBanner(this, findViewById(R.id.ad_banner))"
new = "        AdsManager.setupAndLoadBanner(this, findViewById(R.id.ad_banner), findViewById(R.id.tv_ad_debug))"

if new in content:
    print("-- MineActivity.kt уже передаёт tv_ad_debug, пропускаю")
elif old in content:
    content = content.replace(old, new, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: MineActivity.kt теперь передаёт tv_ad_debug в AdsManager")
else:
    print("!!! Не найдена ожидаемая строка вызова AdsManager.setupAndLoadBanner в MineActivity.kt")
    sys.exit(1)
EOF_PY

echo ""
echo "=== Готово. Пересобери APK: ./gradlew clean assembleDebug ==="
echo "=== git add -A && git commit -m 'Add on-screen ad status line for debugging' && git push ==="
echo ""
echo "После установки открой главный экран — под местом баннера появится серая строка"
echo "'Ad status: ...' — сделай её скриншот и пришли мне, станет понятна причина."
