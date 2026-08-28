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
 * Диагностика (для отладки показа рекламы): каждый шаг пишет свой статус в
 * debugView — маленькую серую строку под баннером. Работает ТОЛЬКО в debug-
 * сборке (проверка applicationInfo.FLAG_DEBUGGABLE) — в релизной сборке,
 * которая уходит в Google Play/Galaxy Store, ни Log.i, ни текст в debugView
 * не пишутся, так что диагностический вывод не может попасть на экран
 * обычного пользователя или в системный logcat.
 */
object AdsManager {

    private var sdkInitialized = false
    private const val TEST_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"
    private const val PROD_BANNER_UNIT_ID = "ca-app-pub-9218963926031039/9552844934"

    private fun isDebuggable(context: android.content.Context): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun setDebugStatus(context: android.content.Context, debugView: TextView?, text: String) {
        if (!isDebuggable(context)) return
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
            setDebugStatus(activity, debugView, "hidden (Pro active)")
            return adView
        }

        setDebugStatus(activity, debugView, "starting…")

        try {
            adView.setAdSize(AdSize.BANNER)

            val isDebuggable = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            adView.adUnitId = if (isDebuggable) TEST_BANNER_UNIT_ID else PROD_BANNER_UNIT_ID
            setDebugStatus(activity, debugView, "isDebuggable=$isDebuggable, unit=${adView.adUnitId}")

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
                            setDebugStatus(activity, debugView, "consent form error: ${formError.message}")
                        }
                        if (consentInformation.canRequestAds()) {
                            initAndLoad(activity, container, adView, debugView)
                        } else {
                            setDebugStatus(activity, debugView, "blocked — canRequestAds()=false (нужно опубликовать Privacy & messaging в AdMob)")
                        }
                    }
                },
                { requestError ->
                    setDebugStatus(activity, debugView, "consent info update error: ${requestError.message}")
                }
            )

            if (consentInformation.canRequestAds() && !sdkInitialized) {
                initAndLoad(activity, container, adView, debugView)
            }
        } catch (e: Exception) {
            // Ловим вообще любое исключение на этом пути, чтобы оно не терялось молча —
            // выводим текст ошибки прямо на экран.
            setDebugStatus(activity, debugView, "EXCEPTION: ${e.javaClass.simpleName}: ${e.message}")
        }

        return adView
    }

    private fun initAndLoad(activity: Activity, container: ViewGroup, adView: AdView, debugView: TextView?) {
        setDebugStatus(activity, debugView, "initializing SDK…")
        if (!sdkInitialized) {
            sdkInitialized = true
            MobileAds.initialize(activity) {
                setDebugStatus(activity, debugView, "SDK initialized, loading ad…")
            }
        }
        container.visibility = View.VISIBLE
        adView.adListener = object : AdListener() {
            override fun onAdLoaded() {
                setDebugStatus(activity, debugView, "loaded OK ✅")
            }
            override fun onAdFailedToLoad(error: LoadAdError) {
                // errorCode 3 = ERROR_CODE_NO_FILL — самая частая причина для новых
                // рекламных блоков: у Google пока нет рекламы для показа именно вам.
                setDebugStatus(activity, debugView, "FAILED code=${error.code} domain=${error.domain} msg=${error.message}")
            }
        }
        setDebugStatus(activity, debugView, "loadAd() called…")
        adView.loadAd(AdRequest.Builder().build())
    }

    /** Вызывать сразу после успешной покупки Pro, чтобы мгновенно убрать баннер без перезапуска экрана. */
    fun hideBanner(container: ViewGroup, adView: AdView) {
        container.visibility = View.GONE
        adView.pause()
    }
}
