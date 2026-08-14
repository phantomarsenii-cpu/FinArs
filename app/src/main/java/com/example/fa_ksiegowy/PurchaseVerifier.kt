package com.example.fa_ksiegowy

import android.util.Base64
import android.util.Log
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/**
 * Проверка подписи покупки локальным публичным ключом лицензирования из Play Console
 * (Play Console -> ваше приложение -> Monetize -> Monetization setup -> Licensing ->
 * "Base64-encoded RSA public key").
 *
 * Зачем это нужно: инструменты вроде Lucky Patcher / freedom apk на рутованных
 * устройствах подменяют ОТВЕТ BillingClient, заставляя приложение думать, что покупка
 * прошла, хотя реальной транзакции в Google Play не было. BillingClient сам НЕ проверяет
 * подпись за вас — эта проверка ложится на приложение (в старом Billing API v3 её делала
 * входящая в комплект библиотека IabHelper, сейчас это нужно писать самим).
 *
 * ВАЖНО (честно): это не защита уровня сервера. Ключ и код проверки лежат в APK,
 * и опытный человек с реверс-инжинирингом теоретически может его вырезать целиком.
 * Настоящая защита "от взлома" делается только серверной проверкой через
 * Google Play Developer API (purchases.products.get) с вашим service account —
 * тогда решение "выдавать Pro или нет" принимает не устройство пользователя, а ваш
 * сервер. Локальная проверка — это разумный компромисс без бэкенда: она отсекает
 * подавляющее большинство массовых "патчеров", которые просто подменяют локальный
 * ответ, но не подделывают RSA-подпись.
 */
/**
 * Update: с переходом на RevenueCat (см. SubscriptionService.kt) этот класс больше НЕ
 * используется — валидацию покупок теперь делает сервер RevenueCat (для Test Store —
 * сам RevenueCat, для боевых Google Play / Galaxy Store — соответствующий магазин).
 * Класс оставлен в проекте на случай, если понадобится доп. локальная проверка,
 * но нигде не вызывается.
 */
object PurchaseVerifier {

    // TODO: обязательно вставьте сюда свой ключ из Play Console (см. описание выше).
    // Пока тут заглушка — проверка работать не будет, пока вы его не подставите.
    private const val BASE64_PUBLIC_KEY = "PASTE_YOUR_LICENSING_PUBLIC_KEY_HERE"

    private val publicKey: PublicKey? by lazy {
        if (BASE64_PUBLIC_KEY == "PASTE_YOUR_LICENSING_PUBLIC_KEY_HERE") {
            Log.w("PurchaseVerifier", "Licensing public key is not configured — signature check is skipped!")
            null
        } else try {
            val keyBytes = Base64.decode(BASE64_PUBLIC_KEY, Base64.DEFAULT)
            KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(keyBytes))
        } catch (e: Exception) {
            Log.e("PurchaseVerifier", "Invalid public key", e)
            null
        }
    }

    /**
     * @return true, если подпись валидна ИЛИ ключ ещё не настроен (fail-open на время разработки,
     * чтобы не сломать вам тестирование, пока вы не вставили реальный ключ — не забудьте это убрать
     * / настроить ключ перед релизом, иначе проверка фактически не работает).
     */
    fun verify(signedData: String, signature: String): Boolean {
        val key = publicKey ?: return true // ключ не настроен — см. предупреждение выше
        return try {
            val sig = Signature.getInstance("SHA1withRSA")
            sig.initVerify(key)
            sig.update(signedData.toByteArray())
            sig.verify(Base64.decode(signature, Base64.DEFAULT))
        } catch (e: Exception) {
            Log.e("PurchaseVerifier", "Signature verification failed", e)
            false
        }
    }
}
