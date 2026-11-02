package tech.tracepay.android

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.coroutines.resume

private const val API = BuildConfig.TRACEPAY_API_BASE_URL

// BiometricPrompt needs a FragmentActivity (it extends ComponentActivity, so Compose works as usual).
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { TraceApp(this) }
    }
}

// Device lock: the phone's own face, fingerprint, PIN, pattern or password (nothing app-specific).
object DeviceLock {
    private const val AUTH = BIOMETRIC_STRONG or BIOMETRIC_WEAK or DEVICE_CREDENTIAL
    fun available(ctx: Context): Boolean = BiometricManager.from(ctx).canAuthenticate(AUTH) == BiometricManager.BIOMETRIC_SUCCESS
    fun hasBiometrics(ctx: Context): Boolean = BiometricManager.from(ctx).canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS
    /** True when the person authenticates, or when the phone has no lock at all (nothing to check). */
    suspend fun authenticate(activity: FragmentActivity, title: String): Boolean {
        if (!available(activity)) return true
        return suspendCancellableCoroutine { cont ->
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { if (cont.isActive) cont.resume(true) }
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { if (cont.isActive) cont.resume(false) }
            })
            prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle(title).setSubtitle("trace.pay").setAllowedAuthenticators(AUTH).build())
        }
    }
}

/** Remembers the sign-in (encrypted with an Android Keystore key). Only read after DeviceLock.authenticate succeeds. */
object Vault {
    private const val ALIAS = "tracepay_vault"
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return gen.generateKey()
    }
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("tracepay_vault", 0)
    fun has(ctx: Context) = prefs(ctx).contains("blob")
    fun who(ctx: Context): String = prefs(ctx).getString("who", "") ?: ""
    fun save(ctx: Context, identifier: String, password: String) {
        try {
            val c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE, key())
            val data = c.doFinal(JSONArray().put(identifier).put(password).toString().toByteArray())
            prefs(ctx).edit().putString("iv", Base64.encodeToString(c.iv, Base64.NO_WRAP))
                .putString("blob", Base64.encodeToString(data, Base64.NO_WRAP)).putString("who", identifier).apply()
        } catch (_: Exception) { }
    }
    fun read(ctx: Context): Pair<String, String>? = try {
        val p = prefs(ctx)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(p.getString("iv", ""), Base64.NO_WRAP)))
        val a = JSONArray(String(c.doFinal(Base64.decode(p.getString("blob", ""), Base64.NO_WRAP))))
        Pair(a.getString(0), a.getString(1))
    } catch (_: Exception) { null }
    fun clear(ctx: Context) { prefs(ctx).edit().clear().apply() }
}

data class Profile(val fullName: String, val vpa: String)
data class Transfer(val ref: String, val sender: String, val receiver: String, val amount: String, val status: String, val createdAt: String, val failure: String)
data class ExternalPayment(val id: Int, val payee: String, val payeeName: String, val amount: String, val app: String, val status: String, val band: String?, val score: Int?, val createdAt: String)
data class Factor(val code: String, val label: String, val points: Int, val detail: String)
data class RiskReport(val name: String, val ref: String, val member: Boolean, val verified: Boolean, val score: Int, val band: String, val title: String,
                      val advice: String, val factors: List<Factor>, val counterfactuals: List<String>, val reports: Int, val records: Int,
                      val confidence: Double, val shield: List<String>)

class ApiError(message: String, val code: Int) : Exception(message)

private fun JSONObject.str(k: String): String = if (isNull(k)) "" else optString(k)

class TraceApi(private val context: Context) {
    private val client = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(30, TimeUnit.SECONDS).build()
    private val prefs get() = context.getSharedPreferences("tracepay", 0)
    var token: String? = prefs.getString("token", null)
        private set
    val identifier: String get() = prefs.getString("identifier", "") ?: ""

    suspend fun call(path: String, method: String = "GET", json: String? = null): String = withContext(Dispatchers.IO) {
        val body = json?.toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url(API.trimEnd('/') + path).apply { token?.let { header("Authorization", "Bearer $it") } }.method(method, body).build()
        client.newCall(req).execute().use { r ->
            val text = r.body?.string().orEmpty()
            if (!r.isSuccessful) {
                val detail = try { JSONObject(text).opt("detail") } catch (_: Exception) { null }
                val msg = when (detail) {
                    is String -> detail
                    is JSONArray -> (0 until detail.length()).joinToString("; ") { detail.optJSONObject(it)?.optString("msg") ?: "" }
                    else -> "Something went wrong (${r.code}). Try again."
                }
                throw ApiError(msg, r.code)
            }
            text
        }
    }

