package com.example.fa_ksiegowy

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.TextView

/** Ekran "O aplikacji" — wczesniej byl to zwykly systemowy AlertDialog (nie
 *  pasowal do ciemnego motywu), teraz pelny ekran w stylu reszty aplikacji. */
class AboutActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_about)

        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        val versionName = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            null
        }
        findViewById<TextView>(R.id.tv_about_version).text =
            getString(R.string.about_version_label, versionName ?: "—")

        findViewById<android.widget.Button>(R.id.btn_about_write).setOnClickListener {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:" + getString(R.string.about_email))
            }
            startActivity(intent)
        }
    }
}
