package tech.tracepay.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.net.URLEncoder
import kotlin.math.roundToInt

private val SViolet = Color(0xFF5B2EFF)
private val SInk = Color(0xFF14092E)
private val SMuted = Color(0xFF5E5480)
private val SPaper = Color(0xFFFFFFFF)
private val SIvory = Color(0xFFF3EEFF)
private val SLine = Color(0xFFDDD3FF)
private val SLime = Color(0xFFC6FF3D)

fun bandColor(band: String): Color = when (band) {
    "high_review" -> Color(0xFFB3261E); "review" -> Color(0xFFE5482F); "watch" -> Color(0xFFE3A127)
    "low" -> Color(0xFF3D9A00); else -> Color(0xFF8A82A8)
}

data class SafetyFactor(val code: String, val label: String, val family: String, val points: Int, val detail: String)
data class SafetyLookup(
    val ref: String, val displayName: String?, val score: Int?, val band: String, val title: String, val advice: String,
    val factors: List<SafetyFactor>, val counterfactuals: List<String>, val confidence: Double, val member: Boolean,
    val merchantVerified: Boolean, val merchantName: String?, val reports: Int, val records: Int,
    val qrName: String?, val qrAmount: String?, val shieldReasons: List<String>
)

private fun strings(a: JSONArray?): List<String> = a?.let { arr -> (0 until arr.length()).map { arr.optString(it) } } ?: emptyList()

suspend fun TraceApi.lookup(ref: String, amount: String = ""): SafetyLookup {
    val amt = amount.toBigDecimalOrNull()?.takeIf { it > BigDecimal.ZERO }?.let { "&amount=${it.toPlainString()}" } ?: ""
    val o = JSONObject(call("/api/v1/lookup?ref=" + URLEncoder.encode(ref, "UTF-8") + amt))
    val fa = o.getJSONArray("factors")
    val factors = (0 until fa.length()).map { i -> fa.getJSONObject(i).let {
        SafetyFactor(it.optString("code"), it.optString("label"), it.optString("family"), it.optInt("points"), it.optString("detail")) } }
    val verdict = o.getJSONObject("verdict"); val merchant = o.optJSONObject("merchant"); val qr = o.optJSONObject("qr")
    val shield = o.optJSONObject("shield")?.optJSONArray("reasons")?.let { a -> (0 until a.length()).map { a.getJSONObject(it).optString("text") } } ?: emptyList()
    return SafetyLookup(
        ref = o.getString("ref"), displayName = o.optString("display_name").takeIf { it.isNotBlank() && it != "null" },
        score = if (o.isNull("score")) null else o.getInt("score"), band = o.getString("band"),
        title = verdict.optString("title"), advice = verdict.optString("advice"), factors = factors,
        counterfactuals = strings(o.optJSONArray("counterfactuals")), confidence = o.optDouble("confidence", 0.0),
        member = o.optBoolean("member"), merchantVerified = merchant?.optBoolean("verified") == true,
        merchantName = merchant?.optString("display_name"), reports = o.getJSONObject("community").optInt("reports"),
        records = o.getJSONObject("history").optInt("records"),
        qrName = qr?.optString("name")?.takeIf { it.isNotBlank() && it != "null" },
        qrAmount = qr?.optString("amount")?.takeIf { it.isNotBlank() && it != "null" }, shieldReasons = shield)
}

suspend fun TraceApi.reportScam(ref: String, category: String, description: String, amount: String) {
    val body = JSONObject().put("target_ref", ref).put("category", category).put("description", description)
    amount.toBigDecimalOrNull()?.let { body.put("amount", it.toPlainString()) }
    call("/api/v1/community/reports", "POST", body.toString())
}

suspend fun TraceApi.recordExternalPayment(payee: String, name: String?, amount: String, app: String, status: String, source: String,
                                           txnId: String?, score: Int?, band: String?) {
    val body = JSONObject().put("payee", payee).put("amount", amount).put("app", app).put("status", status).put("source", source)
    name?.let { body.put("payee_name", it) }; txnId?.let { body.put("upi_txn_id", it) }
    score?.let { body.put("risk_score", it) }; band?.let { body.put("risk_band", it) }
    call("/api/v1/external-payments", "POST", body.toString())
}

/** Animated semicircle gauge that sweeps up to the score and counts up. */
@Composable
fun RiskGauge(score: Int?, band: String, modifier: Modifier = Modifier) {
    val sweep = remember { Animatable(0f) }
    LaunchedEffect(score) { sweep.snapTo(0f); sweep.animateTo((score ?: 0) / 100f, tween(1100, easing = FastOutSlowInEasing)) }
    val color = bandColor(band)
    Box(modifier.size(190.dp, 112.dp), contentAlignment = Alignment.BottomCenter) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 16.dp.toPx(); val d = size.width - stroke
            val topLeft = Offset(stroke / 2, stroke / 2); val arc = Size(d, d)
            drawArc(SIvory, 180f, 180f, false, topLeft, arc, style = Stroke(stroke, cap = StrokeCap.Round))
            drawArc(color, 180f, 180f * sweep.value, false, topLeft, arc, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(if (score == null) "–" else "${(sweep.value * 100).roundToInt()}", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = color)
            Text("TraceScore / 100", fontSize = 11.sp, color = SMuted)
        }
    }
}

