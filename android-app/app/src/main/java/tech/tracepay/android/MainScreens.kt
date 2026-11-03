package tech.tracepay.android

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Drawable
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.OffsetDateTime
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

enum class Tab { Home, Activity, Check, Profile }

data class ActivityItem(val id: String, val title: String, val ref: String, val via: String, val amount: String, val incoming: Boolean,
                        val status: String, val band: String?, val score: Int?, val at: OffsetDateTime?)

fun parseTime(s: String): OffsetDateTime? = try { OffsetDateTime.parse(s) } catch (_: Exception) { null }
fun relative(t: OffsetDateTime?): String {
    if (t == null) return ""
    val m = Duration.between(t, OffsetDateTime.now()).toMinutes()
    return when { m < 1 -> "just now"; m < 60 -> "${m}m ago"; m < 1440 -> "${m / 60}h ago"; m < 2880 -> "yesterday"; else -> "${m / 1440}d ago" }
}
fun copy(ctx: Context, text: String) { (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("trace.pay", text)) }
fun share(ctx: Context, text: String) { ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }, "Share")) }

object Risk {
    fun color(b: String) = when (b) { "high_review", "review" -> TP.bad; "watch" -> TP.warn; "low" -> TP.good; else -> TP.faint }
    fun bg(b: String) = when (b) { "high_review", "review" -> TP.badBg; "watch" -> TP.warnBg; "low" -> TP.goodBg; else -> TP.canvas }
    fun label(b: String) = when (b) { "high_review", "review" -> "Poor"; "watch" -> "Average"; "low" -> "Excellent"; else -> "New" }
    fun icon(code: String): ImageVector = when (code) {
        "INBOUND_BREADTH" -> Icons.Default.Groups; "OUTBOUND_BREADTH" -> Icons.Default.CallSplit; "RAPID_ONWARD", "LARGE_RELAY" -> Icons.Default.Bolt
        "PASS_THROUGH", "HIGH_FORWARDING" -> Icons.Default.SwapHoriz; "SHORT_DWELL" -> Icons.Default.Timer; "FAN_IN_OUT" -> Icons.Default.CallMerge
        "STRUCTURING" -> Icons.Default.GridView; "ROUND_TRIP" -> Icons.Default.Autorenew; "VICTIM_CONVERGENCE" -> Icons.Default.PersonSearch
        "ESCALATION" -> Icons.Default.TrendingUp; "SCAM_AMOUNTS" -> Icons.Default.CurrencyRupee; "MULE_LIFECYCLE" -> Icons.Default.History
        "COORDINATED" -> Icons.Default.Link; "DENSE_CORE", "RING" -> Icons.Default.Workspaces; "BRIDGE" -> Icons.Default.Hub; "ANOMALY" -> Icons.Default.MonitorHeart
        "VERIFIED_REPORTS", "COMMUNITY_REPORTS" -> Icons.Default.Flag; "COMPLAINTS" -> Icons.Default.Report; "INVESTIGATOR_FLAG" -> Icons.Default.GppBad
        "INVESTIGATOR_CLEARED" -> Icons.Default.GppGood; "VERIFIED_MERCHANT" -> Icons.Default.Verified; "REGULAR_CUSTOMERS" -> Icons.Default.Storefront
        "NEW_ACCOUNT" -> Icons.Default.Schedule; else -> Icons.Default.Info
    }
}

