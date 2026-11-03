package tech.tracepay.android

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

// ---------------------------------------------------------------------------------------------
// Design system (matches the iOS app)
// ---------------------------------------------------------------------------------------------
object TP {
    val ink = Color(0xFF120A2B); val ink2 = Color(0xFF2B2347); val muted = Color(0xFF6B6585); val faint = Color(0xFFA39DBB)
    val hair = Color(0xFFECE8F5); val canvas = Color(0xFFF7F5FD); val violet = Color(0xFF5B2EFF); val violetDark = Color(0xFF3A17C9)
    val violetDeep = Color(0xFF24108A); val violetLight = Color(0xFF8F6BFF); val violetSoft = Color(0xFFF1EDFF); val lime = Color(0xFFC6FF3D)
    val good = Color(0xFF0A9D5A); val goodBg = Color(0xFFE6F6EE); val warn = Color(0xFFE59A00); val warnBg = Color(0xFFFFF4DC)
    val bad = Color(0xFFE03E2D); val badBg = Color(0xFFFDEAE7)
}

fun rupees(v: String?): String = try { NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply { maximumFractionDigits = 2 }.format(BigDecimal(v ?: "0")) } catch (_: Exception) { "₹${v ?: "0"}" }
fun initialsOf(text: String): String {
    val parts = text.split(' ', '.', '@', '_').filter { it.isNotBlank() }.take(2)
    return parts.joinToString("") { it.first().uppercase() }.ifBlank { "TP" }
}
fun qrImage(text: String, size: Int = 720): Bitmap {
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) for (y in 0 until size) bmp.setPixel(x, y, if (m[x, y]) 0xFF120A2B.toInt() else 0xFFFFFFFF.toInt())
    return bmp
}

@Composable fun TText(text: String, size: TextUnit = 15.sp, weight: FontWeight = FontWeight.Normal, color: Color = TP.ink, modifier: Modifier = Modifier, align: TextAlign? = null, lineHeight: TextUnit = TextUnit.Unspecified) =
    Text(text, fontSize = size, fontWeight = weight, color = color, modifier = modifier, textAlign = align, lineHeight = lineHeight)
@Composable fun Caption(text: String, modifier: Modifier = Modifier) = Text(text.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 1.4.sp, color = TP.faint, modifier = modifier)

enum class NeoKind { Ink, Violet, White, Danger, Lime }

/** CRED-style elevated button: a flat face with a darker block behind it that the face presses into. */
@Composable
fun NeoButton(text: String, modifier: Modifier = Modifier, kind: NeoKind = NeoKind.Ink, icon: ImageVector? = null, enabled: Boolean = true, busy: Boolean = false, onClick: () -> Unit) {
    val face = when (kind) { NeoKind.Ink -> TP.ink; NeoKind.Violet -> TP.violet; NeoKind.White -> Color.White; NeoKind.Danger -> TP.bad; NeoKind.Lime -> TP.lime }
    val edge = when (kind) { NeoKind.Ink, NeoKind.Violet -> TP.violetDeep; NeoKind.White -> Color(0xFFD6CFE8); NeoKind.Danger -> Color(0xFF8A1D12); NeoKind.Lime -> Color(0xFF739C10) }
    val fg = if (kind == NeoKind.White || kind == NeoKind.Lime) TP.ink else Color.White
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val d = if (pressed && enabled) 4.dp else 0.dp
    Box(modifier.fillMaxWidth().padding(end = 4.dp, bottom = 4.dp).height(54.dp)) {
        Box(Modifier.matchParentSize().offset(4.dp, 4.dp).background(if (enabled) edge else edge.copy(alpha = .3f)))
        Row(Modifier.matchParentSize().offset(d, d).background(if (enabled) face else face.copy(alpha = .45f))
            .then(if (kind == NeoKind.White) Modifier.border(1.dp, TP.hair) else Modifier)
            .clickable(interactionSource = source, indication = null, enabled = enabled && !busy) { onClick() },
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            if (busy) CircularProgressIndicator(color = fg, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            else {
                if (icon != null) { Icon(icon, null, tint = fg, modifier = Modifier.size(19.dp)); Spacer(Modifier.width(8.dp)) }
                Text(text, color = fg, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun TField(value: String, onChange: (String) -> Unit, placeholder: String, icon: ImageVector? = null, prefix: String? = null, keyboard: KeyboardType = KeyboardType.Text, secure: Boolean = false) {
    var reveal by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().height(58.dp).clip(RoundedCornerShape(16.dp)).background(TP.canvas).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        if (prefix != null) { TText(prefix, 16.sp, FontWeight.Medium, TP.muted); Spacer(Modifier.width(12.dp)); Box(Modifier.width(1.dp).height(22.dp).background(TP.hair)); Spacer(Modifier.width(12.dp)) }
        else if (icon != null) { Icon(icon, null, tint = TP.faint, modifier = Modifier.size(21.dp)); Spacer(Modifier.width(12.dp)) }
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) TText(placeholder, 16.sp, FontWeight.Medium, TP.faint)
            BasicTextField(value, onChange, singleLine = true, textStyle = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = TP.ink),
                keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else keyboard),
                visualTransformation = if (secure && !reveal) PasswordVisualTransformation() else VisualTransformation.None, modifier = Modifier.fillMaxWidth())
        }
        if (secure) Icon(if (reveal) Icons.Default.VisibilityOff else Icons.Default.Visibility, if (reveal) "Hide password" else "Show password", tint = TP.faint,
            modifier = Modifier.size(22.dp).clickable { reveal = !reveal })
    }
}

@Composable
fun Segment(options: List<Pair<ImageVector, String>>, selected: Int, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(TP.canvas).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        options.forEachIndexed { i, (icon, label) ->
            Row(Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(11.dp)).background(if (i == selected) Color.White else Color.Transparent).clickable { onSelect(i) },
                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, tint = if (i == selected) TP.ink else TP.muted, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                TText(label, 14.sp, FontWeight.Medium, if (i == selected) TP.ink else TP.muted)
            }
        }
    }
}

