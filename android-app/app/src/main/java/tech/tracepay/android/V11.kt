package tech.tracepay.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.media.AudioManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

private val OvalShape = GenericShape { size, _ -> addOval(Rect(0f, 0f, size.width, size.height)) }

// ---------------------------------------------------------------------------------------------
// TraceID: 5-second video selfie with live blink detection (one person, one trace.pay ID)
// ---------------------------------------------------------------------------------------------
@Composable
fun TraceIdScreen(api: TraceApi, onDone: (File) -> Unit, onCancel: () -> Unit) {
    val ctx = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    LaunchedEffect(Unit) { if (!granted) permission.launch(Manifest.permission.CAMERA) }
    var phase by remember { mutableStateOf("align") }          // align → recording → checking → done
    var faceFound by remember { mutableStateOf(false) }
    var blinks by remember { mutableIntStateOf(0) }
    var progress by remember { mutableFloatStateOf(0f) }
    var result by remember { mutableStateOf<JSONObject?>(null) }
    var message by remember { mutableStateOf("") }
    var video by remember { mutableStateOf<File?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    val previewView = remember { PreviewView(ctx).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }
    val videoCapture = remember { VideoCapture.withOutput(Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.SD)).build()) }
    val state = remember { object { var closed = false; var faceSince = 0L; var started = false; var recording: Recording? = null } }

    fun startRecording() {
        if (state.started) return
        state.started = true
        val file = File(ctx.cacheDir, "traceid-${System.currentTimeMillis()}.mp4"); video = file
        state.recording = videoCapture.output.prepareRecording(ctx, FileOutputOptions.Builder(file).build()).start(ContextCompat.getMainExecutor(ctx)) { ev ->
            if (ev is VideoRecordEvent.Finalize) { if (ev.hasError()) message = "The recording failed. Try again." else phase = "checking" }
        }
        phase = "recording"
    }

    DisposableEffect(granted, attempt) {
        if (!granted) return@DisposableEffect onDispose { }
        val providerFuture = ProcessCameraProvider.getInstance(ctx)
        val detector = FaceDetection.getClient(FaceDetectorOptions.Builder().setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST).build())
        val exec = Executors.newSingleThreadExecutor()
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
            analysis.setAnalyzer(exec) { proxy ->
                val media = proxy.image
                if (media == null) { proxy.close(); return@setAnalyzer }
                detector.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
                    .addOnSuccessListener { faces ->
                        val f = faces.maxByOrNull { it.boundingBox.width() }
                        val now = System.currentTimeMillis()
                        if (f == null) { faceFound = false; state.faceSince = 0L; return@addOnSuccessListener }
                        faceFound = true
                        if (state.faceSince == 0L) state.faceSince = now
                        val l = f.leftEyeOpenProbability; val r = f.rightEyeOpenProbability
                        if (l != null && r != null) {
                            val p = (l + r) / 2f
                            if (p < 0.3f) state.closed = true
                            else if (p > 0.7f && state.closed) { state.closed = false; if (phase == "recording") blinks += 1 }
                        }
                        if (!state.started && now - state.faceSince > 800) startRecording()
                    }
                    .addOnCompleteListener { proxy.close() }
            }
            provider.unbindAll()
            try { provider.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis, videoCapture) }
            catch (_: Exception) {
                // Some phones can't run analysis and recording together: record anyway, the server still checks blinks.
                try { provider.bindToLifecycle(owner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, videoCapture) } catch (_: Exception) { message = "The front camera isn't available." }
            }
        }, ContextCompat.getMainExecutor(ctx))
        onDispose { state.recording?.stop(); runCatching { providerFuture.get().unbindAll() }; exec.shutdown(); detector.close() }
    }
    LaunchedEffect(phase) {
        if (phase == "recording") { for (i in 1..50) { delay(100); progress = i / 50f }; state.recording?.stop(); state.recording = null }
        if (phase == "checking") {
            val f = video
            if (f == null) { message = "The recording failed. Try again."; return@LaunchedEffect }
            try { result = api.traceIdCheck(f) } catch (e: Exception) { message = e.message ?: "Couldn't check the video" }
            phase = "done"
        }
    }
    val live = result?.optBoolean("live") == true
    val (title, sub) = when {
        result != null -> if (live) "Live person confirmed" to "Your TraceID is ready." else "Let's try again" to (result?.optString("reason") ?: "")
        message.isNotBlank() -> "Let's try again" to message
        phase == "align" -> if (faceFound) "Hold still…" to "Starting in a moment" else "Center your face" to "Fit your face inside the oval, in good light"
        phase == "recording" -> if (blinks >= 2) "Great, keep looking" to "Hold still until the ring completes" else "Blink twice slowly" to "Keep your face inside the oval"
        else -> "Checking it's really you" to "Liveness and one-person-one-ID check"
    }
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF24108A), Color(0xFF110828))))) {
        PixelField(TP.lime, Modifier.fillMaxSize())
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = .14f)).clickable { onCancel() }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Close, "Close", tint = Color.White)
                }
                Spacer(Modifier.weight(1f))
                Image(painterResource(R.drawable.tp_mark), null, Modifier.size(20.dp).clip(RoundedCornerShape(5.dp))); Spacer(Modifier.width(6.dp))
                TText("TraceID", 15.sp, FontWeight.Bold, Color.White)
                Spacer(Modifier.weight(1f)); Spacer(Modifier.width(44.dp))
            }
            TText(title, 28.sp, FontWeight.SemiBold, Color.White, Modifier.padding(top = 20.dp), TextAlign.Center)
            TText(sub, 15.sp, color = Color.White.copy(alpha = .75f), modifier = Modifier.padding(top = 6.dp, start = 10.dp, end = 10.dp), align = TextAlign.Center)
            Box(Modifier.padding(top = 22.dp).size(266.dp, 336.dp), contentAlignment = Alignment.Center) {
                if (granted) AndroidView({ previewView }, Modifier.size(250.dp, 320.dp).clip(OvalShape))
                Canvas(Modifier.fillMaxSize()) {
                    drawArc(Color.White.copy(alpha = .15f), 0f, 360f, false, style = Stroke(8.dp.toPx()))
                    drawArc(if (result != null && !live) TP.bad else TP.lime, -90f, 360f * progress, false, style = Stroke(8.dp.toPx(), cap = StrokeCap.Round))
                }
                if (phase == "checking") CircularProgressIndicator(color = Color.White)
                if (result != null) Icon(if (live) Icons.Default.Verified else Icons.Default.Warning, null, tint = if (live) TP.lime else TP.bad, modifier = Modifier.size(64.dp))
            }
            Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                repeat(2) { i ->
                    Row(Modifier.clip(CircleShape).background(Color.White.copy(alpha = .1f)).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)).background(if (i < blinks) TP.lime else Color.White.copy(alpha = .2f)))
                        Spacer(Modifier.width(6.dp)); TText("Blink ${i + 1}", 13.sp, FontWeight.Medium, Color.White.copy(alpha = if (i < blinks) 1f else .6f))
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            val v = video
            when {
                result != null && live && v != null -> NeoButton("Continue", kind = NeoKind.Lime, icon = Icons.Default.ArrowForward) { onDone(v) }
                result != null || message.isNotBlank() -> NeoButton("Record again", kind = NeoKind.Lime, icon = Icons.Default.Refresh) {
                    result = null; message = ""; video = null; blinks = 0; progress = 0f; phase = "align"; state.started = false; state.faceSince = 0L; attempt += 1
                }
                phase == "align" && !faceFound -> NeoButton("Start recording", kind = NeoKind.White, icon = Icons.Default.Videocam) { startRecording() }
            }
            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Lock, null, tint = Color.White.copy(alpha = .6f), modifier = Modifier.size(13.dp)); Spacer(Modifier.width(6.dp))
                TText("5 seconds · encrypted · used only to stop duplicate accounts", 12.sp, color = Color.White.copy(alpha = .6f))
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Check a message (SMS / WhatsApp / Telegram)
// ---------------------------------------------------------------------------------------------
@Composable
fun MessageCheck(api: TraceApi, initial: String = "") {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(initial) }
    var result by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    fun run() { busy = true; message = ""; scope.launch { try { result = api.analyzeMessage(text) } catch (e: Exception) { message = e.message ?: "Couldn't check the message" }; busy = false } }
    LaunchedEffect(initial) { if (initial.length >= 3) run() }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 140.dp).clip(RoundedCornerShape(18.dp)).background(TP.canvas).padding(16.dp)) {
            if (text.isEmpty()) TText("Paste a suspicious message, link or UPI ID…", 15.sp, color = TP.faint)
            BasicTextField(text, { text = it }, textStyle = TextStyle(fontSize = 15.sp, color = TP.ink), modifier = Modifier.fillMaxWidth())
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NeoButton("Paste", Modifier.weight(1f), NeoKind.White, Icons.Default.ContentPaste) {
                (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).primaryClip?.getItemAt(0)?.coerceToText(ctx)?.let { text = it.toString() }
            }
            NeoButton("Check", Modifier.weight(1f), icon = Icons.Default.ManageSearch, busy = busy, enabled = text.trim().length >= 3) { run() }
        }
        ErrorLine(message)
        result?.let { r ->
            val band = r.optString("overall_band"); val col = Risk.color(band)
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Risk.bg(band)).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (r.optInt("overall") >= 50) Icons.Default.GppBad else if (r.optInt("overall") >= 25) Icons.Default.Warning else Icons.Default.VerifiedUser, null, tint = col, modifier = Modifier.size(28.dp))
                Spacer(Modifier.width(12.dp)); Column { TText(r.optString("verdict"), 18.sp, FontWeight.SemiBold, col); TText("Risk ${r.optInt("overall")}%", 13.sp, color = TP.ink2) }
            }
            r.optJSONArray("signals")?.let { a -> for (i in 0 until a.length()) { val s = a.getJSONObject(i)
                val m = s.optJSONArray("matched"); val q = if (m == null) "" else (0 until m.length()).joinToString(", ") { "“${m.getString(it)}”" }
                CheckRow(Icons.Default.Sms, s.optString("label"), q, "+${s.optInt("points")}", TP.bad) } }
            r.optJSONArray("upi_checks")?.let { a -> for (i in 0 until a.length()) { val c = a.getJSONObject(i)
                CheckRow(Icons.Default.AlternateEmail, c.optString("ref") + (c.optString("name").takeIf { it.isNotBlank() && it != "null" }?.let { " · $it" } ?: ""),
                    "${c.optString("title")} · ${c.optInt("reports")} reports", "${c.optInt("score")}%", Risk.color(c.optString("band"))) } }
            r.optJSONArray("phone_checks")?.let { a -> for (i in 0 until a.length()) { val p = a.getJSONObject(i)
                CheckRow(Icons.Default.Phone, p.optString("number"), "${p.optInt("reports")} reports", "${p.optInt("score")}%", Risk.color(p.optString("band"))) } }
            r.optJSONArray("link_checks")?.let { a -> for (i in 0 until a.length()) { val l = a.getJSONObject(i); val sg = l.optJSONArray("signals")
                val why = if (sg == null || sg.length() == 0) "No warning signs" else (0 until sg.length()).joinToString(" · ") { sg.getJSONObject(it).optString("label") }
                CheckRow(Icons.Default.Link, l.optString("host"), why, "${l.optInt("score")}%", Risk.color(l.optString("band"))) } }
        }
    }
}

