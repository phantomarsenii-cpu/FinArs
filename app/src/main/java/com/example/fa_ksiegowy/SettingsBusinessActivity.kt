package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.Toast

/** Настройки -> Тип деятельности: определяет, показывается ли на главном экране "Склад". */
class SettingsBusinessActivity : BaseActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_business)

        val prefs = getSharedPreferences("settings", MODE_PRIVATE)
        applyUi(BusinessKindHelper.get(prefs))

        findViewById<Button>(R.id.btn_business_sales).setOnClickListener { choose(prefs, BusinessKind.SALES) }
        findViewById<Button>(R.id.btn_business_services).setOnClickListener { choose(prefs, BusinessKind.SERVICES) }
        findViewById<Button>(R.id.btn_business_mixed).setOnClickListener { choose(prefs, BusinessKind.MIXED) }
    }

    private fun choose(prefs: android.content.SharedPreferences, kind: BusinessKind) {
        BusinessKindHelper.set(prefs, kind)
        applyUi(kind)
        Toast.makeText(this, getString(R.string.saved), Toast.LENGTH_SHORT).show()
    }

    private fun applyUi(kind: BusinessKind) {
        setState(findViewById(R.id.btn_business_sales), kind == BusinessKind.SALES)
        setState(findViewById(R.id.btn_business_services), kind == BusinessKind.SERVICES)
        setState(findViewById(R.id.btn_business_mixed), kind == BusinessKind.MIXED)
    }

    private fun setState(b: Button, selected: Boolean) {
        b.setBackgroundResource(if (selected) R.drawable.btn_pill_primary else R.drawable.btn_pill_outline)
    }
}
