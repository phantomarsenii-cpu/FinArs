package com.example.fa_ksiegowy

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Ekran "Polityka prywatnosci" — wymagany do publikacji w Google Play.
 * Kazda ponumerowana sekcja to osobna karta (tytul + tresc, plus opcjonalne
 * wypunktowanie z string-array), budowana programowo z osobnych zasobow
 * stringow — bez ryzyka utraty podzialow linii, ktore wystapilo przy
 * poprzedniej wersji z jednym dlugim ciagiem tekstu z \n.
 */
class PrivacyPolicyActivity : BaseActivity() {

    private data class Section(val titleRes: Int, val introRes: Int?, val bodyRes: Int?, val bulletsArrayRes: Int?)

    private val sections = listOf(
        Section(R.string.privacy_section1_title, null, R.string.privacy_section1_body, null),
        Section(R.string.privacy_section2_title, R.string.privacy_section2_intro, null, R.array.privacy_section2_bullets),
        Section(R.string.privacy_section3_title, R.string.privacy_section3_intro, null, R.array.privacy_section3_bullets),
        Section(R.string.privacy_section4_title, R.string.privacy_section4_intro, null, R.array.privacy_section4_bullets),
        Section(R.string.privacy_section5_title, null, R.string.privacy_section5_body, null),
        Section(R.string.privacy_section6_title, null, R.string.privacy_section6_body, null),
        Section(R.string.privacy_section7_title, null, R.string.privacy_section7_body, null),
        Section(R.string.privacy_section8_title, null, R.string.privacy_section8_body, null)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_privacy_policy)
        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }

        findViewById<TextView>(R.id.tv_privacy_updated).text = getString(R.string.privacy_updated_label)

        buildContent()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun buildContent() {
        val container = findViewById<LinearLayout>(R.id.ll_privacy_container)
        container.removeAllViews()

        container.addView(makeCard {
            addView(bodyText(getString(R.string.privacy_intro)))
        })

        for (section in sections) {
            container.addView(makeCard {
                addView(titleText(getString(section.titleRes)))
                section.introRes?.let { addView(bodyText(getString(it)).apply { setPadding(0, 0, 0, dp(8)) }) }
                section.bodyRes?.let { addView(bodyText(getString(it))) }
                section.bulletsArrayRes?.let { arrRes ->
                    resources.getStringArray(arrRes).forEach { bullet -> addView(bulletText(bullet)) }
                }
            })
        }
    }

    private fun makeCard(build: LinearLayout.() -> Unit): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.card_bg)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(12) }
            build()
        }
    }

    private fun titleText(text: String): TextView = TextView(this).apply {
        this.text = text
        setTextColor(getColorCompat(R.color.accent_cyan))
        textSize = 15f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(8) }
    }

    private fun bodyText(text: String): TextView = TextView(this).apply {
        this.text = text
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 14f
        setLineSpacing(dp(2).toFloat(), 1f)
    }

    private fun bulletText(text: String): TextView = TextView(this).apply {
        this.text = "•  $text"
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 13.5f
        setLineSpacing(dp(2).toFloat(), 1f)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
    }

    private fun getColorCompat(colorRes: Int) = androidx.core.content.ContextCompat.getColor(this, colorRes)
}
