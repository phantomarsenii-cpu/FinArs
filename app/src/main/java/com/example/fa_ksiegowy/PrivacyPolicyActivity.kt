package com.example.fa_ksiegowy

import android.os.Bundle

/** Ekran "Polityka prywatnosci" — wymagany do publikacji w Google Play. */
class PrivacyPolicyActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_privacy_policy)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }
    }
}
