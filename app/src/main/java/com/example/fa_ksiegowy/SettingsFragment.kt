package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment

/** Главное меню настроек — теперь просто категории, сами экраны вынесены
 *  в отдельные Activity, чтобы список не занимал весь экран и было место
 *  под будущие разделы. */
class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_settings, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        // Update: setContentView/BottomNavBar.attach убраны — этот экран теперь фрагмент
        // внутри MainActivity, у которого нав-бар и рекламный баннер уже созданы один раз
        // на уровне Activity (см. MainActivity.kt), а не пересоздаются здесь.

        requireView().findViewById<View>(R.id.btn_menu_tax).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsTaxActivity::class.java))
        }
        // Update: пункт меню "Безопасность (PIN/Biometrics)" был потерян в одном
        // из прошлых обновлений — сама логика (SecurityHelper/LockActivity/
        // AppLockState) всё это время оставалась рабочей, но экран настроек был
        // недостижим, поэтому PIN никто не мог задать и блокировка ни разу не
        // срабатывала. Возвращаем переход на экран.
        requireView().findViewById<View>(R.id.btn_menu_security).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsSecurityActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_pit36).setOnClickListener {
            if (BillingManager.isPro(requireContext())) {
                startActivity(Intent(requireContext(), Pit36Activity::class.java))
            } else {
                AlertDialog.Builder(requireContext())
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.pit36_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(requireContext(), SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        requireView().findViewById<View>(R.id.btn_menu_language).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsLanguageActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_backup).setOnClickListener {
            if (BillingManager.isPro(requireContext())) {
                startActivity(Intent(requireContext(), SettingsBackupActivity::class.java))
            } else {
                AlertDialog.Builder(requireContext())
                    .setTitle(getString(R.string.pro_feature_locked_title))
                    .setMessage(getString(R.string.backup_pro_locked_message))
                    .setPositiveButton(getString(R.string.settings_menu_pro)) { _, _ ->
                        startActivity(Intent(requireContext(), SettingsProActivity::class.java))
                    }
                    .setNegativeButton(getString(R.string.dialog_close), null)
                    .show()
            }
        }
        requireView().findViewById<View>(R.id.btn_menu_pro).setOnClickListener {
            startActivity(Intent(requireContext(), SettingsProActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_terms).setOnClickListener {
            val i = Intent(requireContext(), TermsActivity::class.java)
            i.putExtra(TermsActivity.EXTRA_READ_ONLY, true)
            startActivity(i)
        }
        requireView().findViewById<View>(R.id.btn_menu_privacy).setOnClickListener {
            startActivity(Intent(requireContext(), PrivacyPolicyActivity::class.java))
        }
        requireView().findViewById<View>(R.id.btn_menu_about).setOnClickListener {
            startActivity(Intent(requireContext(), AboutActivity::class.java))
        }
    }
}
