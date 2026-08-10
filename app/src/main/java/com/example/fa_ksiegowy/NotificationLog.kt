package com.example.fa_ksiegowy

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Historia powiadomień aplikacji — wpis dodawany przy KAŻDYM realnym powiadomieniu
 * systemowym (patrz LimitsNotificationWorker.showNotification), tak żeby ekran
 * "Historia powiadomień" (otwierany dzwonkiem na Start) pokazywal to, co user
 * faktycznie dostal, nawet jesli juz zniknelo z paska powiadomien systemu.
 *
 * Celowo NIE uzywa Room (zeby uniknac migracji bazy) — prosty JSON w
 * SharedPreferences w zupelnosci wystarcza do listy kilkudziesieciu wpisow.
 */
object NotificationLog {
    data class Entry(val id: Long, val title: String, val text: String, val timeMillis: Long)

    private const val PREFS = "notification_log"
    private const val KEY_ITEMS = "items"
    private const val MAX_ITEMS = 100

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(context: Context, title: String, text: String) {
        val list = getAll(context).toMutableList()
        list.add(0, Entry(System.currentTimeMillis(), title, text, System.currentTimeMillis()))
        val trimmed = list.take(MAX_ITEMS)
        save(context, trimmed)
    }

    fun getAll(context: Context): List<Entry> {
        val raw = prefs(context).getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Entry(o.getLong("id"), o.getString("title"), o.getString("text"), o.getLong("time"))
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun delete(context: Context, id: Long) {
        val list = getAll(context).filterNot { it.id == id }
        save(context, list)
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY_ITEMS).apply()
    }

    private fun save(context: Context, list: List<Entry>) {
        val arr = JSONArray()
        for (e in list) {
            arr.put(JSONObject().apply {
                put("id", e.id)
                put("title", e.title)
                put("text", e.text)
                put("time", e.timeMillis)
            })
        }
        prefs(context).edit().putString(KEY_ITEMS, arr.toString()).apply()
    }
}
