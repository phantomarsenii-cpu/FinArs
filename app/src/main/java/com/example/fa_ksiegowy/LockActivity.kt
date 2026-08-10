package com.example.fa_ksiegowy

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat

/**
 * Экран блокировки приложения. Показывается поверх любого экрана, когда
 * AppLockState.isLocked == true (см. BaseActivity). Не имеет пункта "Настройки"
 * или иного выхода, кроме правильного PIN/биометрии — кнопка "Назад" сворачивает
 * приложение (moveTaskToBack), а не закрывает этот экран.
 */
class LockActivity : BaseActivity() {

    private lateinit var etPin: EditText
    private lateinit var tvError: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_lock)

        etPin = findViewById(R.id.et_pin)
        tvError = findViewById(R.id.tv_lock_error)
        findViewById<ImageView>(R.id.iv_lock_logo).setImageResource(R.drawable.logo)

        findViewById<Button>(R.id.btn_unlock).setOnClickListener { tryUnlock() }
        etPin.setOnEditorActionListener { _, _, _ -> tryUnlock(); true }

        val btnBiometric = findViewById<Button>(R.id.btn_use_biometric)
        val canUseBiometric = SecurityHelper.isBiometricEnabled(this) && SecurityHelper.isBiometricAvailable(this)
        if (canUseBiometric) {
            btnBiometric.visibility = android.view.View.VISIBLE
            btnBiometric.setOnClickListener { showBiometricPrompt() }
        } else {
            btnBiometric.visibility = android.view.View.GONE
        }
    }

    override fun onStart() {
        super.onStart()
        // Автоматически предлагаем биометрию сразу при открытии экрана блокировки,
        // чтобы не заставлять лишний раз нажимать кнопку.
        if (SecurityHelper.isBiometricEnabled(this) && SecurityHelper.isBiometricAvailable(this)) {
            showBiometricPrompt()
        }
    }

    override fun onBackPressed() {
        // Не даём "выйти" из блокировки кнопкой назад — сворачиваем приложение.
        moveTaskToBack(true)
    }

    private fun tryUnlock() {
        val pin = etPin.text.toString()
        if (SecurityHelper.verifyPin(this, pin)) {
            AppLockState.unlock()
            finish()
        } else {
            tvError.visibility = android.view.View.VISIBLE
            etPin.text.clear()
        }
    }

    private fun showBiometricPrompt() {
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                AppLockState.unlock()
                finish()
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // Пользователь отменил/ошибка сенсора — просто остаёмся на вводе PIN.
            }
            override fun onAuthenticationFailed() {
                // Неверный отпечаток — ждём повторную попытку или ввод PIN.
            }
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.lock_biometric_prompt_title))
            .setSubtitle(getString(R.string.lock_biometric_prompt_subtitle))
            .setNegativeButtonText(getString(R.string.lock_use_pin))
            .build()
        prompt.authenticate(info)
    }
}