// ---------------------------------------------------------------------------------------------
// Main shell
// ---------------------------------------------------------------------------------------------
@Composable
fun MainShell(api: TraceApi, activity: MainActivity, profile: Profile, onSignOut: () -> Unit) {
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(Tab.Home) }
    var balance by remember { mutableStateOf("0") }
    var transfers by remember { mutableStateOf(listOf<Transfer>()) }
    var external by remember { mutableStateOf(listOf<ExternalPayment>()) }
    var mustVerify by remember { mutableStateOf(false) }
    var scanner by remember { mutableStateOf(false) }
    var payTo by remember { mutableStateOf<String?>(null) }
    var externalQr by remember { mutableStateOf<String?>(null) }
    var verify by remember { mutableStateOf(false) }
    var help by remember { mutableStateOf(false) }
    var myQr by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<ActivityItem?>(null) }
    var report by remember { mutableStateOf<String?>(null) }
    val ctx = LocalContext.current
    var update by remember { mutableStateOf<AppUpdate?>(null) }
    var updateProgress by remember { mutableStateOf<Float?>(null) }
    var updateMsg by remember { mutableStateOf("") }
    var updatePrompt by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { update = Updater.check(); if (update != null) updatePrompt = true }
    fun installUpdate() {
        val u = update ?: return
        if (!Updater.canInstall(ctx)) { updateMsg = "Allow \"Install unknown apps\" for trace.pay, then tap Install update again."; return }
        updateMsg = ""; updateProgress = 0f
        scope.launch {
            try { val f = Updater.download(ctx, u) { p -> updateProgress = p }; updateProgress = null; Updater.install(ctx, f) }
            catch (e: Exception) { updateProgress = null; updateMsg = e.message ?: "Update failed. Try again." }
        }
    }
    suspend fun refresh() {
        runCatching { balance = api.balance() }
        runCatching { transfers = api.transfers() }
        runCatching { external = api.externalPayments() }
        runCatching { mustVerify = api.emailStatus().first }
    }
    LaunchedEffect(Unit) { while (true) { refresh(); delay(20_000) } }
    val items = remember(transfers, external) {
        (transfers.map { t ->
            val incoming = t.receiver == profile.vpa
            ActivityItem("tp-${t.ref}", if (incoming) t.sender else t.receiver, t.ref, "trace.pay", t.amount, incoming, t.status, null, null, parseTime(t.createdAt))
        } + external.map { e -> ActivityItem("ext-${e.id}", e.payeeName.ifBlank { e.payee }, e.payee, e.app.replaceFirstChar { it.uppercase() }, e.amount, false, e.status, e.band, e.score, parseTime(e.createdAt)) })
            .sortedByDescending { it.at }
    }
    fun pay(vpa: String) { if (mustVerify) verify = true else payTo = vpa }
    fun payExternal(raw: String) { if (mustVerify) verify = true else externalQr = raw }

    when {
        scanner -> { QrCameraScreen(onCode = { raw ->
            val id = normalizeTracePayId(raw)
            when {
                id != null -> { scanner = false; pay(id); null }
                parseUpiQr(raw) != null -> { scanner = false; payExternal(raw); null }
                else -> "That QR has no UPI ID."
            }
        }, onClose = { scanner = false }, onMyQr = { scanner = false; myQr = true }); return }
        verify -> { VerifyEmailScreen(api, profile.fullName, onVerified = { mustVerify = false; verify = false }, onBack = { verify = false }); return }
        payTo != null -> { PayMemberScreen(api, activity, profile, transfers, balance, payTo ?: "", onDone = { payTo = null; scope.launch { refresh() } }); return }
        externalQr != null -> { ExternalPayScreen(api, externalQr ?: "", onDone = { externalQr = null; scope.launch { refresh() } }); return }
        help -> { HelpScreen(onBack = { help = false }, onReport = { help = false; report = it }); return }
    }
    Scaffold(containerColor = Color.White, bottomBar = {
        NavigationBar(containerColor = Color.White, tonalElevation = 0.dp) {
            val c = NavigationBarItemDefaults.colors(selectedIconColor = TP.violet, selectedTextColor = TP.ink, indicatorColor = TP.violetSoft, unselectedIconColor = TP.faint, unselectedTextColor = TP.faint)
            NavigationBarItem(tab == Tab.Home, { tab = Tab.Home }, { Icon(Icons.Default.Home, null) }, label = { Text("Home") }, colors = c)
            NavigationBarItem(tab == Tab.Activity, { tab = Tab.Activity }, { Icon(Icons.Default.ReceiptLong, null) }, label = { Text("Activity") }, colors = c)
            NavigationBarItem(false, { scanner = true }, { Box(Modifier.size(46.dp).clip(RoundedCornerShape(15.dp)).background(TP.violet), contentAlignment = Alignment.Center) { Icon(Icons.Default.QrCodeScanner, "Scan", tint = Color.White) } }, label = { Text("Scan") }, colors = c)
            NavigationBarItem(tab == Tab.Check, { tab = Tab.Check }, { Icon(Icons.Default.VerifiedUser, null) }, label = { Text("Check") }, colors = c)
            NavigationBarItem(tab == Tab.Profile, { tab = Tab.Profile }, { Icon(Icons.Default.Person, null) }, label = { Text("Profile") }, colors = c)
        }
    }) { pad ->
        Box(Modifier.padding(pad)) {
            when (tab) {
                Tab.Home -> HomeScreen(profile, balance, items, transfers, mustVerify, onVerify = { verify = true }, onPay = { pay(it) }, onScan = { scanner = true },
                    onCheck = { tab = Tab.Check }, onQr = { myQr = true }, onHistory = { tab = Tab.Activity }, onHelp = { help = true }, onItem = { detail = it },
                    update = update, updateProgress = updateProgress, updateMsg = updateMsg, onUpdate = { installUpdate() })
                Tab.Activity -> ActivityScreen(items) { detail = it }
                Tab.Check -> CheckScreen(api) { report = it }
                Tab.Profile -> ProfileScreen(activity, profile, onQr = { myQr = true }, onHelp = { help = true }, onSignOut = onSignOut)
            }
        }
    }
    if (myQr) MyQrSheet(profile) { myQr = false }
    update?.let { u -> if (updatePrompt) AlertDialog(onDismissRequest = { updatePrompt = false },
        icon = { Icon(Icons.Default.SystemUpdate, null, tint = TP.violet) },
        title = { Text("Update available") },
        text = { Text("trace.pay ${u.version} is ready. You're on ${BuildConfig.VERSION_NAME}. Install it now to get the latest fixes and features.") },
        confirmButton = { TextButton({ updatePrompt = false; installUpdate() }) { Text("Install update", fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton({ updatePrompt = false }) { Text("Later") } }) }
    detail?.let { d -> PaymentDetailSheet(d, onDismiss = { detail = null }, onReport = { detail = null; report = d.ref }) }
    report?.let { r -> ReportSheet(api, r) { report = null } }
}

// ---------------------------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------------------------
@Composable
fun HomeScreen(profile: Profile, balance: String, items: List<ActivityItem>, transfers: List<Transfer>, mustVerify: Boolean, onVerify: () -> Unit, onPay: (String) -> Unit,
               onScan: () -> Unit, onCheck: () -> Unit, onQr: () -> Unit, onHistory: () -> Unit, onHelp: () -> Unit, onItem: (ActivityItem) -> Unit,
               update: AppUpdate? = null, updateProgress: Float? = null, updateMsg: String = "", onUpdate: () -> Unit = {}) {
    val ctx = LocalContext.current
    val hour = java.time.LocalTime.now().hour
    val people = remember(transfers) { transfers.filter { it.sender == profile.vpa && it.status == "SUCCESS" }.groupingBy { it.receiver }.eachCount().entries.sortedByDescending { it.value }.take(4).map { it.key } }
    val now = OffsetDateTime.now()
    val month = items.filter { i -> i.at?.let { t -> t.month == now.month && t.year == now.year } == true }
    val checked = month.count { it.band != null }; val flagged = month.count { it.band == "review" || it.band == "high_review" }
    val spent = month.filter { !it.incoming && it.status == "SUCCESS" }.sumOf { it.amount.toBigDecimalOrNull() ?: java.math.BigDecimal.ZERO }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.tp_lockup), "trace.pay", Modifier.height(30.dp)); Spacer(Modifier.weight(1f))
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(14.dp)).clickable { onHelp() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Support, "Get help", tint = TP.bad)
            }
        }
        Column {
            TText(when { hour < 12 -> "Good morning,"; hour < 17 -> "Good afternoon,"; else -> "Good evening," }, 15.sp, color = TP.muted)
            TText(profile.fullName.split(" ").first(), 32.sp, FontWeight.SemiBold)
        }
        if (update != null) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(TP.ink).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconSquare(Icons.Default.SystemUpdate, TP.ink, TP.lime, 44.dp); Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) { TText("Update available · ${update.version}", 15.sp, FontWeight.SemiBold, Color.White); TText("Install the latest trace.pay in one tap.", 12.5.sp, color = Color.White.copy(alpha = .7f)) }
            }
            Spacer(Modifier.height(12.dp))
            if (updateProgress != null) {
                LinearProgressIndicator(progress = { updateProgress }, modifier = Modifier.fillMaxWidth().height(6.dp).clip(CircleShape), color = TP.lime, trackColor = Color.White.copy(alpha = .15f))
                TText("Downloading ${(updateProgress * 100).toInt()}%", 12.5.sp, color = Color.White.copy(alpha = .8f), modifier = Modifier.padding(top = 8.dp))
            } else {
                Row(Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(14.dp)).background(TP.lime).clickable { onUpdate() }, horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Download, null, tint = TP.ink); Spacer(Modifier.width(8.dp)); TText("Install update", 15.sp, FontWeight.SemiBold)
                }
            }
            if (updateMsg.isNotBlank()) TText(updateMsg, 12.5.sp, color = TP.lime, modifier = Modifier.padding(top = 8.dp))
        }
        if (mustVerify) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(TP.violetSoft).border(1.dp, TP.violet.copy(alpha = .35f), RoundedCornerShape(18.dp)).clickable { onVerify() }.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically) {
            IconSquare(Icons.Default.MarkEmailUnread, TP.ink, TP.lime, 44.dp); Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) { TText("Verify your email to pay", 15.sp, FontWeight.SemiBold); TText("Payments unlock after you enter the code we email you.", 12.5.sp, color = TP.muted) }
            Icon(Icons.Default.ChevronRight, null, tint = TP.violet)
        }
        // Balance card
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Brush.linearGradient(listOf(TP.violet, TP.violetDark, TP.violetDeep)))) {
            Image(painterResource(R.drawable.tp_mark), null, Modifier.size(150.dp).align(Alignment.TopEnd).offset(30.dp, (-10).dp), alpha = .1f)
            Column(Modifier.padding(22.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TText("trace.pay balance", 13.sp, color = Color.White.copy(alpha = .8f)); Spacer(Modifier.weight(1f))
                    Row(Modifier.clip(CircleShape).background(TP.lime.copy(alpha = .18f)).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.VerifiedUser, null, tint = TP.lime, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(4.dp)); TText("Protected", 12.sp, FontWeight.Medium, TP.lime)
                    }
                }
                TText(rupees(balance), 40.sp, FontWeight.SemiBold, Color.White, Modifier.padding(top = 6.dp))
                Row(Modifier.padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = .14f)).clickable { copy(ctx, profile.vpa) }.padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    TText(profile.vpa, 13.sp, color = Color.White); Spacer(Modifier.width(6.dp)); Icon(Icons.Default.ContentCopy, "Copy", tint = Color.White, modifier = Modifier.size(14.dp))
                }
                Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.weight(1f).height(50.dp).clip(RoundedCornerShape(15.dp)).background(TP.lime).clickable { onScan() }, horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.QrCodeScanner, null, tint = TP.ink, modifier = Modifier.size(19.dp)); Spacer(Modifier.width(8.dp)); TText("Scan & pay", 15.sp, FontWeight.Medium)
                    }
                    Row(Modifier.weight(1f).height(50.dp).clip(RoundedCornerShape(15.dp)).background(Color.White.copy(alpha = .14f)).border(1.dp, Color.White.copy(alpha = .2f), RoundedCornerShape(15.dp)).clickable { onPay("") },
                        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Send, null, tint = Color.White, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); TText("Pay", 15.sp, FontWeight.Medium, Color.White)
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(Triple(Icons.Default.Search, "Check ID", onCheck), Triple(Icons.Default.QrCode, "My QR", onQr), Triple(Icons.Default.History, "History", onHistory), Triple(Icons.Default.Support, "Get help", onHelp))
                .forEachIndexed { i, (ic, label, action) ->
                    Column(Modifier.weight(1f).clickable { action() }, horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.size(60.dp).clip(RoundedCornerShape(20.dp)).background(if (i == 3) TP.badBg else TP.canvas), contentAlignment = Alignment.Center) { Icon(ic, null, tint = if (i == 3) TP.bad else TP.violet) }
                        TText(label, 12.5.sp, FontWeight.Medium, TP.ink2, Modifier.padding(top = 9.dp))
                    }
                }
        }
        CardBox(padding = 18.dp) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(60.dp).clip(CircleShape).background(TP.goodBg), contentAlignment = Alignment.Center) { Icon(Icons.Default.VerifiedUser, null, tint = TP.good, modifier = Modifier.size(28.dp)) }
                Spacer(Modifier.width(14.dp))
                Column {
                    Caption(OffsetDateTime.now().month.getDisplayName(java.time.format.TextStyle.FULL, Locale.ENGLISH) + " safety")
                    TText(if (flagged == 0) "You're well protected" else "$flagged risky payment${if (flagged == 1) "" else "s"} flagged", 18.sp, FontWeight.SemiBold)
                    TText("Payments are checked before they leave", 13.sp, color = TP.muted)
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 14.dp), color = TP.hair)
            Row {
                listOf("$checked" to "Checked", "$flagged" to "Flagged", rupees(spent.toPlainString()) to "Spent").forEachIndexed { i, (v, l) ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        TText(v, 18.sp, FontWeight.SemiBold, if (i == 1 && flagged > 0) TP.bad else TP.ink, maxLinesOne()); TText(l, 12.5.sp, color = TP.muted)
                    }
                }
            }
        }
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) { TText("Recent", 20.sp, FontWeight.SemiBold); Spacer(Modifier.weight(1f)); TText("See all", 14.sp, FontWeight.Medium, TP.violet, Modifier.clickable { onHistory() }) }
            if (items.isEmpty()) TText("No payments yet. Scan any UPI QR to pay safely.", 14.sp, color = TP.muted, modifier = Modifier.padding(vertical = 12.dp))
            items.take(3).forEachIndexed { i, it -> ActivityRow(it) { onItem(it) }; if (i < minOf(2, items.size - 1)) HorizontalDivider(color = TP.hair) }
        }
        if (people.isNotEmpty()) Column {
            TText("Pay again", 20.sp, FontWeight.SemiBold, modifier = Modifier.padding(bottom = 14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                people.forEach { vpa -> Column(Modifier.clickable { onPay(vpa) }, horizontalAlignment = Alignment.CenterHorizontally) { AvatarBox(vpa, 56.dp); TText(vpa.substringBefore("@"), 12.5.sp, color = TP.ink2, modifier = Modifier.padding(top = 8.dp).width(64.dp), align = TextAlign.Center) } }
            }
        }
        Column {
            TText("Know the scams", 20.sp, FontWeight.SemiBold, modifier = Modifier.padding(bottom = 14.dp))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                listOf(Triple(Icons.Default.Work, "Task scams", "\"Like videos, earn money\", then pay to unlock earnings. Real jobs never ask you to pay."),
                    Triple(Icons.Default.Phone, "Fake KYC calls", "No bank asks for your UPI PIN or OTP on a call or link."),
                    Triple(Icons.Default.TrendingUp, "Investment groups", "Guaranteed returns on WhatsApp or Telegram are scams.")).forEachIndexed { i, (ic, t, d) ->
                    val (bg, tint) = listOf(TP.badBg to TP.bad, TP.violetSoft to TP.violet, TP.warnBg to TP.warn)[i]
                    Column(Modifier.width(240.dp).height(200.dp).clip(RoundedCornerShape(24.dp)).background(bg).padding(18.dp)) {
                        IconSquare(ic, tint, Color.White, 46.dp); Spacer(Modifier.weight(1f))
                        TText(t, 16.sp, FontWeight.Medium); TText(d, 13.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp), lineHeight = 18.sp)
                    }
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

private fun maxLinesOne(): Modifier = Modifier

@Composable
fun ActivityRow(item: ActivityItem, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        AvatarBox(item.title, 46.dp); Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(item.title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = TP.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            TText("${item.via} · ${relative(item.at)}", 12.5.sp, color = TP.muted)
        }
        Column(horizontalAlignment = Alignment.End) {
            TText("${if (item.incoming) "+" else "−"}${rupees(item.amount)}", 15.sp, FontWeight.Medium, if (item.status != "SUCCESS") TP.faint else if (item.incoming) TP.good else TP.ink)
            val band = item.band
            when {
                item.status != "SUCCESS" -> TText(item.status.lowercase().replaceFirstChar { it.uppercase() }, 12.sp, color = TP.faint)
                band != null -> TText(Risk.label(band), 12.sp, FontWeight.Medium, Risk.color(band))
                else -> TText(if (item.incoming) "Received" else "Paid", 12.sp, color = TP.muted)
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------------------------
@Composable
fun ActivityScreen(items: List<ActivityItem>, onItem: (ActivityItem) -> Unit) {
    var filter by remember { mutableIntStateOf(0) }
    val shown = when (filter) { 1 -> items.filter { it.via == "trace.pay" }; 2 -> items.filter { it.via != "trace.pay" }; 3 -> items.filter { it.incoming }; else -> items }
    val today = java.time.LocalDate.now()
    val week = (6 downTo 0).map { off ->
        val day = today.minusDays(off.toLong())
        day.dayOfWeek.getDisplayName(java.time.format.TextStyle.NARROW, Locale.ENGLISH) to items.filter { !it.incoming && it.status == "SUCCESS" && it.at?.toLocalDate() == day }.sumOf { it.amount.toDoubleOrNull() ?: 0.0 }
    }
    val maxV = maxOf(1.0, week.maxOf { it.second })
    val monthTotal = items.filter { i -> !i.incoming && i.status == "SUCCESS" && i.at?.let { t -> t.month == today.month && t.year == today.year } == true }.sumOf { it.amount.toDoubleOrNull() ?: 0.0 }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        TText("Activity", 32.sp, FontWeight.SemiBold)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(TP.canvas).padding(20.dp)) {
            Caption("Spent in " + today.month.getDisplayName(java.time.format.TextStyle.FULL, Locale.ENGLISH))
            TText(rupees(monthTotal.toString()), 32.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
            Row(Modifier.fillMaxWidth().height(136.dp).padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Bottom) {
                week.forEachIndexed { i, (d, v) ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.fillMaxWidth().height((8 + 100 * v / maxV).dp).clip(RoundedCornerShape(7.dp)).background(if (i == 6) TP.violet else TP.violetSoft))
                        TText(d, 12.sp, color = TP.muted, modifier = Modifier.padding(top = 8.dp))
                    }
                }
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("All", "trace.pay", "Other apps", "Received").forEachIndexed { i, l ->
                TText(l, 13.5.sp, FontWeight.Medium, if (filter == i) Color.White else TP.ink2,
                    Modifier.clip(RoundedCornerShape(13.dp)).background(if (filter == i) TP.ink else TP.canvas).clickable { filter = i }.padding(horizontal = 15.dp, vertical = 10.dp))
            }
        }
        Column {
            if (shown.isEmpty()) TText("Nothing here yet.", 14.sp, color = TP.muted, modifier = Modifier.padding(vertical = 20.dp))
            shown.forEachIndexed { i, it -> ActivityRow(it) { onItem(it) }; if (i < shown.size - 1) HorizontalDivider(color = TP.hair) }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentDetailSheet(item: ActivityItem, onDismiss: () -> Unit, onReport: () -> Unit) {
    val ctx = LocalContext.current
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            AvatarBox(item.title, 64.dp)
            TText("${if (item.incoming) "Received from" else "Paid to"} ${item.title}", 15.sp, color = TP.muted, align = TextAlign.Center)
            TText(rupees(item.amount), 44.sp, FontWeight.SemiBold)
            val ok = item.status == "SUCCESS"
            TText(if (ok) "Completed" else item.status.lowercase().replaceFirstChar { it.uppercase() }, 13.sp, FontWeight.Medium, if (ok) TP.good else TP.warn,
                Modifier.clip(CircleShape).background(if (ok) TP.goodBg else TP.warnBg).padding(horizontal = 12.dp, vertical = 6.dp))
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(TP.canvas).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val when_ = item.at?.format(java.time.format.DateTimeFormatter.ofPattern("d MMM, h:mm a")) ?: ""
                if (item.band != null) Step("Checked by trace.pay", "Risk ${item.score?.let { "$it%" } ?: ""} · ${Risk.label(item.band)}")
                Step("${if (item.incoming) "Received" else "Paid"} via ${item.via}", when_)
                Step("Saved to your activity", when_)
            }
            CardBox(padding = 16.dp) {
                Row { TText(if (item.incoming) "From" else "To", 14.sp, color = TP.muted); Spacer(Modifier.weight(1f)); TText(item.ref, 14.sp) }
                HorizontalDivider(Modifier.padding(vertical = 12.dp), color = TP.hair)
                Row { TText("App", 14.sp, color = TP.muted); Spacer(Modifier.weight(1f)); TText(item.via, 14.sp) }
            }
            NeoButton("Share receipt", kind = NeoKind.White, icon = Icons.Default.Share) { share(ctx, "trace.pay receipt: ${rupees(item.amount)} ${if (item.incoming) "from" else "to"} ${item.title} (${item.ref})") }
            if (!item.incoming) NeoButton("Report a problem", kind = NeoKind.White, icon = Icons.Default.Flag) { onReport() }
            Spacer(Modifier.height(16.dp))
        }
    }
}
@Composable private fun Step(title: String, sub: String) {
    Row { Box(Modifier.padding(top = 4.dp).size(12.dp).clip(RoundedCornerShape(3.dp)).background(TP.good)); Spacer(Modifier.width(12.dp)); Column { TText(title, 14.5.sp, FontWeight.Medium); TText(sub, 12.5.sp, color = TP.muted) } }
}

// ---------------------------------------------------------------------------------------------
// Risk report (ScoreMeter)
// ---------------------------------------------------------------------------------------------
@Composable
fun ScoreMeter(score: Int, band: String) {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(score) { progress.snapTo(0f); progress.animateTo(score / 100f, tween(1300, easing = FastOutSlowInEasing)) }
    val color = Risk.color(band)
    Box(Modifier.size(250.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val r = 96.dp.toPx(); val c = Offset(size.width / 2, size.height / 2); val sw = 16.dp.toPx()
            for (i in 0..30) {
                val ang = Math.toRadians(135.0 + i * 9)
                val r1 = r + 22.dp.toPx(); val r2 = r1 - (if (i % 5 == 0) 8.dp.toPx() else 4.dp.toPx())
                drawLine(TP.faint.copy(alpha = if (i % 5 == 0) .9f else .45f), Offset(c.x + r1 * cos(ang).toFloat(), c.y + r1 * sin(ang).toFloat()),
                    Offset(c.x + r2 * cos(ang).toFloat(), c.y + r2 * sin(ang).toFloat()), if (i % 5 == 0) 1.6.dp.toPx() else 1.dp.toPx(), StrokeCap.Round)
            }
            val tl = Offset(c.x - r, c.y - r); val sz = Size(r * 2, r * 2)
            drawArc(TP.canvas, 135f, 270f, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            drawArc(color, 135f, 270f * progress.value, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            val ang = Math.toRadians(135.0 + 270 * progress.value)
            val dot = Offset(c.x + r * cos(ang).toFloat(), c.y + r * sin(ang).toFloat())
            drawRoundRect(Color.White, Offset(dot.x - 11.dp.toPx(), dot.y - 11.dp.toPx()), Size(22.dp.toPx(), 22.dp.toPx()), androidx.compose.ui.geometry.CornerRadius(6.dp.toPx()))
            drawRoundRect(color, Offset(dot.x - 5.dp.toPx(), dot.y - 5.dp.toPx()), Size(10.dp.toPx(), 10.dp.toPx()), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
        }
        Column(Modifier.size(148.dp).clip(CircleShape).background(Color.White).border(8.dp, TP.canvas, CircleShape), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Caption("Risk score")
            Row(verticalAlignment = Alignment.Bottom) { TText("${(progress.value * 100).toInt()}", 52.sp, FontWeight.SemiBold); TText("%", 20.sp, FontWeight.Medium, modifier = Modifier.padding(bottom = 10.dp)) }
            TText(Risk.label(band), 12.sp, FontWeight.Medium, color, Modifier.clip(CircleShape).background(Risk.bg(band)).padding(horizontal = 11.dp, vertical = 4.dp))
        }
    }
}

@Composable
fun RiskReportView(r: RiskReport) {
    var shown by remember(r) { mutableIntStateOf(0) }
    var rules by remember { mutableStateOf(false) }
    LaunchedEffect(r) { delay(600); for (i in r.factors.indices) { delay(100); shown = i + 1 } }
    val raises = r.factors.filter { it.points >= 0 }; val lowers = r.factors.filter { it.points < 0 }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            AvatarBox(r.name, 54.dp)
            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                TText(r.name, 20.sp, FontWeight.SemiBold); if (r.verified) { Spacer(Modifier.width(6.dp)); Icon(Icons.Default.Verified, "Verified merchant", tint = Color(0xFF1D9BF0)) }
            }
            TText(r.ref, 13.sp, color = TP.muted)
        }
        TraceScoreBadge()
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            PixelField(Risk.color(r.band), Modifier.fillMaxWidth().height(290.dp))
            ScoreMeter(r.score, r.band)
            Box(Modifier.align(Alignment.TopEnd).size(44.dp).clip(CircleShape).background(Color.White).border(1.dp, TP.hair, CircleShape).clickable { rules = true }, contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Info, "How the score works", tint = TP.violet)
            }
        }
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Risk.bg(r.band)).padding(16.dp)) {
            Icon(if (r.band == "low") Icons.Default.VerifiedUser else Icons.Default.Warning, null, tint = Risk.color(r.band)); Spacer(Modifier.width(12.dp))
            Column { TText(r.title, 16.sp, FontWeight.SemiBold, Risk.color(r.band)); TText(r.advice, 14.sp, color = TP.ink2, lineHeight = 19.sp) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Fact(Icons.Default.Flag, "${r.reports}", "Reports", Modifier.weight(1f)); Fact(Icons.Default.Description, "${r.records}", "Payments seen", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Fact(if (r.member) Icons.Default.Person else Icons.Default.Public, if (r.member) "Member" else "External", "Account", Modifier.weight(1f))
            Fact(Icons.Default.Speed, "${(r.confidence * 100).toInt()}%", "Confidence", Modifier.weight(1f))
        }
        if (r.shield.isNotEmpty()) Section("For this payment") { r.shield.forEach { Row(Modifier.padding(vertical = 10.dp)) { Icon(Icons.Default.Warning, null, tint = TP.warn); Spacer(Modifier.width(10.dp)); TText(it, 14.sp, color = TP.ink2) } } }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TText("Why this score", 18.sp, FontWeight.SemiBold, modifier = Modifier.weight(1f))
            TText("How it's scored", 13.sp, FontWeight.Medium, TP.violet, Modifier.clickable { rules = true }.padding(6.dp))
        }
        if (raises.isNotEmpty()) Section("What raises the risk") { raises.forEachIndexed { i, f -> if (i < shown) FactorRow(f) } }
        if (lowers.isNotEmpty()) Section("What lowers the risk") { lowers.forEachIndexed { i, f -> if (raises.size + i < shown) FactorRow(f) } }
        if (r.counterfactuals.isNotEmpty()) Section("How the score changes") { r.counterfactuals.forEach { Row(Modifier.padding(vertical = 10.dp)) { Icon(Icons.Default.Lightbulb, null, tint = TP.violet); Spacer(Modifier.width(10.dp)); TText(it, 14.sp, color = TP.ink2) } } }
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Lock, null, tint = TP.muted, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(6.dp)); TText("Advisory only. You decide whether to pay.", 12.5.sp, color = TP.muted) }
    }
    if (rules) CurrentApi.api?.let { ScoringInfoSheet(it) { rules = false } }
}
@Composable private fun Fact(icon: ImageVector, value: String, label: String, modifier: Modifier) {
    Row(modifier.clip(RoundedCornerShape(16.dp)).background(TP.canvas).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
        IconSquare(icon, TP.violet, Color.White, 34.dp); Spacer(Modifier.width(10.dp)); Column { TText(value, 16.sp, FontWeight.SemiBold); TText(label, 12.sp, color = TP.muted) }
    }
}
@Composable private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) { Caption(title, Modifier.padding(bottom = 8.dp)); CardBox(padding = 16.dp, content = content) }
}
@Composable fun FactorRow(f: Factor) {
    val lowers = f.points < 0; val tint = if (lowers) TP.good else TP.bad
    val level = if (abs(f.points) >= 15) 3 else if (abs(f.points) >= 8) 2 else 1
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(tint), contentAlignment = Alignment.Center) { Icon(Risk.icon(f.code), null, tint = Color.White, modifier = Modifier.size(20.dp)) }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                TText(f.label, 15.sp, FontWeight.SemiBold)
                if (f.points != 0) TText("${listOf("Low", "Medium", "High")[level - 1]} impact · ${if (lowers) "lowers" else "raises"} risk", 12.sp, color = tint)
            }
            if (f.points != 0) TText("${if (f.points > 0) "+" else "−"}${abs(f.points)}", 16.sp, FontWeight.Bold, tint, Modifier.clip(CircleShape).background(tint.copy(alpha = .1f)).padding(horizontal = 10.dp, vertical = 5.dp))
        }
        if (f.detail.isNotBlank()) TText(f.detail, 13.sp, color = TP.ink2, modifier = Modifier.padding(top = 10.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(TP.canvas).padding(10.dp), lineHeight = 18.sp)
        if (f.points != 0) Box(Modifier.padding(top = 10.dp).fillMaxWidth().height(5.dp).clip(CircleShape).background(TP.hair)) {
            Box(Modifier.fillMaxWidth(minOf(1f, abs(f.points) / 25f)).fillMaxHeight().clip(CircleShape).background(tint))
        }
    }
}

