package com.example.starter

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

private object L {
    val lang: String by lazy {
        val code = Locale.getDefault().language.lowercase()
        if (listOf("tr", "en", "pt", "es").contains(code)) code else "en"
    }

    private val strings: Map<String, Map<String, String>> = mapOf(
        "ready" to mapOf(
            "tr" to "Hazır. İstersen not ekleyip kaydet.",
            "en" to "Ready. Add a note if you like, then save.",
            "pt" to "Pronto. Adicione uma nota se quiser e salve.",
            "es" to "Listo. Agrega una nota si quieres y guarda."
        ),
        "not_found" to mapOf(
            "tr" to "Paylaşılan içerikte bağlantı veya metin bulunamadı.",
            "en" to "No link or text found in the shared content.",
            "pt" to "Nenhum link ou texto encontrado no conteúdo compartilhado.",
            "es" to "No se encontró enlace ni texto en el contenido compartido."
        ),
        "note_placeholder" to mapOf("tr" to "Not (isteğe bağlı)", "en" to "Note (optional)", "pt" to "Nota (opcional)", "es" to "Nota (opcional)"),
        "save" to mapOf("tr" to "Kaydet", "en" to "Save", "pt" to "Salvar", "es" to "Guardar"),
        "cancel" to mapOf("tr" to "Vazgeç", "en" to "Cancel", "pt" to "Cancelar", "es" to "Cancelar"),
        "saved" to mapOf(
            "tr" to "Kaydedildi. Uygulamayı açınca işlenecek.",
            "en" to "Saved. It will be processed when you open the app.",
            "pt" to "Salvo. Será processado quando você abrir o app.",
            "es" to "Guardado. Se procesará al abrir la app."
        )
    )

    fun t(key: String): String = strings[key]?.get(lang) ?: strings[key]?.get("en") ?: key
}

/**
 * Genel amaçlı paylaşım ekranı: başka uygulamadan gelen bağlantıyı/metni
 * alır, isteğe bağlı not ekletir ve pending_shares.json kuyruğuna yazar.
 */
class ShareActivity : Activity() {

    companion object {
        const val QUEUE_FILE = "pending_shares.json"

        /** true: bağlantı yoksa düz metni de kabul et. */
        const val ACCEPTS_PLAIN_TEXT = true
    }

    private val isDarkMode: Boolean by lazy {
        val mode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        mode == Configuration.UI_MODE_NIGHT_YES
    }

    // Marka rengini burada değiştir.
    private val brandColor = Color.parseColor("#FF6B35")
    private val bgColor: Int by lazy { if (isDarkMode) Color.parseColor("#1C1C1E") else Color.WHITE }
    private val textColor: Int by lazy { if (isDarkMode) Color.WHITE else Color.BLACK }
    private val secondaryTextColor: Int by lazy { if (isDarkMode) Color.parseColor("#98989F") else Color.parseColor("#8E8E93") }
    private val fieldBorderColor: Int by lazy { if (isDarkMode) Color.parseColor("#38383A") else Color.parseColor("#C6C6C8") }

    private var extractedUrl: String? = null
    private var extractedText: String? = null
    private lateinit var noteInput: EditText
    private lateinit var saveButton: Button
    private lateinit var messageLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = intent?.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        extractedUrl = Regex("""https?://[^\s<>"]+""").find(shared)?.value?.trimEnd('.', ',', ')', ']', '!', '?')
        val withoutUrl = shared.replace(Regex("""https?://\S+"""), "").trim()
        extractedText = withoutUrl.ifEmpty { null }
        buildUi()
    }

    private val canSave: Boolean
        get() = extractedUrl != null || (ACCEPTS_PLAIN_TEXT && extractedText != null)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun buildUi() {
        val scrollView = ScrollView(this).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(bgColor)
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(20))
        }

        root.addView(TextView(this).apply {
            text = applicationInfo.loadLabel(packageManager)
            textSize = 24f
            typeface = Typeface.create(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            setTextColor(textColor)
        }, marginBottomParams())

        messageLabel = TextView(this).apply {
            text = if (canSave) L.t("ready") else L.t("not_found")
            textSize = 15f
            setTextColor(secondaryTextColor)
            gravity = Gravity.CENTER
        }
        root.addView(messageLabel, marginBottomParams())

        root.addView(TextView(this).apply {
            text = extractedUrl ?: extractedText ?: ""
            textSize = 13f
            maxLines = 3
            setTextColor(secondaryTextColor)
            gravity = Gravity.CENTER
        }, marginBottomParams())

        noteInput = EditText(this).apply {
            hint = L.t("note_placeholder")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            gravity = Gravity.TOP or Gravity.START
            setPadding(dp(12), dp(12), dp(12), dp(12))
            textSize = 15f
            setTextColor(textColor)
            setHintTextColor(secondaryTextColor)
            background = roundedBackground(fieldBorderColor, bgColor, 10, 1)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(90))
        }
        root.addView(noteInput, marginBottomParams())

        saveButton = Button(this).apply {
            text = L.t("save")
            textSize = 17f
            typeface = Typeface.create(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            isAllCaps = false
            background = roundedBackground(brandColor, brandColor, 12, 0)
            isEnabled = canSave
            alpha = if (canSave) 1.0f else 0.55f
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50))
            setOnClickListener { onSave() }
        }
        root.addView(saveButton, marginBottomParams())

        root.addView(Button(this).apply {
            text = L.t("cancel")
            textSize = 16f
            isAllCaps = false
            setTextColor(brandColor)
            background = null
            setOnClickListener { finish() }
        })

        scrollView.addView(root)
        setContentView(scrollView)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    }

    private fun marginBottomParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            setMargins(0, 0, 0, dp(16))
        }
    }

    private fun roundedBackground(strokeColor: Int, fillColor: Int, cornerRadiusDp: Int, strokeWidthDp: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(cornerRadiusDp).toFloat()
            setColor(fillColor)
            if (strokeWidthDp > 0) setStroke(dp(strokeWidthDp), strokeColor)
        }
    }

    private fun onSave() {
        if (!canSave) return
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val payload = JSONObject().apply {
            put("id", UUID.randomUUID().toString())
            put("url", extractedUrl ?: "")
            put("text", extractedText ?: "")
            put("note", noteInput.text.toString().trim())
            put("createdAt", isoFormat.format(Date()))
        }

        val file = File(filesDir, QUEUE_FILE)
        val existing = try {
            if (file.exists()) JSONArray(file.readText()) else JSONArray()
        } catch (e: Exception) {
            JSONArray()
        }
        existing.put(payload)
        file.writeText(existing.toString())

        messageLabel.text = L.t("saved")
        saveButton.isEnabled = false
        saveButton.alpha = 0.55f
        Handler(mainLooper).postDelayed({ finish() }, 400)
    }
}