@Composable fun AvatarBox(name: String, size: Dp = 46.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.3f)).background(TP.violetSoft), contentAlignment = Alignment.Center) {
        TText(initialsOf(name), (size.value / 2.9f).sp, FontWeight.SemiBold, TP.violet)
    }
}
@Composable fun CardBox(modifier: Modifier = Modifier, padding: Dp = 16.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(20.dp)).padding(padding), content = content)
}
@Composable fun IconSquare(icon: ImageVector, tint: Color = TP.violet, bg: Color = TP.violetSoft, size: Dp = 42.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(13.dp)).background(bg), contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(size * 0.48f)) }
}
@Composable fun TopBack(onBack: () -> Unit, close: Boolean = false, trailing: String? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(Color.White).border(1.dp, TP.hair, RoundedCornerShape(14.dp)).clickable { onBack() }, contentAlignment = Alignment.Center) {
            Icon(if (close) Icons.Default.Close else Icons.Default.ArrowBack, if (close) "Close" else "Back", tint = TP.ink)
        }
        Spacer(Modifier.weight(1f))
        if (trailing != null) TText(trailing, 13.sp, color = TP.muted)
    }
}
@Composable fun ErrorLine(msg: String) { if (msg.isNotBlank()) TText(msg, 14.sp, color = TP.bad, lineHeight = 19.sp) }

/** Soft violet/lime glow background used on every screen. */
fun Modifier.screenBackground(): Modifier = this.background(Color.White).background(
    Brush.radialGradient(listOf(TP.violetLight.copy(alpha = .14f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(1100f, 0f), radius = 900f))

@Composable fun ProgressSteps(step: Int, total: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(total) { i -> Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(if (i < step) TP.violet else TP.hair)) }
    }
}

/** Screen scaffold: scrolling content and a bottom action pinned above the system navigation bar. */
@Composable
fun ScreenColumn(bottom: (@Composable ColumnScope.() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().screenBackground().statusBarsPadding().navigationBarsPadding().imePadding()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 12.dp), content = content)
        if (bottom != null) Column(Modifier.fillMaxWidth().background(Color.White).padding(horizontal = 22.dp, vertical = 12.dp), content = bottom)
    }
}

// ---------------------------------------------------------------------------------------------
// Root
// ---------------------------------------------------------------------------------------------
enum class Stage { Loading, Unlock, Auth, Setup, Main }

@Composable
fun TraceApp(activity: MainActivity) {
    val api = remember { TraceApi(activity).also { CurrentApi.api = it } }
    val scope = rememberCoroutineScope()
    var stage by remember { mutableStateOf(if (Vault.has(activity)) Stage.Unlock else if (api.token != null) Stage.Loading else Stage.Auth) }
    var profile by remember { mutableStateOf<Profile?>(null) }
    var locked by remember { mutableStateOf(false) }
    val lockOn = remember { activity.getSharedPreferences("tracepay_settings", 0) }
    fun afterSignIn() { stage = Stage.Loading }
    LaunchedEffect(stage) {
        if (stage == Stage.Loading) {
            try { profile = api.profile(); stage = if (profile == null) Stage.Setup else Stage.Main }
            catch (e: ApiError) { if (e.code == 401) { api.signOut(); stage = Stage.Auth } else stage = Stage.Auth }
            catch (_: Exception) { stage = Stage.Auth }
        }
    }
    // Lock again when the app returns from the background (if device lock is on).
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP && stage == Stage.Main && lockOn.getBoolean("lock", true)) locked = true }
        owner.lifecycle.addObserver(obs); onDispose { owner.lifecycle.removeObserver(obs) }
    }
    MaterialTheme(colorScheme = lightColorScheme(primary = TP.violet, onPrimary = Color.White, surface = Color.White, background = Color.White)) {
        Box(Modifier.fillMaxSize().background(Color.White)) {
            when (stage) {
                Stage.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Image(painterResource(R.drawable.tp_mark), "trace.pay", Modifier.size(84.dp)); Spacer(Modifier.height(18.dp))
                        CircularProgressIndicator(color = TP.violet, strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
                    }
                }
                Stage.Unlock -> UnlockScreen(api, activity, onUnlocked = { afterSignIn() }, onOther = { api.signOut(); stage = Stage.Auth })
                Stage.Auth -> AuthFlow(api, onSignedIn = { afterSignIn() })
                Stage.Setup -> SetupFlow(api, activity, onDone = { scope.launch { profile = api.profile(); stage = Stage.Main } })
                Stage.Main -> profile?.let { p -> MainShell(api, activity, p, onSignOut = { api.signOut(); profile = null; stage = Stage.Auth }) }
            }
            if (locked) LockOverlay(activity) { locked = false }
        }
    }
}