/** "How the score works": the real rules, points and bands from the server. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScoringInfoSheet(api: TraceApi, onDismiss: () -> Unit) {
    var model by remember { mutableStateOf<org.json.JSONObject?>(null) }
    var message by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { try { model = api.scoringModel() } catch (e: Exception) { message = e.message ?: "Couldn't load the scoring rules" } }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            TraceScoreBadge(); TText("How TraceScore works", 28.sp, FontWeight.SemiBold)
            val m = model
            if (m == null) { if (message.isNotBlank()) ErrorLine(message) else CircularProgressIndicator(color = TP.violet) }
            else {
                TText(m.optString("summary"), 15.sp, color = TP.ink2, lineHeight = 21.sp)
                CardBox(padding = 14.dp) {
                    val bands = m.optJSONArray("bands") ?: org.json.JSONArray()
                    for (i in 0 until bands.length()) { val b = bands.getJSONObject(i)
                        Row(Modifier.padding(vertical = 8.dp)) {
                            TText(b.optString("range"), 14.sp, FontWeight.Bold, Risk.color(b.optString("band")), Modifier.width(64.dp))
                            Column { TText(b.optString("label"), 14.5.sp, FontWeight.SemiBold); TText(b.optString("meaning"), 12.5.sp, color = TP.muted) }
                        }
                        if (i < bands.length() - 1) HorizontalDivider(color = TP.hair)
                    }
                }
                listOf("Payment behaviour" to "signals", "Reports and trust" to "community").forEach { (title, key) ->
                    Caption(title)
                    CardBox(padding = 14.dp) {
                        val arr = m.optJSONArray(key) ?: org.json.JSONArray()
                        for (i in 0 until arr.length()) { val r = arr.getJSONObject(i)
                            val pts = r.opt("points"); val text = if (pts is Int) (if (pts > 0) "+$pts" else "$pts") else pts.toString()
                            val lowers = text.startsWith("-")
                            Row(Modifier.padding(vertical = 8.dp)) {
                                IconSquare(Risk.icon(r.optString("code")), if (lowers) TP.good else TP.violet, if (lowers) TP.goodBg else TP.violetSoft, 34.dp); Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) { TText(r.optString("label"), 14.5.sp, FontWeight.SemiBold); TText(r.optString("rule"), 12.5.sp, color = TP.muted, lineHeight = 17.sp) }
                                TText(text, 13.sp, FontWeight.Bold, if (lowers) TP.good else TP.bad, Modifier.padding(start = 8.dp))
                            }
                            if (i < arr.length() - 1) HorizontalDivider(color = TP.hair)
                        }
                    }
                }
                TText(m.optString("window"), 12.5.sp, color = TP.muted)
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

/** The report in a sheet with Pay / Cancel / Report. The chosen action runs after the sheet closes. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RiskSheet(r: RiskReport, payLabel: String, onPay: () -> Unit, onCancel: () -> Unit, onReport: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    fun close(then: () -> Unit) { scope.launch { state.hide() }.invokeOnCompletion { then() } }
    ModalBottomSheet(onDismissRequest = onCancel, sheetState = state, containerColor = Color.White) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 8.dp)) { RiskReportView(r) }
            Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NeoButton(payLabel, kind = if (r.band == "review" || r.band == "high_review") NeoKind.Danger else NeoKind.Ink, icon = Icons.Default.ArrowForward) { close(onPay) }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NeoButton("Cancel", Modifier.weight(1f), NeoKind.White) { close(onCancel) }
                    NeoButton("Report", Modifier.weight(1f), NeoKind.White, Icons.Default.Flag) { close(onReport) }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Check
// ---------------------------------------------------------------------------------------------
@Composable
fun CheckScreen(api: TraceApi, onReport: (String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { ctx.getSharedPreferences("tracepay_settings", 0) }
    var recent by remember { mutableStateOf(prefs.getString("recent", "")!!.split("\n").filter { it.isNotBlank() }) }
    var query by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<RiskReport?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    fun check(q: String) {
        val v = q.trim(); if (v.isBlank()) return
        busy = true; message = ""; result = null
        scope.launch {
            try { val r = api.risk(v); result = r; recent = (listOf(r.ref) + recent.filter { it != r.ref }).take(6); prefs.edit().putString("recent", recent.joinToString("\n")).apply() }
            catch (e: Exception) { message = e.message ?: "Couldn't check this UPI ID" }
            busy = false
        }
    }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TText("Check any UPI ID", 32.sp, FontWeight.SemiBold)
        TText("trace.pay, Google Pay, PhonePe, Paytm or a bank.", 15.sp, color = TP.muted)
        TField(query, { query = it.trim() }, "name@okaxis", Icons.Default.Search, keyboard = KeyboardType.Email)
        NeoButton("Check UPI ID", icon = Icons.Default.VerifiedUser, busy = busy, enabled = query.isNotBlank()) { check(query) }
        ErrorLine(message)
        val r = result
        if (r != null) {
            RiskReportView(r)
            NeoButton("Report this account", kind = NeoKind.White, icon = Icons.Default.Flag) { onReport(r.ref) }
        } else if (recent.isNotEmpty()) {
            Caption("Recent checks", Modifier.padding(top = 10.dp))
            recent.forEach { item ->
                Row(Modifier.fillMaxWidth().clickable { query = item; check(item) }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Schedule, null, tint = TP.faint); Spacer(Modifier.width(12.dp)); TText(item, 15.sp, modifier = Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null, tint = TP.faint)
                }
                HorizontalDivider(color = TP.hair)
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

// ---------------------------------------------------------------------------------------------
// Profile + My QR
// ---------------------------------------------------------------------------------------------
@Composable
fun ProfileScreen(activity: MainActivity, profile: Profile, onQr: () -> Unit, onHelp: () -> Unit, onSignOut: () -> Unit) {
    val scope = rememberCoroutineScope()
    val prefs = remember { activity.getSharedPreferences("tracepay_settings", 0) }
    var lockOn by remember { mutableStateOf(prefs.getBoolean("lock", true)) }
    var cooling by remember { mutableStateOf(prefs.getBoolean("cooling", true)) }
    var limit by remember { mutableIntStateOf(prefs.getInt("limit", 50000)) }
    var confirmOut by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        TText("Profile", 32.sp, FontWeight.SemiBold)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(Brush.linearGradient(listOf(TP.violet, TP.violetDeep))).padding(20.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(58.dp).clip(RoundedCornerShape(18.dp)).background(Color.White.copy(alpha = .16f)), contentAlignment = Alignment.Center) { TText(initialsOf(profile.fullName), 20.sp, FontWeight.SemiBold, Color.White) }
                Spacer(Modifier.width(14.dp)); Column { TText(profile.fullName, 17.sp, FontWeight.SemiBold, Color.White); TText(profile.vpa, 13.sp, color = Color.White.copy(alpha = .8f)) }
            }
            Row(Modifier.padding(top = 16.dp).fillMaxWidth().height(48.dp).clip(RoundedCornerShape(14.dp)).background(TP.lime).clickable { onQr() }, horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.QrCode, null, tint = TP.ink); Spacer(Modifier.width(8.dp)); TText("My QR", 15.sp, FontWeight.Medium)
            }
        }
        SettingGroup("Security") {
            SettingRow(Icons.Default.Fingerprint, "Device lock", "Fingerprint, face, PIN or pattern, as set on your phone") {
                Switch(lockOn, { v -> scope.launch { if (DeviceLock.authenticate(activity, if (v) "Turn on device lock" else "Turn off device lock")) { lockOn = v; prefs.edit().putBoolean("lock", v).apply() } } },
                    colors = SwitchDefaults.colors(checkedTrackColor = TP.violet))
            }
        }
        SettingGroup("Payment safety") {
            SettingRow(Icons.Default.HourglassTop, "Cooling-off for new payees", "Pause before a first payment of ₹5,000+") {
                Switch(cooling, { cooling = it; prefs.edit().putBoolean("cooling", it).apply() }, colors = SwitchDefaults.colors(checkedTrackColor = TP.violet))
            }
            HorizontalDivider(color = TP.hair)
            SettingRow(Icons.Default.Speed, "Daily limit", rupees(limit.toString())) {
                Row {
                    TText("−", 22.sp, FontWeight.Medium, TP.violet, Modifier.clickable { limit = maxOf(1000, limit - 5000); prefs.edit().putInt("limit", limit).apply() }.padding(horizontal = 12.dp))
                    TText("+", 22.sp, FontWeight.Medium, TP.violet, Modifier.clickable { limit = minOf(100000, limit + 5000); prefs.edit().putInt("limit", limit).apply() }.padding(horizontal = 12.dp))
                }
            }
        }
        SettingGroup("App") { SettingRow(Icons.Default.Support, "Help & emergency", "If you've been scammed", onClick = onHelp) { Icon(Icons.Default.ChevronRight, null, tint = TP.faint) } }
        NeoButton("Sign out", kind = NeoKind.White, icon = Icons.Default.Logout) { confirmOut = true }
        TText("trace.pay · version ${BuildConfig.VERSION_NAME}", 12.5.sp, color = TP.muted, modifier = Modifier.fillMaxWidth(), align = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
    }
    if (confirmOut) AlertDialog(onDismissRequest = { confirmOut = false }, title = { Text("Sign out of trace.pay?") },
        confirmButton = { TextButton({ confirmOut = false; onSignOut() }) { Text("Sign out", color = TP.bad) } }, dismissButton = { TextButton({ confirmOut = false }) { Text("Cancel") } })
}
@Composable private fun SettingGroup(title: String, content: @Composable ColumnScope.() -> Unit) { Column { Caption(title, Modifier.padding(bottom = 10.dp)); CardBox(padding = 16.dp, content = content) } }
@Composable private fun SettingRow(icon: ImageVector, title: String, sub: String, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable { onClick() } else Modifier).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconSquare(icon, size = 38.dp); Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) { TText(title, 15.sp, FontWeight.Medium); TText(sub, 12.5.sp, color = TP.muted) }
        trailing()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyQrSheet(profile: Profile, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val payload = "upi://pay?pa=${profile.vpa}&pn=${Uri.encode(profile.fullName)}&cu=INR"
    val bmp = remember(payload) { qrImage(payload) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White) {
        Column(Modifier.fillMaxWidth().padding(22.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Caption("My QR"); TText("Scan to pay me", 24.sp, FontWeight.SemiBold)
            Box(Modifier.padding(vertical = 8.dp).size(256.dp).clip(RoundedCornerShape(26.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(26.dp)).padding(18.dp), contentAlignment = Alignment.Center) {
                Image(bmp.asImageBitmap(), "My UPI QR", Modifier.fillMaxSize())
                Image(painterResource(R.drawable.tp_mark), null, Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(Color.White).padding(3.dp))
            }
            TText(profile.fullName, 17.sp, FontWeight.SemiBold); TText(profile.vpa, 14.sp, color = TP.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                NeoButton("Copy ID", Modifier.weight(1f), NeoKind.White, Icons.Default.ContentCopy) { copy(ctx, profile.vpa) }
                NeoButton("Share", Modifier.weight(1f), icon = Icons.Default.Share) { share(ctx, "Pay me on any UPI app: ${profile.vpa}") }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Verify email (accounts that haven't yet) · payments stay blocked until verified
// ---------------------------------------------------------------------------------------------
@Composable
fun VerifyEmailScreen(api: TraceApi, name: String, onVerified: () -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var resendIn by remember { mutableIntStateOf(0) }
    fun send() { scope.launch { message = ""; try { api.sendEmailCode(name); resendIn = 30 } catch (e: Exception) { message = e.message ?: "Couldn't send the code" } } }
    LaunchedEffect(Unit) { send() }
    LaunchedEffect(resendIn) { if (resendIn > 0) { delay(1000); resendIn -= 1 } }
    ScreenColumn(bottom = {
        if (done) NeoButton("Continue") { onVerified() }
        else NeoButton("Verify email", busy = busy, enabled = code.length == 6) {
            busy = true; message = ""
            scope.launch { try { api.verifyEmailCode(code); done = true } catch (e: Exception) { message = e.message ?: "That code is wrong or has expired" }; busy = false }
        }
    }) {
        TopBack(onBack)
        Box(Modifier.padding(top = 24.dp).size(60.dp).clip(RoundedCornerShape(18.dp)).background(if (done) TP.goodBg else TP.lime), contentAlignment = Alignment.Center) {
            Icon(if (done) Icons.Default.Verified else Icons.Default.MarkEmailUnread, null, tint = if (done) TP.good else TP.ink, modifier = Modifier.size(28.dp))
        }
        TText(if (done) "Email verified" else "Verify your email to pay", 28.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 16.dp))
        TText(if (done) "Payments are unlocked. You're all set." else "We sent a 6-digit code to ${api.identifier}. Enter it to unlock payments.", 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 22.dp))
        if (!done) {
            CodeBoxes(code) { code = it }
            Spacer(Modifier.height(14.dp)); ErrorLine(message)
            TText(if (resendIn > 0) "Resend code in ${resendIn}s" else "Resend code", 14.5.sp, FontWeight.Medium, if (resendIn > 0) TP.faint else TP.violet,
                Modifier.fillMaxWidth().clickable(enabled = resendIn == 0) { send() }.padding(10.dp), TextAlign.Center)
            TText("Didn't get it? Check spam, or wait a minute and resend.", 13.sp, color = TP.muted)
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Pay a trace.pay member: amount → risk report → cooling-off → device lock → result
// ---------------------------------------------------------------------------------------------
@Composable
fun PayMemberScreen(api: TraceApi, activity: MainActivity, profile: Profile, transfers: List<Transfer>, balance: String, prefill: String, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val prefs = remember { activity.getSharedPreferences("tracepay_settings", 0) }
    var step by remember { mutableStateOf(if (prefill.isBlank()) "recipient" else "loading") }
    var input by remember { mutableStateOf(prefill) }
    var vpa by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var risk by remember { mutableStateOf<RiskReport?>(null) }
    var report by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<Transfer?>(null) }
    var remaining by remember { mutableIntStateOf(0) }
    val key = remember { UUID.randomUUID().toString() }
    val isNew = transfers.none { it.receiver == vpa && it.status == "SUCCESS" }
    val today = java.time.LocalDate.now()
    val spentToday = transfers.filter { it.sender == profile.vpa && it.status == "SUCCESS" && parseTime(it.createdAt)?.toLocalDate() == today }.sumOf { it.amount.toDoubleOrNull() ?: 0.0 }
    fun find() {
        val id = normalizeTracePayId(input) ?: run { message = "trace.pay IDs look like name@tracepay."; step = "recipient"; return }
        busy = true; message = ""
        scope.launch { try { name = api.recipientName(id); vpa = id; step = "amount" } catch (e: Exception) { message = e.message ?: "Couldn't find that person"; step = "recipient" }; busy = false }
    }
    fun send() {
        scope.launch {
            if (!DeviceLock.authenticate(activity, "Pay ${rupees(amount)} to $name")) { message = "Payment not confirmed."; step = "amount"; return@launch }
            busy = true
            try { result = api.pay(vpa, amount, key); step = "done" } catch (e: Exception) { message = "${e.message ?: "Payment failed"} Trying again is safe."; step = "amount" }
            busy = false
        }
    }
    LaunchedEffect(Unit) { if (prefill.isNotBlank()) find() }
    LaunchedEffect(remaining, step) { if (step == "cooling" && remaining > 0) { delay(1000); remaining -= 1; if (remaining == 0) send() } }
    when (step) {
        "loading" -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = TP.violet) }
        "recipient" -> ScreenColumn(bottom = { NeoButton("Continue", busy = busy, enabled = input.isNotBlank()) { find() } }) {
            TopBack(onDone, close = true)
            TText("Who are you paying?", 30.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 24.dp, bottom = 18.dp))
            TField(input, { input = it.trim() }, "name@tracepay", Icons.Default.AlternateEmail, keyboard = KeyboardType.Email)
            Spacer(Modifier.height(12.dp)); ErrorLine(message)
            TText("Paying a Google Pay, PhonePe or Paytm QR? Use Scan.", 13.sp, color = TP.muted, modifier = Modifier.padding(top = 8.dp))
        }
        "amount" -> Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().navigationBarsPadding().padding(horizontal = 22.dp, vertical = 10.dp)) {
            TopBack(onDone, close = true)
            Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                AvatarBox(name, 58.dp); TText(name, 17.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp)); TText(vpa, 13.sp, color = TP.muted)
                if (isNew) TText("First payment to this person", 12.sp, FontWeight.Medium, Color(0xFF9A6200), Modifier.padding(top = 6.dp).clip(CircleShape).background(TP.warnBg).padding(horizontal = 10.dp, vertical = 5.dp))
                TText(if (amount.isEmpty()) "₹0" else "₹$amount", 56.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 16.dp))
                TText("Balance ${rupees(balance)}", 13.sp, color = TP.muted)
                if (message.isNotBlank()) TText(message, 13.5.sp, color = TP.bad, modifier = Modifier.padding(top = 8.dp), align = TextAlign.Center)
            }
            Spacer(Modifier.weight(1f))
            listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(".", "0", "⌫")).forEach { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { k ->
                        Box(Modifier.weight(1f).height(58.dp).clip(RoundedCornerShape(18.dp)).clickable {
                            message = ""
                            amount = when {
                                k == "⌫" -> amount.dropLast(1)
                                k == "." && amount.contains(".") -> amount
                                amount.contains(".") && amount.substringAfter(".").length >= 2 -> amount
                                amount.length >= 8 -> amount
                                else -> amount + k
                            }
                        }, contentAlignment = Alignment.Center) { if (k == "⌫") Icon(Icons.Default.Backspace, "Delete", tint = TP.ink) else TText(k, 26.sp) }
                    }
                }
            }
            Spacer(Modifier.height(10.dp))
            NeoButton("Check & continue", icon = Icons.Default.VerifiedUser, busy = busy, enabled = (amount.toDoubleOrNull() ?: 0.0) > 0) {
                val v = amount.toDoubleOrNull() ?: 0.0; val bal = balance.toDoubleOrNull() ?: 0.0; val limit = prefs.getInt("limit", 50000)
                when {
                    v > 100000 -> message = "Each payment is limited to ₹1,00,000."
                    v > bal -> message = "That's more than your balance."
                    spentToday + v > limit -> message = "This passes your daily limit of ${rupees(limit.toString())}. Change it in Profile."
                    else -> { busy = true; scope.launch { try { risk = api.risk(vpa, amount, name) } catch (e: Exception) { message = e.message ?: "Couldn't check this payment" }; busy = false } }
                }
            }
        }
        "cooling" -> Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().navigationBarsPadding().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            val totalSecs = prefs.getInt("coolingMinutes", 1) * 60
            Box(Modifier.size(190.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    drawArc(TP.canvas, 0f, 360f, false, style = Stroke(10.dp.toPx()))
                    drawArc(TP.violet, -90f, 360f * remaining / totalSecs, false, style = Stroke(10.dp.toPx(), cap = StrokeCap.Round))
                }
                TText(String.format(Locale.ENGLISH, "%d:%02d", remaining / 60, remaining % 60), 44.sp, FontWeight.SemiBold)
            }
            TText("Take a moment", 26.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 18.dp))
            TText("This is your first payment of ${rupees(amount)} to $name. Scammers rush you. Do you know them?", 15.sp, color = TP.muted, align = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            Spacer(Modifier.weight(1f))
            NeoButton("Cancel payment", kind = NeoKind.White) { step = "amount" }
        }
        else -> SuccessScreen(result?.status == "SUCCESS", result?.amount ?: amount, name, "trace.pay", result?.ref, result?.failure, onDone)
    }
    risk?.let { r ->
        RiskSheet(r, "Pay ${rupees(amount)}",
            onPay = { risk = null; if (prefs.getBoolean("cooling", true) && isNew && (amount.toDoubleOrNull() ?: 0.0) >= 5000) { remaining = prefs.getInt("coolingMinutes", 1) * 60; step = "cooling" } else send() },
            onCancel = { risk = null }, onReport = { risk = null; report = true })
    }
    if (report) ReportSheet(api, vpa) { report = false }
}

@Composable
fun SuccessScreen(ok: Boolean, amount: String, to: String, via: String, reference: String?, failure: String?, onDone: () -> Unit, details: List<Pair<String, String>> = emptyList()) {
    val ctx = LocalContext.current
    val pop = remember { Animatable(0.4f) }
    LaunchedEffect(Unit) { pop.animateTo(1f, tween(450, easing = FastOutSlowInEasing)) }
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().navigationBarsPadding().padding(22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.size((116 * pop.value).dp).clip(RoundedCornerShape(36.dp)).background(if (ok) TP.good else TP.bad), contentAlignment = Alignment.Center) {
            Icon(if (ok) Icons.Default.Check else Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(56.dp))
        }
        TText(if (ok) "Paid to $to" else "Payment not completed", 15.sp, color = TP.muted, modifier = Modifier.padding(top = 26.dp))
        if (ok) TText(rupees(amount), 52.sp, FontWeight.SemiBold)
        TText(if (ok) "via $via · checked by trace.pay" else (failure?.ifBlank { null } ?: "No money moved. You can try again safely."), 13.sp, color = TP.muted, align = TextAlign.Center)
        val rows = details + (reference?.let { listOf("Reference" to it) } ?: emptyList())
        if (ok && rows.isNotEmpty()) CardBox(Modifier.padding(top = 18.dp), padding = 16.dp) {
            rows.forEachIndexed { i, (k, v) ->
                Row(Modifier.padding(vertical = 9.dp)) { TText(k, 13.5.sp, color = TP.muted, modifier = Modifier.weight(1f)); TText(v, 13.5.sp, FontWeight.Medium, align = TextAlign.End) }
                if (i < rows.size - 1) HorizontalDivider(color = TP.hair)
            }
        } else reference?.let { TText(it, 12.sp, color = TP.muted, modifier = Modifier.padding(top = 4.dp)) }
        Spacer(Modifier.weight(1f))
        if (ok) { NeoButton("Share receipt", kind = NeoKind.White, icon = Icons.Default.Share) { share(ctx, (listOf("trace.pay receipt", "${rupees(amount)} to $to via $via") + details.map { "${it.first}: ${it.second}" } + listOfNotNull(reference?.let { "Reference: $it" })).joinToString("\n")) }; Spacer(Modifier.height(10.dp)) }
        NeoButton("Done") { onDone() }
    }
}

// ---------------------------------------------------------------------------------------------
// Pay any UPI QR with the real installed UPI apps (icons from the phone)
// ---------------------------------------------------------------------------------------------
data class UpiApp(val pkg: String, val label: String, val icon: Drawable?)

/** Known UPI apps (shown in this order when installed). */
val KNOWN_UPI_APPS = listOf("com.google.android.apps.nbu.paisa.user", "com.phonepe.app", "net.one97.paytm", "in.org.npci.upiapp", "com.dreamplug.androidapp",
    "in.amazon.mShop.android.shopping", "com.mobikwik_new", "com.naviapp", "com.flipkart.supermoney")

