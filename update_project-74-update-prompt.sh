#!/usr/bin/env bash
# Update 74: плашка "Доступно обновление" (in-app update prompt).
# При запуске приложения (установка из Google Play) проверяет через Play Core, есть ли новая версия,
# и снизу над навигацией выезжает карточка "Обновить / Позже". "Обновить" открывает FinArs в
# Google Play; "Позже" прячет плашку на 3 дня. Тексты en/pl/ru/uk. Не мешает обучению — показывается
# только после его прохождения. Для APK из Termux/adb не показывается (Play не знает их версию).
# Запускать из КОРНЯ репозитория.
set -euo pipefail

J=app/src/main/java/com/example/fa_ksiegowy
for f in app/build.gradle "$J/MainActivity.kt"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

cat > "$J/UpdatePrompt.kt" <<'KT_UPD'
package com.example.fa_ksiegowy

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.UpdateAvailability

/**
 * Плашка "Доступно обновление" снизу главного экрана.
 *
 * Как работает:
 *  - раз за запуск (и не чаще, чем разрешает "Позже") спрашивает у Google Play, есть ли более
 *    новая версия приложения (Play Core, AppUpdateManager);
 *  - если есть — плавно выезжает карточка с кнопками "Обновить" / "Позже";
 *  - "Обновить" открывает страницу FinArs в Google Play, "Позже" прячет плашку на несколько дней.
 *
 * Работает только для установок из Google Play (у APK из Termux/adb Play не знает о версии).
 * Не показывается поверх обучающего тура и пока тур не пройден.
 */
class UpdatePrompt(private val activity: MainActivity) {

    private val handler = Handler(Looper.getMainLooper())
    private var card: View? = null
    private var checking = false

    fun schedule() {
        if (checkedThisProcess || checking || card != null) return
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ tryCheck() }, 2500)
    }

    fun dismiss(animated: Boolean = false) {
        handler.removeCallbacksAndMessages(null)
        val c = card ?: return
        card = null
        if (animated) {
            c.animate().alpha(0f).translationY(c.height * 0.4f).setDuration(220)
                .withEndAction { (c.parent as? ViewGroup)?.removeView(c) }.start()
        } else {
            c.animate().cancel()
            (c.parent as? ViewGroup)?.removeView(c)
        }
    }

    private fun canShowNow(): Boolean =
        !activity.isFinishing && !activity.isDestroyed && activity.hasWindowFocus() &&
            TermsActivity.isAccepted(activity) && !AppLockState.isLocked &&
            OnboardingTour.isDone(activity) && !isSnoozed(activity)

    private fun tryCheck() {
        if (!canShowNow()) return   // повторим при следующем onResume
        if (StoreDetector.detect(activity) != StoreSource.GOOGLE_PLAY) {
            checkedThisProcess = true
            return
        }
        checking = true
        try {
            AppUpdateManagerFactory.create(activity.applicationContext)
                .appUpdateInfo
                .addOnSuccessListener { info ->
                    checking = false
                    checkedThisProcess = true
                    if (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE && canShowNow()) {
                        show()
                    }
                }
                .addOnFailureListener {
                    checking = false
                    checkedThisProcess = true
                }
        } catch (e: Exception) {
            checking = false
            checkedThisProcess = true
        }
    }

    // ------------------------------------------------------------------ UI

    private fun show() {
        if (card != null) return
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val density = activity.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val c = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            background = ContextCompat.getDrawable(activity, R.drawable.card_bg)
            setPadding(dp(18), dp(16), dp(18), dp(10))
            elevation = 24f * density
        }
        val title = TextView(activity).apply {
            text = activity.getString(R.string.update_available_title)
            setTextColor(ContextCompat.getColor(activity, R.color.text_primary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setTypeface(typeface, Typeface.BOLD)
        }
        val text = TextView(activity).apply {
            text = activity.getString(R.string.update_available_text)
            setTextColor(ContextCompat.getColor(activity, R.color.text_secondary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setPadding(0, dp(6), 0, 0)
        }
        val later = TextView(activity).apply {
            text = activity.getString(R.string.update_later)
            gravity = Gravity.CENTER
            setTextColor(ContextCompat.getColor(activity, R.color.text_secondary))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(dp(14), 0, dp(14), 0)
            minHeight = dp(44)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                snooze(activity)
                dismiss(true)
            }
        }
        val update = TextView(activity).apply {
            text = activity.getString(R.string.update_now)
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(dp(24), 0, dp(24), 0)
            minHeight = dp(44)
            background = ContextCompat.getDrawable(activity, R.drawable.btn_pill_primary)
            isClickable = true
            isFocusable = true
            setOnClickListener {
                openStore()
                snooze(activity)   // вернулся из Play без обновления — не донимаем сразу же
                dismiss(true)
            }
        }
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            addView(later)
            addView(update, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { marginStart = dp(6) })
        }
        c.addView(title)
        c.addView(text)
        c.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(10) })

        // Над плавающей нижней навигацией (если она уже отрисована), иначе — с запасом снизу.
        var bottom = dp(110)
        val nav = root.findViewById<View>(R.id.nav_start)
        if (nav != null && nav.height > 0 && root.height > 0) {
            val a = IntArray(2); val b = IntArray(2)
            nav.getLocationInWindow(a); root.getLocationInWindow(b)
            bottom = (root.height - (a[1] - b[1])) + dp(18)
        }
        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM
            marginStart = dp(16); marginEnd = dp(16); bottomMargin = bottom
        }
        c.alpha = 0f
        root.addView(c, lp)
        card = c
        c.post {
            c.translationY = c.height * 0.5f
            c.animate().alpha(1f).translationY(0f).setDuration(320)
                .setInterpolator(PathInterpolator(0.4f, 0f, 0.2f, 1f)).start()
        }
    }

    private fun openStore() {
        val pkg = activity.packageName
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                .apply { setPackage("com.android.vending") })
        } catch (e: ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$pkg")))
            } catch (e2: Exception) {
                // нет ни Play, ни браузера — молча ничего не делаем
            }
        }
    }

    companion object {
        private const val PREFS = "settings"
        private const val KEY_SNOOZE_UNTIL = "update_prompt_snooze_until"
        private const val SNOOZE_MS = 3L * 24 * 60 * 60 * 1000

        @Volatile private var checkedThisProcess = false

        private fun isSnoozed(context: Context): Boolean =
            System.currentTimeMillis() <
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_SNOOZE_UNTIL, 0L)

        private fun snooze(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_SNOOZE_UNTIL, System.currentTimeMillis() + SNOOZE_MS).apply()
        }
    }
}
KT_UPD
echo "создан: $J/UpdatePrompt.kt"

