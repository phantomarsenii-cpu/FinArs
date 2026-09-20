package com.example.fa_ksiegowy

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.addCallback
import androidx.viewpager2.widget.ViewPager2
import com.google.android.material.tabs.TabLayout
import com.google.android.material.tabs.TabLayoutMediator

/**
 * Короткий онбординг (4 карточки со свайпом), который показывается ровно
 * один раз — после принятия TermsActivity, до первого входа в MainActivity.
 * Гейт стоит в BaseActivity.onResume() (см. isCompleted/markCompleted ниже),
 * поэтому его увидят и уже существующие пользователи при обновлении
 * приложения, а не только новые установки.
 */
class OnboardingActivity : BaseActivity() {

    companion object {
        private const val PREFS_NAME = "settings"
        private const val KEY_ONBOARDING_COMPLETED = "onboarding_completed"

        fun isCompleted(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_ONBOARDING_COMPLETED, false)
        }

        private fun markCompleted(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_ONBOARDING_COMPLETED, true)
                .apply()
        }
    }

    private lateinit var pager: ViewPager2
    private lateinit var pages: List<OnboardingPage>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_onboarding)

        pages = listOf(
            OnboardingPage(
                iconRes = R.drawable.ic_nav_home,
                iconBgColor = R.color.vivid_blue,
                titleRes = R.string.onboarding_title_welcome,
                descriptionRes = R.string.onboarding_desc_welcome
            ),
            OnboardingPage(
                iconRes = R.drawable.ic_cat_income,
                iconBgColor = R.color.vivid_green,
                titleRes = R.string.onboarding_title_entries,
                descriptionRes = R.string.onboarding_desc_entries
            ),
            OnboardingPage(
                iconRes = R.drawable.ic_camera,
                iconBgColor = R.color.vivid_orange,
                titleRes = R.string.onboarding_title_receipts,
                descriptionRes = R.string.onboarding_desc_receipts
            ),
            OnboardingPage(
                iconRes = R.drawable.ic_settings_pit,
                iconBgColor = R.color.vivid_red,
                titleRes = R.string.onboarding_title_tax,
                descriptionRes = R.string.onboarding_desc_tax
            )
        )

        pager = findViewById(R.id.onboarding_pager)
        pager.adapter = OnboardingPagerAdapter(pages)

        val dots = findViewById<TabLayout>(R.id.onboarding_dots)
        TabLayoutMediator(dots, pager) { _, _ -> }.attach()

        val btnNext = findViewById<Button>(R.id.btn_onboarding_next)
        val btnSkip = findViewById<TextView>(R.id.btn_onboarding_skip)

        updateNextButtonLabel(btnNext, 0)

        pager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                updateNextButtonLabel(btnNext, position)
            }
        })

        btnNext.setOnClickListener {
            val next = pager.currentItem + 1
            if (next < pages.size) {
                pager.currentItem = next
            } else {
                finishOnboarding()
            }
        }

        btnSkip.setOnClickListener { finishOnboarding() }

        // Первичный показ нельзя обойти системной кнопкой "назад" — как и
        // TermsActivity, чтобы пользователь не выпал в MainActivity в обход
        // гейта (см. BaseActivity.onResume()).
        onBackPressedDispatcher.addCallback(this, true) {
            /* no-op */
        }
    }

    private fun updateNextButtonLabel(button: Button, position: Int) {
        button.text = if (position == pages.size - 1) {
            getString(R.string.onboarding_get_started)
        } else {
            getString(R.string.onboarding_next)
        }
    }

    private fun finishOnboarding() {
        markCompleted(this)
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }
}