@Composable
private fun CheckRow(icon: ImageVector, title: String, sub: String, value: String, color: Color) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(16.dp)).padding(12.dp)) {
        Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(color), contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp)) }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) { TText(title, 14.5.sp, FontWeight.SemiBold); if (sub.isNotBlank()) TText(sub, 12.5.sp, color = TP.muted) }
        TText(value, 14.sp, FontWeight.Bold, color)
    }
}

// ---------------------------------------------------------------------------------------------
// Golden hour: recovery right after a scam
// ---------------------------------------------------------------------------------------------
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoverySheet(api: TraceApi, paymentId: Int?, transferRef: String?, onReport: (String) -> Unit, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    var pack by remember { mutableStateOf<JSONObject?>(null) }
    var message by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { try { pack = api.recoveryPack(paymentId, transferRef) } catch (e: Exception) { message = e.message ?: "Couldn't load the recovery steps" } }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(48.dp).clip(RoundedCornerShape(14.dp)).background(TP.bad), contentAlignment = Alignment.Center) { Icon(Icons.Default.Timer, null, tint = Color.White) }
                Spacer(Modifier.width(12.dp)); Column { TText("Golden hour", 13.sp, FontWeight.Bold, TP.bad); TText("Act now to get your money back", 22.sp, FontWeight.SemiBold) }
            }
            val p = pack
            if (p == null) { if (message.isNotBlank()) ErrorLine(message) else CircularProgressIndicator(color = TP.violet) }
            else {
                val steps = p.optJSONArray("steps")
                if (steps != null) for (i in 0 until steps.length()) { val st = steps.getJSONObject(i); val action = st.optString("action").takeIf { it.isNotBlank() && it != "null" }
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(18.dp))
                        .clickable(enabled = action != null) {
                            when { action == "report" -> onReport(p.optString("payee"))
                                   action?.startsWith("tel") == true -> ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse(action)))
                                   action != null -> ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(action))) }
                        }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(32.dp).clip(CircleShape).background(if (i == 0) TP.bad else TP.ink), contentAlignment = Alignment.Center) { TText("${i + 1}", 15.sp, FontWeight.Bold, Color.White) }
                        Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { TText(st.optString("title"), 15.sp, FontWeight.SemiBold); TText(st.optString("detail"), 12.5.sp, color = TP.muted, lineHeight = 17.sp) }
                        if (action != null) Icon(Icons.Default.NorthEast, null, tint = TP.violet)
                    }
                }
                listOf("Complaint (paste on cybercrime.gov.in)" to p.optString("complaint_text"), "Letter for your bank" to p.optString("bank_letter")).forEach { (t, body) ->
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Caption(t, Modifier.weight(1f))
                            TText("Copy", 13.sp, FontWeight.SemiBold, TP.violet, Modifier.clickable { copy(ctx, body); copied = t }.padding(6.dp))
                            TText("Share", 13.sp, FontWeight.SemiBold, TP.violet, Modifier.clickable { share(ctx, body) }.padding(6.dp))
                        }
                        TText(body, 13.sp, color = TP.ink2, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(TP.canvas).padding(12.dp), lineHeight = 18.sp)
                    }
                }
                val trail = p.optJSONArray("money_trail")
                if (trail != null && trail.length() > 0) {
                    Caption("Where the money went next")
                    CardBox(padding = 14.dp) {
                        for (i in 0 until trail.length()) { val h = trail.getJSONObject(i)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Box(Modifier.size(10.dp).clip(CircleShape).background(if (h.optInt("hop") == 1) TP.bad else TP.warn)); Box(Modifier.width(2.dp).height(30.dp).background(TP.hair))
                                }
                                Spacer(Modifier.width(10.dp))
                                Column { TText("${h.optString("from")} → ${h.optString("to")}", 13.5.sp, FontWeight.Medium)
                                    TText("${rupees(h.optString("amount"))} · ${parseTime(h.optString("at"))?.toLocalTime()?.withNano(0) ?: ""} · hop ${h.optInt("hop")}", 12.sp, color = TP.muted) }
                            }
                        }
                    }
                }
                if (copied.isNotBlank()) TText("Copied", 13.sp, FontWeight.Medium, TP.good)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyReportsSheet(api: TraceApi, onDismiss: () -> Unit) {
    var rows by remember { mutableStateOf<org.json.JSONArray?>(null) }
    var message by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { try { rows = api.myReports() } catch (e: Exception) { message = e.message ?: "Couldn't load your reports" } }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Caption("Community"); TText("My reports", 28.sp, FontWeight.SemiBold)
            val r = rows
            if (r == null) { if (message.isNotBlank()) ErrorLine(message) else CircularProgressIndicator(color = TP.violet) }
            else if (r.length() == 0) TText("You haven't reported any accounts yet.", 14.sp, color = TP.muted)
            else for (i in 0 until r.length()) { val x = r.getJSONObject(i); val status = x.optString("status"); val warned = x.optInt("warned")
                val (label, color) = when (status) { "verified" -> "Confirmed" to TP.good; "rejected" -> "Not confirmed" to TP.faint; else -> "Under review" to TP.warn }
                CardBox(padding = 14.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically) { TText(x.optString("target_ref"), 15.sp, FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        TText(label, 12.sp, FontWeight.SemiBold, color, Modifier.clip(CircleShape).background(color.copy(alpha = .12f)).padding(horizontal = 10.dp, vertical = 4.dp)) }
                    TText("${x.optString("category_label")} · ${parseTime(x.optString("created_at"))?.toLocalDate() ?: ""}", 12.5.sp, color = TP.muted, modifier = Modifier.padding(top = 4.dp))
                    TText(if (warned == 0) "No one has tried to pay it since" else "Warned $warned ${if (warned == 1) "person" else "people"} since you reported", 13.sp, FontWeight.Medium,
                        if (warned > 0) TP.violet else TP.muted, Modifier.padding(top = 6.dp))
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

// ---------------------------------------------------------------------------------------------
// In-the-moment protection
// ---------------------------------------------------------------------------------------------
object PaymentGuard {
    fun onCall(ctx: Context): Boolean = (ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager).mode.let { it == AudioManager.MODE_IN_CALL || it == AudioManager.MODE_IN_COMMUNICATION }
    fun screenShared(ctx: Context): Boolean = runCatching { (ctx.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).displays.size > 1 }.getOrDefault(false)
}

@Composable
fun GuardBanner() {
    val ctx = LocalContext.current
    val call = remember { PaymentGuard.onCall(ctx) }; val shared = remember { PaymentGuard.screenShared(ctx) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (call) GuardRow(Icons.Default.PhoneInTalk, "You're on a call", "Scammers often stay on the line while you pay. If someone is telling you to pay, hang up first.")
        if (shared) GuardRow(Icons.Default.ScreenShare, "Your screen is being shared or cast", "Stop screen sharing (AnyDesk, TeamViewer, casting) before paying. Never pay while someone can see your screen.")
    }
}
@Composable private fun GuardRow(icon: ImageVector, title: String, text: String) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(TP.badBg).border(1.dp, TP.bad.copy(alpha = .4f), RoundedCornerShape(18.dp)).padding(14.dp)) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(TP.bad), contentAlignment = Alignment.Center) { Icon(icon, null, tint = Color.White) }
        Spacer(Modifier.width(12.dp)); Column { TText(title, 15.sp, FontWeight.Bold, TP.bad); TText(text, 12.5.sp, color = TP.ink2, lineHeight = 17.sp) }
    }
}

