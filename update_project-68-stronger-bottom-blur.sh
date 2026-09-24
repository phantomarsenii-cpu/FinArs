#!/usr/bin/env bash
# Update 68: сильнее размытие под системными кнопками навигации.
# Раньше внизу маска была полностью непрозрачной только на самом краю экрана,
# поэтому через размытие ещё просвечивал читаемый текст. Теперь:
#  1) зона высотой (системный inset + 20dp) закрыта размытием на 100%,
#  2) радиус размытия внизу 45 (было 25),
#  3) сверху накладывается тёмный тон под цвет фона приложения.
# Запускать из КОРНЯ репозитория.
set -euo pipefail

F=app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt
[ -f "$F" ] || { echo "Запусти из корня репозитория (нет $F)"; exit 1; }

BK=".update68_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
cp "$F" "$BK/EdgeToEdge.kt"

python3 - <<'PY'
p = "app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt"
s = open(p, encoding="utf-8").read()
if "BOTTOM_BLUR_RADIUS" in s:
    print("уже применено — пропускаю"); raise SystemExit(0)

def rep(old, new):
    global s
    assert s.count(old) == 1, "не найден фрагмент: " + old[:60]
    s = s.replace(old, new)

# 1) константы
rep("    private const val BOTTOM_EXTRA_DP = 130f\n",
    "    private const val BOTTOM_EXTRA_DP = 130f\n\n"
    "    /** Update 68: dolny pasek — mocniejsze rozmycie niz gora, zeby napisy pod\n"
    "     * systemowymi przyciskami nawigacji nie mylily sie z ikonami przyciskow. */\n"
    "    private const val BOTTOM_BLUR_RADIUS = 45f\n\n"
    "    /** Strefa PELNEGO rozmycia: inset systemowy + tyle dp nad nim. */\n"
    "    private const val BOTTOM_SOLID_EXTRA_DP = 20f\n\n"
    "    /** Ciemny ton (kolor tla aplikacji, ~70%) kladziony na rozmycie u dolu. */\n"
    "    private val BOTTOM_TINT = Color.argb(0xB3, 0x08, 0x0C, 0x20)\n")

# 2) addBlurStrips
rep("        val bottomHeight = bottomInset + (BOTTOM_EXTRA_DP * density).toInt()\n",
    "        val bottomHeight = bottomInset + (BOTTOM_EXTRA_DP * density).toInt()\n"
    "        val bottomSolid = bottomInset + (BOTTOM_SOLID_EXTRA_DP * density).toInt()\n")
rep("            resizeStrip(parent, Gravity.TOP, topHeight)\n            resizeStrip(parent, Gravity.BOTTOM, bottomHeight)\n",
    "            resizeStrip(parent, Gravity.TOP, topHeight, 0)\n            resizeStrip(parent, Gravity.BOTTOM, bottomHeight, bottomSolid)\n")
rep("buildBlurStrip(target, Gravity.TOP, topHeight)", "buildBlurStrip(target, Gravity.TOP, topHeight, 0)")
rep("buildBlurStrip(target, Gravity.BOTTOM, bottomHeight)", "buildBlurStrip(target, Gravity.BOTTOM, bottomHeight, bottomSolid)")

# 3) buildBlurStrip
rep("    private fun buildBlurStrip(target: BlurTarget, gravity: Int, height: Int): FadeBlurStrip {\n"
    "        val strip = FadeBlurStrip(target.context, fadeFromEdge = gravity)\n",
    "    private fun buildBlurStrip(target: BlurTarget, gravity: Int, height: Int, solidPx: Int): FadeBlurStrip {\n"
    "        val strip = FadeBlurStrip(target.context, fadeFromEdge = gravity)\n"
    "        val isBottom = gravity == Gravity.BOTTOM\n"
    "        strip.solidPx = solidPx\n"
    "        strip.tintColor = if (isBottom) BOTTOM_TINT else Color.TRANSPARENT\n")
rep("        strip.blurView.setupWith(target).setBlurRadius(BLUR_RADIUS)\n",
    "        strip.blurView.setupWith(target)\n"
    "            .setBlurRadius(if (isBottom) BOTTOM_BLUR_RADIUS else BLUR_RADIUS)\n")

# 4) resizeStrip
rep("    private fun resizeStrip(parent: ViewGroup, gravity: Int, height: Int) {\n"
    "        val strip = parent.findViewWithTag<View>(stripTag(gravity)) ?: return\n",
    "    private fun resizeStrip(parent: ViewGroup, gravity: Int, height: Int, solidPx: Int) {\n"
    "        val strip = parent.findViewWithTag<View>(stripTag(gravity)) ?: return\n"
    "        (strip as? FadeBlurStrip)?.solidPx = solidPx\n")

# 5) FadeBlurStrip: маска с полностью непрозрачной зоной + тон
rep("        init {\n            setWillNotDraw(false)\n",
    "        /** Wysokosc (px) od krawedzi ekranu, w ktorej rozmycie jest w 100% nieprzezroczyste. */\n"
    "        var solidPx: Int = 0\n"
    "            set(value) {\n"
    "                if (field != value) { field = value; rebuildMask() }\n"
    "            }\n\n"
    "        /** Ciemny ton kladziony na rozmycie (przed maska). */\n"
    "        var tintColor: Int = Color.TRANSPARENT\n\n"
    "        init {\n            setWillNotDraw(false)\n")

a = s.index("        override fun onSizeChanged(")
b = s.index("        override fun dispatchDraw(")
s = s[:a] + (
"        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {\n"
"            super.onSizeChanged(w, h, oldw, oldh)\n"
"            rebuildMask()\n"
"        }\n\n"
"        private fun rebuildMask() {\n"
"            val h = height\n"
"            if (width <= 0 || h <= 0) return\n"
"            maskPaint.shader = if (fadeFromEdge == Gravity.TOP) {\n"
"                // gora nieprzezroczysta -> dol przezroczysty\n"
"                LinearGradient(\n"
"                    0f, 0f, 0f, h.toFloat(),\n"
"                    Color.BLACK, Color.TRANSPARENT,\n"
"                    Shader.TileMode.CLAMP\n"
"                )\n"
"            } else {\n"
"                // gora przezroczysta -> plynnie -> 100% w strefie solidPx przy dolnej krawedzi\n"
"                val solid = solidPx.coerceIn(0, h - 1)\n"
"                val frac = (h - solid).toFloat() / h\n"
"                LinearGradient(\n"
"                    0f, 0f, 0f, h.toFloat(),\n"
"                    intArrayOf(Color.TRANSPARENT, Color.BLACK, Color.BLACK),\n"
"                    floatArrayOf(0f, frac, 1f),\n"
"                    Shader.TileMode.CLAMP\n"
"                )\n"
"            }\n"
"            invalidate()\n"
"        }\n\n") + s[b:]

rep("            super.dispatchDraw(canvas)\n            canvas.drawRect(",
    "            super.dispatchDraw(canvas)\n"
    "            if (Color.alpha(tintColor) > 0) canvas.drawColor(tintColor)\n"
    "            canvas.drawRect(")

open(p, "w", encoding="utf-8").write(s)
print("изменён:", p)
PY

python3 - <<'PY'
s = open("app/src/main/java/com/example/fa_ksiegowy/EdgeToEdge.kt", encoding="utf-8").read()
code = "\n".join(l.split("//")[0] for l in s.splitlines())
ok = code.count("{") == code.count("}")
print("Kotlin скобки:", code.count("{"), code.count("}"), "OK" if ok else "ОШИБКА")
raise SystemExit(0 if ok else 1)
PY
echo "Готово. Бэкап: $BK"