@Composable
fun UnlockScreen(api: TraceApi, activity: MainActivity, onUnlocked: () -> Unit, onOther: () -> Unit) {
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    fun unlock() {
        if (busy) return
        busy = true; message = ""
        scope.launch {
            if (!DeviceLock.authenticate(activity, "Unlock trace.pay")) { message = "Not unlocked. Try again."; busy = false; return@launch }
            val cred = Vault.read(activity)
            if (cred == null) { busy = false; onOther(); return@launch }
            try { api.signIn(cred.first, cred.second); onUnlocked() } catch (e: Exception) { message = e.message ?: "Couldn't sign in" }
            busy = false
        }
    }
    LaunchedEffect(Unit) { unlock() }
    ScreenColumn(bottom = {
        NeoButton(if (DeviceLock.hasBiometrics(activity)) "Unlock with fingerprint or face" else "Unlock with screen lock", icon = Icons.Default.Fingerprint, busy = busy) { unlock() }
        Spacer(Modifier.height(10.dp))
        TText("Use a different account", 15.sp, FontWeight.Medium, TP.violet, Modifier.fillMaxWidth().clickable { onOther() }.padding(8.dp), TextAlign.Center)
    }) {
        Spacer(Modifier.height(90.dp))
        Image(painterResource(R.drawable.tp_mark), "trace.pay", Modifier.size(112.dp).align(Alignment.CenterHorizontally))
        Spacer(Modifier.height(28.dp))
        TText("Welcome back", 28.sp, FontWeight.SemiBold, modifier = Modifier.fillMaxWidth(), align = TextAlign.Center)
        TText(Vault.who(activity).removeSuffix("@mobile.tracepay.app"), 15.sp, color = TP.muted, modifier = Modifier.fillMaxWidth().padding(top = 6.dp), align = TextAlign.Center)
        if (message.isNotBlank()) TText(message, 14.sp, color = TP.bad, modifier = Modifier.fillMaxWidth().padding(top = 14.dp), align = TextAlign.Center)
    }
}

@Composable
fun LockOverlay(activity: MainActivity, onUnlock: () -> Unit) {
    val scope = rememberCoroutineScope()
    fun go() { scope.launch { if (DeviceLock.authenticate(activity, "Unlock trace.pay")) onUnlock() } }
    LaunchedEffect(Unit) { go() }
    Column(Modifier.fillMaxSize().screenBackground().clickable(enabled = false) {}.padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Image(painterResource(R.drawable.tp_mark), "trace.pay", Modifier.size(96.dp)); Spacer(Modifier.height(18.dp))
        TText("trace.pay is locked", 22.sp, FontWeight.SemiBold); Spacer(Modifier.height(22.dp))
        NeoButton("Unlock", icon = Icons.Default.Fingerprint) { go() }
    }
}

// ---------------------------------------------------------------------------------------------
// Sign in / Sign up
// ---------------------------------------------------------------------------------------------
@Composable
fun AuthFlow(api: TraceApi, onSignedIn: () -> Unit) {
    var screen by remember { mutableStateOf("welcome") }
    when (screen) {
        "welcome" -> WelcomeScreen(onCreate = { screen = "signup" }, onSignIn = { screen = "signin" })
        "signin" -> SignInScreen(api, onBack = { screen = "welcome" }, onSignedIn = onSignedIn)
        else -> SignUpScreen(api, onBack = { screen = "welcome" }, onSignedIn = onSignedIn)
    }
}

