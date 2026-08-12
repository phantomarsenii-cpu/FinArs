#!/bin/bash
set -e
cd "$(dirname "$0")"
# Jesli skrypt jest uruchamiany nie z korzenia projektu, zakladamy ze skopiowano go do ~/FA_ksiegowy
if [ ! -f "app/build.gradle" ]; then
  cd ~/FA_ksiegowy
fi

echo "== Update 52: Paywall redesign (Wersja Pro) =="

mkdir -p "$(dirname "app/src/main/res/layout/activity_settings_pro.xml")"
cat > "app/src/main/res/layout/activity_settings_pro.xml" << 'LAYOUT_XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
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

        <!-- Footer -->
        <TextView
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
</FrameLayout>
LAYOUT_XML
echo "  app/src/main/res/layout/activity_settings_pro.xml written"

mkdir -p "$(dirname "app/src/main/java/com/example/fa_ksiegowy/SettingsProActivity.kt")"
cat > "app/src/main/java/com/example/fa_ksiegowy/SettingsProActivity.kt" << 'SETTINGS_PRO_KT'
package com.example.fa_ksiegowy

import android.graphics.Color
import android.os.Bundle
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

/**
 * Ekran "Wersja Pro" — pelnoekranowy paywall subskrypcji (miesiac/rok) przez
 * Google Play Billing, z 7-dniowym okresem probnym. Zastepuje dawne okno
 * dialogowe potwierdzenia zakupu — caly przeplyw miesci sie teraz na jednym
 * ekranie zgodnie z referencyjnym projektem.
 */
class SettingsProActivity : BaseActivity() {

    /** Aktualnie wybrany plan w karcie wyboru — domyslnie roczny (najlepsza oferta). */
    private var selectedProductId: String = BillingManager.PRO_YEARLY_PRODUCT_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_pro)
        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }
        setupHeader()
        setupProSection()
    }

    private fun setupHeader() {
        val tvHeader = findViewById<TextView>(R.id.tv_paywall_header)
        val white = getString(R.string.paywall_header_white)
        val blue = getString(R.string.paywall_header_blue)
        val full = "$white $blue"
        val spannable = SpannableStringBuilder(full)
        spannable.setSpan(
            ForegroundColorSpan(Color.WHITE),
            0, white.length,
            SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        spannable.setSpan(
            ForegroundColorSpan(getColorCompat(R.color.accent_blue_light)),
            white.length + 1, full.length,
            SpannableStringBuilder.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        tvHeader.text = spannable
    }

    private fun getColorCompat(colorRes: Int): Int =
        androidx.core.content.ContextCompat.getColor(this, colorRes)

    private fun refreshUi() {
        val tvStatus = findViewById<TextView>(R.id.tv_pro_status)
        val cardYearly = findViewById<FrameLayout>(R.id.card_yearly)
        val cardMonthly = findViewById<FrameLayout>(R.id.card_monthly)
        val btnCta = findViewById<FrameLayout>(R.id.btn_cta)
        val tvCta = findViewById<TextView>(R.id.tv_cta)

        if (BillingManager.isPro(this)) {
            tvStatus.text = getString(R.string.pro_status_active)
            tvStatus.visibility = View.VISIBLE
            cardYearly.isEnabled = false
            cardMonthly.isEnabled = false
            cardYearly.alpha = 0.5f
            cardMonthly.alpha = 0.5f
            btnCta.isEnabled = false
            btnCta.alpha = 0.5f
            tvCta.text = getString(R.string.pro_status_active)
        } else {
            tvStatus.visibility = View.GONE
            cardYearly.isEnabled = true
            cardMonthly.isEnabled = true
            cardYearly.alpha = 1f
            cardMonthly.alpha = 1f
            btnCta.isEnabled = true
            btnCta.alpha = 1f
            tvCta.text = getString(R.string.paywall_cta)
            applySelectionState()
        }
    }

    private fun applySelectionState() {
        val cardYearly = findViewById<FrameLayout>(R.id.card_yearly)
        val cardMonthly = findViewById<FrameLayout>(R.id.card_monthly)
        val radioYearly = findViewById<ImageView>(R.id.radio_yearly)
        val radioMonthly = findViewById<ImageView>(R.id.radio_monthly)

        val yearlySelected = selectedProductId == BillingManager.PRO_YEARLY_PRODUCT_ID
        cardYearly.setBackgroundResource(if (yearlySelected) R.drawable.card_plan_selected else R.drawable.card_plan_unselected)
        cardMonthly.setBackgroundResource(if (!yearlySelected) R.drawable.card_plan_selected else R.drawable.card_plan_unselected)
        radioYearly.setImageResource(if (yearlySelected) R.drawable.ic_radio_selected else R.drawable.ic_radio_unselected)
        radioMonthly.setImageResource(if (!yearlySelected) R.drawable.ic_radio_selected else R.drawable.ic_radio_unselected)
    }

    private fun setupProSection() {
        val tvPriceYearly = findViewById<TextView>(R.id.tv_price_yearly)
        val tvPriceMonthly = findViewById<TextView>(R.id.tv_price_monthly)
        val tvTrialYearly = findViewById<TextView>(R.id.tv_trial_yearly)
        val tvTrialMonthly = findViewById<TextView>(R.id.tv_trial_monthly)

        // Domyslne ceny (te same co w prawdziwej konfiguracji Google Play) — widoczne
        // od razu, zanim doczyta sie prawdziwa cena z Billing.
        tvTrialYearly.text = getString(R.string.paywall_trial_yearly, getString(R.string.paywall_price_yearly_default))
        tvTrialMonthly.text = getString(R.string.paywall_trial_monthly, getString(R.string.paywall_price_monthly_default))

        refreshUi()

        BillingManager.connect(this) { connected ->
            runOnUiThread {
                if (!connected) return@runOnUiThread
                BillingManager.restorePurchases(this) { refreshUi() }
                if (!BillingManager.isPro(this)) {
                    BillingManager.querySubscriptionPlans { monthly, yearly ->
                        runOnUiThread {
                            if (yearly != null) {
                                tvPriceYearly.text = yearly.price
                                tvTrialYearly.text = getString(R.string.paywall_trial_yearly, yearly.price)
                            }
                            if (monthly != null) {
                                tvPriceMonthly.text = monthly.price
                                tvTrialMonthly.text = getString(R.string.paywall_trial_monthly, monthly.price)
                            }
                        }
                    }
                }
            }
        }

        findViewById<FrameLayout>(R.id.card_yearly).setOnClickListener {
            selectedProductId = BillingManager.PRO_YEARLY_PRODUCT_ID
            applySelectionState()
        }
        findViewById<FrameLayout>(R.id.card_monthly).setOnClickListener {
            selectedProductId = BillingManager.PRO_MONTHLY_PRODUCT_ID
            applySelectionState()
        }
        findViewById<FrameLayout>(R.id.btn_cta).setOnClickListener {
            if (!BillingManager.isPro(this)) {
                BillingManager.launchPurchase(this, selectedProductId)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Na wypadek powrotu z okna oplaty Google Play — odswiez status i wyglad ekranu.
        BillingManager.restorePurchases(this) { refreshUi() }
    }
}
SETTINGS_PRO_KT
echo "  app/src/main/java/com/example/fa_ksiegowy/SettingsProActivity.kt written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_crown_pro.xml")"
cat > "app/src/main/res/drawable/ic_crown_pro.xml" << 'IC_CROWN_PRO'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="96dp" android:height="96dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:pathData="M5,16L3,6l5.5,4L12,4l3.5,6L21,6l-2,10H5z M5,19c0,0.55 0.45,1 1,1h12c0.55,0 1,-0.45 1,-1v-1H5v1z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="4" android:startY="4"
                android:endX="20" android:endY="20"
                android:startColor="#7FB4FF"
                android:centerColor="#3B82F6"
                android:endColor="#1D4ED8"/>
        </aapt:attr>
    </path>
    <path android:fillColor="#E8F1FF" android:fillAlpha="0.9"
        android:pathData="M12,10.2l1.05,1.8l-1.05,1.8l-1.05,-1.8z"/>
</vector>
IC_CROWN_PRO
echo "  app/src/main/res/drawable/ic_crown_pro.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_crown_small.xml")"
cat > "app/src/main/res/drawable/ic_crown_small.xml" << 'IC_CROWN_SMALL'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="16dp" android:height="16dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF"
        android:pathData="M5,16L3,6l5.5,4L12,4l3.5,6L21,6l-2,10H5z M5,19c0,0.55 0.45,1 1,1h12c0.55,0 1,-0.45 1,-1v-1H5v1z"/>
</vector>
IC_CROWN_SMALL
echo "  app/src/main/res/drawable/ic_crown_small.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_check_circle_green.xml")"
cat > "app/src/main/res/drawable/ic_check_circle_green.xml" << 'IC_CHECK_CIRCLE'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="22dp" android:height="22dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#34D399"
        android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,20c-4.41,0 -8,-3.59 -8,-8s3.59,-8 8,-8 8,3.59 8,8 -3.59,8 -8,8z"/>
    <path android:fillColor="#34D399"
        android:pathData="M10.6,14.2l-2.3,-2.3l-1.06,1.06l3.36,3.36l6.5,-6.5l-1.06,-1.06z"/>
</vector>
IC_CHECK_CIRCLE
echo "  app/src/main/res/drawable/ic_check_circle_green.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_radio_selected.xml")"
cat > "app/src/main/res/drawable/ic_radio_selected.xml" << 'IC_RADIO_SEL'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="oval">
            <solid android:color="#00000000"/>
            <stroke android:width="2dp" android:color="@color/accent_blue_light"/>
            <size android:width="24dp" android:height="24dp"/>
        </shape>
    </item>
    <item android:width="12dp" android:height="12dp" android:gravity="center">
        <shape android:shape="oval">
            <solid android:color="@color/accent_blue_light"/>
        </shape>
    </item>
</layer-list>
IC_RADIO_SEL
echo "  app/src/main/res/drawable/ic_radio_selected.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_radio_unselected.xml")"
cat > "app/src/main/res/drawable/ic_radio_unselected.xml" << 'IC_RADIO_UNSEL'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#00000000"/>
    <stroke android:width="2dp" android:color="@color/card_border"/>
    <size android:width="24dp" android:height="24dp"/>
</shape>
IC_RADIO_UNSEL
echo "  app/src/main/res/drawable/ic_radio_unselected.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_star_small.xml")"
cat > "app/src/main/res/drawable/ic_star_small.xml" << 'IC_STAR_SMALL'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="12dp" android:height="12dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF"
        android:pathData="M12,2l3.09,6.26L22,9.27l-5,4.87L18.18,21L12,17.77L5.82,21L7,14.14L2,9.27l6.91,-1.01z"/>
</vector>
IC_STAR_SMALL
echo "  app/src/main/res/drawable/ic_star_small.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_tag_small.xml")"
cat > "app/src/main/res/drawable/ic_tag_small.xml" << 'IC_TAG_SMALL'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="14dp" android:height="14dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="@color/accent_blue_light"
        android:pathData="M21.41,11.58l-9,-9C12.05,2.22 11.55,2 11,2H4C2.9,2 2,2.9 2,4v7c0,0.55 0.22,1.05 0.59,1.41l9,9c0.36,0.36 0.86,0.59 1.41,0.59s1.05,-0.23 1.41,-0.59l7,-7c0.37,-0.36 0.59,-0.86 0.59,-1.41C22,12.44 21.77,11.94 21.41,11.58zM5.5,7C4.67,7 4,6.33 4,5.5S4.67,4 5.5,4S7,4.67 7,5.5S6.33,7 5.5,7z"/>
</vector>
IC_TAG_SMALL
echo "  app/src/main/res/drawable/ic_tag_small.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/ic_shield_check.xml")"
cat > "app/src/main/res/drawable/ic_shield_check.xml" << 'IC_SHIELD_CHECK'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="14dp" android:height="14dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="@color/accent_blue_light"
        android:pathData="M12,1L3,5v6c0,5.55 3.84,10.74 9,12c5.16,-1.26 9,-6.45 9,-12V5z M10.29,16.29l-3.59,-3.59l1.41,-1.41l2.18,2.18l4.6,-4.6l1.41,1.41z"/>
</vector>
IC_SHIELD_CHECK
echo "  app/src/main/res/drawable/ic_shield_check.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/card_plan_selected.xml")"
cat > "app/src/main/res/drawable/card_plan_selected.xml" << 'CARD_PLAN_SEL'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="20dp" />
    <solid android:color="@color/card_bg_light" />
    <stroke android:width="2dp" android:color="@color/accent_blue_light" />
</shape>
CARD_PLAN_SEL
echo "  app/src/main/res/drawable/card_plan_selected.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/card_plan_unselected.xml")"
cat > "app/src/main/res/drawable/card_plan_unselected.xml" << 'CARD_PLAN_UNSEL'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="20dp" />
    <solid android:color="@color/card_bg_light" />
    <stroke android:width="1dp" android:color="@color/card_border" />
</shape>
CARD_PLAN_UNSEL
echo "  app/src/main/res/drawable/card_plan_unselected.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/badge_pill_bg.xml")"
cat > "app/src/main/res/drawable/badge_pill_bg.xml" << 'BADGE_PILL_BG'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="14dp" />
    <solid android:color="@color/badge_bg_blue" />
</shape>
BADGE_PILL_BG
echo "  app/src/main/res/drawable/badge_pill_bg.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/btn_pill_cta.xml")"
cat > "app/src/main/res/drawable/btn_pill_cta.xml" << 'BTN_PILL_CTA'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="28dp" />
    <gradient
        android:angle="45"
        android:startColor="@color/accent_blue_light"
        android:centerColor="#2F6DF0"
        android:endColor="@color/accent_blue_dark" />
</shape>
BTN_PILL_CTA
echo "  app/src/main/res/drawable/btn_pill_cta.xml written"

mkdir -p "$(dirname "app/src/main/res/drawable/circle_translucent_white.xml")"
cat > "app/src/main/res/drawable/circle_translucent_white.xml" << 'CIRCLE_TRANSLUCENT'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#33FFFFFF" />
</shape>
CIRCLE_TRANSLUCENT
echo "  app/src/main/res/drawable/circle_translucent_white.xml written"