/** Every UPI app on this phone: apps that handle upi:// links plus known UPI apps that are installed, with their real names and icons. */
fun installedUpiApps(ctx: Context): List<UpiApp> {
    val pm = ctx.packageManager
    val byLink = runCatching {
        pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay?pa=a@b")), android.content.pm.PackageManager.MATCH_ALL).map { it.activityInfo.packageName }
    }.getOrDefault(emptyList())
    val known = KNOWN_UPI_APPS.filter { pkg -> pm.getLaunchIntentForPackage(pkg) != null }
    return (known + byLink).distinct().filter { it != ctx.packageName }.mapNotNull { pkg ->
        runCatching { val info = pm.getApplicationInfo(pkg, 0); UpiApp(pkg, pm.getApplicationLabel(info).toString(), pm.getApplicationIcon(info)) }.getOrNull()
    }
}

/** The installed app's own icon, as provided by Android. */
fun drawableBitmap(d: Drawable, size: Int = 96): android.graphics.Bitmap {
    val b = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
    val c = android.graphics.Canvas(b); d.setBounds(0, 0, size, size); d.draw(c); return b
}

/** The payee's mobile number when the UPI ID starts with one (e.g. 8142180305@superyes). */
fun mobileFromUpi(vpa: String): String? {
    val head = vpa.substringBefore("@")
    if (head.isEmpty() || !head.all(Char::isDigit) || head.length < 10) return null
    val last = head.takeLast(10)
    return if (last.first() in "6789") last else null
}