python3 - <<'PY'
import re
M = "app/src/main"
J = M + "/java/com/example/fa_ksiegowy"
def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден фрагмент: " + what
    return s.replace(old, new)

# --- зависимость Play Core (in-app updates) ---
p = "app/build.gradle"
s = read(p)
if "com.google.android.play:app-update" not in s:
    old = '    implementation "com.google.android.ump:user-messaging-platform:3.1.0"\n'
    s = rep(s, old, old + '    implementation "com.google.android.play:app-update:2.1.0"\n', "build.gradle ump line")
    write(p, s)
else:
    print("build.gradle: уже применено")

# --- MainActivity ---
p = J + "/MainActivity.kt"
s = read(p)
if "UpdatePrompt" not in s:
    s = rep(s, "    private var tour: OnboardingTour? = null\n",
            "    private var tour: OnboardingTour? = null\n    private val updatePrompt = UpdatePrompt(this)\n", "field")
    s = rep(s, "        scheduleTourIfNeeded()\n    }\n\n    // Пока поверх",
            "        scheduleTourIfNeeded()\n        updatePrompt.schedule()   // Update 74: плашка \"Доступно обновление\"\n    }\n\n    // Пока поверх",
            "onResume")
    s = rep(s, "        tour?.dismiss(false)\n        tour = null\n        super.onDestroy()",
            "        tour?.dismiss(false)\n        tour = null\n        updatePrompt.dismiss()\n        super.onDestroy()", "onDestroy")
    write(p, s)
else:
    print("MainActivity: уже применено")

# --- строки ---
T = {
 "values": {
   "update_available_title": "Update available",
   "update_available_text": "A new version of FinArs is available with improvements and fixes.",
   "update_now": "Update", "update_later": "Later"},
 "values-pl": {
   "update_available_title": "Dostępna aktualizacja",
   "update_available_text": "Dostępna jest nowa wersja FinArs z ulepszeniami i poprawkami.",
   "update_now": "Aktualizuj", "update_later": "Później"},
 "values-ru": {
   "update_available_title": "Доступно обновление",
   "update_available_text": "Вышла новая версия FinArs с улучшениями и исправлениями.",
   "update_now": "Обновить", "update_later": "Позже"},
 "values-uk": {
   "update_available_title": "Доступне оновлення",
   "update_available_text": "Вийшла нова версія FinArs з покращеннями та виправленнями.",
   "update_now": "Оновити", "update_later": "Пізніше"},
}
for d, items in T.items():
    p = M + "/res/" + d + "/strings.xml"
    s = read(p)
    if "update_available_title" in s:
        print(d + ": строки уже добавлены"); continue
    blk = "\n    <!-- ===== Update 74: плашка обновления ===== -->\n" + "".join(
        '    <string name="%s">%s</string>\n' % (k, v) for k, v in items.items())
    idx = s.rfind("</resources>")
    assert idx > 0
    s = s[:idx].rstrip("\n") + "\n" + blk + "</resources>\n"
    write(p, s)

PY

echo
echo "Готово. Нужна сборка с новой зависимостью (com.google.android.play:app-update:2.1.0)."