@Composable
fun WelcomeScreen(onCreate: () -> Unit, onSignIn: () -> Unit) {
    val bob = remember { Animatable(0f) }
    LaunchedEffect(Unit) { while (true) { bob.animateTo(-8f, tween(1400, easing = FastOutSlowInEasing)); bob.animateTo(0f, tween(1400, easing = FastOutSlowInEasing)) } }
    ScreenColumn(bottom = {
        NeoButton("Create account", icon = Icons.Default.ArrowForward) { onCreate() }
        Spacer(Modifier.height(10.dp))
        NeoButton("Sign in", kind = NeoKind.White) { onSignIn() }
    }) {
        Spacer(Modifier.height(36.dp))
        Image(painterResource(R.drawable.tp_mark), "trace.pay", Modifier.size(128.dp).offset(y = bob.value.dp).align(Alignment.CenterHorizontally).shadow(0.dp))
        Spacer(Modifier.height(24.dp))
        Image(painterResource(R.drawable.tp_lockup), "trace.pay", Modifier.height(34.dp).align(Alignment.CenterHorizontally))
        Spacer(Modifier.height(24.dp))
        TText("Pay anyone.\nKnow them first.", 32.sp, FontWeight.SemiBold, modifier = Modifier.fillMaxWidth(), align = TextAlign.Center, lineHeight = 37.sp)
        TText("Every UPI ID is checked for scams before your money leaves, on any app.", 15.sp, color = TP.muted, modifier = Modifier.fillMaxWidth().padding(top = 10.dp), align = TextAlign.Center, lineHeight = 21.sp)
        Spacer(Modifier.height(28.dp))
        listOf(Triple(Icons.Default.VerifiedUser, "Risk score in one second", "Before every payment"),
            Triple(Icons.Default.QrCodeScanner, "Works with any UPI QR", "Google Pay, PhonePe, Paytm and more"),
            Triple(Icons.Default.Fingerprint, "Protected by your device lock", "Fingerprint, face, PIN or pattern")).forEach { (i, t, s) ->
            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                IconSquare(i, size = 44.dp); Spacer(Modifier.width(14.dp))
                Column { TText(t, 15.sp, FontWeight.Medium); TText(s, 13.sp, color = TP.muted) }
            }
        }
    }
}

@Composable
fun SignInScreen(api: TraceApi, onBack: () -> Unit, onSignedIn: () -> Unit) {
    val scope = rememberCoroutineScope()
    var method by remember { mutableIntStateOf(0) }
    var mobile by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var forgot by remember { mutableStateOf(false) }
    if (forgot) { ForgotPasswordScreen(api) { forgot = false }; return }
    ScreenColumn(bottom = {
        NeoButton("Sign in", busy = busy, enabled = password.isNotEmpty()) {
            val id = if (method == 0) mobile.filter(Char::isDigit) else email
            if (id.isBlank()) { message = if (method == 0) "Enter your mobile number." else "Enter your email."; return@NeoButton }
            busy = true; message = ""
            scope.launch { try { api.signIn(id, password); onSignedIn() } catch (e: Exception) { message = e.message ?: "Couldn't sign in" }; busy = false }
        }
    }) {
        TopBack(onBack)
        Image(painterResource(R.drawable.tp_mark), "trace.pay", Modifier.padding(top = 28.dp).size(52.dp))
        TText("Welcome back", 32.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp))
        TText("Sign in with your mobile number or email.", 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
        Segment(listOf(Icons.Default.PhoneAndroid to "Mobile", Icons.Default.Email to "Email"), method) { method = it }
        Spacer(Modifier.height(16.dp))
        if (method == 0) TField(mobile, { mobile = it.filter(Char::isDigit).take(10) }, "10-digit mobile number", prefix = "+91", keyboard = KeyboardType.Phone)
        else TField(email, { email = it.trim() }, "Email", Icons.Default.Email, keyboard = KeyboardType.Email)
        Spacer(Modifier.height(12.dp))
        TField(password, { password = it }, "Password", Icons.Default.Lock, secure = true)
        TText("Forgot password?", 14.5.sp, FontWeight.Medium, TP.violet, Modifier.fillMaxWidth().clickable { forgot = true }.padding(top = 12.dp), TextAlign.End)
        Spacer(Modifier.height(12.dp)); ErrorLine(message)
    }
}

