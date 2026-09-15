package com.example.fa_ksiegowy

import android.os.Bundle
import android.os.CountDownTimer
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
    private lateinit var btnUnlock: Button
    private lateinit var btnBiometric: Button
    private var countdownTimer: CountDownTimer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_lock)

        etPin = findViewById(R.id.et_pin)
        tvError = findViewById(R.id.tv_lock_error)
        btnUnlock = findViewById(R.id.btn_unlock)
        btnBiometric = findViewById(R.id.btn_use_biometric)
        findViewById<ImageView>(R.id.iv_lock_logo).setImageResource(R.drawable.logo)

        btnUnlock.setOnClickListener { tryUnlock() }
        etPin.setOnEditorActionListener { _, _, _ -> tryUnlock(); true }
    }

    override fun onStart() {
        super.onStart()
        applyLockoutState()
    }

    override fun onDestroy() {
        super.onDestroy()
        countdownTimer?.cancel()
    }

    override fun onBackPressed() {
        // Не даём "выйти" из блокировки кнопкой назад — сворачиваем приложение.
        moveTaskToBack(true)
    }

    /** Если сейчас идёт временная блокировка ввода из-за неверных попыток —
     *  блокирует поле/кнопки и запускает обратный отсчёт. Иначе — как обычно,
     *  включая автопоказ биометрии. */
    private fun applyLockoutState() {
        val remaining = SecurityHelper.lockoutRemainingMillis(this)
        countdownTimer?.cancel()

        if (remaining <= 0L) {
            etPin.isEnabled = true
            btnUnlock.isEnabled = true
            tvError.visibility = android.view.View.GONE

            val canUseBiometric = SecurityHelper.isBiometricEnabled(this) && SecurityHelper.isBiometricAvailable(this)
            if (canUseBiometric) {
                btnBiometric.visibility = android.view.View.VISIBLE
                btnBiometric.setOnClickListener { showBiometricPrompt() }
                showBiometricPrompt()
            } else {
                btnBiometric.visibility = android.view.View.GONE
            }
            return
        }

        // Заблокировано: скрываем биометрию (чтобы не обходить блокировку) и
        // показываем оставшееся время в поле ошибки, обновляя раз в секунду.
        etPin.isEnabled = false
        btnUnlock.isEnabled = false
        btnBiometric.visibility = android.view.View.GONE
        etPin.text.clear()
        tvError.visibility = android.view.View.VISIBLE

        countdownTimer = object : CountDownTimer(remaining, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val seconds = (millisUntilFinished / 1000).toInt() + 1
                val minutes = seconds / 60
                val secs = seconds % 60
                tvError.text = if (minutes > 0) {
                    getString(R.string.lock_locked_out_minutes, minutes, secs)
                } else {
                    getString(R.string.lock_locked_out_seconds, secs)
                }
            }
            override fun onFinish() {
                applyLockoutState()
            }
        }.start()
    }

    private fun tryUnlock() {
        if (SecurityHelper.lockoutRemainingMillis(this) > 0L) return
        val pin = etPin.text.toString()
        if (SecurityHelper.verifyPin(this, pin)) {
            AppLockState.unlock()
            finish()
        } else {
            SecurityHelper.registerFailedAttempt(this)
            etPin.text.clear()
            if (SecurityHelper.lockoutRemainingMillis(this) > 0L) {
                applyLockoutState()
            } else {
                tvError.text = getString(R.string.lock_wrong_pin)
                tvError.visibility = android.view.View.VISIBLE
            }
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