@Composable
fun CoolingOffScreen(seconds: Int, reason: String, onDone: () -> Unit, onCancel: () -> Unit) {
    var remaining by remember { mutableIntStateOf(seconds) }
    LaunchedEffect(Unit) { while (remaining > 0) { delay(1000); remaining -= 1 } }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().navigationBarsPadding().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.size(240.dp), contentAlignment = Alignment.Center) {
            PixelField(TP.warn, Modifier.fillMaxSize())
            Canvas(Modifier.size(180.dp)) {
                drawArc(TP.canvas, 0f, 360f, false, style = Stroke(10.dp.toPx()))
                drawArc(TP.violet, -90f, 360f * remaining / maxOf(1, seconds), false, style = Stroke(10.dp.toPx(), cap = StrokeCap.Round))
            }
            TText(String.format(java.util.Locale.ENGLISH, "%d:%02d", remaining / 60, remaining % 60), 42.sp, FontWeight.SemiBold)
        }
        TText("Take a moment", 26.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 14.dp))
        TText(reason, 15.sp, color = TP.muted, align = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp), lineHeight = 21.sp)
        Spacer(Modifier.weight(1f))
        NeoButton(if (remaining > 0) "Wait ${remaining}s" else "Continue to pay", enabled = remaining == 0) { onDone() }
        Spacer(Modifier.height(10.dp))
        NeoButton("Cancel payment", kind = NeoKind.White) { onCancel() }
    }
}