data class Receipt(val amount: String?, val utr: String?, val paidAt: java.time.LocalDateTime?, val success: Boolean?)

/** Reads the payment screenshot on the phone (ML Kit) and pulls out amount, UPI reference, date/time and status. */
object ReceiptReader {
    suspend fun read(ctx: Context, uri: Uri): String = kotlinx.coroutines.suspendCancellableCoroutine { cont ->
        try {
            val image = com.google.mlkit.vision.common.InputImage.fromFilePath(ctx, uri)
            com.google.mlkit.vision.text.TextRecognition.getClient(com.google.mlkit.vision.text.latin.TextRecognizerOptions.DEFAULT_OPTIONS).process(image)
                .addOnSuccessListener { if (cont.isActive) cont.resumeWith(Result.success(it.text)) }
                .addOnFailureListener { if (cont.isActive) cont.resumeWith(Result.success("")) }
        } catch (_: Exception) { if (cont.isActive) cont.resumeWith(Result.success("")) }
    }
    fun parse(text: String): Receipt {
        val amount = Regex("(?:₹|rs\\.?|inr)\\s?([0-9][0-9,]*(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)?.replace(",", "")
        val utr = Regex("(?:utr|upi\\s*(?:transaction\\s*)?(?:id|ref(?:erence)?(?:\\s*no\\.?)?)|transaction\\s*id|ref(?:erence)?\\s*(?:no|number)?)[^0-9]{0,24}([0-9]{12})", RegexOption.IGNORE_CASE)
            .find(text)?.groupValues?.get(1) ?: Regex("\\b([0-9]{12})\\b").find(text)?.groupValues?.get(1)
        val lower = text.lowercase()
        val success = if (lower.contains("failed") || lower.contains("declined")) false else if (lower.contains("success") || lower.contains("paid") || lower.contains("completed")) true else null
        return Receipt(amount, utr, findDate(text), success)
    }
    private fun findDate(text: String): java.time.LocalDateTime? {
        val patterns = listOf("d MMM yyyy, h:mm a", "dd MMM yyyy, hh:mm a", "d MMM yyyy h:mm a", "d MMMM yyyy, h:mm a", "MMM d, yyyy h:mm a", "MMM d, yyyy, h:mm a",
            "dd/MM/yyyy HH:mm", "dd/MM/yyyy, HH:mm", "dd-MM-yyyy HH:mm", "d MMM yyyy, HH:mm", "h:mm a, d MMM yyyy", "h:mm a on d MMM yyyy")
        val candidates = Regex("([0-9]{1,2}[:.][0-9]{2}\\s?(?:[ap]m)?[^\\n]{0,4}(?:on\\s)?[0-9]{1,2}\\s[A-Za-z]{3,9}\\s[0-9]{4})|([0-9]{1,2}[ /-][A-Za-z0-9]{2,9}[ /-][0-9]{4},?\\s(?:at\\s)?[0-9]{1,2}[:.][0-9]{2}\\s?(?:[ap]m)?)|([A-Za-z]{3,9}\\s[0-9]{1,2},\\s[0-9]{4},?\\s(?:at\\s)?[0-9]{1,2}:[0-9]{2}\\s?(?:[ap]m)?)", RegexOption.IGNORE_CASE)
            .findAll(text).map { it.value.replace(" at ", " ").replace('.', ':').replace(Regex("\\s+"), " ").trim() }.toList()
        for (c in candidates) for (p in patterns) {
            val f = java.time.format.DateTimeFormatterBuilder().parseCaseInsensitive().appendPattern(p).toFormatter(Locale.ENGLISH)
            runCatching { return java.time.LocalDateTime.parse(c, f) }
        }
        return null
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExternalPayScreen(api: TraceApi, raw: String, onDone: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val qr = remember(raw) { parseUpiQr(raw) }
    val apps = remember { installedUpiApps(ctx) }
    val vpa = qr?.get("pa") ?: ""
    var amount by remember { mutableStateOf(qr?.get("am") ?: "") }
    var payeeMobile by remember { mutableStateOf(mobileFromUpi(vpa) ?: "") }
    var chosen by remember { mutableStateOf<UpiApp?>(null) }
    var risk by remember { mutableStateOf<RiskReport?>(null) }
    var report by remember { mutableStateOf(false) }
    var guide by remember { mutableStateOf(false) }
    var receipt by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
    var savedOk by remember { mutableStateOf(false) }
    var savedRef by remember { mutableStateOf<String?>(null) }
    val payeeName = risk?.name ?: qr?.get("pn") ?: vpa
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { receipt = true }
    fun openApp(copyValue: String) {
        val app = chosen ?: return
        copy(ctx, copyValue)
        val intent = ctx.packageManager.getLaunchIntentForPackage(app.pkg)
        if (intent != null) launcher.launch(intent) else message = "Couldn't open ${app.label}."
    }
    saved?.let { rows -> SuccessScreen(savedOk, amount, payeeName, chosen?.label ?: "UPI", savedRef, if (!savedOk) "Not paid. Nothing was recorded as a payment." else null, onDone, rows); return }
    if (receipt) {
        ReceiptScreen(amount, chosen?.label ?: "UPI", onCancel = { receipt = false }) { amt, utr, paidAt, status ->
            scope.launch {
                try {
                    api.recordExternal(vpa, payeeName, amt, chosen?.label?.lowercase() ?: "upi", status, "manual", utr, risk?.score, risk?.band,
                        paidAt?.atZone(java.time.ZoneId.systemDefault())?.toOffsetDateTime()?.toString(), payeeMobile.ifBlank { null })
                    amount = amt; savedOk = status == "SUCCESS"; savedRef = utr
                    saved = buildList {
                        add("Amount" to rupees(amt)); add("Paid to" to payeeName); add("UPI ID" to vpa)
                        if (payeeMobile.isNotBlank()) add("Mobile" to "+91 $payeeMobile")
                        paidAt?.let { add("Date & time" to it.format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy, h:mm a"))) }
                        add("App" to (chosen?.label ?: "UPI"))
                        risk?.let { add("Risk at payment" to "${it.score}% · ${Risk.label(it.band)}") }
                    }
                    receipt = false
                } catch (e: Exception) { message = e.message ?: "Couldn't save the payment"; receipt = false }
            }
        }
        return
    }
    ScreenColumn {
        TopBack(onDone, close = true)
        if (qr == null) { TText("This QR has no valid UPI ID.", 15.sp, color = TP.bad, modifier = Modifier.padding(top = 20.dp)); return@ScreenColumn }
        Column(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            AvatarBox(payeeName, 70.dp)
            TText(payeeName, 24.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 10.dp), align = TextAlign.Center)
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TText("@ $vpa", 12.5.sp, color = TP.ink2, modifier = Modifier.clip(CircleShape).background(TP.canvas).padding(horizontal = 10.dp, vertical = 6.dp))
                if (payeeMobile.length == 10) TText("+91 $payeeMobile", 12.5.sp, color = TP.ink2, modifier = Modifier.clip(CircleShape).background(TP.canvas).padding(horizontal = 10.dp, vertical = 6.dp))
            }
        }
        Caption("Amount", Modifier.padding(top = 22.dp, bottom = 8.dp))
        TField(amount, { amount = it.filter { c -> c.isDigit() || c == '.' } }, "0", Icons.Default.CurrencyRupee, keyboard = KeyboardType.Decimal)
        Caption("Payee's mobile number", Modifier.padding(top = 18.dp, bottom = 8.dp))
        TField(payeeMobile, { payeeMobile = it.filter(Char::isDigit).take(10) }, "10-digit mobile (to pay by phone number)", prefix = "+91", keyboard = KeyboardType.Phone)
        TText(if (mobileFromUpi(vpa) != null) "Read from the UPI ID." else "Optional. With it, you can use \"Pay phone number\" in your UPI app.", 12.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp))
        Caption("Pay with", Modifier.padding(top = 22.dp, bottom = 10.dp))
        if (apps.isEmpty()) TText("No UPI apps found on this phone. Install Google Pay, PhonePe, Paytm or BHIM.", 14.sp, color = TP.muted)
        apps.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { app ->
                    val on = chosen?.pkg == app.pkg
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(22.dp)).background(Color.White).border(if (on) 2.dp else 1.dp, if (on) TP.violet else TP.hair, RoundedCornerShape(22.dp))
                        .clickable(enabled = !busy) {
                            if ((amount.toDoubleOrNull() ?: 0.0) <= 0) { message = "Enter the amount first."; return@clickable }
                            chosen = app; busy = true; message = ""
                            scope.launch { try { risk = api.risk(raw, amount, qr["pn"] ?: "") } catch (e: Exception) { message = e.message ?: "Couldn't check this account" }; busy = false }
                        }.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val bmp = remember(app.pkg) { runCatching { app.icon?.let { drawableBitmap(it) }?.asImageBitmap() }.getOrNull() }
                            if (bmp != null) Image(bmp, null, Modifier.size(46.dp).clip(RoundedCornerShape(14.dp))) else IconSquare(Icons.Default.Apps, size = 46.dp)
                            Spacer(Modifier.weight(1f))
                            if (busy && on) CircularProgressIndicator(color = TP.violet, strokeWidth = 2.dp, modifier = Modifier.size(18.dp)) else Icon(Icons.Default.NorthEast, null, tint = TP.faint)
                        }
                        Text(app.label, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = TP.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 12.dp))
                        TText("Installed", 12.sp, color = TP.good)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
        ErrorLine(message)
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Lock, null, tint = TP.muted, modifier = Modifier.size(14.dp)); Spacer(Modifier.width(6.dp)); TText("trace.pay checks the account first. Your UPI PIN is only entered in your UPI app.", 12.5.sp, color = TP.muted) }
    }
    risk?.let { r -> if (!guide) RiskSheet(r, "Pay ${rupees(amount)} with ${chosen?.label ?: "UPI"}", onPay = { guide = true }, onCancel = { risk = null }, onReport = { report = true }) }
    if (report) ReportSheet(api, vpa) { report = false; risk = null }
    if (guide) ModalBottomSheet(onDismissRequest = { guide = false }, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        val byPhone = payeeMobile.length == 10
        Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Caption("Pay in ${chosen?.label ?: "your UPI app"}"); TText("Three quick steps", 26.sp, FontWeight.SemiBold)
            GuideStep("1", if (byPhone) "Copy the phone number" else "Copy the UPI ID", if (byPhone) "+91 $payeeMobile" else vpa) { copy(ctx, if (byPhone) payeeMobile else vpa); copied = if (byPhone) payeeMobile else vpa }
            if (byPhone) GuideStep("·", "Or copy the UPI ID", vpa) { copy(ctx, vpa); copied = vpa }
            GuideStep("2", "Open ${chosen?.label ?: "the app"} → ${if (byPhone) "\"Pay phone number\"" else "\"Pay UPI ID\""}", "Paste, then pay ${rupees(amount)} with your PIN.", null)
            GuideStep("3", "Come back to trace.pay", "Add the payment screenshot and we'll save every detail.", null)
            if (copied.isNotBlank()) TText("Copied $copied", 13.sp, FontWeight.Medium, TP.good)
            NeoButton("Open ${chosen?.label ?: "app"}", icon = Icons.Default.NorthEast) { guide = false; risk = null; openApp(if (byPhone) payeeMobile else vpa) }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun GuideStep(n: String, title: String, sub: String, onCopy: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(18.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(if (n == "·") TP.canvas else TP.ink), contentAlignment = Alignment.Center) { TText(n, 15.sp, FontWeight.Bold, if (n == "·") TP.muted else Color.White) }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) { TText(title, 15.sp, FontWeight.SemiBold); TText(sub, 13.sp, color = TP.muted) }
        if (onCopy != null) TText("Copy", 13.sp, FontWeight.SemiBold, TP.violet, Modifier.clip(CircleShape).background(TP.violetSoft).clickable { onCopy() }.padding(horizontal = 12.dp, vertical = 8.dp))
    }
}

