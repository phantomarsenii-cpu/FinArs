package com.example.fa_ksiegowy

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Ekran "O aplikacji" — wczesniej byl to zwykly systemowy AlertDialog z jednym
 * cigiem tekstu bez akapitow (blad renderowania \n), teraz pelny ekran z
 * osobnymi kartami na kazda sekcje, budowany programowo z string-array w
 * strings.xml — dzieki temu nie ma ryzyka zgubienia podzialow linii.
 */
class AboutActivity : BaseActivity() {

    private data class Section(val titleRes: Int, val bulletsArrayRes: Int)

    private val sections = listOf(
        Section(R.string.about_section_finance_title, R.array.about_bullets_finance),
        Section(R.string.about_section_warehouse_title, R.array.about_bullets_warehouse),
        Section(R.string.about_section_invoices_title, R.array.about_bullets_invoices),
        Section(R.string.about_section_reports_title, R.array.about_bullets_reports),
        Section(R.string.about_section_security_title, R.array.about_bullets_security)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_about)

        findViewById<View>(R.id.iv_back).setOnClickListener { finish() }

        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            null
        }
        findViewById<TextView>(R.id.tv_about_version).text =
            getString(R.string.about_version_label, versionName ?: "—")

        buildContent()

        findViewById<android.widget.Button>(R.id.btn_about_write).setOnClickListener {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:" + getString(R.string.about_email))
            }
            startActivity(intent)
        }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun buildContent() {
        val container = findViewById<LinearLayout>(R.id.ll_about_container)
        container.removeAllViews()

        // Wstep — bez tytulu, sama karta z tekstem.
        container.addView(makeCard {
            addView(bodyText(getString(R.string.about_intro)))
        })

        for (section in sections) {
            container.addView(makeCard {
                addView(titleText(getString(section.titleRes)))
                val bullets = resources.getStringArray(section.bulletsArrayRes)
                bullets.forEach { bullet ->
                    addView(bulletText(bullet))
                }
            })
        }

        container.addView(makeCard {
            addView(bodyText(getString(R.string.about_subscription_note)).apply {
                setTextColor(getColorCompat(R.color.accent_cyan))
            })
        })
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
        setTextColor(getColorCompat(R.color.text_primary))
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
        gravity = Gravity.START
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(6) }
    }

    private fun getColorCompat(colorRes: Int) = androidx.core.content.ContextCompat.getColor(this, colorRes)
}