    /** Email or 10-digit mobile number + password. */
    suspend fun signIn(id: String, password: String) {
        val clean = id.trim().lowercase()
        val o = JSONObject(call("/api/v1/auth/login", "POST", JSONObject().put("identifier", clean).put("email", clean).put("password", password).toString()))
        token = o.getString("access_token")
        prefs.edit().putString("token", token).putString("identifier", clean).apply()
        Vault.save(context, clean, password)
    }
    suspend fun signUp(email: String?, mobile: String?, password: String) {
        val b = JSONObject().put("password", password)
        if (!email.isNullOrBlank()) b.put("email", email.trim().lowercase())
        if (!mobile.isNullOrBlank()) b.put("mobile", mobile)
        call("/api/v1/auth/register", "POST", b.toString())
        signIn(if (!email.isNullOrBlank()) email else mobile ?: "", password)
    }
    fun signOut() { prefs.edit().clear().apply(); Vault.clear(context); token = null }

    suspend fun profile(): Profile? {
        val o = JSONObject(call("/api/v1/pilot/profile"))
        if (o.isNull("profile")) return null
        val p = o.getJSONObject("profile"); return Profile(p.str("full_name"), p.str("vpa_id"))
    }
    suspend fun createProfile(name: String, dob: String, gender: String, photo: File) = withContext(Dispatchers.IO) {
        val body = MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("full_name", name).addFormDataPart("date_of_birth", dob)
            .addFormDataPart("gender", gender).addFormDataPart("consent_profile", "true").addFormDataPart("consent_pilot_ledger", "true")
            .addFormDataPart("face_photo", photo.name, photo.asRequestBody("image/jpeg".toMediaType())).build()
        val req = Request.Builder().url(API.trimEnd('/') + "/api/v1/pilot/profile").header("Authorization", "Bearer $token").post(body).build()
        client.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw ApiError(try { JSONObject(r.body?.string().orEmpty()).optString("detail", "Couldn't save your profile") } catch (_: Exception) { "Couldn't save your profile" }, r.code)
        }
    }
    suspend fun balance(): String = JSONObject(call("/api/v1/pilot/wallet")).str("balance")
    suspend fun transfers(): List<Transfer> {
        val a = JSONArray(call("/api/v1/pilot/transfers?limit=100"))
        return (0 until a.length()).map { i -> a.getJSONObject(i).let { o -> Transfer(o.str("transfer_ref"), o.str("sender_vpa"), o.str("receiver_vpa"), o.str("amount"), o.str("status"), o.str("created_at"), o.str("failure_reason")) } }
    }
    suspend fun externalPayments(): List<ExternalPayment> {
        val a = JSONArray(call("/api/v1/external-payments"))
        return (0 until a.length()).map { i -> a.getJSONObject(i).let { o ->
            ExternalPayment(o.optInt("id"), o.str("payee_vpa"), o.str("payee_name"), o.str("amount"), o.str("app"), o.str("status"),
                o.str("risk_band").ifBlank { null }, if (o.isNull("risk_score")) null else o.optInt("risk_score"), o.str("created_at")) } }
    }
    suspend fun recipientName(vpa: String): String = JSONObject(call("/api/v1/pilot/recipients/${Uri.encode(vpa)}")).str("display_name")

    /** Full explained risk for any UPI ID or QR text. Falls back to the basic rule check so a score always shows. */
    suspend fun risk(ref: String, amount: String = "", name: String = ""): RiskReport {
        val amt = amount.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }?.let { "&amount=${it.toPlainString()}" } ?: ""
        return try {
            val o = JSONObject(call("/api/v1/lookup?ref=" + Uri.encode(ref) + amt))
            val fa = o.optJSONArray("factors") ?: JSONArray()
            val factors = (0 until fa.length()).map { i -> fa.getJSONObject(i).let { f -> Factor(f.str("code"), f.str("label"), f.optInt("points"), f.str("detail")) } }
            val v = o.optJSONObject("verdict"); val cf = o.optJSONArray("counterfactuals") ?: JSONArray()
            val sh = o.optJSONObject("shield")?.optJSONArray("reasons")
            RiskReport(
                name = o.str("display_name").ifBlank { name.ifBlank { o.str("ref") } }, ref = o.str("ref"), member = o.optBoolean("member"),
                verified = o.optJSONObject("merchant")?.optBoolean("verified") == true, score = if (o.isNull("score")) 20 else o.optInt("score", 20),
                band = o.str("band").ifBlank { "insufficient_information" }, title = v?.str("title") ?: "Not enough history",
                advice = v?.str("advice") ?: "Pay only people you know.", factors = factors, counterfactuals = (0 until cf.length()).map { cf.getString(it) },
                reports = o.optJSONObject("community")?.optInt("reports") ?: 0, records = o.optJSONObject("history")?.optInt("records") ?: 0,
                confidence = o.optDouble("confidence", 0.0), shield = sh?.let { a -> (0 until a.length()).map { a.getJSONObject(it).str("text") } } ?: emptyList())
        } catch (e: ApiError) {
            if (e.code == 401 || e.code == 400) throw e
            val req = JSONObject().put("recipient_ref", ref); amount.toBigDecimalOrNull()?.let { req.put("amount", it.toPlainString()) }
            val o = JSONObject(call("/api/v1/risk/check", "POST", req.toString()))
            val level = o.str("level"); val rs = o.optJSONArray("reasons") ?: JSONArray()
            RiskReport(name.ifBlank { ref }, ref, true, false, when (level) { "review" -> 70; "caution" -> 40; "no_known_warning" -> 8; else -> 20 },
                when (level) { "review" -> "review"; "caution" -> "watch"; "no_known_warning" -> "low"; else -> "insufficient_information" },
                when (level) { "review" -> "Risky"; "caution" -> "Be careful"; "no_known_warning" -> "No warning signs"; else -> "Not enough history" },
                o.str("disclaimer"), (0 until rs.length()).map { Factor("RULE", rs.getString(it), 0, "") }, emptyList(), 0, o.optInt("observed_transaction_count"), 0.0, emptyList())
        }
    }
    suspend fun pay(vpa: String, amount: String, key: String): Transfer {
        val o = JSONObject(call("/api/v1/pilot/transfers", "POST", JSONObject().put("receiver_vpa", vpa).put("amount", amount).put("note", "").put("idempotency_key", key).toString()))
        return Transfer(o.str("transfer_ref"), o.str("sender_vpa"), o.str("receiver_vpa"), o.str("amount"), o.str("status"), o.str("created_at"), o.str("failure_reason"))
    }
    suspend fun recordExternal(payee: String, name: String?, amount: String, app: String, status: String, source: String, txn: String?, score: Int?, band: String?) {
        val b = JSONObject().put("payee", payee).put("amount", amount).put("app", app).put("status", status).put("source", source)
        name?.let { b.put("payee_name", it) }; txn?.let { b.put("upi_txn_id", it) }; score?.let { b.put("risk_score", it) }; band?.let { b.put("risk_band", it) }
        call("/api/v1/external-payments", "POST", b.toString())
    }
    suspend fun report(ref: String, category: String, details: String, amount: String) {
        val b = JSONObject().put("target_ref", ref).put("category", category).put("description", details)
        amount.toBigDecimalOrNull()?.let { b.put("amount", it.toPlainString()) }
        call("/api/v1/community/reports", "POST", b.toString())
    }
    /** Email accounts must verify before paying (the server enforces this too). Returns (mustVerify, email). */
    suspend fun emailStatus(): Pair<Boolean, String> {
        val o = JSONObject(call("/api/v1/auth/email/status"))
        return Pair(o.optBoolean("required") && !o.optBoolean("verified"), o.str("email"))
    }
    suspend fun sendEmailCode(name: String) { call("/api/v1/auth/email/send-otp", "POST", JSONObject().put("full_name", name).toString()) }
    suspend fun verifyEmailCode(code: String) { call("/api/v1/auth/email/verify-otp", "POST", JSONObject().put("code", code).toString()) }
}

