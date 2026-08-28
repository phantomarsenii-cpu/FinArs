package com.example.fa_ksiegowy

import android.content.Context
import androidx.biometric.BiometricManager
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Хранит PIN-код приложения (НЕ пароль от аккаунта — чисто локальная блокировка
 * экрана). PIN никогда не хранится в открытом виде: хэшируется алгоритмом
 * PBKDF2WithHmacSHA256 (с солью и большим числом итераций — специально
 * медленный алгоритм, устойчивый к перебору "в лоб" даже если бы кто-то
 * получил доступ к SharedPreferences). Старые установки, где PIN был сохранён
 * прежним быстрым алгоритмом (соль + один проход SHA-256), при следующем
 * успешном вводе автоматически перехэшируются в PBKDF2 — без необходимости
 * заново вводить/менять PIN.
 *
 * Отдельно — переключатель "вход по отпечатку/лицу" (biometric), который можно
 * включить только если PIN уже установлен (biometric — это быстрый способ ввести
 * тот же самый PIN, а не замена его: если сенсор недоступен, всегда можно ввести
 * PIN вручную).
 *
 * Защита от перебора PIN: отдельно от хэширования, [registerFailedAttempt] считает
 * подряд идущие неверные попытки и включает временную блокировку ввода с
 * нарастающей длительностью (см. LockActivity, которая проверяет [lockoutRemainingMillis]
 * перед тем как разрешить попытку).
 */
object SecurityHelper {

    private const val PREFS = "security"
    private const val KEY_SALT = "pin_salt"
    private const val KEY_HASH = "pin_hash"
    private const val KEY_ITERATIONS = "pin_iterations"
    private const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"
    private const val KEY_FAILED_ATTEMPTS = "pin_failed_attempts"
    private const val KEY_LOCKOUT_UNTIL = "pin_lockout_until"

    private const val PBKDF2_ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256

    // После этого числа подряд неверных попыток включается блокировка ввода.
    private const val ATTEMPTS_BEFORE_LOCKOUT = 5
    // Далее за каждую следующую неверную попытку блокировка длиннее (в мс).
    private val LOCKOUT_STEPS_MILLIS = longArrayOf(30_000, 60_000, 5 * 60_000, 15 * 60_000, 30 * 60_000)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasPin(context: Context): Boolean =
        prefs(context).contains(KEY_HASH)

    /** Устанавливает/меняет PIN (4–6 цифр, проверка формата — на стороне UI). */
    fun setPin(context: Context, pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val hash = pbkdf2(pin, salt, PBKDF2_ITERATIONS)
        prefs(context).edit()
            .putString(KEY_SALT, salt.joinToString(",") { it.toString() })
            .putString(KEY_HASH, hash)
            .putInt(KEY_ITERATIONS, PBKDF2_ITERATIONS)
            .apply()
        clearFailedAttempts(context)
    }

    fun verifyPin(context: Context, pin: String): Boolean {
        val p = prefs(context)
        val saltStr = p.getString(KEY_SALT, null) ?: return false
        val expectedHash = p.getString(KEY_HASH, null) ?: return false
        val salt = saltStr.split(",").map { it.toByte() }.toByteArray()
        val iterations = p.getInt(KEY_ITERATIONS, 0)

        val matches = if (iterations > 0) {
            pbkdf2(pin, salt, iterations) == expectedHash
        } else {
            // Совместимость со старыми установками (соль + один проход SHA-256).
            legacySha256(pin, salt) == expectedHash
        }

        if (matches) {
            clearFailedAttempts(context)
            if (iterations <= 0) {
                // Опортунистическая миграция на PBKDF2 при первом успешном входе.
                setPin(context, pin)
            }
        }
        return matches
    }

    /** Полностью отключает блокировку приложения (PIN + биометрию). */
    fun clearPin(context: Context) {
        prefs(context).edit()
            .remove(KEY_SALT)
            .remove(KEY_HASH)
            .remove(KEY_ITERATIONS)
            .remove(KEY_BIOMETRIC_ENABLED)
            .remove(KEY_FAILED_ATTEMPTS)
            .remove(KEY_LOCKOUT_UNTIL)
            .apply()
    }

    fun isBiometricEnabled(context: Context): Boolean =
        hasPin(context) && prefs(context).getBoolean(KEY_BIOMETRIC_ENABLED, false)

    fun setBiometricEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_BIOMETRIC_ENABLED, enabled).apply()
    }

    /** Есть ли на устройстве настроенный отпечаток/лицо, которым можно пользоваться. */
    fun isBiometricAvailable(context: Context): Boolean {
        val manager = BiometricManager.from(context)
        val result = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        return result == BiometricManager.BIOMETRIC_SUCCESS
    }

    /** Сколько мс осталось до конца блокировки ввода PIN (0 — блокировки нет / уже истекла). */
    fun lockoutRemainingMillis(context: Context): Long {
        val until = prefs(context).getLong(KEY_LOCKOUT_UNTIL, 0L)
        val remaining = until - System.currentTimeMillis()
        return if (remaining > 0) remaining else 0L
    }

    /** Вызывать после каждой неверной попытки ввода PIN — считает попытки и,
     *  начиная с [ATTEMPTS_BEFORE_LOCKOUT], включает нарастающую блокировку. */
    fun registerFailedAttempt(context: Context) {
        val p = prefs(context)
        val attempts = p.getInt(KEY_FAILED_ATTEMPTS, 0) + 1
        val editor = p.edit().putInt(KEY_FAILED_ATTEMPTS, attempts)
        if (attempts >= ATTEMPTS_BEFORE_LOCKOUT) {
            val stepIndex = (attempts - ATTEMPTS_BEFORE_LOCKOUT).coerceAtMost(LOCKOUT_STEPS_MILLIS.size - 1)
            val lockoutMillis = LOCKOUT_STEPS_MILLIS[stepIndex]
            editor.putLong(KEY_LOCKOUT_UNTIL, System.currentTimeMillis() + lockoutMillis)
        }
        editor.apply()
    }

    private fun clearFailedAttempts(context: Context) {
        prefs(context).edit()
            .remove(KEY_FAILED_ATTEMPTS)
            .remove(KEY_LOCKOUT_UNTIL)
            .apply()
    }

    private fun pbkdf2(pin: String, salt: ByteArray, iterations: Int): String {
        val spec = PBEKeySpec(pin.toCharArray(), salt, iterations, KEY_LENGTH_BITS)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val bytes = factory.generateSecret(spec).encoded
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun legacySha256(pin: String, salt: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        val bytes = digest.digest(pin.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
