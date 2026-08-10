package com.example.fa_ksiegowy

import android.content.Context
import androidx.biometric.BiometricManager
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Хранит PIN-код приложения (НЕ пароль от аккаунта — чисто локальная блокировка
 * экрана). PIN никогда не хранится в открытом виде: соль генерируется случайно
 * при первой установке PIN и хранится вместе с солёным SHA-256 хэшем в обычных
 * SharedPreferences (для самого хэша шифрование не требуется — по хэшу нельзя
 * восстановить исходный PIN).
 *
 * Отдельно — переключатель "вход по отпечатку/лицу" (biometric), который можно
 * включить только если PIN уже установлен (biometric — это быстрый способ ввести
 * тот же самый PIN, а не замена его: если сенсор недоступен, всегда можно ввести
 * PIN вручную).
 */
object SecurityHelper {

    private const val PREFS = "security"
    private const val KEY_SALT = "pin_salt"
    private const val KEY_HASH = "pin_hash"
    private const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasPin(context: Context): Boolean =
        prefs(context).contains(KEY_HASH)

    /** Устанавливает/меняет PIN (4–6 цифр, проверка формата — на стороне UI). */
    fun setPin(context: Context, pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val hash = hash(pin, salt)
        prefs(context).edit()
            .putString(KEY_SALT, salt.joinToString(",") { it.toString() })
            .putString(KEY_HASH, hash)
            .apply()
    }

    fun verifyPin(context: Context, pin: String): Boolean {
        val p = prefs(context)
        val saltStr = p.getString(KEY_SALT, null) ?: return false
        val expectedHash = p.getString(KEY_HASH, null) ?: return false
        val salt = saltStr.split(",").map { it.toByte() }.toByteArray()
        return hash(pin, salt) == expectedHash
    }

    /** Полностью отключает блокировку приложения (PIN + биометрию). */
    fun clearPin(context: Context) {
        prefs(context).edit()
            .remove(KEY_SALT)
            .remove(KEY_HASH)
            .remove(KEY_BIOMETRIC_ENABLED)
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

    private fun hash(pin: String, salt: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(salt)
        val bytes = digest.digest(pin.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
