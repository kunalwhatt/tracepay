package tech.tracepay.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

private val VInk = Color(0xFF14092E); private val VMuted = Color(0xFF6B6585); private val VCanvas = Color(0xFFF7F5FD)
private val VViolet = Color(0xFF5B2EFF); private val VLime = Color(0xFFC6FF3D); private val VBad = Color(0xFFE03E2D); private val VGood = Color(0xFF0A9D5A)

/** (mustVerify, email) for the signed-in account. Mobile-only accounts never need it. */
suspend fun TraceApi.emailStatus(): Pair<Boolean, String> {
    val o = JSONObject(call("/api/v1/auth/email/status"))
    return Pair(o.optBoolean("required") && !o.optBoolean("verified"), o.optString("email").takeIf { it != "null" } ?: "")
}
suspend fun TraceApi.sendEmailCode(name: String) { call("/api/v1/auth/email/send-otp", "POST", JSONObject().put("full_name", name).toString()) }
suspend fun TraceApi.verifyEmailCode(code: String) { call("/api/v1/auth/email/verify-otp", "POST", JSONObject().put("code", code).toString()) }

/** Shown instead of payments until the account's email is verified. Sends the code on open. */
@Composable
fun VerifyEmailScreen(api: TraceApi, email: String, name: String, onVerified: () -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var resendIn by remember { mutableIntStateOf(0) }
    fun send() { scope.launch { message = ""; try { api.sendEmailCode(name); resendIn = 30 } catch (e: Exception) { message = e.message ?: "Couldn't send the code" } } }
    LaunchedEffect(Unit) { send() }
    LaunchedEffect(resendIn) { if (resendIn > 0) { delay(1000); resendIn -= 1 } }
    Column(Modifier.fillMaxSize().background(Color.White).statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).border(1.dp, Color(0xFFECE8F5), RoundedCornerShape(14.dp)).clickable { onBack() }, contentAlignment = Alignment.Center) {
            Icon(Icons.Default.ArrowBack, "Back", tint = VInk)
        }
        Box(Modifier.size(60.dp).clip(RoundedCornerShape(18.dp)).background(if (done) Color(0xFFE6F6EE) else VLime), contentAlignment = Alignment.Center) {
            Icon(if (done) Icons.Default.Verified else Icons.Default.Email, null, tint = if (done) VGood else VInk, modifier = Modifier.size(28.dp))
        }
        Text(if (done) "Email verified" else "Verify your email to pay", fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = VInk)
        Text(if (done) "Payments are unlocked. You're all set." else "We sent a 6-digit code to $email. Enter it to unlock payments.", fontSize = 15.sp, color = VMuted)
        if (done) {
            Text("Continue", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().background(VInk).clickable { onVerified() }.padding(vertical = 17.dp))
            return@Column
        }
        BasicTextField(value = code, onValueChange = { code = it.filter(Char::isDigit).take(6) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            decorationBox = {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    repeat(6) { i ->
                        Box(Modifier.weight(1f).height(62.dp).clip(RoundedCornerShape(14.dp)).background(VCanvas)
                            .border(1.5.dp, if (i == code.length) VViolet else Color.Transparent, RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                            Text(code.getOrNull(i)?.toString() ?: "", fontSize = 28.sp, fontWeight = FontWeight.SemiBold, color = VInk)
                        }
                    }
                }
            })
        if (message.isNotBlank()) Text(message, color = VBad, fontSize = 14.sp)
        Text(if (busy) "Verifying…" else "Verify email", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().background(if (code.length == 6) VInk else VInk.copy(alpha = 0.4f)).clickable(enabled = code.length == 6 && !busy) {
                busy = true; message = ""
                scope.launch { try { api.verifyEmailCode(code); done = true } catch (e: Exception) { message = e.message ?: "That code is wrong or has expired" }; busy = false }
            }.padding(vertical = 17.dp))
        Text(if (resendIn > 0) "Resend code in ${resendIn}s" else "Resend code", color = if (resendIn > 0) VMuted else VViolet, fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().clickable(enabled = resendIn == 0) { send() }.padding(8.dp))
        Spacer(Modifier.height(4.dp))
        Text("Didn't get it? Check spam, or wait a minute and resend.", color = VMuted, fontSize = 13.sp)
    }
}
