package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.View

/** Главное меню настроек — теперь просто категории, сами экраны вынесены
 *  в отдельные Activity, чтобы список не занимал весь экран и было место
 *  под будущие разделы. */
class SettingsActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)
        BottomNavBar.attach(this, BottomNavBar.Tab.SETTINGS)

        findViewById<View>(R.id.btn_menu_tax).setOnClickListener {
            startActivity(Intent(this, SettingsTaxActivity::class.java))
        }
        // Update: пункт меню "Безопасность (PIN/Biometrics)" был потерян в одном
        // из прошлых обновлений — сама логика (SecurityHelper/LockActivity/
        // AppLockState) всё это время оставалась рабочей, но экран настроек был
        // недостижим, поэтому PIN никто не мог задать и блокировка ни разу не
        // срабатывала. Возвращаем переход на экран.
        findViewById<View>(R.id.btn_menu_security).setOnClickListener {
            startActivity(Intent(this, SettingsSecurityActivity::class.java))
        }
        findViewById<View>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<View>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(this, SettingsLanguageActivity::class.java))
        }
        findViewById<View>(R.id.btn_menu_backup).setOnClickListener {
            if (BillingManager.isPro(this)) {
                startActivity(Intent(this, SettingsBackupActivity::class.java))
            } else {
                AlertDialog.Builder(this)
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.backup_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(this, SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        findViewById<View>(R.id.btn_menu_pro).setOnClickListener {
            startActivity(Intent(this, SettingsProActivity::class.java))
        }
        findViewById<View>(R.id.btn_menu_terms).setOnClickListener {
            val i = Intent(this, TermsActivity::class.java)
            i.putExtra(TermsActivity.EXTRA_READ_ONLY, true)
            startActivity(i)
        }
        findViewById<View>(R.id.btn_menu_privacy).setOnClickListener {
            startActivity(Intent(this, PrivacyPolicyActivity::class.java))
        }
        findViewById<View>(R.id.btn_menu_about).setOnClickListener {
            startActivity(Intent(this, AboutActivity::class.java))
        }
    }
}