@Composable
fun SignUpScreen(api: TraceApi, onBack: () -> Unit, onSignedIn: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(1) }
    var name by remember { mutableStateOf("") }
    var mobile by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }
    var emailCode by remember { mutableStateOf("") }
    var smsTicket by remember { mutableStateOf("") }
    var emailTicket by remember { mutableStateOf("") }
    var resendIn by remember { mutableIntStateOf(0) }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    LaunchedEffect(resendIn) { if (resendIn > 0) { delay(1000); resendIn -= 1 } }
    val rules = listOf("8+ characters" to (password.length >= 8), "Uppercase letter" to password.any(Char::isUpperCase),
        "A number" to password.any(Char::isDigit), "A symbol" to password.any { !it.isLetterOrDigit() })
    val strength = rules.count { it.second }
    val detailsOk = name.trim().length >= 2 && mobile.length == 10 && email.contains("@") && email.contains(".")
    val verified = smsTicket.isNotEmpty() && emailTicket.isNotEmpty()
    val passwordOk = strength == 4 && password == confirm
    fun sendCodes(then: () -> Unit = {}) {
        busy = true; message = ""
        scope.launch {
            try { api.startVerification("sms", mobile, name); api.startVerification("email", email, name); resendIn = 30; then() }
            catch (e: Exception) { message = e.message ?: "Couldn't send the codes" }
            busy = false
        }
    }
    fun check(channel: String, code: String) {
        scope.launch {
            message = ""
            try { val t = api.checkVerification(channel, if (channel == "sms") mobile else email, code); if (channel == "sms") smsTicket = t else emailTicket = t }
            catch (e: Exception) { message = e.message ?: "That code is wrong"; if (channel == "sms") smsCode = "" else emailCode = "" }
        }
    }
    val titles = listOf(Triple("Create account", "Let's set you up", "Your name, mobile number and email. We'll verify both."),
        Triple("Verify", "Enter your OTPs", "We sent a one-time password (OTP) to +91 $mobile and another to $email."),
        Triple("Security", "Create a password", "You'll use it to sign in on a new phone."))
    ScreenColumn(bottom = {
        NeoButton(when (step) { 1 -> "Send one-time password (OTP)"; 2 -> "Continue"; else -> "Create account" }, icon = Icons.Default.ArrowForward, busy = busy,
            enabled = when (step) { 1 -> detailsOk; 2 -> verified; else -> passwordOk }) {
            message = ""
            when (step) {
                1 -> sendCodes { step = 2 }
                2 -> step = 3
                else -> {
                    busy = true
                    ctx.getSharedPreferences("tracepay_settings", 0).edit().putString("pendingName", name.trim()).apply()
                    scope.launch { try { api.signUpVerified(email, mobile, password, emailTicket, smsTicket); onSignedIn() } catch (e: Exception) { message = e.message ?: "Couldn't create the account" }; busy = false }
                }
            }
        }
    }) {
        TopBack(onBack = { if (step == 1) onBack() else step -= 1 }, trailing = "Step $step of 3")
        Spacer(Modifier.height(20.dp)); ProgressSteps(step, 3)
        Caption(titles[step - 1].first, Modifier.padding(top = 24.dp))
        TText(titles[step - 1].second, 32.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
        TText(titles[step - 1].third, 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 22.dp), lineHeight = 21.sp)
        when (step) {
            1 -> {
                TField(name, { name = it }, "Full name", Icons.Default.Person); Spacer(Modifier.height(12.dp))
                TField(mobile, { mobile = it.filter(Char::isDigit).take(10) }, "10-digit mobile number", prefix = "+91", keyboard = KeyboardType.Phone); Spacer(Modifier.height(12.dp))
                TField(email, { email = it.trim() }, "Email", Icons.Default.Email, keyboard = KeyboardType.Email)
                TText("By continuing you agree to the Terms and Privacy Policy.", 12.5.sp, color = TP.muted, modifier = Modifier.padding(top = 14.dp))
            }
            2 -> {
                CodeBlock(Icons.Default.Sms, "SMS OTP", "+91 $mobile", smsCode, smsTicket.isNotEmpty()) { smsCode = it; if (it.length == 6) check("sms", it) }
                Spacer(Modifier.height(22.dp))
                CodeBlock(Icons.Default.Email, "Email OTP", email, emailCode, emailTicket.isNotEmpty()) { emailCode = it; if (it.length == 6) check("email", it) }
                TText(if (resendIn > 0) "Resend OTP in ${resendIn}s" else "Resend OTP", 14.5.sp, FontWeight.Medium, if (resendIn > 0) TP.faint else TP.violet,
                    Modifier.fillMaxWidth().clickable(enabled = resendIn == 0 && !busy) { sendCodes() }.padding(top = 18.dp, bottom = 8.dp), TextAlign.Center)
            }
            else -> {
                TField(password, { password = it }, "Password", Icons.Default.Lock, secure = true)
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val col = listOf(TP.bad, TP.warn, TP.violetLight, TP.good)[maxOf(0, strength - 1)]
                    repeat(4) { i -> Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(if (i < strength) col else TP.hair)) }
                }
                Spacer(Modifier.height(12.dp))
                rules.chunked(2).forEach { pair ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                        pair.forEach { (t, ok) ->
                            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                                Icon(if (ok) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked, null, tint = if (ok) TP.good else TP.faint, modifier = Modifier.size(16.dp))
                                Spacer(Modifier.width(6.dp)); TText(t, 13.sp, color = if (ok) TP.good else TP.faint)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                TField(confirm, { confirm = it }, "Confirm password", Icons.Default.Lock, secure = true)
            }
        }
        Spacer(Modifier.height(12.dp)); ErrorLine(message)
    }
}

