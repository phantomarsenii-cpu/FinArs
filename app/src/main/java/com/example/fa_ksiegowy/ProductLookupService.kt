package com.example.fa_ksiegowy

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Поиск названия товара по штрихкоду через открытую базу Open Food Facts.
 * Покрывает в основном продукты питания/бытовые товары — для остального
 * (или если интернета нет) возвращает null, и приложение переходит
 * к ручному вводу с уже привязанным штрихкодом.
 */
object ProductLookupService {
    suspend fun lookupName(barcode: String): String? = withContext(Dispatchers.IO) {
        try {
            val url = URL("https://world.openfoodfacts.org/api/v0/product/$barcode.json")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 6000
            conn.readTimeout = 6000
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "FA_ksiegowy-Android-App")
            val code = conn.responseCode
            if (code != 200) {
                conn.disconnect()
                return@withContext null
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            conn.disconnect()
            val json = JSONObject(body)
            if (json.optInt("status", 0) != 1) return@withContext null
            val product = json.optJSONObject("product") ?: return@withContext null
            val name = product.optString("product_name").ifBlank {
                product.optString("product_name_ru").ifBlank {
                    product.optString("product_name_pl")
                }
            }
            name.ifBlank { null }
        } catch (e: Exception) {
            null
        }
    }
}