/** Merchant badge, mule stage and name mismatch, shown under the name on a TraceScore report. */
@Composable
fun IdentityChips(r: RiskReport) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            r.badgeLabel?.takeIf { it.isNotBlank() }?.let { label ->
                val verified = r.badgeTier == "verified"
                Box(Modifier.padding(end = 2.dp, bottom = 2.dp)) {
                    Box(Modifier.matchParentSize().offset(2.dp, 2.dp).background(TP.ink))
                    Row(Modifier.background(if (verified) TP.lime else Color.White).border(2.dp, TP.ink).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Verified, null, tint = if (verified) TP.ink else TP.violet, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp))
                        TText(label, 12.sp, FontWeight.Bold, if (verified) TP.ink else TP.violet)
                    }
                }
            }
            if (r.stageLabel.isNotBlank() && r.stageCode != "established") {
                val bad = r.stageCode == "active_mule" || r.stageCode == "recruited"
                TText(r.stageLabel, 12.sp, FontWeight.SemiBold, if (bad) TP.bad else TP.ink2, Modifier.clip(CircleShape).background(if (bad) TP.badBg else TP.canvas).padding(horizontal = 10.dp, vertical = 5.dp))
            }
        }
        if (r.mismatch) TText("The name on this QR doesn't match the account", 12.5.sp, FontWeight.SemiBold, TP.bad,
            Modifier.clip(CircleShape).background(TP.badBg).padding(horizontal = 12.dp, vertical = 7.dp))
    }
}