/**
 * The pop-up shown before every payment: score, verdict, every factor with its points (animated one by one),
 * trust signals, what would change the score, and Pay / Cancel / Report.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RiskSheet(look: SafetyLookup, payLabel: String, onPay: () -> Unit, onCancel: () -> Unit, onReport: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var shown by remember { mutableIntStateOf(0) }
    LaunchedEffect(look) { shown = 0; delay(450); for (i in look.factors.indices) { delay(120); shown = i + 1 } }
    val color = bandColor(look.band)
    val max = (look.factors.maxOfOrNull { kotlin.math.abs(it.points) } ?: 1).coerceAtLeast(1)
    ModalBottomSheet(onDismissRequest = onCancel, sheetState = state, containerColor = SPaper, shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(look.displayName ?: look.ref, fontSize = 19.sp, fontWeight = FontWeight.ExtraBold, color = SInk, textAlign = TextAlign.Center)
                if (look.merchantVerified) Icon(Icons.Default.Verified, "Verified merchant", tint = Color(0xFF1D9BF0), modifier = Modifier.size(20.dp))
            }
            Text(look.ref, fontSize = 12.sp, color = SMuted)
            RiskGauge(look.score, look.band)
            Text(look.title, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = color)
            Text(look.advice, fontSize = 13.sp, color = SInk, textAlign = TextAlign.Center, lineHeight = 18.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOfNotNull(
                    if (look.member) "Trace.Pay member" else "External UPI ID",
                    if (look.merchantVerified) "Verified merchant" else null,
                    "${look.reports} report(s)", "${look.records} record(s)", "Confidence ${(look.confidence * 100).roundToInt()}%"
                ).forEach { Text(it, fontSize = 11.sp, color = SInk, modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(SIvory).padding(horizontal = 10.dp, vertical = 6.dp)) }
            }
            if (look.shieldReasons.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color(0xFFFFF4E5)).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Default.Shield, null, tint = Color(0xFF8A5A00)); Text("TraceShield", fontWeight = FontWeight.ExtraBold, color = Color(0xFF8A5A00)) }
                look.shieldReasons.forEach { Text("• $it", fontSize = 13.sp, color = SInk) }
            }
            Text("Why this score", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = SInk, modifier = Modifier.fillMaxWidth())
            if (look.factors.isEmpty()) Text("No warning or trust signals found for this account.", fontSize = 13.sp, color = SMuted, modifier = Modifier.fillMaxWidth())
            look.factors.forEachIndexed { i, f ->
                AnimatedVisibility(visible = i < shown, enter = fadeIn(tween(300)) + slideInVertically(tween(300)) { it / 2 }) {
                    FactorRow(f, max)
                }
            }
            if (look.counterfactuals.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(SIvory).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Default.Lightbulb, null, tint = SViolet, modifier = Modifier.size(18.dp)); Text("What would change it", fontWeight = FontWeight.Bold, color = SInk) }
                look.counterfactuals.forEach { Text(it, fontSize = 12.5.sp, color = SInk, lineHeight = 17.sp) }
            }
            Text(payLabel, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(if (look.band in setOf("high_review", "review")) color else SViolet)
                    .clickable { onPay() }.padding(vertical = 16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Cancel", color = SInk, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).border(1.dp, SLine, RoundedCornerShape(16.dp)).clickable { onCancel() }.padding(vertical = 14.dp))
                Row(Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(Color(0xFFFFE2DD)).clickable { onReport() }.padding(vertical = 14.dp),
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Flag, null, tint = Color(0xFFB3261E), modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                    Text("Report", color = Color(0xFFB3261E), fontWeight = FontWeight.Bold)
                }
            }
            Text("Advisory only. You decide whether to pay.", fontSize = 11.sp, color = SMuted)
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun FactorRow(f: SafetyFactor, max: Int) {
    val grow by animateFloatAsState(kotlin.math.abs(f.points).toFloat() / max, tween(700, easing = FastOutSlowInEasing), label = "bar")
    val good = f.points < 0
    val tint = if (good) Color(0xFF3D9A00) else Color(0xFFE5482F)
    val fam = when (f.family) { "core" -> "Core"; "community" -> "Community"; "trust" -> "Trust"; else -> "Behaviour" }
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color(0xFFFAF8FF)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(fam, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = SViolet,
                modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(SIvory).padding(horizontal = 6.dp, vertical = 2.dp))
            Spacer(Modifier.width(8.dp))
            Text(f.label, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold, color = SInk, modifier = Modifier.weight(1f))
            Text((if (f.points > 0) "+" else "") + f.points, fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, color = tint)
        }
        Box(Modifier.fillMaxWidth().height(7.dp).clip(RoundedCornerShape(9.dp)).background(SIvory)) {
            Box(Modifier.fillMaxWidth(grow).fillMaxHeight().clip(RoundedCornerShape(9.dp)).background(tint))
        }
        if (f.detail.isNotBlank()) Text(f.detail, fontSize = 11.5.sp, color = SMuted)
    }
}

private val CATEGORIES = listOf("scam_payment" to "Scam payment", "task_scam" to "Task scam", "investment_scam" to "Investment scam",
    "fake_merchant" to "Fake shop", "loan_app" to "Loan app", "impersonation" to "Impersonation", "lottery_prize" to "Prize scam", "other" to "Other")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportSheet(api: TraceApi, ref: String, onDone: (Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    var category by remember { mutableStateOf("scam_payment") }
    var details by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = { onDone(false) }, containerColor = SPaper) {
        Column(Modifier.fillMaxWidth().padding(20.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Report this account", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = SInk)
            Text(ref, fontSize = 12.sp, color = SMuted)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CATEGORIES.forEach { (k, l) -> val sel = category == k
                    Text(l, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = SInk, modifier = Modifier.clip(RoundedCornerShape(99.dp))
                        .background(if (sel) SLime else SIvory).clickable { category = k }.padding(horizontal = 14.dp, vertical = 9.dp)) }
            }
            OutlinedTextField(details, { details = it }, label = { Text("What happened? (optional)") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
            OutlinedTextField(amount, { amount = it }, label = { Text("Amount lost, ₹ (optional)") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
            if (error.isNotBlank()) Text(error, color = Color(0xFFB3261E), fontSize = 13.sp)
            Text(if (busy) "Sending…" else "Send report", color = Color.White, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color(0xFFB3261E)).clickable(enabled = !busy) {
                    busy = true; scope.launch { try { api.reportScam(ref, category, details, amount); onDone(true) } catch (e: Exception) { error = e.message ?: "Could not send"; busy = false } }
                }.padding(vertical = 16.dp))
            Text("Investigators review every report. Confirmed reports warn everyone who tries to pay this account.", fontSize = 11.sp, color = SMuted)
        }
    }
}

/** Parse any UPI QR (GPay, PhonePe, Paytm, BHIM, bank apps). Returns null if it has no valid UPI ID. */
fun parseUpiQr(raw: String): Map<String, String>? {
    val text = raw.trim()
    val uri = runCatching { Uri.parse(text) }.getOrNull()
    val pa = if (text.lowercase().startsWith("upi://")) uri?.getQueryParameter("pa") else text
    val vpa = pa?.trim()?.lowercase() ?: return null
    if (!Regex("^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9.]{1,40}$").matches(vpa)) return null
    return buildMap {
        put("pa", vpa)
        uri?.getQueryParameter("pn")?.let { put("pn", it) }
        uri?.getQueryParameter("am")?.let { put("am", it) }
        uri?.getQueryParameter("tn")?.let { put("tn", it) }
    }
}

