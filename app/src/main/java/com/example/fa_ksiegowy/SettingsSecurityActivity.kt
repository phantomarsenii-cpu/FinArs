package com.example.fa_ksiegowy

import android.app.AlertDialog
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

/**
 * Настройки блокировки приложения: включить/выключить PIN, сменить PIN,
 * включить вход по отпечатку/лицу (доступно только если PIN уже установлен
 * и устройство поддерживает биометрию).
 */
class SettingsSecurityActivity : BaseActivity() {

    private lateinit var switchPin: Switch
    private lateinit var switchBiometric: Switch
    private lateinit var tvChangePin: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings_security)
        findViewById<android.view.View>(R.id.iv_back).setOnClickListener { finish() }

        switchPin = findViewById(R.id.switch_pin)
        switchBiometric = findViewById(R.id.switch_biometric)
        tvChangePin = findViewById(R.id.tv_change_pin)

        refreshUi()
        tvChangePin.setOnClickListener { promptChangePin() }
    }

    override fun onResume() {
        super.onResume()
        refreshUi()
    }

    private fun refreshUi() {
        val hasPin = SecurityHelper.hasPin(this)
        switchPin.setOnCheckedChangeListener(null)
        switchPin.isChecked = hasPin
        switchPin.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !SecurityHelper.hasPin(this)) {
                promptSetNewPin()
            } else if (!isChecked && SecurityHelper.hasPin(this)) {
                promptDisablePin()
            }
        }

        switchBiometric.isEnabled = hasPin
        switchBiometric.setOnCheckedChangeListener(null)
        switchBiometric.isChecked = SecurityHelper.isBiometricEnabled(this)
        switchBiometric.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked && !SecurityHelper.isBiometricAvailable(this)) {
                Toast.makeText(this, getString(R.string.lock_biometric_unavailable), Toast.LENGTH_LONG).show()
                switchBiometric.isChecked = false
                return@setOnCheckedChangeListener
            }
            SecurityHelper.setBiometricEnabled(this, isChecked)
        }

        tvChangePin.visibility = if (hasPin) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun pinInput(): EditText = EditText(this).apply {
        inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
        hint = getString(R.string.lock_pin_hint)
        setTextColor(androidx.core.content.ContextCompat.getColor(context, R.color.text_primary))
        setHintTextColor(androidx.core.content.ContextCompat.getColor(context, R.color.text_hint))
        textSize = 16f
    }

    private fun wrap(view: EditText): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(48, 24, 48, 0)
        addView(view)
    }

    private fun promptSetNewPin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_set_pin_title))
            .setMessage(getString(R.string.security_set_pin_message))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                val pin = input.text.toString()
                if (pin.length < 4 || pin.length > 6) {
                    Toast.makeText(this, getString(R.string.security_pin_length_error), Toast.LENGTH_LONG).show()
                    refreshUi()
                    return@setPositiveButton
                }
                confirmNewPin(pin)
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun confirmNewPin(firstPin: String) {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_confirm_pin_title))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (input.text.toString() == firstPin) {
                    SecurityHelper.setPin(this, firstPin)
                    Toast.makeText(this, getString(R.string.security_pin_saved), Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
                refreshUi()
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun promptDisablePin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_disable_pin_title))
            .setMessage(getString(R.string.security_enter_current_pin))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (SecurityHelper.verifyPin(this, input.text.toString())) {
                    SecurityHelper.clearPin(this)
                    Toast.makeText(this, getString(R.string.security_pin_disabled), Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
                refreshUi()
            }
            .setNegativeButton(getString(R.string.dialog_close)) { _, _ -> refreshUi() }
            .setOnCancelListener { refreshUi() }
            .show()
    }

    private fun promptChangePin() {
        val input = pinInput()
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.security_disable_pin_title))
            .setMessage(getString(R.string.security_enter_current_pin))
            .setView(wrap(input))
            .setPositiveButton(getString(R.string.security_continue)) { _, _ ->
                if (SecurityHelper.verifyPin(this, input.text.toString())) {
                    promptSetNewPin()
                } else {
                    Toast.makeText(this, getString(R.string.security_pin_mismatch), Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton(getString(R.string.dialog_close), null)
            .show()
    }
}