mkdir -p "$(dirname "app/src/main/res/values/strings.xml")"
cat > "app/src/main/res/values/strings.xml" << 'STRINGS_EN'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Add income</string>
    <string name="add_expense">Add expense</string>
    <string name="add_entry">Add +</string>
    <string name="balance">Balance</string>
    <string name="enter_amount">Amount</string>
    <string name="enter_comment">Comment</string>
    <string name="entry_date_label">Transaction date</string>
    <string name="attach_receipt">Attach receipt</string>
    <string name="save">Save</string>
    <string name="settings">Settings</string>
    <string name="tax_percent">Tax percent</string>
    <string name="other_income_label">Other income (%1$d)</string>
    <string name="tax_scale_title">Tax is calculated automatically</string>
    <string name="tax_scale_description" formatted="false">0% up to 30,000 zł/year · 12% on the part between 30,000 and 120,000 zł · 32% on the part above 120,000 zł. The rate applies only to the amount above each threshold, not to the whole sum.</string>
    <string name="other_income_title">Other income</string>
    <string name="other_income_hint">Your total taxable income this year from other sources (job, other business, etc.). Used together with income from this app to check the 30,000 zł annual tax-free limit.</string>
    <string name="saved">Saved</string>
    <string name="auto_tax_button">Calculate automatically</string>
    <string name="auto_tax_result" formatted="false">Suggested rate: %1$.1f% (based on Polish PIT scale: 12% up to 120,000 zł/year, 32% above). You can edit it before saving.</string>
    <string name="export_report">Export report</string>
    <string name="generate_report">Generate report</string>
    <string name="select_period">Select period</string>
    <string name="month">Month</string>
    <string name="year">Year</string>
    <string name="custom_range">Custom range</string>
    <string name="from">From</string>
    <string name="to">To</string>
    <string name="no_entries">No entries</string>
    <string name="search_no_results">Nothing found</string>
    <string name="history_search_hint">Search by comment or amount</string>
    <string name="invoice_search_hint">Search by number, client or amount</string>
    <string name="filter_date_range">Date range</string>
    <string name="filter_clear">Clear filters</string>

    <string name="statistics">Statistics</string>
    <string name="stat_income">Income</string>
    <string name="stat_expense">Expense</string>
    <string name="stat_profit">Profit (gross)</string>
    <string name="stat_tax_format" formatted="false">Tax (%1$.1f%)</string>

    <string name="report_col_date">Date</string>
    <string name="report_col_income">Income</string>
    <string name="report_col_expense">Expense</string>
    <string name="report_col_tax_percent" formatted="false">Tax %</string>
    <string name="report_col_tax_amount">Tax amount</string>
    <string name="report_col_comment">Comment</string>
    <string name="report_sheet_name">Report</string>
    <string name="report_title_month">Report — Month</string>
    <string name="report_title_year">Report — Year</string>
    <string name="report_title_custom">Report — Custom period</string>
    <string name="custom_range_invalid">The end date must be after the start date</string>
    <string name="report_total_income">Total income</string>
    <string name="report_total_expense">Total expense</string>
    <string name="report_total_profit">Total profit</string>
    <string name="report_total_tax">Total tax</string>
    <string name="report_total_net_profit">Net profit (after tax)</string>
    <string name="report_generating">Generating report…</string>
    <string name="report_ready">Report ready</string>
    <string name="report_share_title">Share report</string>
    <string name="report_error">Failed to generate report: %1$s</string>
    <string name="about_app">About the app</string>
    <string name="about_version_label">Version %1$s</string>
    <string name="settings_menu_privacy">Privacy Policy</string>
    <string name="about_email">finars2026@gmail.com</string>

    <string name="privacy_updated_label">Last updated: August 11, 2026</string>
    <string name="privacy_intro">We respect your privacy. FinArs was designed with maximum data security in mind — most information is stored exclusively on your device.</string>

    <string name="privacy_section1_title">1. Data controller</string>
    <string name="privacy_section1_body">The controller of the app is the creator of FinArs. For questions about privacy and data processing, contact: finars2026@gmail.com.</string>

    <string name="privacy_section2_title">2. What data we process and where we store it</string>
    <string name="privacy_section2_intro">All your key financial and business data is stored EXCLUSIVELY LOCALLY on your device. We do not have our own servers and do not collect this information.</string>
    <string-array name="privacy_section2_bullets">
        <item>Financial data and transactions: amounts, dates, categories, comments, and invoice details (including counterparty name and tax ID) never leave your phone.</item>
        <item>Warehouse stock: product and stocktaking data is saved only in the app\'s local database.</item>
        <item>Receipt photos attached manually to transactions: stored exclusively on your device, never uploaded to the cloud.</item>
        <item>Security (PIN / biometrics): the PIN is stored in hashed form in the device\'s secure storage and is never transmitted anywhere.</item>
    </string-array>

    <string name="privacy_section3_title">3. Third-party services</string>
    <string name="privacy_section3_intro">The app uses trusted external services to handle payments and ads:</string>
    <string-array name="privacy_section3_bullets">
        <item>Google Play Billing — handles the purchase and verification of the FinArs Pro subscription. We never see your payment card details (payment is handled by Google).</item>
        <item>RevenueCat — once the app is published, will manage the Pro subscription status (active / expired / trial), processing an anonymous user identifier and purchase status to grant Pro access across your devices.</item>
        <item>Google AdMob — shows ads to users without an active Pro subscription. AdMob may collect an anonymous advertising ID and diagnostic data to serve ads (subject to GDPR consent collected via Google\'s UMP consent form). Google\'s privacy policy: policies.google.com/privacy</item>
    </string-array>

    <string name="privacy_section4_title">4. Required app permissions</string>
    <string name="privacy_section4_intro">The app only requests the permissions necessary for it to work:</string>
    <string-array name="privacy_section4_bullets">
        <item>Camera — required only to scan warehouse barcodes and to photograph receipts.</item>
        <item>Notifications — required to remind you about invoice due dates and exceeded limits (e.g. unregistered activity).</item>
        <item>Storage — required on older Android versions to save backups and export reports (e.g. PDF / CSV).</item>
        <item>Internet access — required only by the ad and billing modules described above; it is not used to upload your financial data.</item>
    </string-array>

    <string name="privacy_section5_title">5. Data management and your rights</string>
    <string name="privacy_section5_body">Since your data lives on your phone, you are always in full control: you can clear all data in the app at any time (Settings -> Backup -> Clear data), or simply uninstall the app. You decide yourself where and when to export your backup file.</string>

    <string name="privacy_section6_title">6. Children</string>
    <string name="privacy_section6_body">The app is not directed at people under 16 years of age and does not knowingly collect any data from children.</string>

    <string name="privacy_section7_title">7. Changes to this Privacy Policy</string>
    <string name="privacy_section7_body">We reserve the right to update this Privacy Policy. Any change will be published here with a new update date.</string>

    <string name="privacy_section8_title">8. Contact</string>
    <string name="privacy_section8_body">If you have any questions about privacy or how the app works, contact us: finars2026@gmail.com</string>

    <string name="about_intro">FinArs is a comprehensive app for managing the finances of unregistered business activity. Track income and expenses, monitor limits, automatically calculate taxes, issue invoices, manage your warehouse, and generate ready-made reports and tax returns — all in one place, with the full history of operations and notifications always at hand.</string>
    <string name="about_subscription_note">⭐ Pro subscription: monthly or yearly plan, 7 days free trial, cancel anytime.</string>

    <string name="about_section_finance_title">📊 Finances and taxes</string>
    <string-array name="about_bullets_finance">
        <item>Income and expense tracking with attached receipts and colour-coded categories</item>
        <item>Automatic profit and tax calculation (12%/32% scale)</item>
        <item>Recurring transactions (rent, subscriptions) created automatically every month</item>
        <item>Unregistered-activity limit tracking (120,000 zł threshold)</item>
        <item>Notification history for approaching and exceeded limits, invoice reminders and more</item>
    </string-array>

    <string name="about_section_warehouse_title">📦 Warehouse</string>
    <string-array name="about_bullets_warehouse">
        <item>Product catalogue with barcode scanning, stock levels and low-stock alerts</item>
        <item>Stocktaking sessions with history</item>
        <item>Products can be added straight to invoices</item>
    </string-array>

    <string name="about_section_invoices_title">🧾 Invoices and receipts (Pro)</string>
    <string-array name="about_bullets_invoices">
        <item>Issue invoices/receipts to individuals and companies with PDF generation</item>
        <item>Statuses: Paid / Pending / Overdue, plus due-date reminders</item>
        <item>Tracking of the annual 20,000 zł cash-sales limit for private individuals</item>
        <item>Invoice history with search and filters</item>
    </string-array>

    <string name="about_section_reports_title">📄 Reports and tax returns</string>
    <string-array name="about_bullets_reports">
        <item>Income/expense summary and 6-month trend chart</item>
        <item>Export monthly report (free), yearly and custom-period reports (Pro) to Excel with receipts</item>
        <item>Generate PIT-36 tax returns — helper PDF and official form filling (Pro)</item>
    </string-array>

    <string name="about_section_security_title">🔒 Security and convenience</string>
    <string-array name="about_bullets_security">
        <item>App lock with PIN code and fingerprint / face unlock</item>
        <item>Backup and restore your data (Pro)</item>
        <item>Modern dark interface</item>
        <item>Available in Polish, Russian and English</item>
        <item>All financial data is stored locally on your device</item>
    </string-array>
    <string name="dialog_close">Close</string>
    <string name="dialog_write">Write</string>
    <string name="pro_status_locked">Pro is locked. Unlock to get yearly/custom Excel reports, backup \&amp; restore, and remove ads.</string>
    <string name="pro_status_active">Pro unlocked. Thank you for your support!</string>
    <string name="pro_unlock_button">Unlock Pro</string>
    <string name="pro_unlock_button_price">Unlock Pro — %1$s</string>
    <string name="pro_trial_hint">7 days free, then billed automatically. Cancel anytime.</string>
    <string name="pro_plan_monthly">Monthly plan</string>
    <string name="pro_plan_yearly">Yearly plan (best value)</string>
    <string name="pro_plan_monthly_price">Monthly — %1$s / month</string>
    <string name="pro_plan_yearly_price">Yearly — %1$s / year</string>
    <string name="pro_loading">Loading price…</string>
    <string name="pro_feature_locked_title">Pro feature</string>
    <string name="pro_feature_locked_message">Yearly and custom reports are a Pro feature. Unlock Pro in Settings to use them.</string>
    <string name="pro_feature_locked_go_settings">Go to Settings</string>
    <string name="invoice_pro_locked_message">Issuing invoices is a Pro feature. Unlock Pro in Settings to use it.</string>
    <string name="backup_pro_locked_message">Backup and restore is a Pro feature. Unlock Pro to keep your data safe with a backup file.</string>
    <string name="pro_purchase_error">Could not start the purchase. Check your connection and try again.</string>
    <string name="pro_info_title">Pro version</string>
    <string name="pro_info_message">Pro unlocks:\n\n\u2022 Issuing invoices and receipts (PDF)\n\u2022 Yearly Excel report\n\u2022 Custom-period Excel report\n\u2022 PIT-36 tax return generation\n\u2022 Backup &amp; restore\n\u2022 No ads</string>
    <string name="pro_info_continue">Continue to purchase</string>
    <string name="paywall_header_white">Unlock</string>
    <string name="paywall_header_blue">FinArs Pro</string>
    <string name="paywall_subtitle">Get full control over your finances\nand work without limits.</string>
    <string name="paywall_feature_1">Issuing invoices and receipts (PDF)</string>
    <string name="paywall_feature_2">PIT-36 tax return generation</string>
    <string name="paywall_feature_3">Yearly and custom Excel reports</string>
    <string name="paywall_feature_4">Cloud and local data backup</string>
    <string name="paywall_feature_5">No ads</string>
    <string name="paywall_badge">MOST POPULAR • SAVE 30%</string>
    <string name="paywall_plan_yearly_title">Yearly Plan</string>
    <string name="paywall_plan_monthly_title">Monthly Plan</string>
    <string name="paywall_price_yearly_default">99.99 zł</string>
    <string name="paywall_price_monthly_default">11.99 zł</string>
    <string name="paywall_per_year">/ year</string>
    <string name="paywall_per_month">/ month</string>
    <string name="paywall_trial_yearly">7 days free, then %1$s / year</string>
    <string name="paywall_trial_monthly">7 days free, then %1$s / month</string>
    <string name="paywall_per_month_note">Only 8.33 zł / month</string>
    <string name="paywall_cta">Try 7 days for 0 zł</string>
    <string name="paywall_footer_1">Free for the first 7 days.\nCancel anytime in Google Play.</string>
    <string name="paywall_data_safe">Your data is safe</string>
    <string name="paywall_footer_2">Billing starts after 7 days.\nYou can cancel at any time.</string>
    <string name="enter_code_button">Have a code?</string>
    <string name="enter_code_title">Enter code</string>
    <string name="enter_code_hint">Code</string>
    <string name="enter_code_apply">Apply</string>
    <string name="enter_code_wrong">Invalid code</string>
    <string name="enter_code_success">Pro unlocked</string>
    <string name="transaction_history">Transaction history</string>
    <string name="stat_net_profit">Net profit (after tax)</string>
    <string name="type_income">Income</string>
    <string name="type_expense">Expense</string>
    <string name="edit_income_title">Edit income</string>
    <string name="edit_expense_title">Edit expense</string>
    <string name="delete_entry">Delete</string>
    <string name="delete_confirm_title">Delete entry?</string>
    <string name="delete_confirm_message">This entry will be permanently deleted. This cannot be undone.</string>
    <string name="delete_confirm_yes">Delete</string>
    <string name="entry_updated">Updated</string>
    <string name="entry_deleted">Deleted</string>
    <string name="clear_all_button">Clear all data</string>
    <string name="clear_all_confirm_title">Are you sure?</string>
    <string name="clear_all_confirm_message">All income and expense entries will be permanently deleted. This cannot be undone.</string>
    <string name="clear_all_confirm_yes">Delete all</string>
    <string name="clear_all_done">All data has been deleted</string>

    <string name="settings_menu_tax">Tax and limits</string>
    <string name="settings_menu_language">Language</string>
    <string name="settings_menu_backup">Backup (Pro)</string>
    <string name="settings_menu_pro">Pro version</string>

    <string name="backup_hint">Save a backup of your income/expense entries — including amounts, dates, comments and attached receipt photos — as a file. In the save dialog you can choose phone storage or Google Drive (if the Drive app is installed). Keep this file safe: it\'s the only way to restore your data if you lose the phone or reinstall the app.</string>
    <string name="backup_in_progress">Working…</string>
    <string name="backup_create">Create backup</string>
    <string name="backup_restore">Restore from backup</string>
    <string name="backup_success">Backup saved (%1$d entries)</string>
    <string name="backup_error">Error: %1$s</string>
    <string name="backup_restore_confirm_title">Restore from backup?</string>
    <string name="backup_restore_confirm_message">Entries from the backup file will be added to what you already have on this device (existing entries are not deleted or overwritten). If you want a clean restore, use \"Clear all data\" first, then restore.</string>
    <string name="backup_invalid_file">This does not look like a valid FinArs backup file</string>
    <string name="backup_restored">Restored %1$d entries</string>
    <string name="backup_never">Last backup: never</string>
    <string name="backup_last_time">Last backup: %1$s</string>

    <string name="settings_menu_security">Security (PIN / fingerprint)</string>
    <string name="settings_menu_pit36">Generate PIT (Pro)</string>
    <string name="pit36_pro_locked_message">PIT-36 generation is a Pro feature. Unlock Pro in Settings to use it.</string>

    <string name="lock_title">FinArs is locked</string>
    <string name="lock_subtitle">Enter your PIN to continue</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Wrong PIN, try again</string>
    <string name="lock_unlock_button">Unlock</string>
    <string name="lock_biometric_button">Use fingerprint / face</string>
    <string name="lock_biometric_prompt_title">Unlock FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Confirm your fingerprint or face</string>
    <string name="lock_use_pin">Use PIN</string>
    <string name="lock_biometric_unavailable">No fingerprint/face is set up on this device. Add one in your phone\'s settings first.</string>

    <string name="security_hint">Protect the app with a PIN code. When enabled, FinArs will ask for the PIN every time you open it after leaving the app. You can also enable fingerprint/face unlock as a quick shortcut for the same PIN.</string>
    <string name="security_pin_switch">Require PIN to open the app</string>
    <string name="security_change_pin">Change PIN</string>
    <string name="security_biometric_switch">Unlock with fingerprint / face</string>
    <string name="security_set_pin_title">Set a PIN</string>
    <string name="security_set_pin_message">Choose a 4–6 digit PIN</string>
    <string name="security_continue">Continue</string>
    <string name="security_pin_length_error">PIN must be 4–6 digits</string>
    <string name="security_confirm_pin_title">Confirm your PIN</string>
    <string name="security_pin_saved">PIN saved</string>
    <string name="security_pin_mismatch">PINs don\'t match, try again</string>
    <string name="security_disable_pin_title">Enter current PIN</string>
    <string name="security_enter_current_pin">Enter your current PIN to continue</string>
    <string name="security_pin_disabled">PIN protection disabled</string>

    <string name="pit_data_title">Personal data for your tax return</string>
    <string name="pit_data_hint">Used only to fill in your PIT helper report (PIT-36 / PIT-36L / PIT-28 — depending on your activity type). Everything stays on your device.</string>
    <string name="pit_first_name">First name</string>
    <string name="pit_last_name">Last name</string>
    <string name="pit_pesel">PESEL (optional)</string>
    <string name="pit_street">Street</string>
    <string name="pit_house_number">House number</string>
    <string name="pit_apartment_number">Apartment number (optional)</string>
    <string name="pit_voivodeship">Voivodeship</string>
    <string name="pit_county">County (powiat)</string>
    <string name="pit_commune">Commune (gmina)</string>
    <string name="pit_postal_code">Postal code</string>
    <string name="pit_city">City</string>
    <string name="pit_tax_office">Tax office (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Reliefs and deductions (optional)</string>
    <string name="pit_children_count">Number of children (ulga na dzieci)</string>
    <string name="pit_internet_relief">Internet relief — amount spent</string>
    <string name="pit_ikze">IKZE contributions</string>
    <string name="pit_donations">Donations (darowizny)</string>
    <string name="pit_joint_spouse">File jointly with spouse</string>
    <string name="pit_spouse_data_title">Spouse personal data</string>
    <string name="pit_spouse_id_hint">Spouse NIP/PESEL</string>
    <string name="pit_spouse_first_name_hint">Spouse first name</string>
    <string name="pit_spouse_last_name_hint">Spouse last name</string>
    <string name="pit_spouse_birth_date_hint">Date of birth (DD.MM.YYYY)</string>
    <string name="pit_spouse_income_hint">Spouse income (optional)</string>
    <string name="pit_data_required_error">Please fill in first name, last name and tax office first</string>

    <string name="pit36_hint">Pick a full calendar year, check your personal data, then generate a helper PDF with the numbers and guidance for filling in your official form on podatki.gov.pl (Twój e-PIT) or on paper.</string>
    <string name="pit_row_przychod">Przychód (income)</string>
    <string name="pit_row_koszty">Koszty (expenses)</string>
    <string name="pit_row_dochod">Dochód (profit)</string>
    <string name="pit_row_tax">Estimated tax</string>
    <string name="pit_data_status_missing">Personal data not filled in yet — required before generating the report.</string>
    <string name="pit_data_status_ready">Personal data ready: %1$s</string>
    <string name="pit_edit_data_button">Edit personal data</string>
    <string name="pit36_generate_button">Generate helper PDF</string>
    <string name="pit36_disclaimer">This report is informational only and is not an official form, e-Deklaracja or tax advice. Always double-check the numbers before submitting your declaration.</string>
    <string name="pit36_calculating">Still calculating, please wait…</string>
    <string name="pit36_generated">PDF report generated</string>
    <string name="pit36_generate_official_button">Fill official form (2025 template)</string>
    <string name="pit36_official_hint">Fills the real %1$s(32)/2025 government PDF: your ID, address and business income/expenses row. You still need to add other income sources and any deductions yourself before submitting — see the disclaimer below.</string>
    <string name="pit36_official_unsupported">The official fillable form is only available for PIT-36 (skala). Your current form is %1$s — use "Generate helper PDF" instead.</string>
    <string name="pit36_official_generated">Official PIT-36 form filled. Please review sections E–K and add other income/deductions before submitting.</string>

    <!-- Activity type / registration rules -->
    <string name="activity_type_title">Activity type</string>
    <string name="activity_type_hint">Choose how you operate — this decides which limit applies and which annual form you should file.</string>
    <string name="activity_type_niezarejestrowana">Unregistered activity (bez rejestracji JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Income must stay under 75% of the minimum wage per month. If exceeded, you must register a JDG within 7 days. Filed via PIT-36, tax scale.</string>
    <string name="activity_type_jdg_skala" formatted="false">Registered JDG — tax scale 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Registered JDG — flat tax 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Registered JDG — lump-sum tax (PIT-28)</string>
    <string name="ryczalt_rate_moved_title">Ryczałt rate by category</string>
    <string name="ryczalt_rate_moved_hint">Each income and each invoice item has its own category — goods, production, services, IT, medical, freelance. The tax rate is applied automatically based on the category chosen.</string>
    <string name="min_wage_label">Minimum monthly wage (zł) — used to calculate the unregistered-activity limit</string>
    <string name="monthly_limit_preview" formatted="false">Monthly limit (75%): %1$,.2f zł</string>

    <!-- Main screen limit gauges -->
    <string name="limits_title">Limits</string>
    <string name="limit_monthly_label">Unregistered activity, this month: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">First tax bracket (120,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_tax_free">Tax-free amount (0–30,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">12%% bracket (30,000–120,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">120,000 zł threshold exceeded — surplus of %1$s zł taxed at 32%%</string>
    <string name="limit_vat_label">VAT exemption (240,000 zł/year): %1$s / %2$s zł</string>
    <string name="limit_bracket_title">Tax bracket (120,000 zł/year)</string>
    <string name="limit_bracket_title_tax_free">Tax-free amount (0–30,000 zł/year)</string>
    <string name="limit_bracket_title_rate12">12% bracket (30,000–120,000 zł/year)</string>
    <string name="limit_bracket_title_rate32">32% bracket (above 120,000 zł/year)</string>
    <string name="limit_exceeded_warning">You have exceeded the unregistered-activity limit! You must register a JDG within 7 days.</string>
    <string name="limits_remaining">Remaining: %1$s zł</string>
    <string name="limits_limit_of">Limit: %1$s zł</string>
    <string name="limits_about_title">About the limits</string>
    <string name="limits_about_desc">Exceeding the unregistered-activity limit may require registering a business and changing your tax form.</string>
    <string name="back">Back</string>
    <string name="category_sale">Sale</string>
    <string name="category_invoice">Invoice</string>
    <string name="category_materials">Purchase of materials</string>
    <string name="category_fuel">Fuel</string>
    <string name="category_transport">Transport service</string>
    <string name="category_other">Other</string>
    <string name="category_label">Category</string>
    <string name="category_choose">Choose category</string>
    <string name="tx_all">All</string>
    <string name="tx_income">Income</string>
    <string name="tx_expense">Expenses</string>
    <string name="add_comment_hint">Add comment</string>
    <string name="add_entry_title">Add</string>
    <string name="edit_entry_title">Edit</string>
    <string name="tab_invoice">Invoice</string>
    <string name="attach_receipt_row">Add receipt / photo</string>
    <string name="no_value_chosen">Not set</string>
    <string name="reports_title">Reports</string>
    <string name="period_this_month">This month</string>
    <string name="period_this_year">This year</string>
    <string name="report_summary">Summary</string>
    <string name="legend_income">Income</string>
    <string name="legend_expense">Expenses</string>
    <string name="legend_tax">Tax</string>
    <string name="legend_tax_pct">Tax (%1$d%%)</string>
    <string name="trend_title">Trend (6 months)</string>
    <string name="report_export_section">Export report</string>
    <string name="summary_total">Total</string>
    <string name="settings_menu_appearance">Appearance</string>
    <string name="appearance_dark_only_message">Dark theme is currently the only available look.</string>
    <string name="notifications_title">Notifications</string>
    <string name="notifications_clear_all">Clear all</string>
    <string name="notifications_empty">No notifications yet</string>
    <string name="edit_limits">Edit</string>
    <string name="recent_transactions_title">Recent transactions</string>
    <string name="view_all">View all</string>
    <string name="no_recent_transactions">No transactions yet</string>
    <string name="monthly_summary_title">Monthly summary</string>
    <string name="balance_vs_prev_month">vs previous month</string>
    <string name="stat_tax_short">Tax</string>

    <!-- Dynamic tax label -->
    <string name="tax_label_zero" formatted="false">Tax (0% — tax-free amount)</string>
    <string name="tax_label_12" formatted="false">Tax (12%)</string>
    <string name="tax_label_32" formatted="false">Tax (32% bracket)</string>
    <string name="tax_label_progressive" formatted="false">Tax (progressive scale 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Tax (flat 19%)</string>
    <string name="tax_label_ryczalt">Tax (lump-sum, of revenue)</string>
    <string name="pit_form_applicable">Applicable declaration: %1$s</string>

    <!-- History table -->
    <string name="history_col_receipt">Receipt</string>
    <string name="history_col_amount">Amount</string>

    <!-- Report columns -->
    <string name="report_col_receipt">Receipt</string>
    <string name="report_receipt_yes">Yes</string>

    <!-- Notifications -->
    <string name="notif_channel_name">Limits and deadlines</string>
    <string name="notif_channel_description">Alerts about activity limits and tax deadlines</string>
    <string name="notif_limit_exceeded_title">Unregistered activity limit exceeded</string>
    <string name="notif_limit_exceeded_text" formatted="false">Your income this month exceeds 75% of the minimum wage. You must register a JDG within 7 days.</string>
    <string name="notif_limit_95_title" formatted="false">95% of the monthly limit reached</string>
    <string name="notif_limit_95_text">You are very close to the unregistered-activity limit for this month.</string>
    <string name="notif_limit_80_title" formatted="false">80% of the monthly limit reached</string>
    <string name="notif_limit_80_text" formatted="false">You have used 80% of the unregistered-activity limit for this month.</string>
    <string name="notif_bracket_title">Approaching the 120,000 zł threshold</string>
    <string name="notif_bracket_text" formatted="false">Your yearly profit is close to 120,000 zł — income above this is taxed at 32% instead of 12%.</string>
    <string name="notif_vat_title">Approaching the VAT exemption limit</string>
    <string name="notif_vat_text">Your yearly revenue is close to 240,000 zł — the VAT exemption threshold.</string>
    <string name="notif_vat_exceeded_critical_title">VAT limit exceeded</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">You have exceeded the 240,000 zł VAT exemption limit. File form VAT-R within 7 days and confirm your registration in Settings — invoicing is blocked until then.</string>
    <string name="notif_kasa_exceeded_title">Fiscal cash register may be required</string>
    <string name="notif_kasa_exceeded_text" formatted="false">You have exceeded the 20,000 zł annual cash-sales limit for private individuals. Confirm in Settings once you have a kasa fiskalna — invoicing is blocked until then.</string>
    <string name="notif_advance_title">Advance tax payment reminder</string>
    <string name="notif_advance_text">Advance tax payments are due by the 20th of the month.</string>
    <string name="notif_pit_deadline_title">Annual tax return reminder</string>
    <string name="notif_pit_deadline_text">Annual tax returns are due between 15 February and 30 April.</string>
    <string name="terms_title">Terms of Service</string>
    <string name="terms_full_text">Terms of Service and Legal Disclaimer\n\nBy tapping “Accept”, you confirm that you have read, understood and fully agree to these terms. If you do not agree, you may not use the FinArs app.\n\n1. No accounting or legal services\nFinArs is a tool only (an automated calculator and record organizer). Neither the app nor its developers are an accredited accounting firm, tax advisor, or law office. All calculations and auto-generated declarations (PIT-36, PIT-36L, PIT-28) are for informational purposes only.\n\n2. Your responsibility\nYou are solely responsible for the accuracy of entered data and for verifying calculations and PDF forms before filing them with tax authorities, and for meeting filing deadlines.\n\n3. Limitation of liability\nThe app is provided “as is”, without warranties. The developer is not liable for fines, tax adjustments, algorithm errors, or data loss on your device.\n\n4. Legal changes\nPolish tax law changes regularly; verify results against podatki.gov.pl or a licensed accountant.\n\n5. Data privacy\nAll data and generated PDFs are stored locally on your device only.\n\n6. Governing law\nThe laws of the Republic of Poland apply.\n\n7. Withdrawal\nThese terms are accepted once, on first launch. If you stop agreeing, you must stop using the app and uninstall it.</string>
    <string name="terms_checkbox_label">I have read and accept the Terms of Service</string>
    <string name="terms_accept_button">Accept and continue</string>
    <string name="terms_status_accepted">Status: Terms accepted (%1$s)</string>
    <string name="terms_status_unknown">Status: Terms accepted</string>
    <string name="settings_menu_terms">Terms of Service</string>


    <!-- Invoices / Rachunki -->
    <string name="nav_invoices">Invoices</string>
    <string name="invoice_form_title">New invoice / receipt</string>
    <string name="invoice_seller_section">Seller (your details)</string>
    <string name="seller_name">Name / company name</string>
    <string name="seller_nip">NIP (leave empty if none)</string>
    <string name="seller_address_street">Street and number</string>
    <string name="seller_address_postal">Postal code</string>
    <string name="seller_address_city">City</string>
    <string name="invoice_buyer_section">Buyer</string>
    <string name="buyer_physical_person_switch">Private individual (no NIP)</string>
    <string name="buyer_name">First and last name / company name</string>
    <string name="buyer_nip">Buyer NIP</string>
    <string name="buyer_address_street">Street and number</string>
    <string name="buyer_address_postal">Postal code</string>
    <string name="buyer_address_city">City</string>
    <string name="invoice_service_section">Item / service</string>
    <string name="service_name">Name of the service or item</string>
    <string name="service_amount">Gross amount (PLN)</string>
    <string name="payment_date_label">Payment date</string>
    <string name="service_date_label">Service / sale date</string>
    <string name="payment_method_label">Payment method</string>
    <string name="payment_method_cash">Cash</string>
    <string name="payment_method_transfer">Transfer</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Paid in cash</string>
    <string name="payment_paid_transfer">Paid by bank transfer</string>
    <string name="payment_paid_blik">Paid by BLIK</string>
    <string name="cash_limit_title">Cash sales to individuals this year</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">You are approaching the annual cash-sales limit for private individuals without a fiscal cash register.</string>
    <string name="cash_limit_exceeded_warning">You have exceeded the 20,000 PLN annual cash-sales limit for private individuals — a fiscal cash register (kasa fiskalna) may now be required.</string>
    <string name="generate_invoice_button">Generate PDF</string>
    <string name="invoice_generated_toast">Invoice saved: %1$s</string>
    <string name="invoice_error_toast">Could not generate the invoice: %1$s</string>
    <string name="open_pdf_button">Open PDF</string>
    <string name="share_invoice_button">Share</string>
    <string name="open_invoices_folder_button">Open invoices folder</string>
    <string name="open_folder_error">Could not open the folder. Files are saved in %1$s</string>
    <string name="invoice_fill_required_fields">Please fill in the buyer, item and amount</string>
    <string name="invoice_blocked_toast">Invoicing is blocked — confirm your VAT/cash-register status in Settings first</string>
    <string name="invoice_is_receipt_label">This invoice is issued for a receipt (paragon)</string>
    <string name="vat_rate_choose">Choose VAT rate</string>
    <string name="vat_rate_selected" formatted="false">VAT rate: %1$s</string>
    <string name="vat_rate_picker_title">VAT rate</string>
    <string name="vat_rate_required_error">Choose a VAT rate for this invoice</string>
    <string name="vat_rate_23">23% (standard)</string>
    <string name="vat_rate_8">8% (reduced)</string>
    <string name="vat_rate_5">5% (minimum)</string>
    <string name="vat_rate_0">0% (export/WDT)</string>
    <string name="vat_rate_zw">zw (exempt)</string>
    <string name="vat_rate_np">np (not subject to tax)</string>
    <string name="vat_limit_block_message" formatted="false">You have exceeded the 240,000 zł VAT exemption limit. Confirm your VAT-R registration in Settings → Taxes to keep invoicing.</string>
    <string name="kasa_limit_block_message" formatted="false">You have exceeded the 20,000 zł annual cash-sales limit for private individuals. Confirm that you have a kasa fiskalna in Settings → Taxes to keep invoicing.</string>

    <!-- Invoice history -->
    <string name="invoice_history_title">Invoice history</string>
    <string name="no_invoices">No invoices yet</string>


    <!-- Invoice PDF labels -->
    <string name="invoice_pdf_faktura">INVOICE</string>
    <string name="invoice_pdf_rachunek">RECEIPT</string>
    <string name="invoice_pdf_issue_date">Issue date</string>
    <string name="invoice_pdf_sale_date">Sale date</string>
    <string name="invoice_pdf_seller">Seller</string>
    <string name="invoice_pdf_buyer">Buyer</string>
    <string name="invoice_pdf_nip">Tax ID (NIP)</string>
    <string name="invoice_pdf_bank_account">Bank account</string>
    <string name="invoice_pdf_buyer_private">Private individual (no Tax ID).</string>
    <string name="invoice_pdf_table_lp">No.</string>
    <string name="invoice_pdf_table_name">Item / service</string>
    <string name="invoice_pdf_table_unit">Unit</string>
    <string name="invoice_pdf_table_qty">Qty</string>
    <string name="invoice_pdf_table_price">Price</string>
    <string name="invoice_pdf_table_total">Total</string>
    <string name="invoice_pdf_unit_piece">pc</string>
    <string name="invoice_pdf_sum_label">Total</string>
    <string name="invoice_pdf_table_price_netto">Net price</string>
    <string name="invoice_pdf_table_netto">Net value</string>
    <string name="invoice_pdf_table_vat_rate">VAT rate</string>
    <string name="invoice_pdf_table_vat_amount">VAT amount</string>
    <string name="invoice_pdf_table_brutto">Gross value</string>
    <string name="invoice_pdf_receipt_label">Invoice issued for the fiscal receipt (paragon)</string>
    <string name="invoice_pdf_paid_stamp">PAID</string>
    <string name="invoice_pdf_payment_date">Payment date</string>
    <string name="invoice_pdf_footer">Document generated in the FinArs app. This is not official accounting or tax advice — if in doubt, consult a tax advisor.</string>
    <string name="seller_bank_account">Bank account (optional)</string>
    <string name="delete_invoice_confirm_title">Delete invoice?</string>
    <string name="delete_invoice_confirm_message">The invoice record and its PDF file will be permanently deleted. This cannot be undone.</string>
    <string name="invoice_deleted">Invoice deleted</string>

    <string name="invoice_status_paid">Paid</string>
    <string name="invoice_status_pending">Pending</string>
    <string name="invoice_status_overdue">Overdue</string>
    <string name="invoice_paid_switch_label">Paid</string>
    <string name="invoice_due_date_label">Due date</string>
    <string name="notif_invoice_overdue_title">Overdue invoice</string>
    <string name="notif_invoice_overdue_text">Invoice №%2$d for %1$s is overdue.</string>
    <string name="notif_invoice_due_soon_title">Payment due soon</string>
    <string name="notif_invoice_due_soon_text">Invoice №%2$d for %1$s is due within 3 days.</string>
    <string name="recurring_switch_label">Repeat monthly</string>
    <string name="chart_title">Income and expenses, last 6 months</string>
    <string name="invoice_status_filter_all">All</string>

    <string name="invoice_pdf_pending_stamp">AWAITING PAYMENT</string>

    <!-- Update 41: business kind, magazin, barcode, receipt OCR -->
    <string name="settings_menu_business">Sales type (goods/services)</string>
    <string name="business_kind_title">Sales type (goods/services)</string>
    <string name="business_kind_description">Choose what best matches your activity. Selecting Sales or Mixed adds a Warehouse (Magazyn) button on the main screen for tracking stock.</string>
    <string name="business_kind_sales">Sales</string>
    <string name="business_kind_services">Services</string>
    <string name="business_kind_mixed">Mixed (sales and services)</string>
    <string name="nav_magazin">Warehouse</string>
    <string name="magazin_title">Warehouse</string>
    <string name="magazin_empty">No products yet. Add one manually or scan a barcode.</string>
    <string name="add_product_manually">Add manually</string>
    <string name="scan_barcode">Scan barcode</string>
    <string name="scan_short">Scan</string>
    <string name="scan_barcode_prompt">Point the camera at the barcode</string>
    <string name="looking_up_product">Looking up product…</string>
    <string name="product_name">Product name</string>
    <string name="product_barcode">Barcode (optional)</string>
    <string name="product_quantity">Quantity in stock</string>
    <string name="product_unit">Unit (e.g. pcs, kg)</string>
    <string name="product_low_stock">Low stock threshold</string>
    <string name="product_price">Purchase price</string>
    <string name="product_price_sell">Sale price</string>
    <string name="product_margin">Margin %</string>
    <string name="product_margin_hint" formatted="false">Enter sale price directly, or enter a margin % to calculate it automatically from the purchase price (e.g. 60 = purchase price +60%).</string>
    <string name="gallery_scan_receipt_button">Scan receipt from gallery</string>
    <string name="product_saved">Product saved</string>
    <string name="low_stock_banner">%1$d product(s) running low</string>
    <string name="notif_low_stock_title">Stock running low</string>
    <string name="notif_low_stock_text">%1$s: only %2$s %3$s left</string>
    <string name="add_from_warehouse">Add items from warehouse</string>
    <string name="select_products_title">Select products</string>
    <string name="in_stock_suffix">in stock</string>
    <string name="select_at_least_one_product">Select at least one product</string>
    <string name="scan_receipt_button">Scan receipt (auto-fill)</string>
    <string name="receipt_scan_processing">Recognizing receipt…</string>
    <string name="receipt_scan_done">Receipt recognized, please check the fields</string>
    <string name="receipt_scan_no_text">Could not read the receipt, please enter manually</string>

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Mark as paid?</string>
    <string name="invoice_mark_paid_confirm_message">This sets the invoice status to paid today and updates the saved PDF file to reflect the new status.</string>
    <string name="invoice_marked_paid_toast">Invoice marked as paid</string>
    <string name="invoice_marked_paid_pdf_warning">Status updated, but the PDF file could not be regenerated</string>

    <!-- Update 42: warehouse inventory count + better receipt scanning -->
    <string name="start_inventory">Take inventory</string>
    <string name="inventory_title">Warehouse inventory</string>
    <string name="inventory_hint">Check the actual quantity of each product. Only changed items will be updated.</string>
    <string name="inventory_current_stock">In system: %1$s %2$s</string>
    <string name="inventory_save">Save inventory</string>
    <string name="inventory_no_changes">No differences found, nothing changed</string>
    <string name="inventory_saved_title">Inventory saved</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>

    <!-- Update 43: inventory PDF report + history + barcode scan, receipt item parsing fix -->
    <string name="inventory_scan_button">Scan product</string>
    <string name="inventory_history_button">Inventory history</string>
    <string name="inventory_scan_not_found">No product found for code %1$s</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">Inventory history</string>
    <string name="inventory_history_empty">No inventory counts yet</string>
    <string name="inventory_session_number">Inventory #%1$s</string>
    <string name="inventory_session_meta">%1$s items · changed: %2$s</string>
    <string name="inventory_session_meta_sell">Missed/extra revenue: %1$s</string>
    <string name="inventory_pdf_title">Inventory report #%1$s</string>
    <string name="inventory_pdf_date">Date</string>
    <string name="inventory_pdf_col_product">Product</string>
    <string name="inventory_pdf_col_unit">Unit</string>
    <string name="inventory_pdf_col_before">Before</string>
    <string name="inventory_pdf_col_after">After</string>
    <string name="inventory_pdf_col_diff">Diff</string>
    <string name="inventory_pdf_col_diff_value">Cost diff</string>
    <string name="inventory_pdf_col_diff_value_sell">Missed revenue</string>
    <string name="inventory_pdf_total_products">Total items checked</string>
    <string name="inventory_pdf_total_changed">Items changed</string>
    <string name="inventory_pdf_total_diff_value">Total cost value difference</string>
    <string name="inventory_pdf_total_diff_value_sell">Total missed/extra revenue (sale price)</string>

    <!-- Ryczałt categories: rate applied per transaction instead of one flat setting -->
    <string name="ryczalt_cat_3">3% — goods (towar)</string>
    <string name="ryczalt_cat_5_5">5.5% — production / manufactured products</string>
    <string name="ryczalt_cat_8_5">8.5% — services</string>
    <string name="ryczalt_cat_12">12% — IT services</string>
    <string name="ryczalt_cat_14">14% — medical services</string>
    <string name="ryczalt_cat_17">17% — freelance profession</string>
    <string name="ryczalt_category_picker_title">Ryczałt category</string>
    <string name="ryczalt_category_choose">Choose ryczałt category ▾</string>
    <string name="ryczalt_category_selected">Category: %1$s</string>
    <string name="ryczalt_category_required_error">Choose a ryczałt category for every item</string>
    <string name="income_ryczalt_category_required_error">Choose a ryczałt category for this income</string>

    <!-- VAT / kasa fiskalna compliance (Settings → Taxes) -->
    <string name="vat_compliance_title">VAT registration</string>
    <string name="vat_compliance_hint" formatted="false">You have exceeded the 240,000 zł annual VAT exemption limit. You must file form VAT-R within 7 days of the day you crossed the limit, and start charging VAT on the transaction that crossed it. Confirm below once you have registered — invoicing stays blocked until you do.</string>
    <string name="cb_vat_registered_label">I confirm I have registered as a VAT payer (filed VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Confirmed: registered as a VAT payer</string>
    <string name="kasa_compliance_title">Fiscal cash register (kasa fiskalna)</string>
    <string name="kasa_compliance_hint">You have exceeded the 20,000 zł annual limit of cash sales to private individuals. A fiscal cash register may now be required. Confirm below once you have one — invoicing stays blocked until you do.</string>
    <string name="kasa_compliance_hint_registered">Your business is registered (JDG), so you may already have a fiscal cash register from the start. If you do, confirm it below — this unlocks the \"issued for a receipt\" option when filling out invoices.</string>
    <string name="cb_kasa_label">I confirm I have a fiscal cash register (kasa fiskalna)</string>
    <string name="cb_kasa_confirmed_label">Confirmed: fiscal cash register in use</string>
    <string name="vat_confirm_dialog_title">Confirm VAT registration</string>
    <string name="vat_confirm_dialog_message">This confirms you have filed VAT-R and are now a VAT payer. This cannot be undone in the app. Continue?</string>
    <string name="kasa_confirm_dialog_title">Confirm fiscal cash register</string>
    <string name="kasa_confirm_dialog_message">This confirms you have a fiscal cash register (kasa fiskalna). This cannot be undone in the app. Continue?</string>
    <string name="confirm_yes">Yes, confirm</string>
    <string name="confirm_cancel">Cancel</string>

    <!-- Push notification frequency (Settings → Taxes) -->
    <string name="push_frequency_title">Push notification frequency</string>
    <string name="push_frequency_hint">How many times per day you can receive alerts about exceeded limits and overdue invoices (1–50).</string>
    <string name="push_frequency_saved">Notification frequency saved</string>
    <string name="push_frequency_invalid">Enter a number between 1 and 50</string>
    <string name="income_ryczalt_category_label">Ryczałt category for this income</string>

    <!-- Multi-item invoices -->
    <string name="invoice_item_number_label">Item %1$d</string>
    <string name="add_invoice_item_row">+ Add item</string>
    <string name="invoice_items_limit_reached">You can add up to %1$d items per invoice</string>
    <string name="invoice_item_min_required">An invoice needs at least one item</string>
    <string name="invoice_total_label">Total: %1$s zł</string>
    <string name="item_qty_hint">Qty</string>
    <string name="invoice_income_comment">Invoice #%1$d — %2$s</string>

    <!-- Update: teksty prawne na dokumencie PDF (faktura/rachunek) — CELOWO tylko
         w tym pliku (bez odpowiedników w values-pl/values-ru), bo to formalna treść
         z polskiej ustawy o VAT i musi zostać po polsku na dokumencie niezależnie od
         języka interfejsu aplikacji (patrz InvoicePdfGenerator.kt). -->
    <string name="invoice_pdf_seller_nierejestrowana_note">Osoba fizyczna prowadząca działalność nierejestrowaną (bez NIP).</string>
    <string name="invoice_pdf_legal_basis_title">Podstawa prawna zwolnienia z VAT:</string>
    <string name="invoice_pdf_legal_basis_text">Sprzedawca zwolniony z podatku od towarów i usług na podstawie art. 113 ust. 1 (lub ust. 9) ustawy o VAT.</string>

    <!-- Update: moduł Korekta (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Correction invoice</string>
    <string name="correction_original_invoice_label">Original document: #%1$d, %2$s</string>
    <string name="correction_original_amount_label">Original amount</string>
    <string name="correction_corrected_amount_hint">Corrected amount (zł)</string>
    <string name="correction_reason_hint">Reason for the correction</string>
    <string name="correction_apply_to_income_label">Apply the difference to income (Przychód)</string>
    <string name="correction_save_button">Issue correction</string>
    <string name="correction_zero_delta_error">The corrected amount is the same as the original — nothing to correct</string>
    <string name="correction_reason_required_error">Please enter the reason for the correction</string>
    <string name="correction_saved_toast">Correction invoice issued</string>
    <string name="correction_pdf_title">CORRECTION INVOICE</string>
    <string name="correction_pdf_to_invoice">Correction to invoice</string>
    <string name="correction_pdf_reason_label">Reason for the correction</string>
    <string name="correction_pdf_before_label">Amount before correction</string>
    <string name="correction_pdf_after_label">Amount after correction</string>
    <string name="correction_pdf_delta_label">Difference</string>
    <!-- Update: items table on the correction PDF + signature fields on both PDFs -->
    <string name="correction_pdf_before_table_title">Before correction</string>
    <string name="correction_pdf_after_table_title">After correction</string>
    <string name="invoice_pdf_signature_issued_by">Issued by:</string>
    <string name="invoice_pdf_signature_received_by">Received by:</string>
    <string name="invoice_pdf_signature_issued_by_caption">Signature of the person authorized to issue</string>
    <string name="invoice_pdf_signature_received_by_caption">Signature of the person authorized to receive</string>
    <!-- Update: corrections now also appear in Historia faktur (Invoice history) -->
    <string name="correction_history_row_title">Correction #%1$d → invoice #%2$d</string>
    <string name="correction_history_row_title_solo">Correction #%1$d</string>
    <string name="delete_correction_confirm_title">Delete correction?</string>
    <string name="delete_correction_confirm_message">The correction record and its PDF file will be permanently deleted. This cannot be undone. The income entry created by this correction (if any) will not be reverted automatically.</string>
    <string name="correction_deleted">Correction deleted</string>
    <string name="nav_start">Start</string>
    <string name="nav_transactions">Transactions</string>
    <string name="nav_reports">Reports</string>
    <string name="nav_settings">Settings</string>
</resources>

STRINGS_EN
echo "  app/src/main/res/values/strings.xml written"

mkdir -p "$(dirname "app/src/main/res/values-pl/strings.xml")"
cat > "app/src/main/res/values-pl/strings.xml" << 'STRINGS_PL'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Dodaj przychód</string>
    <string name="add_expense">Dodaj wydatek</string>
    <string name="add_entry">Dodaj +</string>
    <string name="balance">Bilans</string>
    <string name="enter_amount">Kwota</string>
    <string name="enter_comment">Komentarz</string>
    <string name="entry_date_label">Data transakcji</string>
    <string name="attach_receipt">Dołącz paragon</string>
    <string name="save">Zapisz</string>
    <string name="settings">Ustawienia</string>
    <string name="tax_percent">Procent podatku</string>
    <string name="other_income_label">Inne przychody (%1$d)</string>
    <string name="tax_scale_title">Podatek liczony jest automatycznie</string>
    <string name="tax_scale_description" formatted="false">0% do 30 000 zł/rok · 12% od kwoty od 30 000 do 120 000 zł · 32% od kwoty powyżej 120 000 zł. Stawka dotyczy tylko części ponad każdy próg, a nie całej kwoty.</string>
    <string name="other_income_title">Inne przychody</string>
    <string name="other_income_hint">Twój łączny dochód podlegający opodatkowaniu w tym roku z innych źródeł (etat, inna działalność itd.). Uwzględniany razem z dochodem z tej aplikacji przy sprawdzaniu rocznego limitu wolnego od podatku 30 000 zł.</string>
    <string name="saved">Zapisano</string>
    <string name="auto_tax_button">Oblicz automatycznie</string>
    <string name="auto_tax_result" formatted="false">Sugerowana stawka: %1$.1f% (wg skali PIT: 12% do 120 000 zł/rok, 32% powyżej). Przed zapisaniem można poprawić ręcznie.</string>
    <string name="export_report">Eksportuj raport</string>
    <string name="generate_report">Generuj raport</string>
    <string name="select_period">Wybierz okres</string>
    <string name="month">Miesiąc</string>
    <string name="year">Rok</string>
    <string name="custom_range">Zakres niestandardowy</string>
    <string name="from">Od</string>
    <string name="to">Do</string>
    <string name="no_entries">Brak wpisów</string>
    <string name="search_no_results">Nic nie znaleziono</string>
    <string name="history_search_hint">Szukaj po komentarzu lub kwocie</string>
    <string name="invoice_search_hint">Szukaj po numerze, kliencie lub kwocie</string>
    <string name="filter_date_range">Zakres dat</string>
    <string name="filter_clear">Wyczyść filtry</string>

    <string name="statistics">Statystyka</string>
    <string name="stat_income">Przychód</string>
    <string name="stat_expense">Wydatek</string>
    <string name="stat_profit">Zysk (brutto)</string>
    <string name="stat_tax_format" formatted="false">Podatek (%1$.1f%)</string>

    <string name="report_col_date">Data</string>
    <string name="report_col_income">Przychód</string>
    <string name="report_col_expense">Wydatek</string>
    <string name="report_col_tax_percent" formatted="false">Podatek %</string>
    <string name="report_col_tax_amount">Kwota podatku</string>
    <string name="report_col_comment">Komentarz</string>
    <string name="report_sheet_name">Raport</string>
    <string name="report_title_month">Raport — Miesiąc</string>
    <string name="report_title_year">Raport — Rok</string>
    <string name="report_title_custom">Raport — Zakres niestandardowy</string>
    <string name="custom_range_invalid">Data końcowa musi być późniejsza niż data początkowa</string>
    <string name="report_total_income">Suma przychodów</string>
    <string name="report_total_expense">Suma wydatków</string>
    <string name="report_total_profit">Suma zysku</string>
    <string name="report_total_tax">Suma podatku</string>
    <string name="report_total_net_profit">Zysk netto (po podatku)</string>
    <string name="report_generating">Generuję raport…</string>
    <string name="report_ready">Raport gotowy</string>
    <string name="report_share_title">Udostępnij raport</string>
    <string name="report_error">Błąd generowania raportu: %1$s</string>
    <string name="about_app">O aplikacji</string>
    <string name="about_version_label">Wersja %1$s</string>
    <string name="settings_menu_privacy">Polityka prywatności</string>
    <string name="about_email">finars2026@gmail.com</string>

    <string name="privacy_updated_label">Ostatnia aktualizacja: 11 sierpnia 2026 r.</string>
    <string name="privacy_intro">Szanujemy Twoją prywatność. Aplikacja FinArs została zaprojektowana z myślą o maksymalnym bezpieczeństwie Twoich danych — większość informacji przechowywana jest wyłącznie na Twoim urządzeniu.</string>

    <string name="privacy_section1_title">1. Administrator danych osobowych</string>
    <string name="privacy_section1_body">Administratorem aplikacji jest twórca FinArs. W sprawach związanych z ochroną prywatności i przetwarzaniem danych możesz skontaktować się pod adresem e-mail: finars2026@gmail.com.</string>

    <string name="privacy_section2_title">2. Jakie dane przetwarzamy i gdzie je przechowujemy?</string>
    <string name="privacy_section2_intro">Wszystkie Twoje kluczowe dane finansowe i biznesowe są przechowywane WYŁĄCZNIE LOKALNIE w pamięci Twojego urządzenia. Nie posiadamy własnych serwerów i nie zbieramy tych informacji.</string>
    <string-array name="privacy_section2_bullets">
        <item>Dane finansowe i transakcje: kwoty, daty, kategorie, komentarze oraz numery i dane faktur (w tym dane kontrahentów i NIP) nie opuszczają Twojego telefonu.</item>
        <item>Stan magazynowy: dane o produktach i inwentaryzacji są zapisywane wyłącznie w lokalnej bazie danych aplikacji.</item>
        <item>Zdjęcia paragonów dołączane ręcznie do transakcji: przechowywane wyłącznie lokalnie na Twoim urządzeniu, nigdy nie są wysyłane do chmury.</item>
        <item>Zabezpieczenia (PIN / biometria): kod PIN jest przechowywany w postaci zaszyfrowanej w bezpiecznym magazynie danych urządzenia i nigdy nie jest nigdzie przesyłany.</item>
    </string-array>

    <string name="privacy_section3_title">3. Usługi zewnętrzne (podmioty trzecie)</string>
    <string name="privacy_section3_intro">Aplikacja korzysta z zaufanych usług zewnętrznych do obsługi płatności i reklam:</string>
    <string-array name="privacy_section3_bullets">
        <item>Google Play Billing — obsługuje proces zakupu i weryfikacji subskrypcji FinArs Pro. Nie mamy dostępu do danych Twojej karty płatniczej (płatność obsługuje Google).</item>
        <item>RevenueCat — po publikacji aplikacji będzie zarządzać statusem subskrypcji Pro (aktywna / wygasła / okres próbny), przetwarzając anonimowy identyfikator użytkownika i status zakupu, aby przyznać dostęp do funkcji Pro na wszystkich Twoich urządzeniach.</item>
        <item>Google AdMob — wyświetla reklamy użytkownikom bez aktywnej subskrypcji Pro. AdMob może zbierać anonimowy identyfikator reklamowy oraz dane diagnostyczne w celu serwowania reklam (zgodnie z wyrażoną zgodą RODO/GDPR za pośrednictwem formularza zgody Google UMP). Polityka prywatności Google: policies.google.com/privacy</item>
    </string-array>

    <string name="privacy_section4_title">4. Wymagane uprawnienia aplikacji</string>
    <string name="privacy_section4_intro">Aplikacja prosi tylko o uprawnienia niezbędne do jej prawidłowego działania:</string>
    <string-array name="privacy_section4_bullets">
        <item>Aparat — wymagany wyłącznie do skanowania kodów kreskowych w magazynie oraz robienia zdjęć paragonów.</item>
        <item>Powiadomienia — wymagane do przypominania o terminach płatności faktur oraz przekroczeniu limitów (np. działalności nierejestrowanej).</item>
        <item>Pamięć — wymagana na starszych wersjach systemu Android do zapisywania kopii zapasowych oraz eksportu raportów (np. PDF / CSV).</item>
        <item>Dostęp do internetu — wymagany wyłącznie przez opisane wyżej moduły reklam i płatności; nie jest wykorzystywany do przesyłania Twoich danych finansowych.</item>
    </string-array>

    <string name="privacy_section5_title">5. Zarządzanie danymi i Twoje prawa</string>
    <string name="privacy_section5_body">Ponieważ Twoje dane znajdują się na Twoim telefonie, masz nad nimi pełną kontrolę: możesz w dowolnym momencie wyczyścić wszystkie dane w aplikacji (Ustawienia -> Kopia zapasowa -> Wyczyść dane) lub po prostu odinstalować aplikację. Samodzielnie decydujesz, gdzie i kiedy eksportujesz plik kopii zapasowej.</string>

    <string name="privacy_section6_title">6. Dzieci</string>
    <string name="privacy_section6_body">Aplikacja nie jest skierowana do osób poniżej 16 roku życia i nie zbiera świadomie żadnych danych od dzieci.</string>

    <string name="privacy_section7_title">7. Zmiany w Polityce Prywatności</string>
    <string name="privacy_section7_body">Zastrzegamy sobie prawo do aktualizacji niniejszej Polityki Prywatności. Każda zmiana zostanie opublikowana w tym miejscu wraz z nową datą aktualizacji.</string>

    <string name="privacy_section8_title">8. Kontakt</string>
    <string name="privacy_section8_body">W razie jakichkolwiek pytań dotyczących prywatności lub działania aplikacji, skontaktuj się z nami: finars2026@gmail.com</string>

    <string name="about_intro">FinArs to kompleksowa aplikacja do zarządzania finansami działalności nierejestrowanej. Śledź przychody i wydatki, kontroluj limity, automatycznie licz podatki, wystawiaj faktury, zarządzaj magazynem i generuj gotowe raporty oraz deklaracje PIT — wszystko w jednym miejscu, z pełną historią operacji i powiadomień zawsze pod ręką.</string>
    <string name="about_subscription_note">⭐ Subskrypcja Pro: plan miesięczny lub roczny, 7 dni za darmo, anulowanie w każdej chwili.</string>

    <string name="about_section_finance_title">📊 Finanse i podatki</string>
    <string-array name="about_bullets_finance">
        <item>Ewidencja przychodów i wydatków z załącznikami paragonów i kolorowymi kategoriami</item>
        <item>Automatyczne obliczanie zysku i podatku (skala 12%/32%)</item>
        <item>Transakcje cykliczne (czynsz, abonamenty) tworzone automatycznie co miesiąc</item>
        <item>Kontrola limitu działalności nierejestrowanej (próg 120 000 zł)</item>
        <item>Historia powiadomień o zbliżających się i przekroczonych limitach, terminach faktur i innych</item>
    </string-array>

    <string name="about_section_warehouse_title">📦 Magazyn</string>
    <string-array name="about_bullets_warehouse">
        <item>Katalog produktów ze skanowaniem kodów kreskowych, stanami magazynowymi i alertami o niskim stanie</item>
        <item>Sesje inwentaryzacji z historią</item>
        <item>Produkty można dodawać bezpośrednio do faktur</item>
    </string-array>

    <string name="about_section_invoices_title">🧾 Faktury i rachunki (Pro)</string>
    <string-array name="about_bullets_invoices">
        <item>Wystawianie faktur/rachunków dla osób fizycznych i firm z generowaniem PDF</item>
        <item>Statusy: Zapłacona / Oczekuje na zapłatę / Zaległa, plus przypomnienia o terminie płatności</item>
        <item>Kontrola rocznego limitu gotówki (20 000 zł) dla sprzedaży osobom fizycznym</item>
        <item>Historia faktur z wyszukiwaniem i filtrami</item>
    </string-array>

    <string name="about_section_reports_title">📄 Raporty i deklaracje</string>
    <string-array name="about_bullets_reports">
        <item>Podsumowanie przychodów/wydatków i wykres trendu za 6 miesięcy</item>
        <item>Eksport raportu miesięcznego (bezpłatnie), rocznego i za dowolny okres (Pro) do Excela wraz z paragonami</item>
        <item>Generowanie deklaracji PIT-36 — pomocniczy PDF oraz wypełnienie oficjalnego formularza (Pro)</item>
    </string-array>

    <string name="about_section_security_title">🔒 Bezpieczeństwo i wygoda</string>
    <string-array name="about_bullets_security">
        <item>Blokada aplikacji kodem PIN oraz odciskiem palca / twarzą</item>
        <item>Kopia zapasowa i przywracanie danych (Pro)</item>
        <item>Nowoczesny ciemny interfejs</item>
        <item>Dostępne w języku polskim, rosyjskim i angielskim</item>
        <item>Wszystkie dane finansowe są przechowywane lokalnie na urządzeniu</item>
    </string-array>
    <string name="dialog_close">Zamknij</string>
    <string name="dialog_write">Napisz</string>
    <string name="pro_status_locked">Pro jest zablokowane. Odblokuj, aby uzyskać roczne i niestandardowe raporty Excel, kopię zapasową i przywracanie danych oraz usunąć reklamy.</string>
    <string name="pro_status_active">Pro odblokowane. Dziękujemy za wsparcie!</string>
    <string name="pro_unlock_button">Odblokuj Pro</string>
    <string name="pro_unlock_button_price">Odblokuj Pro — %1$s</string>
    <string name="pro_trial_hint">7 dni za darmo, potem naliczana automatycznie. Anuluj w każdej chwili.</string>
    <string name="pro_plan_monthly">Plan miesięczny</string>
    <string name="pro_plan_yearly">Plan roczny (najlepsza oferta)</string>
    <string name="pro_plan_monthly_price">Miesięcznie — %1$s / mies.</string>
    <string name="pro_plan_yearly_price">Rocznie — %1$s / rok</string>
    <string name="pro_loading">Ładowanie ceny…</string>
    <string name="pro_feature_locked_title">Funkcja Pro</string>
    <string name="pro_feature_locked_message">Raporty roczne i niestandardowe są dostępne tylko w wersji Pro. Odblokuj Pro w ustawieniach.</string>
    <string name="pro_feature_locked_go_settings">Przejdź do ustawień</string>
    <string name="invoice_pro_locked_message">Wystawianie faktur jest dostępne tylko w wersji Pro. Odblokuj Pro w ustawieniach.</string>
    <string name="backup_pro_locked_message">Kopia zapasowa i przywracanie to funkcja Pro. Odblokuj Pro, aby zabezpieczyć swoje dane plikiem kopii zapasowej.</string>
    <string name="pro_purchase_error">Nie udało się otworzyć zakupu. Sprawdź połączenie i spróbuj ponownie.</string>
    <string name="pro_info_title">Wersja Pro</string>
    <string name="pro_info_message">Pro odblokowuje:\n\n\u2022 Wystawianie faktur i rachunków (PDF)\n\u2022 Raport roczny w Excelu\n\u2022 Raport za dowolny okres\n\u2022 Generowanie deklaracji PIT-36\n\u2022 Kopia zapasowa i przywracanie danych\n\u2022 Brak reklam</string>
    <string name="pro_info_continue">Przejdź do zakupu</string>
    <string name="paywall_header_white">Odblokuj</string>
    <string name="paywall_header_blue">FinArs Pro</string>
    <string name="paywall_subtitle">Zyskaj pełną kontrolę nad finansami\ni pracuj bez ograniczeń.</string>
    <string name="paywall_feature_1">Wystawianie faktur i rachunków (PDF)</string>
    <string name="paywall_feature_2">Generowanie deklaracji PIT-36</string>
    <string name="paywall_feature_3">Raporty roczne i niestandardowe (Excel)</string>
    <string name="paywall_feature_4">Kopia zapasowa danych w chmurze i lokalnie</string>
    <string name="paywall_feature_5">Brak reklam</string>
    <string name="paywall_badge">NAJPOPULARNIEJSZY • OSZCZĘDZASZ 30%</string>
    <string name="paywall_plan_yearly_title">Plan Roczny</string>
    <string name="paywall_plan_monthly_title">Plan Miesięczny</string>
    <string name="paywall_price_yearly_default">99,99 zł</string>
    <string name="paywall_price_monthly_default">11,99 zł</string>
    <string name="paywall_per_year">/ rok</string>
    <string name="paywall_per_month">/ miesiąc</string>
    <string name="paywall_trial_yearly">7 dni za 0 zł, potem %1$s / rok</string>
    <string name="paywall_trial_monthly">7 dni za 0 zł, potem %1$s / miesiąc</string>
    <string name="paywall_per_month_note">Tylko 8,33 zł / miesiąc</string>
    <string name="paywall_cta">Wypróbuj 7 dni za 0 zł</string>
    <string name="paywall_footer_1">Bez opłat przez pierwsze 7 dni.\nAnulujesz w każdej chwili w Google Play.</string>
    <string name="paywall_data_safe">Twoje dane są bezpieczne</string>
    <string name="paywall_footer_2">Płatność rozpocznie się po 7 dniach.\nMożesz anulować w dowolnym momencie.</string>
    <string name="enter_code_button">Masz kod?</string>
    <string name="enter_code_title">Wprowadź kod</string>
    <string name="enter_code_hint">Kod</string>
    <string name="enter_code_apply">Zastosuj</string>
    <string name="enter_code_wrong">Nieprawidłowy kod</string>
    <string name="enter_code_success">Pro odblokowane</string>
    <string name="transaction_history">Historia transakcji</string>
    <string name="stat_net_profit">Zysk netto (po podatku)</string>
    <string name="type_income">Przychód</string>
    <string name="type_expense">Wydatek</string>
    <string name="edit_income_title">Edytuj przychód</string>
    <string name="edit_expense_title">Edytuj wydatek</string>
    <string name="delete_entry">Usuń</string>
    <string name="delete_confirm_title">Usunąć wpis?</string>
    <string name="delete_confirm_message">Wpis zostanie trwale usunięty. Tej czynności nie można cofnąć.</string>
    <string name="delete_confirm_yes">Usuń</string>
    <string name="entry_updated">Zaktualizowano</string>
    <string name="entry_deleted">Usunięto</string>
    <string name="clear_all_button">Wyczyść wszystkie dane</string>
    <string name="clear_all_confirm_title">Na pewno?</string>
    <string name="clear_all_confirm_message">Wszystkie przychody i wydatki zostaną trwale usunięte. Tej czynności nie można cofnąć.</string>
    <string name="clear_all_confirm_yes">Usuń wszystko</string>
    <string name="clear_all_done">Wszystkie dane zostały usunięte</string>

    <string name="settings_menu_tax">Podatek i limity</string>
    <string name="settings_menu_language">Język</string>
    <string name="settings_menu_backup">Kopia zapasowa (Pro)</string>
    <string name="settings_menu_pro">Wersja Pro</string>

    <string name="backup_hint">Zapisz kopię zapasową przychodów/wydatków — kwoty, daty, komentarze i załączone zdjęcia paragonów — jako plik. W oknie zapisu możesz wybrać pamięć telefonu lub Dysk Google (jeśli aplikacja Dysku jest zainstalowana). Przechowuj ten plik w bezpiecznym miejscu — to jedyny sposób odzyskania danych w razie utraty telefonu lub reinstalacji aplikacji.</string>
    <string name="backup_in_progress">Trwa…</string>
    <string name="backup_create">Utwórz kopię zapasową</string>
    <string name="backup_restore">Przywróć z kopii</string>
    <string name="backup_success">Kopia zapisana (%1$d wpisów)</string>
    <string name="backup_error">Błąd: %1$s</string>
    <string name="backup_restore_confirm_title">Przywrócić z kopii?</string>
    <string name="backup_restore_confirm_message">Wpisy z pliku kopii zostaną dodane do tych, które już są na tym urządzeniu (istniejące wpisy nie są usuwane ani nadpisywane). Jeśli potrzebujesz "czystego" przywrócenia — najpierw użyj "Wyczyść wszystkie dane", a potem przywróć kopię.</string>
    <string name="backup_invalid_file">To nie wygląda na poprawny plik kopii zapasowej FinArs</string>
    <string name="backup_restored">Przywrócono wpisów: %1$d</string>
    <string name="backup_never">Ostatnia kopia: nigdy</string>
    <string name="backup_last_time">Ostatnia kopia: %1$s</string>

    <string name="settings_menu_security">Bezpieczeństwo (PIN / odcisk palca)</string>
    <string name="settings_menu_pit36">Generuj PIT (Pro)</string>
    <string name="pit36_pro_locked_message">Generowanie PIT-36 to funkcja Pro. Odblokuj Pro w Ustawieniach, aby z niej skorzystać.</string>

    <string name="lock_title">FinArs jest zablokowany</string>
    <string name="lock_subtitle">Wpisz PIN, aby kontynuować</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Błędny PIN, spróbuj ponownie</string>
    <string name="lock_unlock_button">Odblokuj</string>
    <string name="lock_biometric_button">Użyj odcisku palca / twarzy</string>
    <string name="lock_biometric_prompt_title">Odblokuj FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Potwierdź odciskiem palca lub twarzą</string>
    <string name="lock_use_pin">Użyj PIN-u</string>
    <string name="lock_biometric_unavailable">Na tym urządzeniu nie skonfigurowano odcisku palca/twarzy. Dodaj go najpierw w ustawieniach telefonu.</string>

    <string name="security_hint">Zabezpiecz aplikację kodem PIN. Gdy funkcja jest włączona, FinArs poprosi o PIN za każdym razem, gdy wrócisz do aplikacji po jej opuszczeniu. Możesz też włączyć odblokowanie odciskiem palca/twarzą jako szybki skrót zamiast wpisywania tego samego PIN-u.</string>
    <string name="security_pin_switch">Wymagaj PIN-u przy otwieraniu aplikacji</string>
    <string name="security_change_pin">Zmień PIN</string>
    <string name="security_biometric_switch">Odblokowanie odciskiem palca / twarzą</string>
    <string name="security_set_pin_title">Ustaw PIN</string>
    <string name="security_set_pin_message">Wybierz PIN z 4–6 cyfr</string>
    <string name="security_continue">Dalej</string>
    <string name="security_pin_length_error">PIN musi mieć 4–6 cyfr</string>
    <string name="security_confirm_pin_title">Potwierdź PIN</string>
    <string name="security_pin_saved">PIN zapisany</string>
    <string name="security_pin_mismatch">PIN-y się nie zgadzają, spróbuj ponownie</string>
    <string name="security_disable_pin_title">Wpisz aktualny PIN</string>
    <string name="security_enter_current_pin">Wpisz aktualny PIN, aby kontynuować</string>
    <string name="security_pin_disabled">Ochrona PIN-em wyłączona</string>

    <string name="pit_data_title">Dane osobowe do zeznania podatkowego</string>
    <string name="pit_data_hint">Używane wyłącznie do wypełnienia pomocniczego raportu PIT (PIT-36 / PIT-36L / PIT-28 — zależnie od rodzaju działalności). Wszystko zostaje na Twoim urządzeniu.</string>
    <string name="pit_first_name">Imię</string>
    <string name="pit_last_name">Nazwisko</string>
    <string name="pit_pesel">PESEL (opcjonalnie)</string>
    <string name="pit_street">Ulica</string>
    <string name="pit_house_number">Numer domu</string>
    <string name="pit_apartment_number">Numer mieszkania (opcjonalnie)</string>
    <string name="pit_voivodeship">Województwo</string>
    <string name="pit_county">Powiat</string>
    <string name="pit_commune">Gmina</string>
    <string name="pit_postal_code">Kod pocztowy</string>
    <string name="pit_city">Miejscowość</string>
    <string name="pit_tax_office">Urząd skarbowy</string>
    <string name="pit_reliefs_title">Ulgi i odliczenia (opcjonalnie)</string>
    <string name="pit_children_count">Liczba dzieci (ulga na dzieci)</string>
    <string name="pit_internet_relief">Ulga internetowa — poniesiony wydatek</string>
    <string name="pit_ikze">Wpłaty na IKZE</string>
    <string name="pit_donations">Darowizny</string>
    <string name="pit_joint_spouse">Rozliczenie wspólnie z małżonkiem</string>
    <string name="pit_spouse_data_title">Dane osobowe małżonka</string>
    <string name="pit_spouse_id_hint">NIP/PESEL małżonka</string>
    <string name="pit_spouse_first_name_hint">Imię małżonka</string>
    <string name="pit_spouse_last_name_hint">Nazwisko małżonka</string>
    <string name="pit_spouse_birth_date_hint">Data urodzenia (DD.MM.RRRR)</string>
    <string name="pit_spouse_income_hint">Dochód małżonka (opcjonalnie)</string>
    <string name="pit_data_required_error">Uzupełnij najpierw imię, nazwisko i urząd skarbowy</string>

    <string name="pit36_hint">Wybierz pełny rok kalendarzowy, sprawdź swoje dane osobowe, a następnie wygeneruj pomocniczy plik PDF z liczbami i wskazówkami do wypełnienia Twojej właściwej deklaracji na podatki.gov.pl (Twój e-PIT) lub na papierze.</string>
    <string name="pit_row_przychod">Przychód</string>
    <string name="pit_row_koszty">Koszty</string>
    <string name="pit_row_dochod">Dochód</string>
    <string name="pit_row_tax">Szacowany podatek</string>
    <string name="pit_data_status_missing">Dane osobowe nie zostały jeszcze uzupełnione — są wymagane przed wygenerowaniem raportu.</string>
    <string name="pit_data_status_ready">Dane osobowe gotowe: %1$s</string>
    <string name="pit_edit_data_button">Edytuj dane osobowe</string>
    <string name="pit36_generate_button">Wygeneruj pomocniczy PDF</string>
    <string name="pit36_disclaimer">Ten raport ma charakter wyłącznie informacyjny i nie jest oficjalnym formularzem, e-Deklaracją ani poradą podatkową. Zawsze zweryfikuj liczby przed złożeniem deklaracji.</string>
    <string name="pit36_calculating">Trwa obliczanie, chwila…</string>
    <string name="pit36_generated">Raport PDF wygenerowany</string>
    <string name="pit36_generate_official_button">Wypełnij oficjalny formularz (szablon 2025)</string>
    <string name="pit36_official_hint">Wypełnia prawdziwy urzędowy PDF %1$s(32)/2025: Twoje dane, adres i wiersz przychodów/kosztów działalności. Pozostałe źródła dochodu i odliczenia musisz uzupełnić samodzielnie — zobacz zastrzeżenie poniżej.</string>
    <string name="pit36_official_unsupported">Oficjalny wypełniony formularz jest dostępny tylko dla PIT-36 (skala). Twoja aktualna forma to %1$s — użyj przycisku „Wygeneruj pomocniczy PDF”.</string>
    <string name="pit36_official_generated">Oficjalny formularz PIT-36 wypełniony. Sprawdź sekcje E–K i dodaj inne dochody/odliczenia przed złożeniem.</string>

    <!-- Rodzaj działalności / zasady rejestracji -->
    <string name="activity_type_title">Rodzaj działalności</string>
    <string name="activity_type_hint">Wybierz, jak działasz — od tego zależy stosowany limit i to, którą deklarację złożysz.</string>
    <string name="activity_type_niezarejestrowana">Działalność nierejestrowana (bez JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Przychód nie może przekroczyć 75% minimalnego wynagrodzenia miesięcznie. W razie przekroczenia musisz zarejestrować JDG w ciągu 7 dni. Rozliczenie przez PIT-36, skala podatkowa.</string>
    <string name="activity_type_jdg_skala" formatted="false">Zarejestrowana JDG — skala 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Zarejestrowana JDG — podatek liniowy 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Zarejestrowana JDG — ryczałt (PIT-28)</string>
    <string name="ryczalt_rate_moved_title">Stawka ryczałtu według kategorii</string>
    <string name="ryczalt_rate_moved_hint">Każdy przychód i każda pozycja faktury ma swoją kategorię — towar, produkcja, usługi, usługi IT, usługi medyczne, wolny zawód. Stawka podatku dobierana jest automatycznie na podstawie wybranej kategorii.</string>
    <string name="min_wage_label">Minimalne wynagrodzenie miesięczne (zł) — do obliczenia limitu działalności nierejestrowanej</string>
    <string name="monthly_limit_preview" formatted="false">Limit miesięczny (75%): %1$,.2f zł</string>

    <!-- Wskaźniki limitów na ekranie głównym -->
    <string name="limits_title">Limity</string>
    <string name="limit_monthly_label">Działalność nierejestrowana, ten miesiąc: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Pierwszy próg podatkowy (120 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_tax_free">Kwota wolna od podatku (0–30 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">Próg 12%% (30 000–120 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">Próg 120 000 zł przekroczony — nadwyżka %1$s zł opodatkowana stawką 32%%</string>
    <string name="limit_vat_label">Zwolnienie z VAT (240 000 zł/rok): %1$s / %2$s zł</string>
    <string name="limit_bracket_title">Próg podatkowy (120 000 zł/rok)</string>
    <string name="limit_bracket_title_tax_free">Kwota wolna od podatku (0–30 000 zł/rok)</string>
    <string name="limit_bracket_title_rate12">Próg 12% (30 000–120 000 zł/rok)</string>
    <string name="limit_bracket_title_rate32">Próg 32% (powyżej 120 000 zł/rok)</string>
    <string name="limit_exceeded_warning">Przekroczono limit działalności nierejestrowanej! Musisz zarejestrować JDG w ciągu 7 dni.</string>
    <string name="limits_remaining">Pozostało: %1$s zł</string>
    <string name="limits_limit_of">Limit: %1$s zł</string>
    <string name="limits_about_title">O limitach</string>
    <string name="limits_about_desc">Przekroczenie limitu działalności nierejestrowanej może spowodować konieczność rejestracji firmy i zmianę formy opodatkowania.</string>
    <string name="back">Wstecz</string>
    <string name="category_sale">Przychód ze sprzedaży</string>
    <string name="category_invoice">Faktura</string>
    <string name="category_materials">Zakup materiałów</string>
    <string name="category_fuel">Paliwo</string>
    <string name="category_transport">Usługa transportowa</string>
    <string name="category_other">Inne</string>
    <string name="category_label">Kategoria</string>
    <string name="category_choose">Wybierz kategorię</string>
    <string name="tx_all">Wszystkie</string>
    <string name="tx_income">Przychody</string>
    <string name="tx_expense">Wydatki</string>
    <string name="add_comment_hint">Dodaj komentarz…</string>
    <string name="add_entry_title">Dodaj</string>
    <string name="edit_entry_title">Edytuj</string>
    <string name="tab_invoice">Faktura</string>
    <string name="attach_receipt_row">Dodaj paragon / zdjęcie</string>
    <string name="no_value_chosen">Nie ustawiono</string>
    <string name="reports_title">Raporty</string>
    <string name="period_this_month">Ten miesiąc</string>
    <string name="period_this_year">Ten rok</string>
    <string name="report_summary">Podsumowanie</string>
    <string name="legend_income">Przychód</string>
    <string name="legend_expense">Wydatki</string>
    <string name="legend_tax">Podatek</string>
    <string name="legend_tax_pct">Podatek (%1$d%%)</string>
    <string name="trend_title">Trend (6 miesięcy)</string>
    <string name="report_export_section">Eksport raportu</string>
    <string name="summary_total">Suma</string>
    <string name="settings_menu_appearance">Wygląd</string>
    <string name="appearance_dark_only_message">Ciemny motyw jest obecnie jedynym dostępnym wyglądem aplikacji.</string>
    <string name="notifications_title">Powiadomienia</string>
    <string name="notifications_clear_all">Wyczyść wszystkie</string>
    <string name="notifications_empty">Brak powiadomień</string>
    <string name="edit_limits">Edytuj</string>
    <string name="recent_transactions_title">Ostatnie transakcje</string>
    <string name="view_all">Zobacz wszystkie</string>
    <string name="no_recent_transactions">Brak transakcji</string>
    <string name="monthly_summary_title">Podsumowanie miesiąca</string>
    <string name="balance_vs_prev_month">vs poprzedni miesiąc</string>
    <string name="stat_tax_short">Podatek</string>

    <!-- Dynamiczna etykieta podatku -->
    <string name="tax_label_zero" formatted="false">Podatek (0% — kwota wolna)</string>
    <string name="tax_label_12" formatted="false">Podatek (12%)</string>
    <string name="tax_label_32" formatted="false">Podatek (próg 32%)</string>
    <string name="tax_label_progressive" formatted="false">Podatek (skala progresywna 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Podatek (liniowy 19%)</string>
    <string name="tax_label_ryczalt">Podatek (ryczałt, od przychodu)</string>
    <string name="pit_form_applicable">Właściwa deklaracja: %1$s</string>

    <!-- Tabela historii -->
    <string name="history_col_receipt">Paragon</string>
    <string name="history_col_amount">Kwota</string>

    <!-- Kolumny raportu -->
    <string name="report_col_receipt">Paragon</string>
    <string name="report_receipt_yes">Tak</string>

    <!-- Powiadomienia -->
    <string name="notif_channel_name">Limity i terminy</string>
    <string name="notif_channel_description">Powiadomienia o limitach działalności i terminach podatkowych</string>
    <string name="notif_limit_exceeded_title">Przekroczono limit działalności nierejestrowanej</string>
    <string name="notif_limit_exceeded_text" formatted="false">Przychód w tym miesiącu przekracza 75% minimalnego wynagrodzenia. Zarejestruj JDG w ciągu 7 dni.</string>
    <string name="notif_limit_95_title" formatted="false">Osiągnięto 95% limitu miesięcznego</string>
    <string name="notif_limit_95_text">Jesteś bardzo blisko limitu działalności nierejestrowanej na ten miesiąc.</string>
    <string name="notif_limit_80_title" formatted="false">Osiągnięto 80% limitu miesięcznego</string>
    <string name="notif_limit_80_text" formatted="false">Wykorzystano 80% limitu działalności nierejestrowanej na ten miesiąc.</string>
    <string name="notif_bracket_title">Zbliżasz się do progu 120 000 zł</string>
    <string name="notif_bracket_text" formatted="false">Roczny dochód zbliża się do 120 000 zł — nadwyżka będzie opodatkowana stawką 32% zamiast 12%.</string>
    <string name="notif_vat_title">Zbliżasz się do limitu zwolnienia z VAT</string>
    <string name="notif_vat_text">Roczny przychód zbliża się do 240 000 zł — progu zwolnienia z VAT.</string>
    <string name="notif_vat_exceeded_critical_title">Przekroczono limit VAT</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Złóż VAT-R w ciągu 7 dni i potwierdź rejestrację w Ustawieniach — do tego czasu wystawianie faktur jest zablokowane.</string>
    <string name="notif_kasa_exceeded_title">Może być wymagana kasa fiskalna</string>
    <string name="notif_kasa_exceeded_text" formatted="false">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Potwierdź w Ustawieniach posiadanie kasy fiskalnej — do tego czasu wystawianie faktur jest zablokowane.</string>
    <string name="notif_advance_title">Przypomnienie o zaliczce na podatek</string>
    <string name="notif_advance_text">Zaliczki na podatek należy wpłacać do 20 dnia każdego miesiąca.</string>
    <string name="notif_pit_deadline_title">Przypomnienie o rocznym zeznaniu podatkowym</string>
    <string name="notif_pit_deadline_text">Roczne zeznania podatkowe składa się od 15 lutego do 30 kwietnia.</string>
    <string name="terms_title">Regulamin</string>
    <string name="terms_full_text">Regulamin i wyłączenie odpowiedzialności (Terms of Service &amp; Legal Disclaimer)\n\nKlikając „Akceptuję”, potwierdzasz, że przeczytałeś/aś, zrozumiałeś/aś i w pełni akceptujesz warunki niniejszego regulaminu. Jeśli się nie zgadzasz, nie masz prawa korzystać z aplikacji FinArs.\n\n1. Wyłączenie usług księgowych i prawnych\n— Aplikacja FinArs jest wyłącznie narzędziem (kalkulatorem i organizerem danych).\n— Aplikacja, jej twórcy i właściciele NIE są akredytowanym biurem rachunkowym, doradcą podatkowym ani kancelarią prawną.\n— Wszystkie obliczenia i automatyczne generowanie deklaracji (PIT-36, PIT-36L, PIT-28) mają charakter wyłącznie informacyjny.\n\n2. Odpowiedzialność za dane\nUżytkownik ponosi pełną odpowiedzialność za poprawność wprowadzanych danych, weryfikację obliczeń i formularzy PDF przed złożeniem do urzędu skarbowego oraz za terminowość rozliczeń.\n\n3. Ograniczenie odpowiedzialności\nAplikacja jest dostarczana „tak jak jest”, bez żadnych gwarancji. Twórca nie odpowiada za kary, zaległości podatkowe, błędy algorytmów ani utratę danych na urządzeniu.\n\n4. Zmiany w przepisach\nPrzepisy podatkowe RP ulegają zmianom — zalecana jest weryfikacja na podatki.gov.pl lub u licencjonowanego księgowego.\n\n5. Poufność danych\nWszystkie dane i pliki PDF są przechowywane lokalnie na urządzeniu użytkownika.\n\n6. Prawo właściwe\nZastosowanie ma prawo Rzeczypospolitej Polskiej.\n\n7. Wycofanie zgody\nRegulamin akceptowany jest jednorazowo przy pierwszym uruchomieniu. Brak zgody oznacza obowiązek zaprzestania korzystania z aplikacji i jej usunięcia.</string>
    <string name="terms_checkbox_label">Przeczytałem/am i akceptuję regulamin</string>
    <string name="terms_accept_button">Akceptuję i kontynuuję</string>
    <string name="terms_status_accepted">Status: Regulamin zaakceptowano (%1$s)</string>
    <string name="terms_status_unknown">Status: Regulamin zaakceptowano</string>
    <string name="settings_menu_terms">Regulamin</string>


    <!-- Faktury / Rachunki -->
    <string name="nav_invoices">Faktury</string>
    <string name="invoice_form_title">Nowa faktura / rachunek</string>
    <string name="invoice_seller_section">Sprzedawca (Twoje dane)</string>
    <string name="seller_name">Imię i nazwisko / nazwa firmy</string>
    <string name="seller_nip">NIP (zostaw puste, jeśli brak)</string>
    <string name="seller_address_street">Ulica i numer</string>
    <string name="seller_address_postal">Kod pocztowy</string>
    <string name="seller_address_city">Miasto</string>
    <string name="invoice_buyer_section">Nabywca</string>
    <string name="buyer_physical_person_switch">Osoba fizyczna (bez NIP)</string>
    <string name="buyer_name">Imię i nazwisko / nazwa firmy</string>
    <string name="buyer_nip">NIP nabywcy</string>
    <string name="buyer_address_street">Ulica i numer</string>
    <string name="buyer_address_postal">Kod pocztowy</string>
    <string name="buyer_address_city">Miasto</string>
    <string name="invoice_service_section">Usługa / towar</string>
    <string name="service_name">Nazwa usługi lub towaru</string>
    <string name="service_amount">Kwota brutto (PLN)</string>
    <string name="payment_date_label">Data zapłaty</string>
    <string name="service_date_label">Data wykonania usługi / sprzedaży</string>
    <string name="payment_method_label">Sposób płatności</string>
    <string name="payment_method_cash">Gotówka</string>
    <string name="payment_method_transfer">Przelew</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Zapłacono gotówką</string>
    <string name="payment_paid_transfer">Zapłacono przelewem</string>
    <string name="payment_paid_blik">Zapłacono BLIK</string>
    <string name="cash_limit_title">Sprzedaż gotówkowa dla osób fizycznych w tym roku</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">Zbliżasz się do rocznego limitu sprzedaży gotówkowej dla osób fizycznych bez kasy fiskalnej.</string>
    <string name="cash_limit_exceeded_warning">Przekroczono roczny limit 20 000 PLN sprzedaży gotówkowej dla osób fizycznych — może być wymagana kasa fiskalna.</string>
    <string name="generate_invoice_button">Generuj PDF</string>
    <string name="invoice_generated_toast">Zapisano dokument: %1$s</string>
    <string name="invoice_error_toast">Nie udało się wygenerować dokumentu: %1$s</string>
    <string name="open_pdf_button">Otwórz PDF</string>
    <string name="share_invoice_button">Udostępnij</string>
    <string name="open_invoices_folder_button">Otwórz folder z fakturami</string>
    <string name="open_folder_error">Nie udało się otworzyć folderu. Pliki są zapisane w %1$s</string>
    <string name="invoice_fill_required_fields">Uzupełnij dane nabywcy, usługę i kwotę</string>
    <string name="invoice_blocked_toast">Wystawianie faktur zablokowane — najpierw potwierdź status VAT/kasy fiskalnej w Ustawieniach</string>
    <string name="invoice_is_receipt_label">Faktura jest wystawiana do paragonu</string>
    <string name="vat_rate_choose">Wybierz stawkę VAT</string>
    <string name="vat_rate_selected" formatted="false">Stawka VAT: %1$s</string>
    <string name="vat_rate_picker_title">Stawka VAT</string>
    <string name="vat_rate_required_error">Wybierz stawkę VAT dla tej faktury</string>
    <string name="vat_rate_23">23% (podstawowa)</string>
    <string name="vat_rate_8">8% (obniżona)</string>
    <string name="vat_rate_5">5% (minimalna)</string>
    <string name="vat_rate_0">0% (eksport/WDT)</string>
    <string name="vat_rate_zw">zw (zwolnienie)</string>
    <string name="vat_rate_np">np (nie podlega opodatkowaniu)</string>
    <string name="vat_limit_block_message" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Potwierdź rejestrację VAT-R w Ustawienia → Podatki, aby dalej wystawiać faktury.</string>
    <string name="kasa_limit_block_message" formatted="false">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Potwierdź posiadanie kasy fiskalnej w Ustawienia → Podatki, aby dalej wystawiać faktury.</string>

    <!-- Historia faktur -->
    <string name="invoice_history_title">Historia faktur</string>
    <string name="no_invoices">Nie wystawiono jeszcze żadnych faktur</string>


    <!-- Etykiety PDF faktury -->
    <string name="invoice_pdf_faktura">FAKTURA</string>
    <string name="invoice_pdf_rachunek">RACHUNEK</string>
    <string name="invoice_pdf_issue_date">Data wystawienia</string>
    <string name="invoice_pdf_sale_date">Data sprzedaży</string>
    <string name="invoice_pdf_seller">Sprzedawca</string>
    <string name="invoice_pdf_buyer">Nabywca</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Konto</string>
    <string name="invoice_pdf_buyer_private">Osoba fizyczna nieprowadząca działalności gospodarczej (bez NIP).</string>
    <string name="invoice_pdf_table_lp">Lp</string>
    <string name="invoice_pdf_table_name">Nazwa towaru/usługi</string>
    <string name="invoice_pdf_table_unit">Jedn.</string>
    <string name="invoice_pdf_table_qty">Ilość</string>
    <string name="invoice_pdf_table_price">Cena</string>
    <string name="invoice_pdf_table_total">Razem</string>
    <string name="invoice_pdf_unit_piece">szt</string>
    <string name="invoice_pdf_sum_label">Łącznie</string>
    <string name="invoice_pdf_table_price_netto">Cena netto</string>
    <string name="invoice_pdf_table_netto">Wartość netto</string>
    <string name="invoice_pdf_table_vat_rate">Stawka VAT</string>
    <string name="invoice_pdf_table_vat_amount">Kwota VAT</string>
    <string name="invoice_pdf_table_brutto">Wartość brutto</string>
    <string name="invoice_pdf_receipt_label">Faktura wystawiona do paragonu fiskalnego</string>
    <string name="invoice_pdf_paid_stamp">ZAPŁACONO</string>
    <string name="invoice_pdf_payment_date">Data zapłaty</string>
    <string name="invoice_pdf_footer">Dokument wygenerowany w aplikacji FinArs. Nie stanowi oficjalnej porady księgowej ani podatkowej — w razie wątpliwości skonsultuj się z doradcą podatkowym.</string>
    <string name="seller_bank_account">Numer konta (opcjonalnie)</string>
    <string name="delete_invoice_confirm_title">Usunąć fakturę?</string>
    <string name="delete_invoice_confirm_message">Wpis oraz plik PDF faktury zostaną trwale usunięte. Tej operacji nie można cofnąć.</string>
    <string name="invoice_deleted">Faktura usunięta</string>

    <string name="invoice_status_paid">Zapłacona</string>
    <string name="invoice_status_pending">Oczekuje na zapłatę</string>
    <string name="invoice_status_overdue">Zaległa</string>
    <string name="invoice_paid_switch_label">Zapłacona</string>
    <string name="invoice_due_date_label">Termin płatności</string>
    <string name="notif_invoice_overdue_title">Zaległa faktura</string>
    <string name="notif_invoice_overdue_text">Faktura nr %2$d dla %1$s jest zaległa.</string>
    <string name="notif_invoice_due_soon_title">Zbliża się termin płatności</string>
    <string name="notif_invoice_due_soon_text">Termin płatności faktury nr %2$d dla %1$s upływa w ciągu 3 dni.</string>
    <string name="recurring_switch_label">Powtarzaj co miesiąc</string>
    <string name="chart_title">Przychody i wydatki — ostatnie 6 miesięcy</string>
    <string name="invoice_status_filter_all">Wszystkie</string>

    <string name="invoice_pdf_pending_stamp">OCZEKUJE NA ZAPŁATĘ</string>

    <!-- Update 41: rodzaj działalności, magazyn, kody kreskowe, OCR paragonów -->
    <string name="settings_menu_business">Typ sprzedaży (towar/usługa)</string>
    <string name="business_kind_title">Typ sprzedaży (towar/usługa)</string>
    <string name="business_kind_description">Wybierz to, co najlepiej pasuje do Twojej działalności. Przy wyborze \"Sprzedaż\" lub \"Mieszana\" na ekranie głównym pojawi się przycisk \"Magazyn\".</string>
    <string name="business_kind_sales">Sprzedaż</string>
    <string name="business_kind_services">Usługi</string>
    <string name="business_kind_mixed">Mieszana (sprzedaż i usługi)</string>
    <string name="nav_magazin">Magazyn</string>
    <string name="magazin_title">Magazyn</string>
    <string name="magazin_empty">Brak produktów. Dodaj ręcznie lub zeskanuj kod kreskowy.</string>
    <string name="add_product_manually">Dodaj ręcznie</string>
    <string name="scan_barcode">Skanuj kod kreskowy</string>
    <string name="scan_short">Skanuj</string>
    <string name="scan_barcode_prompt">Skieruj aparat na kod kreskowy</string>
    <string name="looking_up_product">Szukam produktu w bazie…</string>
    <string name="product_name">Nazwa produktu</string>
    <string name="product_barcode">Kod kreskowy (opcjonalnie)</string>
    <string name="product_quantity">Ilość w magazynie</string>
    <string name="product_unit">Jednostka (szt., kg itp.)</string>
    <string name="product_low_stock">Próg \"kończy się\"</string>
    <string name="product_price">Cena zakupu</string>
    <string name="product_price_sell">Cena sprzedaży</string>
    <string name="product_margin">Marża %</string>
    <string name="product_margin_hint" formatted="false">Wpisz cenę sprzedaży bezpośrednio albo podaj % marży — cena sprzedaży zostanie wyliczona automatycznie od ceny zakupu (np. 60 = zakup +60%).</string>
    <string name="gallery_scan_receipt_button">Skanuj paragon z galerii</string>
    <string name="product_saved">Produkt zapisany</string>
    <string name="low_stock_banner">Kończy się: %1$d produkt(ów)</string>
    <string name="notif_low_stock_title">Produkt się kończy</string>
    <string name="notif_low_stock_text">%1$s: zostało %2$s %3$s</string>
    <string name="add_from_warehouse">Dodaj towary z magazynu</string>
    <string name="select_products_title">Wybór produktów</string>
    <string name="in_stock_suffix">w magazynie</string>
    <string name="select_at_least_one_product">Wybierz co najmniej jeden produkt</string>
    <string name="scan_receipt_button">Skanuj paragon (autouzupełnianie)</string>
    <string name="receipt_scan_processing">Rozpoznaję paragon…</string>
    <string name="receipt_scan_done">Paragon rozpoznany, sprawdź pola</string>
    <string name="receipt_scan_no_text">Nie udało się odczytać paragonu, wpisz ręcznie</string>

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Oznaczyć jako opłaconą?</string>
    <string name="invoice_mark_paid_confirm_message">Status faktury zmieni się na „opłacona” z dzisiejszą datą, a zapisany plik PDF zostanie zaktualizowany, by odzwierciedlić nowy status.</string>
    <string name="invoice_marked_paid_toast">Faktura oznaczona jako opłacona</string>
    <string name="invoice_marked_paid_pdf_warning">Status zaktualizowany, ale nie udało się odświeżyć pliku PDF</string>

    <!-- Update 42: inwentaryzacja magazynu + lepsze skanowanie paragonów -->
    <string name="start_inventory">Zrób inwentaryzację</string>
    <string name="inventory_title">Inwentaryzacja magazynu</string>
    <string name="inventory_hint">Sprawdź faktyczną ilość każdego produktu. Zaktualizowane zostaną tylko zmienione pozycje.</string>
    <string name="inventory_current_stock">W systemie: %1$s %2$s</string>
    <string name="inventory_save">Zapisz inwentaryzację</string>
    <string name="inventory_no_changes">Nie znaleziono różnic, nic się nie zmieniło</string>
    <string name="inventory_saved_title">Inwentaryzacja zapisana</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>

    <!-- Update 43: raport PDF inwentaryzacji + historia + skanowanie kodów, naprawa parsowania pozycji paragonu -->
    <string name="inventory_scan_button">Skanuj towar</string>
    <string name="inventory_history_button">Historia inwentaryzacji</string>
    <string name="inventory_scan_not_found">Nie znaleziono produktu o kodzie %1$s</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">Historia inwentaryzacji</string>
    <string name="inventory_history_empty">Brak przeprowadzonych inwentaryzacji</string>
    <string name="inventory_session_number">Inwentaryzacja nr %1$s</string>
    <string name="inventory_session_meta">pozycji: %1$s · zmienionych: %2$s</string>
    <string name="inventory_session_meta_sell">Utracona/dodatkowa sprzedaż: %1$s</string>
    <string name="inventory_pdf_title">Inwentaryzacja nr %1$s</string>
    <string name="inventory_pdf_date">Data</string>
    <string name="inventory_pdf_col_product">Produkt</string>
    <string name="inventory_pdf_col_unit">Jedn.</string>
    <string name="inventory_pdf_col_before">Było</string>
    <string name="inventory_pdf_col_after">Jest</string>
    <string name="inventory_pdf_col_diff">Różnica</string>
    <string name="inventory_pdf_col_diff_value">Różnica zakup</string>
    <string name="inventory_pdf_col_diff_value_sell">Utracona sprzedaż</string>
    <string name="inventory_pdf_total_products">Sprawdzonych pozycji</string>
    <string name="inventory_pdf_total_changed">Zmienionych pozycji</string>
    <string name="inventory_pdf_total_diff_value">Łączna różnica wg kosztu zakupu</string>
    <string name="inventory_pdf_total_diff_value_sell">Łączna utracona/dodatkowa sprzedaż (cena sprzedaży)</string>

    <!-- Kategorie ryczałtu: stawka dobierana dla każdej operacji zamiast jednego ustawienia -->
    <string name="ryczalt_cat_3">3% — towar</string>
    <string name="ryczalt_cat_5_5">5,5% — produkt/produkcja</string>
    <string name="ryczalt_cat_8_5">8,5% — usługi</string>
    <string name="ryczalt_cat_12">12% — usługi IT</string>
    <string name="ryczalt_cat_14">14% — usługi medyczne</string>
    <string name="ryczalt_cat_17">17% — wolny zawód</string>
    <string name="ryczalt_category_picker_title">Kategoria ryczałtu</string>
    <string name="ryczalt_category_choose">Wybierz kategorię ryczałtu ▾</string>
    <string name="ryczalt_category_selected">Kategoria: %1$s</string>
    <string name="ryczalt_category_required_error">Wybierz kategorię ryczałtu dla każdej pozycji</string>
    <string name="income_ryczalt_category_required_error">Wybierz kategorię ryczałtu dla tego przychodu</string>

    <!-- Zgodność VAT / kasa fiskalna (Ustawienia → Podatki) -->
    <string name="vat_compliance_title">Rejestracja VAT</string>
    <string name="vat_compliance_hint" formatted="false">Przekroczono roczny limit zwolnienia z VAT (240 000 zł). Musisz złożyć formularz VAT-R w ciągu 7 dni od dnia przekroczenia limitu i zacząć naliczać VAT na transakcji, która przekroczyła próg. Potwierdź poniżej po zarejestrowaniu — wystawianie faktur pozostaje zablokowane do tego czasu.</string>
    <string name="cb_vat_registered_label">Potwierdzam, że zarejestrowałem/-am się jako podatnik VAT (złożono VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Potwierdzono: zarejestrowany podatnik VAT</string>
    <string name="kasa_compliance_title">Kasa fiskalna</string>
    <string name="kasa_compliance_hint">Przekroczono roczny limit 20 000 zł sprzedaży gotówkowej dla osób fizycznych. Może być wymagana kasa fiskalna. Potwierdź poniżej, gdy ją posiadasz — wystawianie faktur pozostaje zablokowane do tego czasu.</string>
    <string name="kasa_compliance_hint_registered">Twoja działalność jest zarejestrowana (JDG), więc mogłeś/aś posiadać kasę fiskalną już od początku. Jeśli tak, potwierdź to poniżej — odblokuje to opcję „wydana do paragonu\" przy wystawianiu faktur.</string>
    <string name="cb_kasa_label">Potwierdzam, że posiadam kasę fiskalną</string>
    <string name="cb_kasa_confirmed_label">Potwierdzono: kasa fiskalna w użyciu</string>
    <string name="vat_confirm_dialog_title">Potwierdź rejestrację VAT</string>
    <string name="vat_confirm_dialog_message">To potwierdza, że złożono VAT-R i jesteś podatnikiem VAT. Nie można tego cofnąć w aplikacji. Kontynuować?</string>
    <string name="kasa_confirm_dialog_title">Potwierdź kasę fiskalną</string>
    <string name="kasa_confirm_dialog_message">To potwierdza posiadanie kasy fiskalnej. Nie można tego cofnąć w aplikacji. Kontynuować?</string>
    <string name="confirm_yes">Tak, potwierdzam</string>
    <string name="confirm_cancel">Anuluj</string>

    <!-- Częstotliwość powiadomień push (Ustawienia → Podatki) -->
    <string name="push_frequency_title">Częstotliwość powiadomień push</string>
    <string name="push_frequency_hint">Ile razy dziennie mogą przychodzić powiadomienia o przekroczonych limitach i zaległych fakturach (1–50).</string>
    <string name="push_frequency_saved">Zapisano częstotliwość powiadomień</string>
    <string name="push_frequency_invalid">Podaj liczbę od 1 do 50</string>
    <string name="income_ryczalt_category_label">Kategoria ryczałtu dla tego przychodu</string>

    <!-- Wiele pozycji na fakturze -->
    <string name="invoice_item_number_label">Pozycja %1$d</string>
    <string name="add_invoice_item_row">+ Dodaj pozycję</string>
    <string name="invoice_items_limit_reached">Możesz dodać maksymalnie %1$d pozycji na fakturę</string>
    <string name="invoice_item_min_required">Faktura musi mieć przynajmniej jedną pozycję</string>
    <string name="invoice_total_label">Razem: %1$s zł</string>
    <string name="item_qty_hint">Ilość</string>
    <string name="invoice_income_comment">Faktura nr %1$d — %2$s</string>

    <!-- Update: moduł Korekta (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Faktura korygująca</string>
    <string name="correction_original_invoice_label">Dokument oryginalny: nr %1$d, %2$s</string>
    <string name="correction_original_amount_label">Kwota oryginalna</string>
    <string name="correction_corrected_amount_hint">Kwota po korekcie (zł)</string>
    <string name="correction_reason_hint">Przyczyna korekty</string>
    <string name="correction_apply_to_income_label">Zastosuj różnicę do przychodu</string>
    <string name="correction_save_button">Wystaw korektę</string>
    <string name="correction_zero_delta_error">Kwota po korekcie jest taka sama jak oryginalna — nie ma czego korygować</string>
    <string name="correction_reason_required_error">Podaj przyczynę korekty</string>
    <string name="correction_saved_toast">Faktura korygująca wystawiona</string>
    <string name="correction_pdf_title">FAKTURA KORYGUJĄCA</string>
    <string name="correction_pdf_to_invoice">Korekta do faktury</string>
    <string name="correction_pdf_reason_label">Przyczyna korekty</string>
    <string name="correction_pdf_before_label">Kwota przed korektą</string>
    <string name="correction_pdf_after_label">Kwota po korekcie</string>
    <string name="correction_pdf_delta_label">Różnica</string>
    <!-- Update: tabela pozycji na fakturze korygującej + pola podpisu na obu dokumentach -->
    <string name="correction_pdf_before_table_title">Przed korektą</string>
    <string name="correction_pdf_after_table_title">Po korekcie</string>
    <string name="invoice_pdf_signature_issued_by">Wystawił(a):</string>
    <string name="invoice_pdf_signature_received_by">Odebrał(a):</string>
    <string name="invoice_pdf_signature_issued_by_caption">Podpis osoby upoważnionej do wystawienia</string>
    <string name="invoice_pdf_signature_received_by_caption">Podpis osoby upoważnionej do odbioru</string>
    <!-- Update: korekty pojawiają się teraz też w Historii faktur -->
    <string name="correction_history_row_title">Korekta nr %1$d → faktura nr %2$d</string>
    <string name="correction_history_row_title_solo">Korekta nr %1$d</string>
    <string name="delete_correction_confirm_title">Usunąć korektę?</string>
    <string name="delete_correction_confirm_message">Rekord korekty i jej plik PDF zostaną trwale usunięte. Tej operacji nie można cofnąć. Wpis przychodu utworzony przez tę korektę (jeśli był) nie zostanie automatycznie cofnięty.</string>
    <string name="correction_deleted">Korekta usunięta</string>
    <string name="nav_start">Start</string>
    <string name="nav_transactions">Transakcje</string>
    <string name="nav_reports">Raporty</string>
    <string name="nav_settings">Ustawienia</string>
</resources>

STRINGS_PL
echo "  app/src/main/res/values-pl/strings.xml written"

mkdir -p "$(dirname "app/src/main/res/values-ru/strings.xml")"
cat > "app/src/main/res/values-ru/strings.xml" << 'STRINGS_RU'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">FinArs</string>
    <string name="app_subtitle">FinArs</string>
    <string name="add_income">Добавить доход</string>
    <string name="add_expense">Добавить расход</string>
    <string name="add_entry">Добавить +</string>
    <string name="balance">Баланс</string>
    <string name="enter_amount">Сумма</string>
    <string name="enter_comment">Комментарий</string>
    <string name="entry_date_label">Дата операции</string>
    <string name="attach_receipt">Прикрепить чек</string>
    <string name="save">Сохранить</string>
    <string name="settings">Настройки</string>
    <string name="tax_percent">Процент налога</string>
    <string name="other_income_label">Прочие доходы (%1$d)</string>
    <string name="tax_scale_title">Налог считается автоматически</string>
    <string name="tax_scale_description" formatted="false">0% до 30 000 zł/год · 12% с суммы от 30 000 до 120 000 zł · 32% с суммы свыше 120 000 zł. Ставка применяется только к части сверх каждого порога, а не ко всей сумме.</string>
    <string name="other_income_title">Прочие доходы</string>
    <string name="other_income_hint">Ваш общий налогооблагаемый доход за этот год из других источников (работа, другая деятельность и т.д.). Учитывается вместе с доходом из этого приложения при проверке годового необлагаемого лимита в 30 000 zł.</string>
    <string name="saved">Сохранено</string>
    <string name="auto_tax_button">Рассчитать автоматически</string>
    <string name="auto_tax_result" formatted="false">Предложенная ставка: %1$.1f% (по шкале PIT: 12% до 120 000 zł/год, 32% свыше). Перед сохранением можно поправить вручную.</string>
    <string name="export_report">Экспорт отчёта</string>
    <string name="generate_report">Сгенерировать отчёт</string>
    <string name="select_period">Выберите период</string>
    <string name="month">Месяц</string>
    <string name="year">Год</string>
    <string name="custom_range">Произвольный период</string>
    <string name="from">От</string>
    <string name="to">До</string>
    <string name="no_entries">Нет записей</string>
    <string name="search_no_results">Ничего не найдено</string>
    <string name="history_search_hint">Поиск по комментарию или сумме</string>
    <string name="invoice_search_hint">Поиск по номеру, клиенту или сумме</string>
    <string name="filter_date_range">Диапазон дат</string>
    <string name="filter_clear">Сбросить фильтры</string>

    <string name="statistics">Статистика</string>
    <string name="stat_income">Доход</string>
    <string name="stat_expense">Расход</string>
    <string name="stat_profit">Прибыль (до налога)</string>
    <string name="stat_tax_format" formatted="false">Налог (%1$.1f%)</string>

    <string name="report_col_date">Дата</string>
    <string name="report_col_income">Доход</string>
    <string name="report_col_expense">Расход</string>
    <string name="report_col_tax_percent" formatted="false">Налог %</string>
    <string name="report_col_tax_amount">Сумма налога</string>
    <string name="report_col_comment">Комментарий</string>
    <string name="report_sheet_name">Отчёт</string>
    <string name="report_title_month">Отчёт — Месяц</string>
    <string name="report_title_year">Отчёт — Год</string>
    <string name="report_title_custom">Отчёт — Произвольный период</string>
    <string name="custom_range_invalid">Дата окончания должна быть позже даты начала</string>
    <string name="report_total_income">Итого доход</string>
    <string name="report_total_expense">Итого расход</string>
    <string name="report_total_profit">Итого прибыль</string>
    <string name="report_total_tax">Итого налог</string>
    <string name="report_total_net_profit">Чистая прибыль (после налога)</string>
    <string name="report_generating">Формирую отчёт…</string>
    <string name="report_ready">Отчёт готов</string>
    <string name="report_share_title">Поделиться отчётом</string>
    <string name="report_error">Ошибка формирования отчёта: %1$s</string>
    <string name="about_app">О приложении</string>
    <string name="about_version_label">Версия %1$s</string>
    <string name="settings_menu_privacy">Политика конфиденциальности</string>
    <string name="about_email">finars2026@gmail.com</string>

    <string name="privacy_updated_label">Последнее обновление: 11 августа 2026 г.</string>
    <string name="privacy_intro">Мы уважаем вашу приватность. Приложение FinArs спроектировано с учётом максимальной безопасности ваших данных — большая часть информации хранится исключительно на вашем устройстве.</string>

    <string name="privacy_section1_title">1. Оператор персональных данных</string>
    <string name="privacy_section1_body">Оператором приложения является разработчик FinArs. По вопросам защиты приватности и обработки данных вы можете связаться по адресу: finars2026@gmail.com.</string>

    <string name="privacy_section2_title">2. Какие данные мы обрабатываем и где их храним?</string>
    <string name="privacy_section2_intro">Все ваши ключевые финансовые и деловые данные хранятся ИСКЛЮЧИТЕЛЬНО ЛОКАЛЬНО в памяти вашего устройства. У нас нет собственных серверов, и мы не собираем эту информацию.</string>
    <string-array name="privacy_section2_bullets">
        <item>Финансовые данные и операции: суммы, даты, категории, комментарии, а также номера и данные счетов (включая данные контрагентов и NIP) не покидают ваш телефон.</item>
        <item>Складские остатки: данные о товарах и инвентаризации сохраняются только в локальной базе данных приложения.</item>
        <item>Фото чеков, прикреплённые вручную к операциям: хранятся исключительно на вашем устройстве, никогда не отправляются в облако.</item>
        <item>Защита (PIN / биометрия): PIN-код хранится в хэшированном виде в защищённом хранилище устройства и никогда никуда не передаётся.</item>
    </string-array>

    <string name="privacy_section3_title">3. Сторонние сервисы</string>
    <string name="privacy_section3_intro">Приложение использует доверенные внешние сервисы для обработки платежей и рекламы:</string>
    <string-array name="privacy_section3_bullets">
        <item>Google Play Billing — обрабатывает покупку и проверку подписки FinArs Pro. У нас нет доступа к данным вашей платёжной карты (платёж обрабатывает Google).</item>
        <item>RevenueCat — после публикации приложения будет управлять статусом подписки Pro (активна / истекла / пробный период), обрабатывая анонимный идентификатор пользователя и статус покупки, чтобы предоставить доступ к функциям Pro на всех ваших устройствах.</item>
        <item>Google AdMob — показывает рекламу пользователям без активной подписки Pro. AdMob может собирать анонимный рекламный идентификатор и диагностические данные для показа рекламы (в том числе персонализированной, с согласия пользователей из ЕС, собираемого через форму согласия Google UMP). Политика конфиденциальности Google: policies.google.com/privacy</item>
    </string-array>

    <string name="privacy_section4_title">4. Необходимые разрешения приложения</string>
    <string name="privacy_section4_intro">Приложение запрашивает только разрешения, необходимые для его корректной работы:</string>
    <string-array name="privacy_section4_bullets">
        <item>Камера — требуется только для сканирования штрихкодов на складе и фотографирования чеков.</item>
        <item>Уведомления — требуются для напоминаний о сроках оплаты счетов и превышении лимитов (например, незарегистрированной деятельности).</item>
        <item>Память — требуется на старых версиях Android для сохранения резервных копий и экспорта отчётов (например, PDF / CSV).</item>
        <item>Доступ в интернет — требуется только модулями рекламы и оплаты, описанными выше; не используется для отправки ваших финансовых данных.</item>
    </string-array>

    <string name="privacy_section5_title">5. Управление данными и ваши права</string>
    <string name="privacy_section5_body">Поскольку ваши данные находятся на вашем телефоне, вы полностью их контролируете: вы можете в любой момент очистить все данные в приложении (Настройки -> Резервная копия -> Очистить данные) либо просто удалить приложение. Вы сами решаете, где и когда экспортировать файл резервной копии.</string>

    <string name="privacy_section6_title">6. Дети</string>
    <string name="privacy_section6_body">Приложение не предназначено для лиц младше 16 лет и сознательно не собирает никакие данные детей.</string>

    <string name="privacy_section7_title">7. Изменения политики конфиденциальности</string>
    <string name="privacy_section7_body">Мы оставляем за собой право обновлять данную Политику конфиденциальности. Любое изменение будет опубликовано здесь с новой датой обновления.</string>

    <string name="privacy_section8_title">8. Контакт</string>
    <string name="privacy_section8_body">Если у вас есть вопросы о приватности или работе приложения, свяжитесь с нами: finars2026@gmail.com</string>

    <string name="about_intro">FinArs — комплексное приложение для управления финансами нерегистрируемой деятельности. Ведите учёт доходов и расходов, контролируйте лимиты, автоматически считайте налоги, выставляйте счета, управляйте складом и формируйте готовые отчёты и налоговые декларации — всё в одном месте, с полной историей операций и уведомлений всегда под рукой.</string>
    <string name="about_subscription_note">⭐ Подписка Pro: месячный или годовой план, 7 дней бесплатно, отмена в любой момент.</string>

    <string name="about_section_finance_title">📊 Финансы и налоги</string>
    <string-array name="about_bullets_finance">
        <item>Учёт доходов и расходов с чеками и цветными категориями</item>
        <item>Автоматический расчёт прибыли и налога (шкала 12%/32%)</item>
        <item>Повторяющиеся операции (аренда, подписки) создаются автоматически каждый месяц</item>
        <item>Контроль лимита незарегистрированной деятельности (порог 120 000 zł)</item>
        <item>История уведомлений о приближении и превышении лимитов, сроках счетов и другом</item>
    </string-array>

    <string name="about_section_warehouse_title">📦 Склад</string>
    <string-array name="about_bullets_warehouse">
        <item>Каталог товаров со сканированием штрихкодов, остатками и уведомлениями о низком запасе</item>
        <item>Сессии инвентаризации с историей</item>
        <item>Товары можно добавлять прямо в счета</item>
    </string-array>

    <string name="about_section_invoices_title">🧾 Счета и чеки (Pro)</string>
    <string-array name="about_bullets_invoices">
        <item>Выставление счетов/чеков физлицам и компаниям с созданием PDF</item>
        <item>Статусы: Оплачен / Ожидает оплаты / Просрочен, плюс напоминания о сроке оплаты</item>
        <item>Контроль годового лимита наличных (20 000 zł) для продаж физлицам</item>
        <item>История счетов с поиском и фильтрами</item>
    </string-array>

    <string name="about_section_reports_title">📄 Отчёты и декларации</string>
    <string-array name="about_bullets_reports">
        <item>Сводка доходов/расходов и график тренда за 6 месяцев</item>
        <item>Экспорт месячного отчёта (бесплатно), годового и за произвольный период (Pro) в Excel с чеками</item>
        <item>Формирование декларации PIT-36 — вспомогательный PDF и заполнение официальной формы (Pro)</item>
    </string-array>

    <string name="about_section_security_title">🔒 Безопасность и удобство</string>
    <string-array name="about_bullets_security">
        <item>Блокировка приложения PIN-кодом и отпечатком пальца / лицом</item>
        <item>Резервное копирование и восстановление данных (Pro)</item>
        <item>Современный тёмный интерфейс</item>
        <item>Доступно на польском, русском и английском</item>
        <item>Все финансовые данные хранятся локально на устройстве</item>
    </string-array>
    <string name="dialog_close">Закрыть</string>
    <string name="dialog_write">Написать</string>
    <string name="pro_status_locked">Pro не активирован. Разблокируйте, чтобы получить годовые и произвольные отчёты в Excel, резервное копирование и восстановление, а также убрать рекламу.</string>
    <string name="pro_status_active">Pro активирован. Спасибо за поддержку!</string>
    <string name="pro_unlock_button">Разблокировать Pro</string>
    <string name="pro_unlock_button_price">Разблокировать Pro — %1$s</string>
    <string name="pro_trial_hint">7 дней бесплатно, затем списывается автоматически. Отмена в любой момент.</string>
    <string name="pro_plan_monthly">Месячный план</string>
    <string name="pro_plan_yearly">Годовой план (выгоднее)</string>
    <string name="pro_plan_monthly_price">Помесячно — %1$s / мес.</string>
    <string name="pro_plan_yearly_price">Ежегодно — %1$s / год</string>
    <string name="pro_loading">Загрузка цены…</string>
    <string name="pro_feature_locked_title">Функция Pro</string>
    <string name="pro_feature_locked_message">Годовые и произвольные отчёты доступны только в Pro-версии. Разблокируйте Pro в настройках.</string>
    <string name="pro_feature_locked_go_settings">Перейти в настройки</string>
    <string name="invoice_pro_locked_message">Выставление фактур доступно только в Pro-версии. Разблокируйте Pro в настройках.</string>
    <string name="backup_pro_locked_message">Резервное копирование и восстановление — Pro-функция. Разблокируйте Pro, чтобы сохранить данные в файл на случай потери.</string>
    <string name="pro_purchase_error">Не удалось открыть окно оплаты. Проверьте соединение и попробуйте снова.</string>
    <string name="pro_info_title">Pro-версия</string>
    <string name="pro_info_message">Pro открывает:\n\n\u2022 Выставление счетов и фактур (PDF)\n\u2022 Годовой отчёт в Excel\n\u2022 Отчёт за произвольный период\n\u2022 Формирование декларации PIT-36\n\u2022 Резервное копирование и восстановление\n\u2022 Без рекламы</string>
    <string name="pro_info_continue">Перейти к покупке</string>
    <string name="paywall_header_white">Откройте</string>
    <string name="paywall_header_blue">FinArs Pro</string>
    <string name="paywall_subtitle">Получите полный контроль над финансами\nи работайте без ограничений.</string>
    <string name="paywall_feature_1">Выставление счетов и фактур (PDF)</string>
    <string name="paywall_feature_2">Формирование декларации PIT-36</string>
    <string name="paywall_feature_3">Годовые и произвольные отчёты Excel</string>
    <string name="paywall_feature_4">Резервная копия данных в облаке и локально</string>
    <string name="paywall_feature_5">Без рекламы</string>
    <string name="paywall_badge">САМЫЙ ПОПУЛЯРНЫЙ • ЭКОНОМИЯ 30%</string>
    <string name="paywall_plan_yearly_title">Годовой план</string>
    <string name="paywall_plan_monthly_title">Месячный план</string>
    <string name="paywall_price_yearly_default">99,99 zł</string>
    <string name="paywall_price_monthly_default">11,99 zł</string>
    <string name="paywall_per_year">/ год</string>
    <string name="paywall_per_month">/ месяц</string>
    <string name="paywall_trial_yearly">7 дней бесплатно, потом %1$s / год</string>
    <string name="paywall_trial_monthly">7 дней бесплатно, потом %1$s / месяц</string>
    <string name="paywall_per_month_note">Всего 8,33 zł / месяц</string>
    <string name="paywall_cta">Попробовать 7 дней за 0 zł</string>
    <string name="paywall_footer_1">Бесплатно первые 7 дней.\nОтмена в любой момент в Google Play.</string>
    <string name="paywall_data_safe">Ваши данные защищены</string>
    <string name="paywall_footer_2">Списание начнётся через 7 дней.\nВы можете отменить в любой момент.</string>
    <string name="enter_code_button">Есть код?</string>
    <string name="enter_code_title">Введите код</string>
    <string name="enter_code_hint">Код</string>
    <string name="enter_code_apply">Применить</string>
    <string name="enter_code_wrong">Неверный код</string>
    <string name="enter_code_success">Pro активирован</string>
    <string name="transaction_history">История операций</string>
    <string name="stat_net_profit">Чистая прибыль (после налога)</string>
    <string name="type_income">Доход</string>
    <string name="type_expense">Расход</string>
    <string name="edit_income_title">Редактировать доход</string>
    <string name="edit_expense_title">Редактировать расход</string>
    <string name="delete_entry">Удалить</string>
    <string name="delete_confirm_title">Удалить запись?</string>
    <string name="delete_confirm_message">Запись будет удалена без возможности восстановления.</string>
    <string name="delete_confirm_yes">Удалить</string>
    <string name="entry_updated">Обновлено</string>
    <string name="entry_deleted">Удалено</string>
    <string name="clear_all_button">Очистить все данные</string>
    <string name="clear_all_confirm_title">Вы уверены?</string>
    <string name="clear_all_confirm_message">Все доходы и расходы будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="clear_all_confirm_yes">Удалить всё</string>
    <string name="clear_all_done">Все данные удалены</string>

    <string name="settings_menu_tax">Налог и лимиты</string>
    <string name="settings_menu_language">Язык</string>
    <string name="settings_menu_backup">Резервная копия (Pro)</string>
    <string name="settings_menu_pro">Pro версия</string>

    <string name="backup_hint">Сохраните резервную копию доходов/расходов — суммы, даты, комментарии и прикреплённые фото чеков — в виде файла. В окне сохранения можно выбрать память телефона или Google Диск (если установлено приложение Диска). Храните этот файл в надёжном месте — только по нему можно восстановить данные при потере телефона или переустановке приложения.</string>
    <string name="backup_in_progress">Выполняется…</string>
    <string name="backup_create">Создать резервную копию</string>
    <string name="backup_restore">Восстановить из копии</string>
    <string name="backup_success">Копия сохранена (%1$d записей)</string>
    <string name="backup_error">Ошибка: %1$s</string>
    <string name="backup_restore_confirm_title">Восстановить из копии?</string>
    <string name="backup_restore_confirm_message">Записи из файла копии будут добавлены к тем, что уже есть на этом устройстве (существующие записи не удаляются и не перезаписываются). Если нужно "чистое" восстановление — сначала используйте "Очистить все данные", затем восстановление.</string>
    <string name="backup_invalid_file">Это не похоже на файл резервной копии FinArs</string>
    <string name="backup_restored">Восстановлено записей: %1$d</string>
    <string name="backup_never">Последняя копия: никогда</string>
    <string name="backup_last_time">Последняя копия: %1$s</string>

    <string name="settings_menu_security">Безопасность (PIN / отпечаток)</string>
    <string name="settings_menu_pit36">Сформировать PIT (Pro)</string>
    <string name="pit36_pro_locked_message">Генерация PIT-36 — функция Pro. Разблокируйте Pro в настройках, чтобы ей пользоваться.</string>

    <string name="lock_title">FinArs заблокирован</string>
    <string name="lock_subtitle">Введите PIN, чтобы продолжить</string>
    <string name="lock_pin_hint">PIN</string>
    <string name="lock_wrong_pin">Неверный PIN, попробуйте ещё раз</string>
    <string name="lock_unlock_button">Разблокировать</string>
    <string name="lock_biometric_button">Войти по отпечатку / лицу</string>
    <string name="lock_biometric_prompt_title">Разблокировка FinArs</string>
    <string name="lock_biometric_prompt_subtitle">Подтвердите отпечатком пальца или лицом</string>
    <string name="lock_use_pin">Ввести PIN</string>
    <string name="lock_biometric_unavailable">На этом устройстве не настроен отпечаток/лицо. Сначала добавьте его в настройках телефона.</string>

    <string name="security_hint">Защитите приложение PIN-кодом. Когда функция включена, FinArs будет спрашивать PIN каждый раз, когда вы возвращаетесь в приложение после его сворачивания. Также можно включить вход по отпечатку/лицу — это быстрый способ ввести тот же PIN.</string>
    <string name="security_pin_switch">Запрашивать PIN при открытии приложения</string>
    <string name="security_change_pin">Изменить PIN</string>
    <string name="security_biometric_switch">Вход по отпечатку / лицу</string>
    <string name="security_set_pin_title">Установите PIN</string>
    <string name="security_set_pin_message">Выберите PIN из 4–6 цифр</string>
    <string name="security_continue">Продолжить</string>
    <string name="security_pin_length_error">PIN должен состоять из 4–6 цифр</string>
    <string name="security_confirm_pin_title">Подтвердите PIN</string>
    <string name="security_pin_saved">PIN сохранён</string>
    <string name="security_pin_mismatch">PIN-коды не совпадают, попробуйте ещё раз</string>
    <string name="security_disable_pin_title">Введите текущий PIN</string>
    <string name="security_enter_current_pin">Введите текущий PIN, чтобы продолжить</string>
    <string name="security_pin_disabled">Защита PIN-ом отключена</string>

    <string name="pit_data_title">Личные данные для налоговой декларации</string>
    <string name="pit_data_hint">Используются только для заполнения вспомогательного отчёта PIT (PIT-36 / PIT-36L / PIT-28 — в зависимости от вида деятельности). Всё остаётся на вашем устройстве.</string>
    <string name="pit_first_name">Имя</string>
    <string name="pit_last_name">Фамилия</string>
    <string name="pit_pesel">PESEL (необязательно)</string>
    <string name="pit_street">Улица</string>
    <string name="pit_house_number">Номер дома</string>
    <string name="pit_apartment_number">Номер квартиры (необязательно)</string>
    <string name="pit_voivodeship">Воеводство</string>
    <string name="pit_county">Повят</string>
    <string name="pit_commune">Гмина</string>
    <string name="pit_postal_code">Почтовый индекс</string>
    <string name="pit_city">Город</string>
    <string name="pit_tax_office">Налоговая инспекция (urząd skarbowy)</string>
    <string name="pit_reliefs_title">Льготы и вычеты (необязательно)</string>
    <string name="pit_children_count">Количество детей (ulga na dzieci)</string>
    <string name="pit_internet_relief">Льгота на интернет — сумма расходов</string>
    <string name="pit_ikze">Взносы на IKZE</string>
    <string name="pit_donations">Пожертвования (darowizny)</string>
    <string name="pit_joint_spouse">Совместная подача с супругом</string>
    <string name="pit_spouse_data_title">Личные данные супруга(и)</string>
    <string name="pit_spouse_id_hint">NIP/PESEL супруга(и)</string>
    <string name="pit_spouse_first_name_hint">Имя супруга(и)</string>
    <string name="pit_spouse_last_name_hint">Фамилия супруга(и)</string>
    <string name="pit_spouse_birth_date_hint">Дата рождения (ДД.ММ.ГГГГ)</string>
    <string name="pit_spouse_income_hint">Доход супруга(и) (опционально)</string>
    <string name="pit_data_required_error">Сначала укажите имя, фамилию и налоговую инспекцию</string>

    <string name="pit36_hint">Выберите полный календарный год, проверьте личные данные, затем сформируйте вспомогательный PDF с цифрами и подсказками для заполнения вашей декларации на podatki.gov.pl (Twój e-PIT) или на бумаге.</string>
    <string name="pit_row_przychod">Przychód (доход)</string>
    <string name="pit_row_koszty">Koszty (расходы)</string>
    <string name="pit_row_dochod">Dochód (прибыль)</string>
    <string name="pit_row_tax">Расчётный налог</string>
    <string name="pit_data_status_missing">Личные данные ещё не заполнены — это нужно сделать перед формированием отчёта.</string>
    <string name="pit_data_status_ready">Личные данные готовы: %1$s</string>
    <string name="pit_edit_data_button">Изменить личные данные</string>
    <string name="pit36_generate_button">Сформировать вспомогательный PDF</string>
    <string name="pit36_disclaimer">Этот отчёт носит исключительно информационный характер и не является официальным бланком, e-Deklaracją или налоговой консультацией. Всегда перепроверяйте цифры перед подачей декларации.</string>
    <string name="pit36_calculating">Идёт расчёт, подождите…</string>
    <string name="pit36_generated">PDF-отчёт сформирован</string>
    <string name="pit36_generate_official_button">Заполнить официальный бланк (шаблон 2025)</string>
    <string name="pit36_official_hint">Заполняет настоящий государственный PDF %1$s(32)/2025: ваши данные, адрес и строку доходов/расходов бизнеса. Остальные источники дохода и вычеты нужно дозаполнить самостоятельно — см. предупреждение ниже.</string>
    <string name="pit36_official_unsupported">Официальный заполненный бланк доступен только для PIT-36 (skala). Ваша текущая форма — %1$s, используйте кнопку «Сформировать вспомогательный PDF».</string>
    <string name="pit36_official_generated">Официальный бланк PIT-36 заполнен. Проверьте разделы E–K и добавьте другие доходы/вычеты перед подачей.</string>

    <!-- Тип деятельности / правила регистрации -->
    <string name="activity_type_title">Форма деятельности</string>
    <string name="activity_type_hint">Выберите, как вы работаете — от этого зависит применяемый лимит и то, какую декларацию подавать.</string>
    <string name="activity_type_niezarejestrowana">Незарегистрированная деятельность (без JDG)</string>
    <string name="activity_type_niezarejestrowana_desc" formatted="false">Доход не должен превышать 75% минимальной зарплаты в месяц. При превышении нужно зарегистрировать JDG в течение 7 дней. Подаётся через PIT-36 по обычной шкале.</string>
    <string name="activity_type_jdg_skala" formatted="false">Зарегистрированное ИП (JDG) — шкала 12% / 32% (PIT-36)</string>
    <string name="activity_type_jdg_liniowy" formatted="false">Зарегистрированное ИП (JDG) — плоский налог 19% (PIT-36L)</string>
    <string name="activity_type_jdg_ryczalt">Зарегистрированное ИП (JDG) — ryczałt (PIT-28)</string>
    <string name="ryczalt_rate_moved_title">Ставка ryczałtu по категориям</string>
    <string name="ryczalt_rate_moved_hint">У каждого дохода и каждой позиции фактуры есть своя категория — товар, продукция, услуги, IT-услуги, медицинские услуги, свободная профессия. Ставка налога подбирается автоматически на основе выбранной категории.</string>
    <string name="min_wage_label">Минимальная месячная зарплата (zł) — для расчёта лимита незарегистрированной деятельности</string>
    <string name="monthly_limit_preview" formatted="false">Месячный лимит (75%): %1$.2f zł</string>

    <!-- Гейджи лимитов на главном экране -->
    <string name="limits_title">Лимиты</string>
    <string name="limit_monthly_label">Незарегистрированная деятельность, этот месяц: %1$s / %2$s zł</string>
    <string name="limit_bracket_label">Первый налоговый порог (120 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_tax_free">Необлагаемый минимум (0–30 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate12">Порог 12%% (30 000–120 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_label_rate32">Порог 120 000 zł превышен — излишек %1$s zł облагается по ставке 32%%</string>
    <string name="limit_vat_label">Освобождение от VAT (240 000 zł/год): %1$s / %2$s zł</string>
    <string name="limit_bracket_title">Налоговый порог (120 000 zł/год)</string>
    <string name="limit_bracket_title_tax_free">Необлагаемый минимум (0–30 000 zł/год)</string>
    <string name="limit_bracket_title_rate12">Порог 12% (30 000–120 000 zł/год)</string>
    <string name="limit_bracket_title_rate32">Порог 32% (свыше 120 000 zł/год)</string>
    <string name="limit_exceeded_warning">Превышен лимит незарегистрированной деятельности! Вы обязаны зарегистрировать JDG в течение 7 дней.</string>
    <string name="limits_remaining">Осталось: %1$s zł</string>
    <string name="limits_limit_of">Лимит: %1$s zł</string>
    <string name="limits_about_title">О лимитах</string>
    <string name="limits_about_desc">Превышение лимита незарегистрированной деятельности может потребовать регистрации бизнеса и смены формы налогообложения.</string>
    <string name="back">Назад</string>
    <string name="category_sale">Продажа</string>
    <string name="category_invoice">Счёт-фактура</string>
    <string name="category_materials">Закупка материалов</string>
    <string name="category_fuel">Топливо</string>
    <string name="category_transport">Транспортные услуги</string>
    <string name="category_other">Другое</string>
    <string name="category_label">Категория</string>
    <string name="category_choose">Выберите категорию</string>
    <string name="tx_all">Все</string>
    <string name="tx_income">Доходы</string>
    <string name="tx_expense">Расходы</string>
    <string name="add_comment_hint">Добавить комментарий</string>
    <string name="add_entry_title">Добавить</string>
    <string name="edit_entry_title">Изменить</string>
    <string name="tab_invoice">Счёт</string>
    <string name="attach_receipt_row">Добавить чек / фото</string>
    <string name="no_value_chosen">Не задано</string>
    <string name="reports_title">Отчёты</string>
    <string name="period_this_month">Этот месяц</string>
    <string name="period_this_year">Этот год</string>
    <string name="report_summary">Сводка</string>
    <string name="legend_income">Доход</string>
    <string name="legend_expense">Расходы</string>
    <string name="legend_tax">Налог</string>
    <string name="legend_tax_pct">Налог (%1$d%%)</string>
    <string name="trend_title">Тренд (6 месяцев)</string>
    <string name="report_export_section">Экспорт отчёта</string>
    <string name="summary_total">Итого</string>
    <string name="settings_menu_appearance">Внешний вид</string>
    <string name="appearance_dark_only_message">Тёмная тема — пока единственный доступный вид приложения.</string>
    <string name="notifications_title">Уведомления</string>
    <string name="notifications_clear_all">Очистить все</string>
    <string name="notifications_empty">Пока нет уведомлений</string>
    <string name="edit_limits">Изменить</string>
    <string name="recent_transactions_title">Последние транзакции</string>
    <string name="view_all">Смотреть все</string>
    <string name="no_recent_transactions">Пока нет операций</string>
    <string name="monthly_summary_title">Итоги месяца</string>
    <string name="balance_vs_prev_month">по сравнению с прошлым месяцем</string>
    <string name="stat_tax_short">Налог</string>

    <!-- Динамическая подпись налога -->
    <string name="tax_label_zero" formatted="false">Налог (0% — необлагаемый минимум)</string>
    <string name="tax_label_12" formatted="false">Налог (12%)</string>
    <string name="tax_label_32" formatted="false">Налог (ставка 32%)</string>
    <string name="tax_label_progressive" formatted="false">Налог (прогрессивная шкала 12% / 32%)</string>
    <string name="tax_label_liniowy" formatted="false">Налог (плоский 19%)</string>
    <string name="tax_label_ryczalt">Налог (ryczałt, от дохода)</string>
    <string name="pit_form_applicable">Применимая декларация: %1$s</string>

    <!-- Таблица истории -->
    <string name="history_col_receipt">Чек</string>
    <string name="history_col_amount">Сумма</string>

    <!-- Колонки отчёта -->
    <string name="report_col_receipt">Чек</string>
    <string name="report_receipt_yes">Есть</string>

    <!-- Уведомления -->
    <string name="notif_channel_name">Лимиты и сроки</string>
    <string name="notif_channel_description">Оповещения о лимитах деятельности и налоговых сроках</string>
    <string name="notif_limit_exceeded_title">Превышен лимит незарегистрированной деятельности</string>
    <string name="notif_limit_exceeded_text" formatted="false">Доход в этом месяце превышает 75% минимальной зарплаты. Зарегистрируйте JDG в течение 7 дней.</string>
    <string name="notif_limit_95_title" formatted="false">Достигнуто 95% месячного лимита</string>
    <string name="notif_limit_95_text">Вы очень близки к лимиту незарегистрированной деятельности за этот месяц.</string>
    <string name="notif_limit_80_title" formatted="false">Достигнуто 80% месячного лимита</string>
    <string name="notif_limit_80_text" formatted="false">Использовано 80% лимита незарегистрированной деятельности за этот месяц.</string>
    <string name="notif_bracket_title">Приближение к порогу 120 000 zł</string>
    <string name="notif_bracket_text" formatted="false">Годовая прибыль приближается к 120 000 zł — доход сверх этой суммы облагается по 32% вместо 12%.</string>
    <string name="notif_vat_title">Приближение к лимиту освобождения от VAT</string>
    <string name="notif_vat_text">Годовой доход приближается к 240 000 zł — порогу освобождения от VAT.</string>
    <string name="notif_vat_exceeded_critical_title">Превышен лимит VAT</string>
    <string name="notif_vat_exceeded_critical_text" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Подайте VAT-R в течение 7 дней и подтвердите регистрацию в Настройках — до этого выставление фактур заблокировано.</string>
    <string name="notif_kasa_exceeded_title">Может понадобиться кассовый аппарат</string>
    <string name="notif_kasa_exceeded_text" formatted="false">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Подтвердите в Настройках наличие кассового аппарата — до этого выставление фактур заблокировано.</string>
    <string name="notif_advance_title">Напоминание об авансовом платеже</string>
    <string name="notif_advance_text">Авансовые платежи по налогу нужно вносить до 20 числа каждого месяца.</string>
    <string name="notif_pit_deadline_title">Напоминание о подаче годовой декларации</string>
    <string name="notif_pit_deadline_text">Годовые декларации подаются с 15 февраля по 30 апреля.</string>
    <string name="terms_title">Пользовательское соглашение</string>
    <string name="terms_full_text">Пользовательское соглашение и Отказ от ответственности (Terms of Service &amp; Legal Disclaimer)\n\nНажимая кнопку «Принять», вы подтверждаете, что прочитали, поняли и полностью согласны со всеми условиями данного соглашения. Если вы не согласны с условиями, вы не имеете права использовать приложение FinArs.\n\n1. Отказ от оказания бухгалтерских и юридических услуг\n— Приложение FinArs является исключительно инструментальным сервисом (автоматизированным калькулятором и органайзером учета данных).\n— Приложение, его разработчики и правообладатели НЕ являются аккредитованной бухгалтерской компанией, налоговыми консультантами (Doradca podatkowy) или юридическим бюро.\n— Все расчеты, автоматические генерации деклараций (включая формы PIT-36, PIT-36L, PIT-28), шкалы лимитов и уведомления носят исключительно информационный и справочный характер.\n\n2. Ответственность за точность и подачу данных\nПользователь несет полную и единоличную ответственность за достоверность вводимых данных, проверку итоговых расчетов и PDF-форм перед подачей в налоговые органы, а также за соблюдение сроков подачи деклараций и регистрации деятельности.\n\n3. Ограничение ответственности разработчика\nПриложение предоставляется «как есть», без каких-либо гарантий. Разработчик не несет ответственности за штрафы, доначисления, ошибки алгоритмов и потерю данных на устройстве пользователя.\n\n4. Изменения в законодательстве\nЗаконодательство Республики Польша регулярно меняется. Рекомендуется сверять результаты с podatki.gov.pl или лицензированными бухгалтерами.\n\n5. Конфиденциальность и хранение данных\nВсе данные и PDF-файлы хранятся локально на устройстве пользователя. Разработчик не собирает и не передает финансовые документы на внешние серверы.\n\n6. Применимое право\nК настоящему Соглашению применяется законодательство Республики Польша.\n\n7. Отзыв согласия\nСоглашение принимается однократно при первом запуске. Если пользователь больше не согласен с условиями — он обязан прекратить использование приложения и удалить его.</string>
    <string name="terms_checkbox_label">Я прочитал(а) и принимаю условия соглашения</string>
    <string name="terms_accept_button">Принять и продолжить</string>
    <string name="terms_status_accepted">Статус: Соглашение принято (%1$s)</string>
    <string name="terms_status_unknown">Статус: Соглашение принято</string>
    <string name="settings_menu_terms">Пользовательское соглашение</string>


    <!-- Счета / Фактуры -->
    <string name="nav_invoices">Счета</string>
    <string name="invoice_form_title">Новый счёт / рахунек</string>
    <string name="invoice_seller_section">Продавец (ваши данные)</string>
    <string name="seller_name">Имя и фамилия / название фирмы</string>
    <string name="seller_nip">NIP (оставьте пустым, если нет)</string>
    <string name="seller_address_street">Улица и номер</string>
    <string name="seller_address_postal">Почтовый индекс</string>
    <string name="seller_address_city">Город</string>
    <string name="invoice_buyer_section">Покупатель</string>
    <string name="buyer_physical_person_switch">Физическое лицо (без NIP)</string>
    <string name="buyer_name">Имя и фамилия / название фирмы</string>
    <string name="buyer_nip">NIP покупателя</string>
    <string name="buyer_address_street">Улица и номер</string>
    <string name="buyer_address_postal">Почтовый индекс</string>
    <string name="buyer_address_city">Город</string>
    <string name="invoice_service_section">Услуга / товар</string>
    <string name="service_name">Наименование услуги или товара</string>
    <string name="service_amount">Сумма брутто (PLN)</string>
    <string name="payment_date_label">Дата оплаты</string>
    <string name="service_date_label">Дата оказания услуги / продажи</string>
    <string name="payment_method_label">Способ оплаты</string>
    <string name="payment_method_cash">Наличные</string>
    <string name="payment_method_transfer">Перевод</string>
    <string name="payment_method_blik">BLIK</string>
    <string name="payment_paid_cash">Оплачено наличными</string>
    <string name="payment_paid_transfer">Оплачено переводом</string>
    <string name="payment_paid_blik">Оплачено через BLIK</string>
    <string name="cash_limit_title">Наличные продажи физлицам за год</string>
    <string name="cash_limit_label">%1$s / %2$s PLN</string>
    <string name="cash_limit_warning">Вы приближаетесь к годовому лимиту наличных расчётов с физлицами без кассового аппарата.</string>
    <string name="cash_limit_exceeded_warning">Превышен годовой лимит 20 000 PLN наличных расчётов с физлицами — может потребоваться кассовый аппарат.</string>
    <string name="generate_invoice_button">Сформировать PDF</string>
    <string name="invoice_generated_toast">Документ сохранён: %1$s</string>
    <string name="invoice_error_toast">Не удалось создать документ: %1$s</string>
    <string name="open_pdf_button">Открыть PDF</string>
    <string name="share_invoice_button">Отправить</string>
    <string name="open_invoices_folder_button">Открыть папку со счетами</string>
    <string name="open_folder_error">Не удалось открыть папку. Файлы сохранены в %1$s</string>
    <string name="invoice_fill_required_fields">Заполните данные покупателя, услугу и сумму</string>
    <string name="invoice_blocked_toast">Выставление фактур заблокировано — сначала подтвердите статус VAT/кассы в Настройках</string>
    <string name="invoice_is_receipt_label">Фактура выставляется к чеку (paragon)</string>
    <string name="vat_rate_choose">Выбрать ставку VAT</string>
    <string name="vat_rate_selected" formatted="false">Ставка VAT: %1$s</string>
    <string name="vat_rate_picker_title">Ставка VAT</string>
    <string name="vat_rate_required_error">Выберите ставку VAT для этой фактуры</string>
    <string name="vat_rate_23">23% (базовая)</string>
    <string name="vat_rate_8">8% (сниженная)</string>
    <string name="vat_rate_5">5% (минимальная)</string>
    <string name="vat_rate_0">0% (экспорт/WDT)</string>
    <string name="vat_rate_zw">zw (освобождение)</string>
    <string name="vat_rate_np">np (не подлежит налогообложению)</string>
    <string name="vat_limit_block_message" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Подтвердите регистрацию VAT-R в Настройки → Налоги, чтобы продолжить выставлять фактуры.</string>
    <string name="kasa_limit_block_message" formatted="false">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Подтвердите наличие кассового аппарата в Настройки → Налоги, чтобы продолжить выставлять фактуры.</string>

    <!-- История счетов -->
    <string name="invoice_history_title">История счетов</string>
    <string name="no_invoices">Вы ещё не выставили ни одного счёта</string>


    <!-- Метки PDF счёта -->
    <string name="invoice_pdf_faktura">СЧЁТ-ФАКТУРА</string>
    <string name="invoice_pdf_rachunek">СЧЁТ</string>
    <string name="invoice_pdf_issue_date">Дата выставления</string>
    <string name="invoice_pdf_sale_date">Дата продажи</string>
    <string name="invoice_pdf_seller">Продавец</string>
    <string name="invoice_pdf_buyer">Покупатель</string>
    <string name="invoice_pdf_nip">NIP</string>
    <string name="invoice_pdf_bank_account">Счёт</string>
    <string name="invoice_pdf_buyer_private">Физическое лицо без предпринимательской деятельности (без NIP).</string>
    <string name="invoice_pdf_table_lp">№</string>
    <string name="invoice_pdf_table_name">Наименование товара/услуги</string>
    <string name="invoice_pdf_table_unit">Ед.</string>
    <string name="invoice_pdf_table_qty">Кол-во</string>
    <string name="invoice_pdf_table_price">Цена</string>
    <string name="invoice_pdf_table_total">Сумма</string>
    <string name="invoice_pdf_unit_piece">шт</string>
    <string name="invoice_pdf_sum_label">Итого</string>
    <string name="invoice_pdf_table_price_netto">Цена нетто</string>
    <string name="invoice_pdf_table_netto">Стоимость нетто</string>
    <string name="invoice_pdf_table_vat_rate">Ставка VAT</string>
    <string name="invoice_pdf_table_vat_amount">Сумма VAT</string>
    <string name="invoice_pdf_table_brutto">Стоимость брутто</string>
    <string name="invoice_pdf_receipt_label">Фактура выставлена к фискальному чеку</string>
    <string name="invoice_pdf_paid_stamp">ОПЛАЧЕНО</string>
    <string name="invoice_pdf_payment_date">Дата оплаты</string>
    <string name="invoice_pdf_footer">Документ создан в приложении FinArs. Не является официальной бухгалтерской или налоговой консультацией — в случае сомнений обратитесь к налоговому консультанту.</string>
    <string name="seller_bank_account">Номер счёта (необязательно)</string>
    <string name="delete_invoice_confirm_title">Удалить счёт?</string>
    <string name="delete_invoice_confirm_message">Запись и PDF-файл счёта будут безвозвратно удалены. Это действие нельзя отменить.</string>
    <string name="invoice_deleted">Счёт удалён</string>

    <string name="invoice_status_paid">Оплачена</string>
    <string name="invoice_status_pending">Ожидает оплаты</string>
    <string name="invoice_status_overdue">Просрочена</string>
    <string name="invoice_paid_switch_label">Оплачена</string>
    <string name="invoice_due_date_label">Срок оплаты</string>
    <string name="notif_invoice_overdue_title">Просроченная фактура</string>
    <string name="notif_invoice_overdue_text">Фактура №%2$d для %1$s просрочена.</string>
    <string name="notif_invoice_due_soon_title">Скоро срок оплаты</string>
    <string name="notif_invoice_due_soon_text">Срок оплаты фактуры №%2$d для %1$s истекает в течение 3 дней.</string>
    <string name="recurring_switch_label">Повторять ежемесячно</string>
    <string name="chart_title">Доходы и расходы за последние 6 месяцев</string>
    <string name="invoice_status_filter_all">Все</string>

    <string name="invoice_pdf_pending_stamp">ОЖИДАЕТ ОПЛАТЫ</string>

    <!-- Update 41: тип деятельности, склад, штрихкоды, OCR чеков -->
    <string name="settings_menu_business">Тип продаж (товары/услуги)</string>
    <string name="business_kind_title">Тип продаж (товары/услуги)</string>
    <string name="business_kind_description">Выберите, что больше подходит вашему бизнесу. При выборе \"Продажи\" или \"Смешанная\" на главном экране появится кнопка \"Склад\" для учёта товаров.</string>
    <string name="business_kind_sales">Продажи</string>
    <string name="business_kind_services">Услуги</string>
    <string name="business_kind_mixed">Смешанная (продажи и услуги)</string>
    <string name="nav_magazin">Склад</string>
    <string name="magazin_title">Склад</string>
    <string name="magazin_empty">Пока нет товаров. Добавьте вручную или отсканируйте штрихкод.</string>
    <string name="add_product_manually">Добавить вручную</string>
    <string name="scan_barcode">Сканировать штрихкод</string>
    <string name="scan_short">Скан</string>
    <string name="scan_barcode_prompt">Наведите камеру на штрихкод</string>
    <string name="looking_up_product">Ищу товар в базе…</string>
    <string name="product_name">Название товара</string>
    <string name="product_barcode">Штрихкод (необязательно)</string>
    <string name="product_quantity">Количество на складе</string>
    <string name="product_unit">Единица (шт., кг и т.п.)</string>
    <string name="product_low_stock">Порог \"заканчивается\"</string>
    <string name="product_price">Цена закупки</string>
    <string name="product_price_sell">Цена продажи</string>
    <string name="product_margin">Наценка %</string>
    <string name="product_margin_hint" formatted="false">Введите цену продажи напрямую, либо укажите % наценки — цена продажи посчитается автоматически от цены закупки (например, 60 = закупка +60%).</string>
    <string name="gallery_scan_receipt_button">Сканировать чек из галереи</string>
    <string name="product_saved">Товар сохранён</string>
    <string name="low_stock_banner">Заканчивается: %1$d товар(ов)</string>
    <string name="notif_low_stock_title">Товар заканчивается</string>
    <string name="notif_low_stock_text">%1$s: осталось %2$s %3$s</string>
    <string name="add_from_warehouse">Добавить товары со склада</string>
    <string name="select_products_title">Выбор товаров</string>
    <string name="in_stock_suffix">в наличии</string>
    <string name="select_at_least_one_product">Выберите хотя бы один товар</string>
    <string name="scan_receipt_button">Сканировать чек (автозаполнение)</string>
    <string name="receipt_scan_processing">Распознаю чек…</string>
    <string name="receipt_scan_done">Чек распознан, проверьте поля</string>
    <string name="receipt_scan_no_text">Не удалось распознать чек, заполните вручную</string>

    <!-- Update 41 fix 6 -->
    <string name="invoice_mark_paid_confirm_title">Отметить как оплаченную?</string>
    <string name="invoice_mark_paid_confirm_message">Статус фактуры изменится на «оплачена» сегодняшним числом, а сохранённый PDF-файл будет обновлён с новым статусом.</string>
    <string name="invoice_marked_paid_toast">Фактура отмечена как оплаченная</string>
    <string name="invoice_marked_paid_pdf_warning">Статус обновлён, но не удалось перезаписать PDF-файл</string>

    <!-- Update 42: инвентаризация склада + улучшенное сканирование чеков -->
    <string name="start_inventory">Провести инвентаризацию</string>
    <string name="inventory_title">Инвентаризация склада</string>
    <string name="inventory_hint">Проверьте фактическое количество каждого товара. Обновятся только изменённые позиции.</string>
    <string name="inventory_current_stock">По учёту: %1$s %2$s</string>
    <string name="inventory_save">Сохранить инвентаризацию</string>
    <string name="inventory_no_changes">Расхождений не найдено, ничего не изменилось</string>
    <string name="inventory_saved_title">Инвентаризация сохранена</string>
    <string name="inventory_diff_line">%1$s: %2$s → %3$s (%4$s)</string>

    <!-- Update 43: PDF-отчёт инвентаризации + история + сканирование штрихкода, починка разбора позиций чека -->
    <string name="inventory_scan_button">Сканировать товар</string>
    <string name="inventory_history_button">История инвентаризаций</string>
    <string name="inventory_scan_not_found">Товар с кодом %1$s не найден</string>
    <string name="inventory_scan_found">%1$s: %2$s</string>
    <string name="inventory_history_title">История инвентаризаций</string>
    <string name="inventory_history_empty">Пока нет проведённых инвентаризаций</string>
    <string name="inventory_session_number">Инвентаризация №%1$s</string>
    <string name="inventory_session_meta">позиций: %1$s · изменено: %2$s</string>
    <string name="inventory_session_meta_sell">Упущено/лишнее по продаже: %1$s</string>
    <string name="inventory_pdf_title">Инвентаризация №%1$s</string>
    <string name="inventory_pdf_date">Дата</string>
    <string name="inventory_pdf_col_product">Товар</string>
    <string name="inventory_pdf_col_unit">Ед.</string>
    <string name="inventory_pdf_col_before">Было</string>
    <string name="inventory_pdf_col_after">Стало</string>
    <string name="inventory_pdf_col_diff">Разница</string>
    <string name="inventory_pdf_col_diff_value">Разница по закупке</string>
    <string name="inventory_pdf_col_diff_value_sell">Упущ. выручка</string>
    <string name="inventory_pdf_total_products">Всего проверено позиций</string>
    <string name="inventory_pdf_total_changed">Изменено позиций</string>
    <string name="inventory_pdf_total_diff_value">Итоговая разница по себестоимости</string>
    <string name="inventory_pdf_total_diff_value_sell">Итоговая упущенная/лишняя выручка (по цене продажи)</string>

    <!-- Категории ryczałtu: ставка выбирается по каждой операции, а не одной общей настройкой -->
    <string name="ryczalt_cat_3">3% — товар</string>
    <string name="ryczalt_cat_5_5">5,5% — продукт/производство</string>
    <string name="ryczalt_cat_8_5">8,5% — услуги</string>
    <string name="ryczalt_cat_12">12% — IT-услуги</string>
    <string name="ryczalt_cat_14">14% — медицинские услуги</string>
    <string name="ryczalt_cat_17">17% — свободная профессия</string>
    <string name="ryczalt_category_picker_title">Категория ryczałt</string>
    <string name="ryczalt_category_choose">Выберите категорию ryczałt ▾</string>
    <string name="ryczalt_category_selected">Категория: %1$s</string>
    <string name="ryczalt_category_required_error">Выберите категорию ryczałt для каждой позиции</string>
    <string name="income_ryczalt_category_required_error">Выберите категорию ryczałt для этого дохода</string>

    <!-- Соответствие VAT / кассового аппарата (Настройки → Налоги) -->
    <string name="vat_compliance_title">Регистрация VAT</string>
    <string name="vat_compliance_hint" formatted="false">Превышен годовой лимит освобождения от VAT (240 000 zł). Вы обязаны подать форму VAT-R в течение 7 дней с даты превышения лимита и начислить VAT на транзакции, которая превысила порог. Подтвердите ниже после регистрации — до этого выставление фактур остаётся заблокированным.</string>
    <string name="cb_vat_registered_label">Подтверждаю, что зарегистрировался как плательщик VAT (подана VAT-R)</string>
    <string name="cb_vat_registered_confirmed_label">Подтверждено: зарегистрированный плательщик VAT</string>
    <string name="kasa_compliance_title">Кассовый аппарат</string>
    <string name="kasa_compliance_hint">Превышен годовой лимит 20 000 zł наличной продажи физическим лицам. Может понадобиться кассовый аппарат. Подтвердите ниже, когда он у вас появится — до этого выставление фактур остаётся заблокированным.</string>
    <string name="kasa_compliance_hint_registered">Ваша деятельность зарегистрирована (JDG), поэтому кассовый аппарат у вас мог быть уже с самого начала. Если это так, подтвердите это ниже — это откроет опцию «выдана к чеку» при заполнении фактур.</string>
    <string name="cb_kasa_label">Подтверждаю, что у меня есть кассовый аппарат</string>
    <string name="cb_kasa_confirmed_label">Подтверждено: кассовый аппарат используется</string>
    <string name="vat_confirm_dialog_title">Подтвердить регистрацию VAT</string>
    <string name="vat_confirm_dialog_message">Это подтверждает, что вы подали VAT-R и являетесь плательщиком VAT. Отменить это в приложении нельзя. Продолжить?</string>
    <string name="kasa_confirm_dialog_title">Подтвердить кассовый аппарат</string>
    <string name="kasa_confirm_dialog_message">Это подтверждает наличие у вас кассового аппарата. Отменить это в приложении нельзя. Продолжить?</string>
    <string name="confirm_yes">Да, подтверждаю</string>
    <string name="confirm_cancel">Отмена</string>

    <!-- Частота push-уведомлений (Настройки → Налоги) -->
    <string name="push_frequency_title">Частота push-уведомлений</string>
    <string name="push_frequency_hint">Сколько раз в день могут приходить уведомления о превышенных лимитах и просроченных фактурах (1–50).</string>
    <string name="push_frequency_saved">Частота уведомлений сохранена</string>
    <string name="push_frequency_invalid">Введите число от 1 до 50</string>
    <string name="income_ryczalt_category_label">Категория ryczałt для этого дохода</string>

    <!-- Несколько позиций в фактуре -->
    <string name="invoice_item_number_label">Позиция %1$d</string>
    <string name="add_invoice_item_row">+ Добавить позицию</string>
    <string name="invoice_items_limit_reached">Можно добавить не более %1$d позиций на счёт</string>
    <string name="invoice_item_min_required">В счёте должна остаться хотя бы одна позиция</string>
    <string name="invoice_total_label">Итого: %1$s zł</string>
    <string name="item_qty_hint">Кол-во</string>
    <string name="invoice_income_comment">Счёт №%1$d — %2$s</string>

    <!-- Update: модуль корректировок (Faktura korygująca) -->
    <string name="invoice_history_korekta_button">↺</string>
    <string name="correction_title">Корректировочный счёт</string>
    <string name="correction_original_invoice_label">Исходный документ: №%1$d, %2$s</string>
    <string name="correction_original_amount_label">Исходная сумма</string>
    <string name="correction_corrected_amount_hint">Сумма после корректировки (zł)</string>
    <string name="correction_reason_hint">Причина корректировки</string>
    <string name="correction_apply_to_income_label">Применить разницу к доходу (Przychód)</string>
    <string name="correction_save_button">Выставить корректировку</string>
    <string name="correction_zero_delta_error">Сумма после корректировки совпадает с исходной — нечего корректировать</string>
    <string name="correction_reason_required_error">Укажите причину корректировки</string>
    <string name="correction_saved_toast">Корректировочный счёт выставлен</string>
    <string name="correction_pdf_title">КОРРЕКТИРОВОЧНЫЙ СЧЁТ</string>
    <string name="correction_pdf_to_invoice">Корректировка к счёту</string>
    <string name="correction_pdf_reason_label">Причина корректировки</string>
    <string name="correction_pdf_before_label">Сумма до корректировки</string>
    <string name="correction_pdf_after_label">Сумма после корректировки</string>
    <string name="correction_pdf_delta_label">Разница</string>
    <!-- Update: таблица позиций в корректировочном счёте + поля подписи на обоих документах -->
    <string name="correction_pdf_before_table_title">До корректировки</string>
    <string name="correction_pdf_after_table_title">После корректировки</string>
    <string name="invoice_pdf_signature_issued_by">Выставил(а):</string>
    <string name="invoice_pdf_signature_received_by">Получил(а):</string>
    <string name="invoice_pdf_signature_issued_by_caption">Подпись лица, уполномоченного на выставление</string>
    <string name="invoice_pdf_signature_received_by_caption">Подпись лица, уполномоченного на получение</string>
    <!-- Update: корректировки теперь тоже отображаются в Истории счетов -->
    <string name="correction_history_row_title">Корректировка №%1$d → счёт №%2$d</string>
    <string name="correction_history_row_title_solo">Корректировка №%1$d</string>
    <string name="delete_correction_confirm_title">Удалить корректировку?</string>
    <string name="delete_correction_confirm_message">Запись корректировки и её PDF-файл будут удалены безвозвратно. Действие нельзя отменить. Запись дохода, созданная этой корректировкой (если была), автоматически не отменяется.</string>
    <string name="correction_deleted">Корректировка удалена</string>
    <string name="nav_start">Старт</string>
    <string name="nav_transactions">Транзакции</string>
    <string name="nav_reports">Отчёты</string>
    <string name="nav_settings">Настройки</string>
</resources>

STRINGS_RU
echo "  app/src/main/res/values-ru/strings.xml written"


echo "== Update 52: git add / commit / push =="
git add -A
git commit -m "Update 52: redesign Paywall (Wersja Pro) to match reference screen, remove old confirmation dialog"
git push

echo "== Update 52 done =="