private fun parseUpiResponse(resp: String?): Pair<String, String?>? {
    if (resp.isNullOrBlank()) return null
    val map = resp.split("&").mapNotNull { p -> p.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0].lowercase() to it[1] } }.toMap()
    val status = map["status"]?.uppercase() ?: return null
    val norm = when { status.startsWith("SUCCESS") -> "SUCCESS"; status.startsWith("SUBMIT") -> "SUBMITTED"; else -> "FAILURE" }
    return norm to (map["txnid"] ?: map["approvalrefno"] ?: map["txnref"])
}

/**
 * Pay any UPI QR (GPay, PhonePe, Paytm…) safely: check the account, show the risk pop-up, hand off to the
 * user's UPI app, then record the result. Banks may decline payments started from apps that are not
 * registered merchants; "Open UPI app and scan there" always works, and the user confirms afterwards.
 */
@Composable
fun ExternalPayScreen(api: TraceApi, rawQr: String, onDone: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val qr = remember(rawQr) { parseUpiQr(rawQr) }
    var amount by remember { mutableStateOf(qr?.get("am") ?: "") }
    var look by remember { mutableStateOf<SafetyLookup?>(null) }
    var sheet by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var lastApp by remember { mutableStateOf("other") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var recorded by remember { mutableStateOf<String?>(null) }
    val vpa = qr?.get("pa") ?: ""
    val upiApps = remember {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        ctx.packageManager.queryIntentActivities(probe, 0).map { it.activityInfo.packageName to it.loadLabel(ctx.packageManager).toString() }.distinctBy { it.first }
    }
    fun record(status: String, source: String, txn: String?) {
        scope.launch {
            try { api.recordExternalPayment(vpa, look?.displayName ?: qr?.get("pn"), amount, lastApp, status, source, txn, look?.score, look?.band)
                recorded = status } catch (e: Exception) { message = e.message ?: "Could not record the payment" }
        }
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
        val parsed = parseUpiResponse(res.data?.getStringExtra("response") ?: res.data?.getStringExtra("Status"))
        if (parsed != null && res.resultCode == Activity.RESULT_OK) record(parsed.first, "upi_response", parsed.second) else confirm = true
    }
    fun check() {
        if (amount.toBigDecimalOrNull()?.let { it > BigDecimal.ZERO } != true) { message = "Enter the amount first."; return }
        busy = true; message = ""
        scope.launch { try { look = api.lookup(rawQr, amount); sheet = true } catch (e: Exception) { message = e.message ?: "Could not check this account" }; busy = false }
    }
    fun payViaIntent() {
        val uri = Uri.Builder().scheme("upi").authority("pay").appendQueryParameter("pa", vpa)
            .appendQueryParameter("pn", look?.displayName ?: qr?.get("pn") ?: vpa).appendQueryParameter("am", amount.toBigDecimal().setScale(2).toPlainString())
            .appendQueryParameter("cu", "INR").appendQueryParameter("tn", qr?.get("tn") ?: "Checked with Trace.Pay").build()
        lastApp = "upi_chooser"
        launcher.launch(Intent.createChooser(Intent(Intent.ACTION_VIEW, uri), "Pay with"))
    }

    Column(Modifier.fillMaxSize().background(SIvory).statusBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(42.dp).clip(CircleShape).background(SPaper).clickable { onDone() }, contentAlignment = Alignment.Center) { Icon(Icons.Default.ArrowBack, "Back", tint = SInk) }
            Spacer(Modifier.width(12.dp)); Text("Pay any UPI QR", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = SInk)
        }
        if (qr == null) { Text("This QR has no valid UPI ID.", color = Color(0xFFB3261E)); return@Column }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(SPaper).padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("PAYING", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = SMuted)
            Text(qr["pn"] ?: vpa, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = SInk)
            Text(vpa, fontSize = 13.sp, color = SMuted)
            if (qr["tn"] != null) Text("Note: ${qr["tn"]}", fontSize = 12.sp, color = SMuted)
        }
        OutlinedTextField(amount, { amount = it.filter { c -> c.isDigit() || c == '.' } }, label = { Text("Amount (₹)") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
        if (message.isNotBlank()) Text(message, color = Color(0xFFB3261E), fontSize = 13.sp)
        if (recorded != null) Text(if (recorded == "SUCCESS") "Payment recorded. It now appears in your activity." else "Recorded as ${recorded!!.lowercase()}.",
            color = Color(0xFF3D9A00), fontWeight = FontWeight.Bold)
        Text(if (busy) "Checking account…" else "Check & pay", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(SViolet).clickable(enabled = !busy) { check() }.padding(vertical = 16.dp))
        Text("Trace.Pay checks the account first, then hands over to your UPI app. Your UPI PIN is only ever entered in your bank's app.",
            fontSize = 12.sp, color = SMuted, lineHeight = 17.sp)
        if (upiApps.isNotEmpty()) {
            Text("Or open your UPI app and scan there", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = SInk)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                upiApps.forEach { (pkg, label) ->
                    Text(label, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = SInk, modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(SPaper)
                        .border(1.dp, SLine, RoundedCornerShape(99.dp)).clickable {
                            ctx.packageManager.getLaunchIntentForPackage(pkg)?.let { lastApp = label.lowercase(); launcher.launch(it) }
                        }.padding(horizontal = 14.dp, vertical = 10.dp))
                }
            }
        }
    }
    look?.let { l ->
        if (sheet) RiskSheet(l, "Pay ₹$amount with UPI app", onPay = { sheet = false; payViaIntent() }, onCancel = { sheet = false }, onReport = { sheet = false; report = true })
    }
    if (report) ReportSheet(api, vpa) { sent -> report = false; if (sent) message = "Thanks. Your report was sent for review." }
    if (confirm) AlertDialog(onDismissRequest = { confirm = false },
        title = { Text("Did the payment go through?") },
        text = { Text("Some UPI apps don't report back. Confirm so Trace.Pay can record it.") },
        confirmButton = { TextButton({ confirm = false; record("SUCCESS", "manual", null) }) { Text("Yes, I paid") } },
        dismissButton = { TextButton({ confirm = false; record("CANCELLED", "manual", null) }) { Text("No") } })
}
