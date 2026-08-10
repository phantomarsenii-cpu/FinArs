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