@Composable
fun CodeBlock(icon: ImageVector, title: String, sub: String, code: String, done: Boolean, onChange: (String) -> Unit) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconSquare(if (done) Icons.Default.Verified else icon, if (done) TP.good else TP.violet, if (done) TP.goodBg else TP.violetSoft, 36.dp)
            Spacer(Modifier.width(10.dp))
            Column { TText(if (done) "$title verified" else title, 15.sp, FontWeight.SemiBold, if (done) TP.good else TP.ink); TText(sub, 12.5.sp, color = TP.muted) }
        }
        if (!done) { Spacer(Modifier.height(10.dp)); CodeBoxes(code, onChange) }
    }
}

@Composable
fun ForgotPasswordScreen(api: TraceApi, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var method by remember { mutableIntStateOf(0) }
    var mobile by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var done by remember { mutableStateOf(false) }
    val identifier = if (method == 0) mobile else email.trim().lowercase()
    val strong = password.length >= 8 && password.any(Char::isUpperCase) && password.any(Char::isDigit) && password.any { !it.isLetterOrDigit() }
    fun send() { busy = true; message = ""; scope.launch { try { api.forgotPassword(identifier); sent = true } catch (e: Exception) { message = e.message ?: "Couldn't send the code" }; busy = false } }
    ScreenColumn(bottom = {
        when {
            done -> NeoButton("Back to sign in") { onBack() }
            !sent -> NeoButton("Send one-time password (OTP)", busy = busy, enabled = identifier.length >= 5) { send() }
            else -> NeoButton("Update password", busy = busy, enabled = code.length == 6 && strong && password == confirm) {
                busy = true; message = ""
                scope.launch { try { api.resetPassword(identifier, code, password); done = true } catch (e: Exception) { message = e.message ?: "Couldn't reset the password" }; busy = false }
            }
        }
    }) {
        TopBack(onBack)
        Box(Modifier.padding(top = 22.dp).size(58.dp).clip(RoundedCornerShape(18.dp)).background(if (done) TP.goodBg else TP.violetSoft), contentAlignment = Alignment.Center) {
            Icon(if (done) Icons.Default.Verified else Icons.Default.Key, null, tint = if (done) TP.good else TP.violet, modifier = Modifier.size(26.dp))
        }
        TText(if (done) "Password updated" else if (sent) "Reset your password" else "Forgot password?", 28.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 16.dp))
        TText(if (done) "Sign in with your new password." else if (sent) "Enter the OTP we sent to ${if (method == 0) "+91 $identifier" else identifier}, then choose a new password."
              else "We'll send a code to your mobile number or email.", 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 22.dp), lineHeight = 21.sp)
        if (!done && !sent) {
            Segment(listOf(Icons.Default.PhoneAndroid to "Mobile", Icons.Default.Email to "Email"), method) { method = it }
            Spacer(Modifier.height(14.dp))
            if (method == 0) TField(mobile, { mobile = it.filter(Char::isDigit).take(10) }, "10-digit mobile number", prefix = "+91", keyboard = KeyboardType.Phone)
            else TField(email, { email = it.trim() }, "Email", Icons.Default.Email, keyboard = KeyboardType.Email)
        } else if (!done) {
            CodeBoxes(code) { code = it }; Spacer(Modifier.height(14.dp))
            TField(password, { password = it }, "New password (8+ characters)", Icons.Default.Lock, secure = true); Spacer(Modifier.height(12.dp))
            TField(confirm, { confirm = it }, "Confirm new password", Icons.Default.Lock, secure = true)
            TText("Use 8+ characters with an uppercase letter, a number and a symbol.", 12.5.sp, color = if (strong) TP.good else TP.muted, modifier = Modifier.padding(top = 10.dp))
            TText("Resend OTP", 14.5.sp, FontWeight.Medium, TP.violet, Modifier.fillMaxWidth().clickable { send() }.padding(top = 14.dp), TextAlign.Center)
        }
        Spacer(Modifier.height(12.dp)); ErrorLine(message)
    }
}