/** After paying in the UPI app: add the screenshot, read the details on the phone, confirm and save. */
@Composable
fun ReceiptScreen(amount: String, app: String, onCancel: () -> Unit, onSave: (String, String?, java.time.LocalDateTime?, String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var image by remember { mutableStateOf<Uri?>(null) }
    var reading by remember { mutableStateOf(false) }
    var amt by remember { mutableStateOf(amount) }
    var utr by remember { mutableStateOf("") }
    var paidAt by remember { mutableStateOf<java.time.LocalDateTime?>(java.time.LocalDateTime.now()) }
    var success by remember { mutableStateOf(true) }
    var note by remember { mutableStateOf("") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            image = uri; reading = true
            scope.launch {
                val r = ReceiptReader.parse(ReceiptReader.read(ctx, uri))
                r.amount?.let { amt = it }; r.utr?.let { utr = it }; r.paidAt?.let { paidAt = it }; r.success?.let { success = it }
                note = listOfNotNull(r.amount?.let { "₹$it" }, r.utr?.let { "Ref $it" }, r.paidAt?.format(java.time.format.DateTimeFormatter.ofPattern("d MMM, h:mm a"))).joinToString(" · ")
                    .ifBlank { "Couldn't read details. Fill them in below." }
                reading = false
            }
        }
    }
    ScreenColumn(bottom = {
        NeoButton("Save payment", icon = Icons.Default.Check, enabled = amt.toDoubleOrNull() != null) { onSave(amt, utr.ifBlank { null }, paidAt, if (success) "SUCCESS" else "FAILURE") }
        Spacer(Modifier.height(10.dp))
        NeoButton("I didn't pay", kind = NeoKind.White) { onSave(amt.ifBlank { "0" }, null, null, "CANCELLED") }
    }) {
        Caption("Payment receipt", Modifier.padding(top = 12.dp))
        TText("Did the payment go through?", 26.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
        TText("Add the payment screenshot from $app. We'll read the amount, reference and time from it.", 14.5.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp), lineHeight = 20.sp)
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(18.dp))
            .clickable { picker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            IconSquare(if (image == null) Icons.Default.AddPhotoAlternate else Icons.Default.Image, size = 54.dp); Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                TText(if (image == null) "Choose the screenshot" else "Screenshot added", 15.sp, FontWeight.SemiBold)
                TText(if (reading) "Reading the details…" else if (image == null) "From your gallery" else note, 12.5.sp, color = TP.muted)
            }
            if (reading) CircularProgressIndicator(color = TP.violet, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.height(14.dp))
        TField(amt, { amt = it.filter { c -> c.isDigit() || c == '.' } }, "Amount", Icons.Default.CurrencyRupee, keyboard = KeyboardType.Decimal); Spacer(Modifier.height(12.dp))
        TField(utr, { utr = it.filter(Char::isDigit).take(12) }, "UPI reference / UTR (12 digits)", Icons.Default.Tag, keyboard = KeyboardType.Number); Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth().height(58.dp).clip(RoundedCornerShape(16.dp)).background(TP.canvas).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CalendarMonth, null, tint = TP.faint); Spacer(Modifier.width(12.dp))
            TText("Paid at", 16.sp, FontWeight.Medium, TP.muted, Modifier.weight(1f))
            TText(paidAt?.format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy, h:mm a")) ?: "—", 15.sp, FontWeight.Medium)
        }
        Spacer(Modifier.height(12.dp))
        Segment(listOf(Icons.Default.CheckCircle to "Successful", Icons.Default.Cancel to "Failed"), if (success) 0 else 1) { success = it == 0 }
        TText("Cancel", 14.5.sp, FontWeight.Medium, TP.muted, Modifier.fillMaxWidth().clickable { onCancel() }.padding(top = 16.dp), TextAlign.Center)
    }
}