/** Trace.Pay IDs are always name@tracepay. Returns null for other UPI handles. */
fun normalizeTracePayId(input: String): String? {
    var raw = input.trim().lowercase()
    if (raw.startsWith("upi://") || raw.startsWith("tracepay://")) raw = try { Uri.parse(raw).getQueryParameter("pa")?.lowercase() ?: "" } catch (_: Exception) { "" }
    if (raw.isNotEmpty() && !raw.contains("@")) raw += "@tracepay"
    return if (Regex("^[a-z0-9][a-z0-9._-]{1,63}@tracepay$").matches(raw)) raw else null
}

/** Any UPI QR (Google Pay, PhonePe, Paytm, BHIM, bank apps) or bare UPI ID. */
fun parseUpiQr(raw: String): Map<String, String>? {
    val text = raw.trim()
    val isLink = text.lowercase().startsWith("upi://")
    val uri = runCatching { Uri.parse(text) }.getOrNull()
    val pa = if (isLink) uri?.getQueryParameter("pa") else text
    val vpa = pa?.trim()?.lowercase() ?: return null
    if (!Regex("^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}$").matches(vpa)) return null
    val out = mutableMapOf("pa" to vpa)
    if (isLink) {
        uri?.getQueryParameter("pn")?.let { out["pn"] = it }
        uri?.getQueryParameter("am")?.let { out["am"] = it }
        uri?.getQueryParameter("tn")?.let { out["tn"] = it }
    }
    return out
}