// ---------------------------------------------------------------------------------------------
// Profile setup: about you → live selfie → device lock → verify email (email accounts only)
// ---------------------------------------------------------------------------------------------
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupFlow(api: TraceApi, activity: MainActivity, onDone: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = remember { ctx.getSharedPreferences("tracepay_settings", 0) }
    // Email and mobile are verified during sign-up now; older unverified accounts verify from the Home banner.
    val needsEmail = false
    val total = if (needsEmail) 4 else 3
    var step by remember { mutableIntStateOf(1) }
    var name by remember { mutableStateOf(settings.getString("pendingName", "") ?: "") }
    var dob by remember { mutableStateOf<Long?>(null) }
    var showDate by remember { mutableStateOf(false) }
    var gender by remember { mutableStateOf("Prefer not to say") }
    var photo by remember { mutableStateOf<File?>(null) }
    var camera by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var resendIn by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    LaunchedEffect(resendIn) { if (resendIn > 0) { delay(1000); resendIn -= 1 } }
    fun sendCode() { scope.launch { message = ""; try { api.sendEmailCode(name.trim()); resendIn = 30; step = 4 } catch (e: Exception) { message = e.message ?: "Couldn't send the code" } } }
    fun finish() {
        val p = photo ?: run { step = 2; return }
        busy = true; message = ""
        scope.launch {
            try {
                if (step == 4) api.verifyEmailCode(code)
                val date = java.time.Instant.ofEpochMilli(dob ?: 0L).atZone(java.time.ZoneOffset.UTC).toLocalDate().toString()
                api.createProfile(name.trim(), date, gender, p)
                settings.edit().putBoolean("lock", true).remove("pendingName").apply()
                onDone()
            } catch (e: Exception) { message = e.message ?: "Something went wrong" }
            busy = false
        }
    }
    if (camera) { FaceCaptureScreen(onCaptured = { f -> photo = try { normalizeSelfie(ctx, f) } catch (_: Exception) { f }; camera = false }, onCancel = { camera = false }); return }
    if (showDate) {
        val state = rememberDatePickerState(initialSelectedDateMillis = dob ?: (System.currentTimeMillis() - 21L * 365 * 24 * 3600 * 1000))
        DatePickerDialog(onDismissRequest = { showDate = false }, confirmButton = { TextButton({ dob = state.selectedDateMillis; showDate = false }) { Text("Done") } }) { DatePicker(state) }
    }
    val canGo = when (step) { 1 -> name.trim().length >= 2 && dob != null; 2 -> photo != null; 4 -> code.length == 6; else -> true }
    ScreenColumn(bottom = {
        NeoButton(when (step) { 3 -> "Turn on device lock"; 4 -> "Verify and finish"; else -> "Continue" }, busy = busy, enabled = canGo) {
            when (step) {
                1, 2 -> step += 1
                3 -> scope.launch {
                    if (!DeviceLock.authenticate(activity, "Turn on device lock for trace.pay")) { message = "Device lock wasn't confirmed. Try again."; return@launch }
                    if (needsEmail) sendCode() else finish()
                }
                else -> finish()
            }
        }
    }) {
        Row(Modifier.fillMaxWidth()) { Spacer(Modifier.weight(1f)); TText("Step $step of $total", 13.sp, color = TP.muted) }
        Spacer(Modifier.height(12.dp)); ProgressSteps(step, total)
        Caption(listOf("About you", "Identity", "Device lock", "Verify email")[step - 1], Modifier.padding(top = 24.dp))
        TText(listOf("Tell us about you", "Take a live selfie", "Lock trace.pay with your phone", "Check your email")[step - 1], 30.sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp), lineHeight = 35.sp)
        TText(listOf("Used for your trace.pay profile.", "Encrypted and only checked for one clear face.", "We use the lock you already have. Nothing new to remember.",
            "We sent a 6-digit code to ${api.identifier}.")[step - 1], 15.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp, bottom = 24.dp))
        when (step) {
            1 -> {
                TField(name, { name = it }, "Full name", Icons.Default.Person); Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth().height(58.dp).clip(RoundedCornerShape(16.dp)).background(TP.canvas).clickable { showDate = true }.padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CalendarMonth, null, tint = TP.faint); Spacer(Modifier.width(12.dp))
                    TText(dob?.let { java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate().format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy")) } ?: "Date of birth",
                        16.sp, FontWeight.Medium, if (dob == null) TP.faint else TP.ink)
                }
                Caption("Gender", Modifier.padding(top = 18.dp, bottom = 10.dp))
                listOf("Male", "Female", "Non-binary", "Prefer not to say").chunked(2).forEach { row ->
                    Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { g ->
                            val on = gender == g
                            Row(Modifier.weight(1f).height(50.dp).clip(RoundedCornerShape(14.dp)).background(if (on) TP.violetSoft else TP.canvas).clickable { gender = g }.padding(horizontal = 14.dp),
                                verticalAlignment = Alignment.CenterVertically) {
                                TText(g, 14.5.sp, FontWeight.Medium, if (on) TP.violet else TP.ink2, Modifier.weight(1f))
                                Icon(if (on) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked, null, tint = if (on) TP.violet else TP.faint, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
            2 -> {
                Box(Modifier.fillMaxWidth().height(290.dp).clip(RoundedCornerShape(28.dp)).background(Brush.verticalGradient(listOf(TP.violetSoft, Color.White)))
                    .border(1.dp, TP.hair, RoundedCornerShape(28.dp)), contentAlignment = Alignment.Center) {
                    val p = photo
                    if (p != null) {
                        val bmp = remember(p) { android.graphics.BitmapFactory.decodeFile(p.absolutePath) }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            if (bmp != null) Image(bmp.asImageBitmap(), "Your selfie", Modifier.size(170.dp, 214.dp).clip(RoundedCornerShape(100.dp)).border(4.dp, TP.good, RoundedCornerShape(100.dp)),
                                contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                            TText("Clear face captured", 14.sp, FontWeight.SemiBold, TP.good, Modifier.padding(top = 12.dp).clip(CircleShape).background(TP.goodBg).padding(horizontal = 12.dp, vertical = 6.dp))
                        }
                    } else {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(Modifier.size(150.dp, 190.dp).border(3.dp, TP.violet.copy(alpha = .35f), RoundedCornerShape(100.dp)), contentAlignment = Alignment.Center) {
                                Icon(Icons.Default.Face, null, tint = TP.violet, modifier = Modifier.size(70.dp))
                            }
                            TText("Your face goes inside the oval", 14.sp, FontWeight.Medium, TP.ink2, Modifier.padding(top = 12.dp))
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
                CardBox(padding = 16.dp) {
                    listOf(Triple(Icons.Default.WbSunny, "Good light", "Face a window or a lamp; avoid strong light behind you."),
                        Triple(Icons.Default.FaceRetouchingOff, "Nothing covering your face", "Take off sunglasses, masks and caps."),
                        Triple(Icons.Default.PanTool, "Hold still", "The photo is taken automatically when your face is clear."),
                        Triple(Icons.Default.Lock, "Private", "Encrypted, and only checked for one clear face.")).forEach { (ic, t, d) ->
                        Row(Modifier.padding(vertical = 6.dp)) {
                            IconSquare(ic, size = 32.dp); Spacer(Modifier.width(12.dp))
                            Column { TText(t, 14.sp, FontWeight.SemiBold); TText(d, 12.5.sp, color = TP.muted, lineHeight = 17.sp) }
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
                NeoButton(if (photo == null) "Open camera" else "Retake selfie", kind = if (photo == null) NeoKind.Violet else NeoKind.White, icon = Icons.Default.CameraAlt) { camera = true }
            }
            3 -> {
                Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(140.dp).clip(RoundedCornerShape(38.dp)).background(Brush.linearGradient(listOf(TP.violet, TP.violetDeep))), contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.Fingerprint, null, tint = Color.White, modifier = Modifier.size(70.dp))
                    }
                }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    listOf(Icons.Default.Fingerprint to "Fingerprint", Icons.Default.Face to "Face", Icons.Default.Dialpad to "PIN or pattern").forEachIndexed { i, (ic, l) ->
                        val on = if (DeviceLock.hasBiometrics(ctx)) i < 2 else i == 2
                        Column(Modifier.weight(1f).height(84.dp).clip(RoundedCornerShape(16.dp)).background(if (on) TP.violetSoft else TP.canvas)
                            .border(1.5.dp, if (on) TP.violet else Color.Transparent, RoundedCornerShape(16.dp)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                            Icon(ic, null, tint = TP.violet); Spacer(Modifier.height(8.dp)); TText(l, 12.5.sp, FontWeight.Medium, if (on) TP.ink else TP.muted)
                        }
                    }
                }
                TText("You'll use it to open trace.pay and confirm payments.", 13.sp, color = TP.muted, modifier = Modifier.fillMaxWidth().padding(top = 14.dp), align = TextAlign.Center)
            }
            else -> {
                CodeBoxes(code) { code = it }
                Spacer(Modifier.height(16.dp))
                TText(if (resendIn > 0) "Resend code in ${resendIn}s" else "Resend code", 14.5.sp, FontWeight.Medium, if (resendIn > 0) TP.faint else TP.violet,
                    Modifier.fillMaxWidth().clickable(enabled = resendIn == 0) { sendCode() }.padding(8.dp), TextAlign.Center)
                TText("Didn't get it? Check spam, or wait a minute and resend.", 13.sp, color = TP.muted, modifier = Modifier.padding(top = 6.dp))
            }
        }
        Spacer(Modifier.height(12.dp)); ErrorLine(message)
    }
}

/** Six polished code boxes over one hidden number field: auto-fills, supports paste, animates as digits arrive. */
@Composable
fun CodeBoxes(code: String, onChange: (String) -> Unit) {
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    BasicTextField(code, { onChange(it.filter(Char::isDigit).take(6)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        modifier = Modifier.focusRequester(focus),
        decorationBox = {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(6) { i ->
                    val filled = i < code.length; val active = i == code.length
                    val scale by androidx.compose.animation.core.animateFloatAsState(if (filled) 1f else 0.96f, label = "otp")
                    Box(Modifier.weight(1f).height(64.dp).graphicsLayer { scaleX = scale; scaleY = scale }
                        .shadow(if (filled) 3.dp else 0.dp, RoundedCornerShape(16.dp)).clip(RoundedCornerShape(16.dp))
                        .background(if (filled) Color.White else TP.canvas)
                        .border(if (active) 2.dp else 1.dp, if (active) TP.violet else if (filled) TP.hair else Color.Transparent, RoundedCornerShape(16.dp)),
                        contentAlignment = Alignment.Center) {
                        TText(code.getOrNull(i)?.toString() ?: "", 28.sp, FontWeight.SemiBold)
                    }
                }
            }
        })
}