// ---------------------------------------------------------------------------------------------
// Help and report
// ---------------------------------------------------------------------------------------------
@Composable
fun HelpScreen(onBack: () -> Unit, onReport: (String) -> Unit) {
    val ctx = LocalContext.current
    var scammer by remember { mutableStateOf("") }
    ScreenColumn {
        TopBack(onBack)
        Box(Modifier.padding(top = 22.dp).size(58.dp).clip(RoundedCornerShape(18.dp)).background(TP.badBg), contentAlignment = Alignment.Center) { Icon(Icons.Default.Support, null, tint = TP.bad, modifier = Modifier.size(28.dp)) }
        TText("Act within the first hour", 28.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 16.dp))
        TText("Money reported quickly is the easiest to freeze.", 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp))
        CardBox(padding = 4.dp) {
            listOf(Triple(Icons.Default.Phone, "Call 1930" to "National cyber-crime helpline. Share the amount, time and UPI ID.", "tel:1930"),
                Triple(Icons.Default.Description, "File a complaint" to "At cybercrime.gov.in. Keep screenshots of the chat and payment.", "https://cybercrime.gov.in"),
                Triple(Icons.Default.AccountBalance, "Call your bank" to "Ask them to block the transaction and raise a dispute.", "")).forEachIndexed { i, (ic, tt, link) ->
                Row(Modifier.fillMaxWidth().clickable(enabled = link.isNotEmpty()) { ctx.startActivity(Intent(if (link.startsWith("tel")) Intent.ACTION_DIAL else Intent.ACTION_VIEW, Uri.parse(link))) }.padding(16.dp)) {
                    IconSquare(ic, TP.bad, TP.badBg, 40.dp); Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) { TText(tt.first, 16.sp, FontWeight.SemiBold); TText(tt.second, 13.sp, color = TP.muted, lineHeight = 18.sp) }
                }
                if (i < 2) HorizontalDivider(Modifier.padding(start = 70.dp), color = TP.hair)
            }
        }
        Column(Modifier.padding(top = 16.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(TP.canvas).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TText("Warn others", 16.sp, FontWeight.SemiBold); TText("Report the account so everyone who tries to pay it gets a warning.", 13.sp, color = TP.muted)
            TField(scammer, { scammer = it.trim() }, "Scammer's UPI ID", Icons.Default.Link, keyboard = KeyboardType.Email)
            NeoButton("Report on trace.pay", kind = NeoKind.Danger, icon = Icons.Default.Flag, enabled = parseUpiQr(scammer) != null) { onReport(scammer) }
        }
        TText("Never share your UPI PIN or OTP, and never install screen-sharing apps when a caller asks.", 12.5.sp, color = TP.muted, modifier = Modifier.padding(vertical = 16.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportSheet(api: TraceApi, ref: String, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var category by remember { mutableStateOf("task_scam") }
    var details by remember { mutableStateOf("") }
    var lost by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }
    val cats = listOf(Triple("scam_payment", "Scam payment", Icons.Default.CurrencyRupee), Triple("task_scam", "Task scam", Icons.Default.Work),
        Triple("investment_scam", "Investment scam", Icons.Default.TrendingUp), Triple("fake_merchant", "Fake shop", Icons.Default.Storefront),
        Triple("loan_app", "Loan app", Icons.Default.PhoneAndroid), Triple("impersonation", "Impersonation", Icons.Default.PersonOff))
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = Color.White, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).navigationBarsPadding().imePadding(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Caption("Report an account")
            TText(if (sent) "Thanks. We'll review it." else "What happened?", 26.sp, FontWeight.SemiBold); TText(ref, 13.5.sp, color = TP.muted)
            if (sent) {
                TText("Investigators review every report. If it's confirmed, everyone who tries to pay this account will be warned.", 15.sp, color = TP.muted)
                NeoButton("Done") { onDismiss() }
            } else {
                cats.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { (k, l, ic) ->
                            val on = category == k
                            Row(Modifier.weight(1f).height(48.dp).clip(RoundedCornerShape(14.dp)).background(if (on) TP.ink else TP.canvas).clickable { category = k }.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(ic, null, tint = if (on) Color.White else TP.ink2, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)); TText(l, 13.5.sp, FontWeight.Medium, if (on) Color.White else TP.ink2)
                            }
                        }
                    }
                }
                TField(details, { details = it }, "Add details (optional)", Icons.Default.Notes)
                TField(lost, { lost = it.filter { c -> c.isDigit() || c == '.' } }, "Amount lost (optional)", Icons.Default.CurrencyRupee, keyboard = KeyboardType.Decimal)
                ErrorLine(message)
                NeoButton("Send report", kind = NeoKind.Danger, icon = Icons.Default.Flag, busy = busy) {
                    busy = true; message = ""
                    scope.launch { try { api.report(ref, category, details, lost); sent = true } catch (e: Exception) { message = e.message ?: "Couldn't send the report" }; busy = false }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}


// ---------------------------------------------------------------------------------------------
// TraceScore brand
// ---------------------------------------------------------------------------------------------
@Composable
fun TraceScoreBadge() {
    Row(Modifier.clip(CircleShape).background(Color.White).border(1.dp, TP.hair, CircleShape).padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.drawable.tp_mark), null, Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)))
        Spacer(Modifier.width(8.dp))
        Text(androidx.compose.ui.text.buildAnnotatedString {
            pushStyle(androidx.compose.ui.text.SpanStyle(color = TP.ink, fontWeight = FontWeight.Bold)); append("Trace"); pop()
            pushStyle(androidx.compose.ui.text.SpanStyle(color = TP.violet, fontWeight = FontWeight.Bold)); append("Score"); pop()
        }, fontSize = 15.sp)
        Spacer(Modifier.width(6.dp)); TText("by trace.pay", 11.5.sp, FontWeight.Medium, TP.muted)
    }
}

