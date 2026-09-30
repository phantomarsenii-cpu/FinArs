#!/usr/bin/env bash
# Update 79: мелкие правки перед публикацией в Google Play (не влияют на работу приложения).
#  1) RevenueCat: в релизной сборке логи WARN вместо DEBUG (в debug-сборке из Actions остаётся DEBUG).
#  2) RevenueCat: в релизной сборке больше не используется тестовый ключ Test Store — вне Google Play
#     покупка просто будет недоступна (вместо симулированной покупки). В debug-сборках (Termux/Actions)
#     Test Store работает как раньше.
#  3) Рекламный баннер: отступ до нижней навигации 6 dp -> 16 dp (меньше риск случайных кликов, политика AdMob).
# Запускать из КОРНЯ репозитория.
set -euo pipefail

J=app/src/main/java/com/example/fa_ksiegowy
L=app/src/main/res/layout/activity_main.xml
for f in "$J/SubscriptionService.kt" "$L"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория (нет $f)"; exit 1; }
done

python3 - <<'PY'
J = "app/src/main/java/com/example/fa_ksiegowy"
def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s); print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден фрагмент: " + what
    return s.replace(old, new)

# ---- SubscriptionService.kt ----
p = J + "/SubscriptionService.kt"
s = read(p)
if "Update 79" in s:
    print("SubscriptionService: уже применено")
else:
    s = rep(s,
        "        Purchases.logLevel = LogLevel.DEBUG\n",
        "        // Update 79: подробные логи RevenueCat только в debug-сборке.\n"
        "        Purchases.logLevel = if (isDebuggableBuild(context)) LogLevel.DEBUG else LogLevel.WARN\n",
        "logLevel")
    s = rep(s,
        "        val useGooglePlay = detectedStore == StoreSource.GOOGLE_PLAY && GOOGLE_PLAY_API_KEY.isNotBlank()\n",
        "        // Update 79: в РЕЛИЗНОЙ сборке тестовый ключ Test Store не используется никогда —\n"
        "        // вне Google Play покупка просто не пройдёт. Test Store остаётся только для debug-сборок.\n"
        "        val useGooglePlay = (detectedStore == StoreSource.GOOGLE_PLAY || !isDebuggableBuild(appContext)) &&\n"
        "            GOOGLE_PLAY_API_KEY.isNotBlank()\n",
        "useGooglePlay")
    s = rep(s,
        "    private fun buildConfiguration(context: Context): PurchasesConfiguration {\n",
        "    private fun isDebuggableBuild(context: Context): Boolean =\n"
        "        (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0\n\n"
        "    private fun buildConfiguration(context: Context): PurchasesConfiguration {\n",
        "buildConfiguration")
    write(p, s)

# ---- activity_main.xml ----
p = "app/src/main/res/layout/activity_main.xml"
s = read(p)
old = '            android:layout_marginBottom="6dp"\n            android:visibility="gone"/>'
new = '            android:layout_marginBottom="16dp"\n            android:visibility="gone"/>'
if new in s:
    print("activity_main: уже применено")
else:
    s = rep(s, old, new, "ad_container margin")
    write(p, s)
PY
