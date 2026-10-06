#!/usr/bin/env bash
# Update 81: правки интерфейса Pro-замков после Update 80.
#  1) Magazyn: вместо отдельного экрана с замком — обычный экран склада, слегка затемнённый и не
#     реагирующий на нажатия; при заходе на вкладку и при любом касании всплывает то же окно
#     "🔒 Функция Pro" с кнопкой оформления подписки.
#  2) Окно "Функция Pro": кнопка больше не обрезает текст (короткая подпись "Оформить Pro" + кнопки
#     диалога в одну строку с автоподбором размера шрифта — это действует на все диалоги приложения).
# Запускать из КОРНЯ репозитория, ДО git add/commit/push. Скрипт идемпотентный.
set -euo pipefail

J=app/src/main/java/com/example/fa_ksiegowy
R=app/src/main/res
for f in "$J/AppDialog.kt" "$J/ProGate.kt" "$J/MagazinFragment.kt" \
         "$R/values/strings.xml" "$R/values-pl/strings.xml" "$R/values-ru/strings.xml" "$R/values-uk/strings.xml"; do
  [ -f "$f" ] || { echo "Запусти из корня репозитория, после Update 80 (нет $f)"; exit 1; }
done

python3 - <<'PY'
import re, os
J = "app/src/main/java/com/example/fa_ksiegowy"
R = "app/src/main/res"

def read(p): return open(p, encoding="utf-8").read()
def write(p, s):
    open(p, "w", encoding="utf-8").write(s)
    print("изменён:", p)
def rep(s, old, new, what):
    assert s.count(old) == 1, "не найден (или не уникален) фрагмент: " + what
    return s.replace(old, new)

# ------------------------------------------------------------ AppDialog: кнопки в одну строку
p = J + "/AppDialog.kt"
s = read(p)
if "Update 81" in s:
    print("AppDialog: уже применено")
else:
    fix = (
        "{i}// Update 81: длинный текст не переносится на 2 строки и не обрезается.\n"
        "{i}maxLines = 1\n"
        "{i}setPadding((8 * density).toInt(), 0, (8 * density).toInt(), 0)\n"
        "{i}androidx.core.widget.TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(\n"
        "{i}    this, 10, 14, 1, android.util.TypedValue.COMPLEX_UNIT_SP\n"
        "{i})\n"
    )
    s = rep(s,
        "                setBackgroundResource(R.drawable.btn_pill_outline)\n"
        "                setOnClickListener {\n"
        "                    onNegative?.invoke()\n",
        "                setBackgroundResource(R.drawable.btn_pill_outline)\n" + fix.format(i="                ") +
        "                setOnClickListener {\n"
        "                    onNegative?.invoke()\n",
        "AppDialog negative button")
    s = rep(s,
        "            setBackgroundResource(R.drawable.btn_pill_primary)\n"
        "            setOnClickListener {\n"
        "                onPositive()\n",
        "            setBackgroundResource(R.drawable.btn_pill_primary)\n" + fix.format(i="            ") +
        "            setOnClickListener {\n"
        "                onPositive()\n",
        "AppDialog positive button")
    write(p, s)

# ------------------------------------------------------------ ProGate: короткая подпись кнопки
p = J + "/ProGate.kt"
s = read(p)
if "pro_gate_subscribe" in s:
    print("ProGate: уже применено")
else:
    s = rep(s,
        "positiveText = context.getString(R.string.pro_unlock_button),",
        "positiveText = context.getString(R.string.pro_gate_subscribe),",
        "ProGate button text")
    write(p, s)

STR = {
 "values": "Get Pro",
 "values-pl": "Odblokuj Pro",
 "values-ru": "Оформить Pro",
 "values-uk": "Оформити Pro",
}
for folder, text in STR.items():
    p = R + "/" + folder + "/strings.xml"
    s = read(p)
    if 'name="pro_gate_subscribe"' in s:
        print(folder + "/strings.xml: уже применено")
        continue
    s = rep(s, "</resources>", '    <string name="pro_gate_subscribe">%s</string>\n</resources>' % text, folder + " </resources>")
    write(p, s)

# ------------------------------------------------------------ Magazyn: затемнение вместо отдельного экрана
p = J + "/MagazinFragment.kt"
s = read(p)
if "Update 81" in s:
    print("MagazinFragment: уже применено")
else:
    pat = r"        // Update 80: Magazyn закрыт целиком под Pro.*?        updateLockOverlay\(\)\n    \}\n"
    assert len(re.findall(pat, s, re.S)) == 1, "не найден блок оверлея в MagazinFragment"
    new = '''        // Update 81: Magazyn закрыт под Pro, но выглядит как обычный экран приложения — он слегка
        // затемнён и не реагирует на нажатия; любое касание показывает окно "Функция Pro".
        val root = view as ViewGroup
        val overlay = View(requireContext()).apply {
            setBackgroundColor(0x66000000)
            isClickable = true
            isFocusable = true
            setOnClickListener { showLockedPopup() }
        }
        root.addView(overlay, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        lockOverlay = overlay
        updateLockOverlay()
        // Окно "Функция Pro" при первом заходе на вкладку (при повторных заходах — onHiddenChanged).
        if (savedInstanceState == null && !BillingManager.isPro(requireContext())) showLockedPopup()
    }

    private fun showLockedPopup() {
        ProGate.showLockedDialog(requireContext(), R.string.magazin_locked_message)
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (!hidden) {
            updateLockOverlay()
            if (!BillingManager.isPro(requireContext())) showLockedPopup()
        }
    }
'''
    s = re.sub(pat, lambda _m: new, s, flags=re.S)
    write(p, s)

# старый отдельный экран с замком больше не нужен
lay = R + "/layout/view_magazin_locked.xml"
if os.path.exists(lay):
    os.remove(lay)
    print("удалён:", lay)

print("\nГотово. Update 81 применён.")
PY

echo "Update 81 OK. Теперь: git add -A && git commit -m 'Update 81: Pro lock UI' && git pull --rebase && git push"