/** Floating pixel squares (the logo's corner squares) drifting in 3D behind the score meter. */
@Composable
fun PixelField(tint: Color, modifier: Modifier = Modifier) {
    val pixels = remember { List(34) { i -> floatArrayOf(Math.random().toFloat(), Math.random().toFloat(), 5f + 10f * Math.random().toFloat(),
        0.25f + 0.55f * Math.random().toFloat(), (Math.random() * Math.PI * 2).toFloat(), 0.3f + 0.7f * Math.random().toFloat(), if (i % 5 == 0) 1f else 0f) } }
    val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "pixels")
    val t by transition.animateFloat(0f, (Math.PI * 200).toFloat(), androidx.compose.animation.core.infiniteRepeatable(tween(600_000, easing = androidx.compose.animation.core.LinearEasing)), label = "t")
    Canvas(modifier.graphicsLayer { rotationX = sin(t * 0.35f) * 9f; rotationY = cos(t * 0.28f) * 11f; cameraDistance = 14f * density }) {
        val c = Offset(size.width / 2, size.height / 2); val maxR = size.minDimension * 0.62f
        pixels.forEach { p ->
            val dx = sin(t * p[3] + p[4]) * 14.dp.toPx() * p[5]; val dy = cos(t * p[3] * 0.8f + p[4]) * 18.dp.toPx() * p[5]
            val x = p[0] * size.width + dx; val y = p[1] * size.height + dy
            val fade = (1f - ((Offset(x, y) - c).getDistance() / maxR)).coerceIn(0f, 1f)
            val s = p[2].dp.toPx() * (0.6f + 0.4f * p[5])
            val color = if (p[6] > 0f) TP.lime else if ((p[4] * 10).toInt() % 3 == 0) tint else TP.violetLight
            drawRoundRect(color.copy(alpha = (0.18f + 0.5f * p[5]) * fade), Offset(x - s / 2, y - s / 2), Size(s, s), androidx.compose.ui.geometry.CornerRadius(s * 0.22f))
        }
    }
}
