package com.example.fa_ksiegowy

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Единый стиль всплывающих диалогов приложения — тёмная карточка (card_bg) со
 * скруглёнными углами и кнопками-пилюлями (btn_pill_primary/btn_pill_outline),
 * вместо стандартного светлого системного AlertDialog, который визуально выбивался
 * из тёмного интерфейса приложения. Используется и для простых диалогов с полем
 * ввода (см. InventoryActivity — количество при сканировании), и для компактного
 * вертикального меню выбора одного варианта (см. showOptionPicker — категория
 * ryczałtu в AddEntryActivity/AddInvoiceActivity).
 */
object AppDialog {

    /** Небольшая карточка-диалог: заголовок + необязательное сообщение + произвольный
     *  контент (например EditText или список вариантов) + одна или две кнопки-пилюли
     *  снизу. Возвращает созданный Dialog — можно дополнительно повесить
     *  setOnShowListener (например, чтобы показать клавиатуру). */
    fun show(
        context: Context,
        title: String,
        message: String? = null,
        contentView: View? = null,
        positiveText: String,
        onPositive: () -> Unit,
        negativeText: String? = null,
        onNegative: (() -> Unit)? = null,
        cancelable: Boolean = true
    ): Dialog {
        val density = context.resources.displayMetrics.density
        val pad = (20 * density).toInt()

        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundResource(R.drawable.card_bg)
            setPadding(pad, pad, pad, pad)
        }

        val tvTitle = TextView(context).apply {
            text = title
            setTextColor(context.resources.getColor(R.color.accent_cyan, context.theme))
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
        }
        root.addView(tvTitle)

        if (!message.isNullOrBlank()) {
            val tvMsg = TextView(context).apply {
                text = message
                setTextColor(context.resources.getColor(R.color.text_secondary, context.theme))
                textSize = 13f
                setPadding(0, (8 * density).toInt(), 0, 0)
            }
            root.addView(tvMsg)
        }

        contentView?.let { cv ->
            (cv.parent as? ViewGroup)?.removeView(cv)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.topMargin = (14 * density).toInt()
            root.addView(cv, lp)
        }

        val buttonsRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.topMargin = (20 * density).toInt()
            layoutParams = lp
        }

        val dialog = Dialog(context)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setCancelable(cancelable)
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))

        if (negativeText != null) {
            val btnNeg = Button(context).apply {
                text = negativeText
                isAllCaps = false
                setTextColor(context.resources.getColor(R.color.text_secondary, context.theme))
                setBackgroundResource(R.drawable.btn_pill_outline)
                setOnClickListener {
                    onNegative?.invoke()
                    dialog.dismiss()
                }
            }
            val lpNeg = LinearLayout.LayoutParams(0, (48 * density).toInt(), 1f)
            lpNeg.marginEnd = (8 * density).toInt()
            buttonsRow.addView(btnNeg, lpNeg)
        }

        val btnPos = Button(context).apply {
            text = positiveText
            isAllCaps = false
            setTextColor(context.resources.getColor(R.color.text_primary, context.theme))
            setBackgroundResource(R.drawable.btn_pill_primary)
            setOnClickListener {
                onPositive()
                dialog.dismiss()
            }
        }
        val lpPos = LinearLayout.LayoutParams(0, (48 * density).toInt(), 1f)
        if (negativeText != null) lpPos.marginStart = (8 * density).toInt()
        buttonsRow.addView(btnPos, lpPos)

        root.addView(buttonsRow)
        dialog.setContentView(root)
        dialog.window?.setLayout(
            (context.resources.displayMetrics.widthPixels * 0.86).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        dialog.window?.setGravity(Gravity.CENTER)
        dialog.show()
        return dialog
    }

    /** Компактное вертикальное меню выбора ОДНОГО варианта из списка — маленький
     *  всплывающий диалог в стиле приложения (не системное меню), каждый вариант —
     *  отдельная "таблетка". Закрывается сразу после выбора одного из вариантов. */
    fun showOptionPicker(
        context: Context,
        title: String,
        options: List<Pair<String, String>>,
        onSelected: (String) -> Unit
    ) {
        val density = context.resources.displayMetrics.density
        val container = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val dialogRef = arrayOfNulls<Dialog>(1)

        for ((index, pair) in options.withIndex()) {
            val (value, label) = pair
            val btn = Button(context).apply {
                text = label
                isAllCaps = false
                textSize = 14f
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                setPadding((18 * density).toInt(), 0, (18 * density).toInt(), 0)
                setTextColor(context.resources.getColor(R.color.text_primary, context.theme))
                setBackgroundResource(R.drawable.input_field_bg)
                setOnClickListener {
                    onSelected(value)
                    dialogRef[0]?.dismiss()
                }
            }
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (52 * density).toInt())
            if (index > 0) lp.topMargin = (10 * density).toInt()
            container.addView(btn, lp)
        }

        val dialog = show(
            context = context,
            title = title,
            contentView = container,
            positiveText = context.getString(R.string.dialog_close),
            onPositive = {},
            cancelable = true
        )
        dialogRef[0] = dialog
    }
}
