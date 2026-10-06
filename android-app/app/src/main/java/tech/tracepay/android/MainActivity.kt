package tech.tracepay.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.animation.AnimatedVisibility
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricPrompt
import android.provider.Settings
import android.os.Build
import android.app.KeyguardManager
import androidx.biometric.BiometricManager
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.fragment.app.FragmentActivity
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.GlobalScope
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.math.BigDecimal
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.*

// 4.3 pixel-t identity: token names kept so every screen re-themes; Coral is now the primary violet, Mint/Green the lime success pair.
private val Ivory=Color(0xFFF3EEFF); private val Paper=Color(0xFFFFFFFF); private val Ink=Color(0xFF14092E); private val Coral=Color(0xFF5B2EFF); private val CoralSoft=Color(0xFFE4DCFF); private val Muted=Color(0xFF5E5480); private val Line=Color(0xFFDDD3FF); private val Mint=Color(0xFFECFFC2); private val Green=Color(0xFF3D5600); private val Lime=Color(0xFFC6FF3D)

/** Trace.Pay IDs are always name@tracepay (mirror of backend app/ids.py). Returns null for other UPI handles. */
fun normalizeTracePayId(input:String):String?{var raw=input.trim().lowercase();if(raw.startsWith("upi://")||raw.startsWith("tracepay://")){raw=try{android.net.Uri.parse(raw).getQueryParameter("pa")?.lowercase()?:""}catch(_:Exception){""}};if(raw.isNotEmpty()&&!raw.contains("@"))raw+="@tracepay";return if(Regex("^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?@tracepay$").matches(raw)) raw else null}
private const val API=BuildConfig.TRACEPAY_API_BASE_URL
private fun money(v:String?)=try{NumberFormat.getCurrencyInstance(Locale("en","IN")).apply{maximumFractionDigits=2}.format(BigDecimal(v?:"0"))}catch(_:Exception){"₹${v?:"0"}"}

// BiometricPrompt requires a FragmentActivity (FragmentActivity extends ComponentActivity, so setContent still works).
class MainActivity: FragmentActivity(){ override fun onCreate(savedInstanceState: Bundle?){super.onCreate(savedInstanceState);setContent{TracePayApp(this)}}
 /** Confirm a payment with fingerprint / face, or the phone's PIN, pattern or password when no biometric is set up. */
 fun biometric(onSuccess:()->Unit,onError:(String)->Unit={}){
  val credential=BiometricManager.Authenticators.DEVICE_CREDENTIAL
  // Android 11+ accepts strong biometrics or the screen lock; Android 8-10 only allow weak biometrics combined with the screen lock.
  val allowed=if(Build.VERSION.SDK_INT>=Build.VERSION_CODES.R) BiometricManager.Authenticators.BIOMETRIC_STRONG or credential else BiometricManager.Authenticators.BIOMETRIC_WEAK or credential
  val keyguard=getSystemService(KeyguardManager::class.java)
  if(BiometricManager.from(this).canAuthenticate(allowed)!=BiometricManager.BIOMETRIC_SUCCESS&&keyguard?.isDeviceSecure!=true){
   onError(NO_SCREEN_LOCK_MESSAGE);return}
  val prompt=BiometricPrompt(this,mainExecutor,object:BiometricPrompt.AuthenticationCallback(){
   override fun onAuthenticationSucceeded(r:BiometricPrompt.AuthenticationResult){onSuccess()}
   override fun onAuthenticationError(code:Int,msg:CharSequence){onError(msg.toString())}})
  // No negative button: when the screen lock is allowed, Android shows its own "Use PIN" and cancel options.
  prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("Confirm Trace.Pay payment").setSubtitle("Use your fingerprint, face or screen lock").setAllowedAuthenticators(allowed).build())
 }
 fun openScreenLockSettings(){try{startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))}catch(_:Exception){startActivity(Intent(Settings.ACTION_SETTINGS))}}
}

const val NO_SCREEN_LOCK_MESSAGE="This phone has no screen lock. Set a PIN, pattern or password in Settings to confirm payments."

data class Auth(val access_token:String,val role:String)
data class Profile(val full_name:String,val vpa_id:String,val gender:String,val selfie_status:String)
data class Wallet(val balance:String,val vpa_id:String)
data class Transfer(val transfer_ref:String,val sender_vpa:String,val receiver_vpa:String,val amount:String,val status:String,val created_at:String,val note:String="",val failure_reason:String="")
data class Risk(val assessment_id:Int,val recipient_ref:String,val level:String,val reasons:List<String>,val observed_transaction_count:Int,val rule_version:String,val disclaimer:String,val data_as_of:String="",val shieldLevel:String="",val shieldReasons:List<String> = emptyList())

class TraceApi(private val context:Context){private val client=OkHttpClient.Builder().build();private var token:String?=context.getSharedPreferences("tracepay",0).getString("token",null)
 suspend fun call(path:String,method:String="GET",json:String?=null):String=withContext(Dispatchers.IO){val b=json?.toRequestBody("application/json".toMediaType());val req=Request.Builder().url(API.trimEnd('/')+path).apply{token?.let{header("Authorization","Bearer $it")}}.method(method,b).build();client.newCall(req).execute().use{r->val body=r.body?.string().orEmpty();if(r.code==401&&token!=null&&!path.startsWith("/api/v1/auth/login")){token=null;context.getSharedPreferences("tracepay",0).edit().remove("token").apply();Handler(Looper.getMainLooper()).post{onExpired?.invoke()}};if(!r.isSuccessful)throw Exception(JSONObject(body).optString("detail","Request failed ${r.code}"));body}}
 suspend fun login(email:String,pw:String):Auth{val o=JSONObject(call("/api/v1/auth/login","POST",JSONObject().put("email",email).put("password",pw).toString()));val a=Auth(o.getString("access_token"),o.getString("role"));token=a.access_token;context.getSharedPreferences("tracepay",0).edit().putString("token",token).putString("email",email).apply();return a}
 suspend fun register(email:String,pw:String)=call("/api/v1/auth/register","POST",JSONObject().put("email",email).put("password",pw).toString())
 suspend fun profile():Profile?{val o=JSONObject(call("/api/v1/pilot/profile"));if(o.isNull("profile"))return null;val p=o.getJSONObject("profile");return Profile(p.getString("full_name"),p.getString("vpa_id"),p.getString("gender"),p.getString("selfie_status"))}
 suspend fun wallet():Wallet{val o=JSONObject(call("/api/v1/pilot/wallet"));return Wallet(o.getString("balance"),o.getString("vpa_id"))}
 suspend fun transfers():List<Transfer>{val a=org.json.JSONArray(call("/api/v1/pilot/transfers?limit=100"));return (0 until a.length()).map{val o=a.getJSONObject(it);Transfer(o.getString("transfer_ref"),o.optString("sender_vpa"),o.getString("receiver_vpa"),o.getString("amount"),o.getString("status"),o.getString("created_at"),o.optString("note"),if(o.isNull("failure_reason"))"" else o.optString("failure_reason"))}}
 suspend fun recipient(vpa:String):String{val o=JSONObject(call("/api/v1/pilot/recipients/${Uri.encode(vpa)}"));return o.getString("display_name")}
 suspend fun risk(vpa:String,amount:String=""):Risk{val req=JSONObject().put("recipient_ref",vpa);amount.toBigDecimalOrNull()?.let{req.put("amount",it.toPlainString())};val o=JSONObject(call("/api/v1/risk/check","POST",req.toString()));val rs=o.getJSONArray("reasons");val sh=o.optJSONObject("shield");val shieldReasons=sh?.optJSONArray("reasons")?.let{a->(0 until a.length()).map{a.getJSONObject(it).optString("text")}}?:emptyList();return Risk(o.getInt("assessment_id"),o.getString("recipient_ref"),o.getString("level"),(0 until rs.length()).map{rs.getString(it)},o.getInt("observed_transaction_count"),o.getString("rule_version"),o.getString("disclaimer"),o.optString("data_as_of"),sh?.optString("level")?:"",shieldReasons)}
 /** idempotencyKey is created once per payment attempt and reused on retry, so a dropped connection cannot pay twice. */
 suspend fun transfer(vpa:String,amount:String,note:String,idempotencyKey:String):Transfer{val o=JSONObject(call("/api/v1/pilot/transfers","POST",JSONObject().put("receiver_vpa",vpa).put("amount",amount).put("note",note).put("idempotency_key",idempotencyKey).toString()));return Transfer(o.getString("transfer_ref"),o.optString("sender_vpa"),o.getString("receiver_vpa"),o.getString("amount"),o.getString("status"),o.getString("created_at"),o.optString("note"),if(o.isNull("failure_reason"))"" else o.optString("failure_reason"))}
 suspend fun createProfile(name:String,dob:String,gender:String,file:File){withContext(Dispatchers.IO){val body=MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("full_name",name).addFormDataPart("date_of_birth",dob).addFormDataPart("gender",gender).addFormDataPart("consent_profile","true").addFormDataPart("consent_pilot_ledger","true").addFormDataPart("face_photo",file.name,file.asRequestBody("image/jpeg".toMediaType())).build();val req=Request.Builder().url(API.trimEnd('/')+"/api/v1/pilot/profile").header("Authorization","Bearer ${token}").post(body).build();client.newCall(req).execute().use{r->if(!r.isSuccessful)throw Exception(JSONObject(r.body?.string().orEmpty()).optString("detail","Profile creation failed"))}}}
 fun logout(){context.getSharedPreferences("tracepay",0).edit().clear().apply();token=null}
 /** Called on the main thread when the server rejects the session (expired or revoked). */
 var onExpired:(()->Unit)?=null
 fun email():String=context.getSharedPreferences("tracepay",0).getString("email","")?:""
 /** Expiry read from the JWT so the "Session mm:ss" chip is accurate; the server stays the authority. */
 fun tokenExpiryMillis():Long?{val t=token?:return null;val parts=t.split(".");if(parts.size!=3)return null;return try{JSONObject(String(Base64.decode(parts[1],Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING))).getLong("exp")*1000}catch(_:Exception){null}}
 /** Renew the token when under five minutes remain; expired tokens cannot be renewed. */
 suspend fun refreshIfNeeded(){val exp=tokenExpiryMillis()?:return;val left=exp-System.currentTimeMillis();if(left<=0||left>300_000)return;try{val o=JSONObject(call("/api/v1/auth/refresh","POST","{}"));token=o.getString("access_token");context.getSharedPreferences("tracepay",0).edit().putString("token",token).apply()}catch(_:Exception){}}
}

@Composable fun TracePayApp(activity:MainActivity){val api=remember{TraceApi(activity)};var logged by remember{mutableStateOf(activity.getSharedPreferences("tracepay",0).getString("token",null)!=null)};var profile by remember{mutableStateOf<Profile?>(null)};var loading by remember{mutableStateOf(logged)};var expired by remember{mutableStateOf(false)};LaunchedEffect(api){api.onExpired={logged=false;profile=null;expired=true}};LaunchedEffect(logged){if(logged){loading=true;profile=try{api.profile()}catch(_:Exception){null};loading=false}};Surface(color=Ivory){Box(Modifier.fillMaxSize()){when{!logged->LoginScreen(api){expired=false;logged=true};loading->SplashLoading();profile==null&&logged->ProfileScreen(api){activityScope(api){profile=api.profile()}};else->MainScreen(api,activity,profile!!){api.logout();logged=false}};if(expired&&!logged)ExpiredBanner(Modifier.align(Alignment.TopCenter)){expired=false}}}}

@Composable fun Brand(){Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(9.dp)){Image(painterResource(R.drawable.tracepay_mark),contentDescription="trace.pay",modifier=Modifier.size(34.dp).clip(RoundedCornerShape(11.dp)));Text("trace",fontSize=21.sp,fontWeight=FontWeight.ExtraBold,color=Ink);Text(".",fontSize=21.sp,fontWeight=FontWeight.ExtraBold,color=Coral);Text("pay",fontSize=21.sp,fontWeight=FontWeight.ExtraBold,color=Ink)}}
@Composable fun SplashLoading(){val infinite=rememberInfiniteTransition(label="spin");val a by infinite.animateFloat(0.8f,1.15f,infiniteRepeatable(tween(1200),RepeatMode.Reverse),label="pulse");Column(Modifier.fillMaxSize(),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center){Box(Modifier.size(74.dp).scale(a).clip(CircleShape).background(CoralSoft),contentAlignment=Alignment.Center){Text("t.",fontSize=28.sp,fontWeight=FontWeight.ExtraBold,color=Coral)};Spacer(Modifier.height(15.dp));Text("Getting things ready…",fontSize=11.sp,color=Muted)}}

@Composable fun LoginScreen(api:TraceApi,onLogged:()->Unit){
 var register by remember{mutableStateOf(false)}
 var email by remember{mutableStateOf("")}
 var pw by remember{mutableStateOf("")}
 var pw2 by remember{mutableStateOf("")}
 var show by remember{mutableStateOf(false)}
 var busy by remember{mutableStateOf(false)}
 var error by remember{mutableStateOf("")}
 val drift by rememberInfiniteTransition(label="hero").animateFloat(0f,1f,infiniteRepeatable(tween(6000,easing=LinearEasing),RepeatMode.Reverse),label="drift")
 val checks=listOf("12+ characters" to (pw.length>=12),"Uppercase letter" to pw.any{it.isUpperCase()},"Number" to pw.any{it.isDigit()},"Symbol" to pw.any{!it.isLetterOrDigit()})
 val strength=checks.count{it.second}
 val emailOk=Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim())
 val canSubmit=!busy&&emailOk&&(if(register) strength==4&&pw==pw2 else pw.isNotBlank())
 fun submit(){busy=true;error="";activityScope(api){try{if(register)api.register(email.trim(),pw);api.login(email.trim(),pw);onLogged()}catch(e:Exception){error=e.message?:"Something went wrong. Try again."};busy=false}}
 Column(Modifier.fillMaxSize().background(Ivory).verticalScroll(rememberScrollState())){
  Box(Modifier.fillMaxWidth().height(310.dp).clip(RoundedCornerShape(bottomStart=38.dp,bottomEnd=38.dp)).background(Brush.linearGradient(listOf(Coral,Color(0xFF7B57FF))))){
   Box(Modifier.size(170.dp).offset(x=(230+30*drift).dp,y=(-50+24*drift).dp).clip(CircleShape).background(Lime))
   Box(Modifier.size(120.dp).offset(x=(-40+24*drift).dp,y=(200-30*drift).dp).clip(CircleShape).background(Color.White.copy(alpha=.13f)))
   Box(Modifier.size(56.dp).offset(x=(180-24*drift).dp,y=(160+18*drift).dp).clip(CircleShape).background(Color(0xFF8F6BFF)))
   Column(Modifier.statusBarsPadding().padding(24.dp)){
    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){
     Image(painterResource(R.drawable.tracepay_mark),null,Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).border(1.dp,Color.White.copy(alpha=.45f),RoundedCornerShape(12.dp)))
     Row{Text("trace",fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Color.White);Text(".",fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Lime);Text("pay",fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Color.White)}}
    Spacer(Modifier.height(40.dp))
    AnimatedContent(targetState=register,label="title"){r->Column{
     Text(if(r)"Create your\naccount." else "Welcome\nback.",fontSize=42.sp,fontWeight=FontWeight.ExtraBold,color=Color.White,lineHeight=44.sp)
     Text(if(r)"Your Trace.Pay ID is ready in a minute." else "Pay safely. See the trail behind every payment.",fontSize=14.sp,color=Color.White.copy(alpha=.88f),modifier=Modifier.padding(top=8.dp))}}}}
  Column(Modifier.offset(y=(-36).dp).padding(horizontal=18.dp).fillMaxWidth().shadow(22.dp,RoundedCornerShape(28.dp),ambientColor=Coral,spotColor=Coral).background(Paper,RoundedCornerShape(28.dp)).padding(18.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
   Row(Modifier.fillMaxWidth().background(Ivory,RoundedCornerShape(16.dp)).padding(4.dp)){listOf("Sign in" to false,"Create account" to true).forEach{(t,v)->val sel=register==v
    Box(Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(12.dp)).background(if(sel)Coral else Color.Transparent).clickable{register=v;error=""},contentAlignment=Alignment.Center){Text(t,fontWeight=FontWeight.Bold,fontSize=14.sp,color=if(sel)Color.White else Muted)}}}
   AuthField("Email",email,{email=it;error=""},Icons.Default.Email,KeyboardType.Email,isValid=email.isBlank()||emailOk)
   AuthField("Password",pw,{pw=it;error=""},Icons.Default.Lock,KeyboardType.Password,password=true,show=show,onToggle={show=!show})
   AnimatedVisibility(register){Column(verticalArrangement=Arrangement.spacedBy(10.dp)){
    Row(horizontalArrangement=Arrangement.spacedBy(5.dp)){repeat(4){i->Box(Modifier.weight(1f).height(6.dp).clip(RoundedCornerShape(3.dp)).background(if(i<strength)listOf(Color(0xFFE5482F),Color(0xFFE3A127),Color(0xFF8FD14F),Color(0xFF3D9A00))[strength-1] else Line))}}
    checks.chunked(2).forEach{row->Row{row.forEach{(t,ok)->Row(Modifier.weight(1f),verticalAlignment=Alignment.CenterVertically){Icon(if(ok)Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked,null,tint=if(ok)Color(0xFF3D9A00) else Muted,modifier=Modifier.size(15.dp));Spacer(Modifier.width(5.dp));Text(t,fontSize=12.sp,color=if(ok)Ink else Muted)}}}}
    AuthField("Confirm password",pw2,{pw2=it},Icons.Default.Lock,KeyboardType.Password,password=true,show=show,onToggle={show=!show},isValid=pw2.isBlank()||pw2==pw)}}
   ErrorText(error)
   TPPrimary(if(register)"Create account" else "Sign in",busy=busy,enabled=canSubmit){submit()}
   Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically){Icon(Icons.Default.Lock,null,tint=Muted,modifier=Modifier.size(13.dp));Spacer(Modifier.width(5.dp));Text("We never ask for your UPI PIN, OTP or bank password.",fontSize=11.sp,color=Muted)}}}}

@Composable fun AuthField(label:String,value:String,onChange:(String)->Unit,icon:ImageVector,type:KeyboardType,password:Boolean=false,show:Boolean=false,onToggle:()->Unit={},isValid:Boolean=true){
 OutlinedTextField(value,onChange,label={Text(label)},singleLine=true,leadingIcon={Icon(icon,null,tint=Coral)},
  trailingIcon={if(password)Icon(if(show)Icons.Default.VisibilityOff else Icons.Default.Visibility,if(show)"Hide password" else "Show password",tint=Muted,modifier=Modifier.clip(CircleShape).clickable{onToggle()}.padding(6.dp))},
  visualTransformation=if(password&&!show)PasswordVisualTransformation() else VisualTransformation.None,
  keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=type),isError=!isValid,
  colors=OutlinedTextFieldDefaults.colors(focusedBorderColor=Coral,unfocusedBorderColor=Line,focusedContainerColor=Paper,unfocusedContainerColor=Paper,errorBorderColor=ErrorRed),
  shape=RoundedCornerShape(16.dp),modifier=Modifier.fillMaxWidth())}

@Composable fun ProfileScreen(api:TraceApi,onDone:()->Unit){
 var name by remember{mutableStateOf("")}
 var dob by remember{mutableStateOf("2000-01-01")}
 var gender by remember{mutableStateOf("Prefer not to say")}
 var photo by remember{mutableStateOf<File?>(null)}
 var camera by remember{mutableStateOf(false)}
 var busy by remember{mutableStateOf(false)}
 var error by remember{mutableStateOf("")}
 if(camera){FaceCaptureScreen(onCaptured={photo=it;camera=false;error=""},onCancel={camera=false});return}
 val bmp=remember(photo){photo?.let{BitmapFactory.decodeFile(it.absolutePath)?.asImageBitmap()}}
 val dobOk=Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(dob)
 Column(Modifier.fillMaxSize().background(Ivory).verticalScroll(rememberScrollState()).statusBarsPadding().padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
  Brand()
  Text("Set up your profile",fontSize=32.sp,fontWeight=FontWeight.ExtraBold,color=Ink,lineHeight=36.sp)
  Text("Three quick steps. Your Trace.Pay ID and wallet are created at the end.",fontSize=13.sp,color=Muted)
  StepHeader(1,"Live selfie",photo!=null)
  Box(Modifier.fillMaxWidth().height(190.dp).clip(RoundedCornerShape(24.dp)).background(Paper).border(1.dp,if(photo!=null)Lime else Line,RoundedCornerShape(24.dp)).clickable{camera=true},contentAlignment=Alignment.Center){
   if(bmp!=null){Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(16.dp)){
     Image(bmp,"Your selfie",Modifier.size(118.dp).clip(CircleShape).border(4.dp,Lime,CircleShape),contentScale=androidx.compose.ui.layout.ContentScale.Crop)
     Column{Text("Face captured",fontWeight=FontWeight.Bold,color=Ink,fontSize=16.sp);Text("Tap to retake",color=Coral,fontSize=13.sp,fontWeight=FontWeight.SemiBold)}}}
   else{Column(horizontalAlignment=Alignment.CenterHorizontally){
     Box(Modifier.size(72.dp).clip(CircleShape).background(CoralSoft),contentAlignment=Alignment.Center){Icon(Icons.Default.Face,null,tint=Coral,modifier=Modifier.size(38.dp))}
     Spacer(Modifier.height(10.dp));Text("Take a live selfie",fontWeight=FontWeight.Bold,color=Ink,fontSize=16.sp)
     Text("Face detection guides you · camera only",color=Muted,fontSize=12.sp)}}}
  StepHeader(2,"About you",name.trim().length>1&&dobOk)
  TPTextField("Full name",name,{name=it},KeyboardType.Text)
  TPTextField("Date of birth (YYYY-MM-DD)",dob,{dob=it},KeyboardType.Number)
  StepHeader(3,"Gender",true)
  Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)){listOf("Female","Male","Non-binary","Prefer not to say","Other").forEach{v->val sel=gender==v
   Text(v,fontSize=13.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.clip(RoundedCornerShape(99.dp)).background(if(sel)Lime else Paper).border(1.dp,if(sel)Color.Transparent else Line,RoundedCornerShape(99.dp)).clickable{gender=v}.padding(horizontal=14.dp,vertical=9.dp))}}
  ErrorText(error)
  TPPrimary(if(busy)"Creating your Trace.Pay ID…" else "Create my Trace.Pay ID",busy=busy,enabled=!busy&&name.trim().length>1&&photo!=null&&dobOk){
   busy=true;error="";activityScope(api){try{api.createProfile(name.trim(),dob,gender,photo!!);onDone()}catch(e:Exception){error=e.message?:"Profile creation failed"};busy=false}}
  Row(verticalAlignment=Alignment.CenterVertically){Icon(Icons.Default.Lock,null,tint=Muted,modifier=Modifier.size(13.dp));Spacer(Modifier.width(6.dp));Text("Your selfie is encrypted and only checked for one clear face.",fontSize=11.sp,color=Muted)}
  Spacer(Modifier.height(40.dp))}}

@Composable fun StepHeader(n:Int,title:String,done:Boolean){Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){
 Box(Modifier.size(28.dp).clip(CircleShape).background(if(done)Lime else CoralSoft),contentAlignment=Alignment.Center){if(done)Icon(Icons.Default.Check,null,tint=Ink,modifier=Modifier.size(16.dp)) else Text("$n",fontWeight=FontWeight.ExtraBold,color=Coral)}
 Text(title,fontSize=16.sp,fontWeight=FontWeight.Bold,color=Ink)}}

@Composable fun ShieldCard(level:String,reasons:List<String>){val (tint,fill)=when(level){"stop"->ErrorRed to Color(0xFFFFE2DD);"caution"->Color(0xFF8A5A00) to Color(0xFFFFF1D2);else->Coral to CoralSoft}
 Column(Modifier.fillMaxWidth().background(fill,RoundedCornerShape(22.dp)).padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){
  Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){Icon(Icons.Default.Shield,null,tint=tint);Text(if(level=="stop")"TraceShield · think twice before paying" else "TraceShield",fontWeight=FontWeight.ExtraBold,color=tint,fontSize=14.sp)}
  reasons.forEach{Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Text("•",color=tint,fontWeight=FontWeight.Bold);Text(it,fontSize=13.sp,color=Ink,lineHeight=18.sp)}}
  Text("You decide. Trace.Pay never blocks a payment on its own.",fontSize=11.sp,color=Muted)}}

// ---------------------------------------------------------------------------------------------
// 4.3 main app: home, pay flow, scan / my QR, activity, profile (matches the Play design files)
// ---------------------------------------------------------------------------------------------
enum class MainTab { Home, Pay, Qr, Activity, Profile }
enum class PayStage { Recipient, Amount, Review, Authorising, Result }
data class RiskStyle(val label:String,val headline:String,val icon:ImageVector,val tint:Color,val fill:Color)
private val ErrorRed=Color(0xFFB3261E)

fun riskStyle(level:String)=when(level.lowercase()){
 "review"->RiskStyle("REVIEW","Two or more pattern reasons showed up.",Icons.Default.Report,ErrorRed,Color(0xFFFFE2DD))
 "caution"->RiskStyle("CAUTION","One pattern reason showed up.",Icons.Default.Warning,Color(0xFF8A5A00),CoralSoft)
 "no_known_warning"->RiskStyle("NO KNOWN WARNING","No configured pattern showed up.",Icons.Default.VerifiedUser,Green,Mint)
 else->RiskStyle("NOT ENOUGH RECORDS","Trace.Pay has too few records to assess this recipient.",Icons.Default.HelpOutline,Muted,CoralSoft)}

fun initials(vpa:String):String{val parts=vpa.substringBefore("@").split('.','_','-').filter{it.isNotEmpty()};return if(parts.isEmpty())"TP" else parts.take(2).map{it.first().uppercaseChar()}.joinToString("")}
fun keypadPress(value:String,k:String):String{
 if(k=="⌫")return value.dropLast(1)
 if(k==".")return if(value.contains("."))value else if(value.isEmpty())"0." else "$value."
 val dot=value.indexOf('.')
 if(dot>=0&&value.length-dot>2)return value      // two decimals max
 if(dot<0&&value.length>=6)return value
 return if(value=="0")k else value+k}
fun copyText(ctx:Context,text:String){(ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Trace.Pay ID",text))}
fun shareText(ctx:Context,text:String){ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply{type="text/plain";putExtra(Intent.EXTRA_TEXT,text)},"Share Trace.Pay ID"))}
fun qrBitmap(text:String,size:Int):Bitmap{
 val m=com.google.zxing.qrcode.QRCodeWriter().encode(text,com.google.zxing.BarcodeFormat.QR_CODE,size,size,mapOf(com.google.zxing.EncodeHintType.MARGIN to 1))
 val ink=0xFF14092E.toInt();val white=0xFFFFFFFF.toInt();val px=IntArray(size*size)
 for(y in 0 until size)for(x in 0 until size)px[y*size+x]=if(m.get(x,y))ink else white
 return Bitmap.createBitmap(px,size,size,Bitmap.Config.ARGB_8888)}
fun shortTime(iso:String):String=try{java.time.OffsetDateTime.parse(iso).atZoneSameInstant(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("h:mm a"))}catch(_:Exception){"now"}

@Composable fun TPCard(modifier:Modifier=Modifier,fill:Color=Paper,content:@Composable ColumnScope.()->Unit){Column(modifier.fillMaxWidth().background(fill,RoundedCornerShape(24.dp)).then(if(fill==Paper)Modifier.border(1.dp,Line,RoundedCornerShape(24.dp)) else Modifier).padding(16.dp),content=content)}
@Composable fun TPChip(text:String,fill:Color=Lime,onClick:(()->Unit)?=null){Text(text,fontSize=11.sp,fontWeight=FontWeight.ExtraBold,color=Ink,modifier=Modifier.clip(RoundedCornerShape(99.dp)).background(fill).then(if(onClick!=null)Modifier.clickable{onClick()} else Modifier).padding(horizontal=12.dp,vertical=7.dp))}
@Composable fun BackHeader(chip:String?=null,chipFill:Color=Lime,onBack:()->Unit){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Text("‹ Back",fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.clip(RoundedCornerShape(10.dp)).clickable{onBack()}.padding(vertical=6.dp,horizontal=2.dp));Spacer(Modifier.weight(1f));if(chip!=null)TPChip(chip,chipFill)}}
@Composable fun TPPrimary(text:String,modifier:Modifier=Modifier,busy:Boolean=false,enabled:Boolean=true,fill:Color=Coral,textColor:Color=Color.White,onClick:()->Unit){Button(onClick=onClick,enabled=enabled&&!busy,colors=ButtonDefaults.buttonColors(containerColor=fill,contentColor=textColor,disabledContainerColor=fill.copy(alpha=.45f),disabledContentColor=textColor.copy(alpha=.85f)),shape=RoundedCornerShape(20.dp),modifier=modifier.fillMaxWidth().height(56.dp)){if(busy){CircularProgressIndicator(Modifier.size(18.dp),color=textColor,strokeWidth=2.dp);Spacer(Modifier.width(8.dp))};Text(text,fontSize=16.sp,fontWeight=FontWeight.Bold)}}
@Composable fun TPSecondary(text:String,modifier:Modifier=Modifier,textColor:Color=Ink,onClick:()->Unit){OutlinedButton(onClick=onClick,border=BorderStroke(1.dp,Line),colors=ButtonDefaults.outlinedButtonColors(containerColor=Paper,contentColor=textColor),shape=RoundedCornerShape(20.dp),modifier=modifier.fillMaxWidth().height(56.dp)){Text(text,fontSize=16.sp,fontWeight=FontWeight.Bold)}}
@Composable fun ErrorText(msg:String){if(msg.isNotBlank())Text(msg,fontSize=13.sp,fontWeight=FontWeight.SemiBold,color=ErrorRed,lineHeight=18.sp,modifier=Modifier.fillMaxWidth().background(Color(0xFFFFE2DD),RoundedCornerShape(16.dp)).padding(12.dp))}
@Composable fun StatTile(value:String,label:String,modifier:Modifier=Modifier){Column(modifier.background(Paper,RoundedCornerShape(18.dp)).border(1.dp,Line,RoundedCornerShape(18.dp)).padding(12.dp)){Text(value,fontSize=16.sp,fontWeight=FontWeight.ExtraBold,color=Ink,maxLines=1);Text(label,fontSize=11.sp,color=Muted)}}
@Composable fun InfoLine(title:String,value:String){Row(Modifier.fillMaxWidth().padding(vertical=10.dp)){Text(title,fontSize=13.sp,color=Muted,modifier=Modifier.weight(1f));Text(value,fontSize=13.sp,fontWeight=FontWeight.SemiBold,color=Ink)}}

@Composable fun SessionChip(api:TraceApi){
 var now by remember{mutableStateOf(System.currentTimeMillis())}
 LaunchedEffect(Unit){while(true){kotlinx.coroutines.delay(1000);now=System.currentTimeMillis();val left=(api.tokenExpiryMillis()?:now)-now;if(left in 1..299_999&&(left/1000)%30==0L)api.refreshIfNeeded()}}
 val left=(((api.tokenExpiryMillis()?:now)-now)/1000).coerceAtLeast(0)
 Text("Session %02d:%02d".format(left/60,left%60),fontSize=11.sp,fontWeight=FontWeight.Bold,color=if(left<120)ErrorRed else Ink,modifier=Modifier.background(CoralSoft,RoundedCornerShape(99.dp)).padding(horizontal=11.dp,vertical=8.dp))}

@Composable fun ExpiredBanner(modifier:Modifier=Modifier,onDismiss:()->Unit){Row(modifier.padding(16.dp).statusBarsPadding().fillMaxWidth().background(Paper,RoundedCornerShape(20.dp)).border(1.dp,Line,RoundedCornerShape(20.dp)).padding(14.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){Icon(Icons.Default.Schedule,null,tint=Coral);Column(Modifier.weight(1f)){Text("Your session ended",fontSize=14.sp,fontWeight=FontWeight.Bold,color=Ink);Text("For your security, sign in again to continue.",fontSize=12.sp,color=Muted)};Icon(Icons.Default.Close,"Dismiss",tint=Muted,modifier=Modifier.clip(CircleShape).clickable{onDismiss()}.padding(4.dp))}}

@Composable fun MainScreen(api:TraceApi,activity:MainActivity,profile:Profile,onLogout:()->Unit){
 var tab by remember{mutableStateOf(MainTab.Home)}
 var qrMode by remember{mutableStateOf(0)}
 var prefill by remember{mutableStateOf("")}
 var wallet by remember{mutableStateOf<Wallet?>(null)}
 var transfers by remember{mutableStateOf<List<Transfer>>(emptyList())}
 val scope=rememberCoroutineScope()
 val refresh:()->Unit={scope.launch{wallet=try{api.wallet()}catch(_:Exception){wallet};transfers=try{api.transfers()}catch(_:Exception){transfers};api.refreshIfNeeded()}}
 LaunchedEffect(tab){refresh()}
 Box(Modifier.fillMaxSize().background(Ivory).statusBarsPadding()){
  AnimatedContent(targetState=tab,label="tabs"){t->when(t){
   MainTab.Home->HomeScreen(api,profile,wallet,transfers,onNavigate={tab=it},onQrMode={qrMode=it},onPay={prefill=it;tab=MainTab.Pay})
   MainTab.Pay->PayFlow(api,activity,profile,wallet,prefill,onConsumePrefill={prefill=""},onNavigate={tab=it},onQrMode={qrMode=it},refresh=refresh)
   MainTab.Qr->ScanQrScreen(activity,profile,qrMode,onMode={qrMode=it},onNavigate={tab=it},onPay={prefill=it;tab=MainTab.Pay})
   MainTab.Activity->ActivityScreen(profile,transfers)
   MainTab.Profile->ProfileMain(profile,api.email(),onShowQr={qrMode=1;tab=MainTab.Qr},onLogout=onLogout)}}
  if(tab!=MainTab.Pay&&!(tab==MainTab.Qr&&qrMode==0))TPTabBar(tab,{tab=it},Modifier.align(Alignment.BottomCenter))}}

@Composable fun HomeTile(title:String,icon:ImageVector,fill:Color,modifier:Modifier=Modifier,onClick:()->Unit){Column(modifier.clip(RoundedCornerShape(16.dp)).clickable{onClick()},horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.size(60.dp).clip(RoundedCornerShape(20.dp)).background(fill).then(if(fill==Paper)Modifier.border(1.dp,Line,RoundedCornerShape(20.dp)) else Modifier),contentAlignment=Alignment.Center){Icon(icon,null,tint=Ink)};Text(title,fontSize=12.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.padding(top=7.dp))}}

@Composable fun BalanceCard(balance:String?,hidden:Boolean,toggle:()->Unit){Box(Modifier.fillMaxWidth().height(150.dp).clip(RoundedCornerShape(28.dp)).background(Brush.linearGradient(listOf(Coral,Color(0xFF7B57FF))))){
 Box(Modifier.size(190.dp).offset(x=170.dp,y=(-40).dp).clip(CircleShape).background(Color(0xFF8F6BFF).copy(alpha=.55f)))
 Box(Modifier.size(110.dp).offset(x=280.dp,y=80.dp).clip(CircleShape).background(Lime))
 Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){
  Row(verticalAlignment=Alignment.CenterVertically){Text("TRACE.PAY BALANCE",fontSize=11.sp,fontWeight=FontWeight.ExtraBold,color=Color.White.copy(alpha=.9f),letterSpacing=1.sp,modifier=Modifier.weight(1f));Text(if(hidden)"SHOW" else "HIDE",fontSize=10.sp,fontWeight=FontWeight.ExtraBold,color=Ink,modifier=Modifier.clip(RoundedCornerShape(99.dp)).background(Color.White.copy(alpha=.9f)).clickable{toggle()}.padding(horizontal=10.dp,vertical=5.dp))}
  Text(if(hidden)"₹ •••••" else money(balance),fontSize=36.sp,fontWeight=FontWeight.ExtraBold,color=Color.White,maxLines=1)
  Text("Available in your Trace.Pay wallet",fontSize=11.sp,color=Color.White.copy(alpha=.8f))}}}

@Composable fun TransferRow(t:Transfer,me:String){val incoming=t.receiver_vpa==me&&t.sender_vpa!=me;val ok=t.status=="SUCCESS"
 Row(Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(20.dp)).border(1.dp,Line,RoundedCornerShape(20.dp)).padding(12.dp),verticalAlignment=Alignment.CenterVertically){
  Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(CoralSoft),contentAlignment=Alignment.Center){Icon(if(incoming)Icons.Default.SouthWest else Icons.Default.NorthEast,null,tint=Coral)}
  Column(Modifier.weight(1f).padding(start=12.dp)){Text(if(incoming)t.sender_vpa else t.receiver_vpa,fontSize=14.sp,fontWeight=FontWeight.Bold,color=Ink,maxLines=1);Text("${t.transfer_ref} · ${if(incoming)"Received" else "Sent"}",fontSize=11.sp,color=Muted)}
  Column(horizontalAlignment=Alignment.End){Text((if(incoming)"+" else "")+money(t.amount),fontSize=14.sp,fontWeight=FontWeight.ExtraBold,color=Ink);Text(t.status,fontSize=9.sp,fontWeight=FontWeight.ExtraBold,color=if(ok)Green else Muted,modifier=Modifier.padding(top=4.dp).background(if(ok)Lime else CoralSoft,RoundedCornerShape(99.dp)).padding(horizontal=8.dp,vertical=4.dp))}}}

@Composable fun HomeScreen(api:TraceApi,profile:Profile,wallet:Wallet?,transfers:List<Transfer>,onNavigate:(MainTab)->Unit,onQrMode:(Int)->Unit,onPay:(String)->Unit){
 val ctx=LocalContext.current
 var hidden by remember{mutableStateOf(false)}
 var copied by remember{mutableStateOf(false)}
 LaunchedEffect(copied){if(copied){kotlinx.coroutines.delay(1600);copied=false}}
 val hour=remember{Calendar.getInstance().get(Calendar.HOUR_OF_DAY)}
 val greeting=if(hour<12)"Good morning" else if(hour<17)"Good afternoon" else "Good evening"
 val payees=remember(transfers){transfers.filter{it.sender_vpa==profile.vpa_id&&it.status=="SUCCESS"}.map{it.receiver_vpa}.distinct().take(6)}
 Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=18.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){
  Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){
   Image(painterResource(R.drawable.tracepay_mark),null,Modifier.size(50.dp).clip(RoundedCornerShape(14.dp)))
   Column(Modifier.weight(1f)){Text(greeting,fontSize=12.sp,color=Muted);Text(profile.full_name,fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Ink,maxLines=1)}
   SessionChip(api)}
  BalanceCard(wallet?.balance,hidden){hidden=!hidden}
  Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){
   HomeTile("Pay",Icons.Default.ArrowForward,Paper,Modifier.weight(1f)){onPay("")}
   HomeTile("Scan",Icons.Default.QrCodeScanner,Lime,Modifier.weight(1f)){onQrMode(0);onNavigate(MainTab.Qr)}
   HomeTile("My QR",Icons.Default.QrCode,CoralSoft,Modifier.weight(1f)){onQrMode(1);onNavigate(MainTab.Qr)}
   HomeTile("Activity",Icons.Default.ShowChart,Paper,Modifier.weight(1f)){onNavigate(MainTab.Activity)}}
  TPCard{Row(verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text("YOUR TRACE.PAY ID",fontSize=10.sp,fontWeight=FontWeight.ExtraBold,color=Muted,letterSpacing=1.sp);Text(profile.vpa_id,fontSize=17.sp,fontWeight=FontWeight.ExtraBold,color=Ink,maxLines=1)};TPChip(if(copied)"Copied" else "Copy ID"){copyText(ctx,profile.vpa_id);copied=true}}}
  TPCard{Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){Box(Modifier.size(44.dp).clip(CircleShape).background(Lime),contentAlignment=Alignment.Center){Icon(Icons.Default.VerifiedUser,null,tint=Ink)};Column(Modifier.weight(1f)){Text("Risk check before every payment",fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink);Text("rules-v1 · an advisory from the records Trace.Pay can see, not proof of fraud",fontSize=11.sp,color=Muted,lineHeight=15.sp)}}}
  TPCard{Text("How a payment works",fontSize=16.sp,fontWeight=FontWeight.Bold,color=Ink);Spacer(Modifier.height(12.dp))
   Row{listOf(Icons.Default.Person to "Recipient",Icons.Default.Warning to "Risk review",Icons.Default.Fingerprint to "Biometric",Icons.Default.VerifiedUser to "Ledger").forEach{(icon,label)->Column(Modifier.weight(1f),horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.size(42.dp).clip(CircleShape).background(CoralSoft),contentAlignment=Alignment.Center){Icon(icon,null,tint=Coral,modifier=Modifier.size(20.dp))};Text(label,fontSize=10.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.padding(top=6.dp))}}}
   Text("Only completed payments move money. Failed attempts never do.",fontSize=11.sp,color=Muted,lineHeight=15.sp,modifier=Modifier.padding(top=12.dp))}
  if(payees.isNotEmpty()){
   Row(verticalAlignment=Alignment.CenterVertically){Text("Pay again",fontSize=18.sp,fontWeight=FontWeight.ExtraBold,color=Ink,modifier=Modifier.weight(1f));Text("Tap to pay",fontSize=11.sp,color=Muted)}
   Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(14.dp)){payees.forEachIndexed{i,vpa->Column(Modifier.width(64.dp).clip(RoundedCornerShape(14.dp)).clickable{onPay(vpa)},horizontalAlignment=Alignment.CenterHorizontally){Box(Modifier.size(54.dp).clip(CircleShape).background(if(i%2==1)Lime else CoralSoft),contentAlignment=Alignment.Center){Text(initials(vpa),fontSize=15.sp,fontWeight=FontWeight.ExtraBold,color=Ink)};Text(vpa.substringBefore("@"),fontSize=10.sp,fontWeight=FontWeight.SemiBold,color=Ink,maxLines=1,modifier=Modifier.padding(top=6.dp))}}}}
  Row(verticalAlignment=Alignment.CenterVertically){Text("Recent",fontSize=18.sp,fontWeight=FontWeight.ExtraBold,color=Ink,modifier=Modifier.weight(1f));Text("See all",fontSize=12.sp,fontWeight=FontWeight.Bold,color=Coral,modifier=Modifier.clip(RoundedCornerShape(8.dp)).clickable{onNavigate(MainTab.Activity)}.padding(4.dp))}
  if(transfers.isEmpty())EmptyState("No transfers yet","Your Trace.Pay payments will appear here.") else transfers.take(3).forEach{TransferRow(it,profile.vpa_id)}
  Spacer(Modifier.height(100.dp))}}

@Composable fun Keypad(value:String,onChange:(String)->Unit){val keys=listOf("1","2","3","4","5","6","7","8","9",".","0","⌫")
 Column(verticalArrangement=Arrangement.spacedBy(10.dp)){keys.chunked(3).forEach{row->Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){row.forEach{k->Box(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(18.dp)).background(Paper).border(1.dp,Line,RoundedCornerShape(18.dp)).clickable{onChange(keypadPress(value,k))},contentAlignment=Alignment.Center){if(k=="⌫")Icon(Icons.Default.Backspace,"Delete",tint=Ink) else Text(k,fontSize=24.sp,fontWeight=FontWeight.Bold,color=Ink)}}}}}}

@Composable fun PayFlow(api:TraceApi,activity:MainActivity,profile:Profile,wallet:Wallet?,prefill:String,onConsumePrefill:()->Unit,onNavigate:(MainTab)->Unit,onQrMode:(Int)->Unit,refresh:()->Unit){
 val scope=rememberCoroutineScope()
 var stage by remember{mutableStateOf(PayStage.Recipient)}
 var input by remember{mutableStateOf("")}
 var recipientVpa by remember{mutableStateOf("")}
 var recipientName by remember{mutableStateOf("")}
 var amount by remember{mutableStateOf("")}
 var risk by remember{mutableStateOf<Risk?>(null)}
 var result by remember{mutableStateOf<Transfer?>(null)}
 var message by remember{mutableStateOf("")}
 var busy by remember{mutableStateOf(false)}
 // One key per payment attempt; reused on retry so a dropped connection can never pay twice.
 var attemptKey by remember{mutableStateOf(UUID.randomUUID().toString())}
 fun reset(home:Boolean){stage=PayStage.Recipient;input="";recipientVpa="";recipientName="";amount="";risk=null;result=null;message="";busy=false;attemptKey=UUID.randomUUID().toString();if(home)onNavigate(MainTab.Home)}
 fun find(){val id=normalizeTracePayId(input);if(id==null){message="Trace.Pay IDs look like name@tracepay. Other UPI handles are not Trace.Pay accounts.";return}
  if(id==profile.vpa_id){message="That's your own Trace.Pay ID. Choose someone else.";return}
  busy=true;message="";scope.launch{try{recipientName=api.recipient(id);recipientVpa=id;input=id;amount="";stage=PayStage.Amount}catch(e:Exception){message=e.message?:"Recipient not found"};busy=false}}
 fun check(){val v=amount.toBigDecimalOrNull()?:BigDecimal.ZERO;val bal=wallet?.balance?.toBigDecimalOrNull()
  if(v>BigDecimal("100000")){message="Each payment is limited to ₹1,00,000.";return}
  if(bal!=null&&v>bal){message="That's more than your Trace.Pay balance of ${money(wallet?.balance)}.";return}
  busy=true;message="";scope.launch{try{risk=api.risk(recipientVpa,amount);attemptKey=UUID.randomUUID().toString();stage=PayStage.Review}catch(e:Exception){message=e.message?:"Could not assess recipient"};busy=false}}
 fun submit(){busy=true;scope.launch{try{val t=api.transfer(recipientVpa,amount,"",attemptKey);attemptKey=UUID.randomUUID().toString();result=t;stage=PayStage.Result;refresh()}catch(e:Exception){message="${e.message?:"Network error."} The payment was not confirmed; retrying is safe.";stage=PayStage.Review};busy=false}}
 fun authorise(){message="";stage=PayStage.Authorising;activity.biometric(onSuccess={submit()},onError={err->message=err;stage=PayStage.Review})}
 LaunchedEffect(prefill){if(prefill.isNotBlank()){input=prefill;onConsumePrefill();find()}}
 Column(Modifier.fillMaxSize().background(Ivory).padding(horizontal=18.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
  when(stage){
   PayStage.Recipient->{
    BackHeader("SECURE"){reset(true)}
    Text("Who are you paying?",fontSize=32.sp,fontWeight=FontWeight.ExtraBold,color=Ink,lineHeight=36.sp)
    Text("Enter their Trace.Pay ID. Every Trace.Pay ID ends in @tracepay.",fontSize=13.sp,color=Muted)
    OutlinedTextField(input,{input=it;message=""},singleLine=true,placeholder={Text("name")},suffix={if(!input.contains("@"))Text("@tracepay",color=Muted)},keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=KeyboardType.Email),colors=OutlinedTextFieldDefaults.colors(focusedBorderColor=Coral,unfocusedBorderColor=Line,focusedContainerColor=Paper,unfocusedContainerColor=Paper),shape=RoundedCornerShape(18.dp),textStyle=TextStyle(fontSize=17.sp,fontWeight=FontWeight.SemiBold),modifier=Modifier.fillMaxWidth())
    Text("Scan a Trace.Pay QR instead",fontSize=14.sp,fontWeight=FontWeight.Bold,color=Coral,modifier=Modifier.clip(RoundedCornerShape(8.dp)).clickable{onQrMode(0);onNavigate(MainTab.Qr)}.padding(4.dp))
    ErrorText(message)
    Spacer(Modifier.weight(1f))
    TPPrimary("Find recipient",busy=busy,enabled=input.isNotBlank()){find()}}
   PayStage.Amount->{
    BackHeader("SECURE"){message="";stage=PayStage.Recipient}
    Text("To: $recipientName · $recipientVpa",fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink,maxLines=1,modifier=Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(18.dp)).border(1.dp,Line,RoundedCornerShape(18.dp)).padding(horizontal=16.dp,vertical=15.dp))
    Column(Modifier.fillMaxWidth(),horizontalAlignment=Alignment.CenterHorizontally){Text("HOW MUCH?",fontSize=11.sp,fontWeight=FontWeight.ExtraBold,color=Muted,letterSpacing=1.sp);Text("₹"+amount.ifEmpty{"0"},fontSize=60.sp,fontWeight=FontWeight.ExtraBold,color=Coral,maxLines=1);Text("Balance ${money(wallet?.balance)} · limit ₹1,00,000",fontSize=12.sp,color=Muted)}
    Keypad(amount){amount=it;message=""}
    ErrorText(message)
    Spacer(Modifier.weight(1f))
    TPPrimary("Check recipient",busy=busy,enabled=(amount.toBigDecimalOrNull()?:BigDecimal.ZERO)>BigDecimal.ZERO){check()}}
   PayStage.Review->{
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(14.dp)){
     BackHeader("RISK REVIEW",CoralSoft){message="";stage=PayStage.Amount}
     risk?.let{r->val s=riskStyle(r.level)
      if(r.shieldReasons.isNotEmpty())ShieldCard(r.shieldLevel,r.shieldReasons)
      Column(Modifier.fillMaxWidth().background(s.fill,RoundedCornerShape(24.dp)).padding(18.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){Icon(s.icon,null,tint=s.tint,modifier=Modifier.size(18.dp));Text(s.label,fontSize=13.sp,fontWeight=FontWeight.ExtraBold,color=s.tint)};Text(s.headline,fontSize=27.sp,fontWeight=FontWeight.ExtraBold,color=Ink,lineHeight=31.sp)}
      TPCard{Text("Why this category",fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink);r.reasons.forEach{Text(it,fontSize=13.sp,color=Ink,lineHeight=18.sp,modifier=Modifier.padding(top=8.dp))}}
      Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){StatTile("${r.observed_transaction_count}","Records",Modifier.weight(1f));StatTile(r.rule_version,"Rule",Modifier.weight(1f));StatTile(shortTime(r.data_as_of),"As of",Modifier.weight(1f))}
      Text(r.disclaimer,fontSize=11.sp,color=Muted,lineHeight=15.sp)
      TPCard{Row(verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text("Paying",fontSize=11.sp,color=Muted);Text(recipientName,fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink);Text(recipientVpa,fontSize=11.sp,color=Muted)};Text(money(amount),fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Coral)}}}
     ErrorText(message)}
    TPSecondary("Cancel"){reset(true)}
    if(message==NO_SCREEN_LOCK_MESSAGE)TPSecondary("Open screen lock settings"){activity.openScreenLockSettings()}
    TPPrimary("Confirm with fingerprint or screen lock"){authorise()}}
   PayStage.Authorising->{
    Row{TPChip("CONFIRM")}
    Spacer(Modifier.weight(1f))
    val spin by rememberInfiniteTransition(label="ring").animateFloat(0f,360f,infiniteRepeatable(tween(1400,easing=LinearEasing)),label="spin")
    Box(Modifier.fillMaxWidth(),contentAlignment=Alignment.Center){Box(Modifier.size(190.dp).clip(CircleShape).background(Paper),contentAlignment=Alignment.Center){Icon(Icons.Default.Fingerprint,null,tint=Ink,modifier=Modifier.size(64.dp))};CircularProgressIndicator(progress={0.22f},modifier=Modifier.size(190.dp).rotate(spin),color=Coral,strokeWidth=4.dp,trackColor=Color.Transparent)}
    Text(if(busy)"Confirming with Trace.Pay…" else "Confirm on your phone",fontSize=26.sp,fontWeight=FontWeight.ExtraBold,color=Ink,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())
    Text("Use your fingerprint, face or phone PIN to send ${money(amount)} to $recipientName",fontSize=13.sp,color=Muted,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())
    Spacer(Modifier.weight(1f))}
   PayStage.Result->{
    val ok=result?.status=="SUCCESS"
    Spacer(Modifier.weight(1f))
    Box(Modifier.size(150.dp).clip(CircleShape).background(if(ok)Lime else CoralSoft).align(Alignment.CenterHorizontally),contentAlignment=Alignment.Center){Icon(if(ok)Icons.Default.Check else Icons.Default.Close,null,tint=Ink,modifier=Modifier.size(64.dp))}
    Text(if(ok)"Sent ${money(result?.amount)}" else "Payment not completed",fontSize=30.sp,fontWeight=FontWeight.ExtraBold,color=Ink,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())
    Text(if(ok)"to $recipientName · $recipientVpa" else (result?.failure_reason?.ifBlank{null}?:"The transfer failed."),fontSize=14.sp,color=Muted,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())
    Text(result?.transfer_ref?:"",fontSize=13.sp,fontWeight=FontWeight.Bold,fontFamily=FontFamily.Monospace,color=Ink,modifier=Modifier.align(Alignment.CenterHorizontally).background(Paper,RoundedCornerShape(99.dp)).border(1.dp,Line,RoundedCornerShape(99.dp)).padding(horizontal=14.dp,vertical=8.dp))
    Text(if(ok)"Payment complete. Both sides of the Trace.Pay ledger were updated." else "No ledger value was moved.",fontSize=12.sp,color=Muted,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())
    Spacer(Modifier.weight(1f))
    if(ok){TPPrimary("Back home"){reset(true)};TPSecondary("View activity"){reset(false);onNavigate(MainTab.Activity)}}
    else{TPPrimary("Try again"){message="";result=null;stage=PayStage.Amount};TPSecondary("Back home"){reset(true)}}}}}}

@Composable fun ScanQrScreen(activity:MainActivity,profile:Profile,mode:Int,onMode:(Int)->Unit,onNavigate:(MainTab)->Unit,onPay:(String)->Unit){
 val ctx=LocalContext.current
 var message by remember{mutableStateOf("")}
 var copied by remember{mutableStateOf(false)}
 LaunchedEffect(copied){if(copied){kotlinx.coroutines.delay(1600);copied=false}}
 val payload=remember(profile.vpa_id){"tracepay://pay?pa=${profile.vpa_id}&pn=${Uri.encode(profile.full_name)}"}
 val qr=remember(payload){qrBitmap(payload,720)}
 val line by rememberInfiniteTransition(label="scan").animateFloat(-100f,100f,infiniteRepeatable(tween(1800),RepeatMode.Reverse),label="line")
 if(mode==0){QrCameraScreen(onCode={raw->val id=normalizeTracePayId(raw);if(id!=null){onPay(id);null}else "That QR is not a Trace.Pay ID."},onClose={onNavigate(MainTab.Home)},onMyQr={onMode(1)});return}
 fun startScan(){scan(activity,onResult={raw->val id=normalizeTracePayId(raw);if(id!=null){message="";onPay(id)}else{message="That QR is not a Trace.Pay ID. Trace.Pay only pays name@tracepay accounts."}},onError={message=it})}
 Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=18.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
  BackHeader("TRACE.PAY QR"){onNavigate(MainTab.Home)}
  Row(Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(18.dp)).border(1.dp,Line,RoundedCornerShape(18.dp)).padding(4.dp)){listOf("Scan","My QR").forEachIndexed{i,label->Box(Modifier.weight(1f).height(42.dp).clip(RoundedCornerShape(14.dp)).background(if(mode==i)Coral else Color.Transparent).clickable{onMode(i);message=""},contentAlignment=Alignment.Center){Text(label,fontSize=15.sp,fontWeight=FontWeight.Bold,color=if(mode==i)Color.White else Ink)}}}
  if(mode==0){
   Box(Modifier.fillMaxWidth().height(300.dp).clip(RoundedCornerShape(28.dp)).background(Coral).clickable{startScan()},contentAlignment=Alignment.Center){
    Canvas(Modifier.fillMaxSize().padding(28.dp)){val l=36.dp.toPx();val w=6.dp.toPx();val c=Lime;val sw=size.width;val sh=size.height
     drawLine(c,Offset(0f,l),Offset(0f,0f),w,StrokeCap.Round);drawLine(c,Offset(0f,0f),Offset(l,0f),w,StrokeCap.Round)
     drawLine(c,Offset(sw-l,0f),Offset(sw,0f),w,StrokeCap.Round);drawLine(c,Offset(sw,0f),Offset(sw,l),w,StrokeCap.Round)
     drawLine(c,Offset(sw,sh-l),Offset(sw,sh),w,StrokeCap.Round);drawLine(c,Offset(sw,sh),Offset(sw-l,sh),w,StrokeCap.Round)
     drawLine(c,Offset(l,sh),Offset(0f,sh),w,StrokeCap.Round);drawLine(c,Offset(0f,sh),Offset(0f,sh-l),w,StrokeCap.Round)}
    Box(Modifier.fillMaxWidth().padding(horizontal=44.dp).height(3.dp).offset(y=line.dp).background(Lime))
    Text("Tap to open the camera",fontSize=14.sp,fontWeight=FontWeight.Bold,color=Color.White,modifier=Modifier.align(Alignment.BottomCenter).padding(bottom=40.dp))}
   Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){TPSecondary("Open camera",Modifier.weight(1f)){startScan()};TPPrimary("Enter ID",Modifier.weight(1f),fill=Lime,textColor=Ink){onPay("")}}
  } else {
   Column(Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(28.dp)).border(1.dp,Line,RoundedCornerShape(28.dp)).padding(20.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(10.dp)){
    Image(qr.asImageBitmap(),"QR code for ${profile.vpa_id}",Modifier.size(238.dp).background(Color.White,RoundedCornerShape(22.dp)).border(4.dp,Lime,RoundedCornerShape(22.dp)).padding(14.dp),filterQuality=FilterQuality.None)
    Text(profile.full_name,fontSize=22.sp,fontWeight=FontWeight.ExtraBold,color=Ink)
    Text(profile.vpa_id,fontSize=14.sp,fontWeight=FontWeight.SemiBold,color=Muted)
    TPChip(if(copied)"Copied" else "Copy ID",CoralSoft){copyText(ctx,profile.vpa_id);copied=true}}
   TPPrimary("Share my Trace.Pay ID",fill=Lime,textColor=Ink){shareText(ctx,"Pay me on Trace.Pay: ${profile.vpa_id}")}
   Text("Share this code to receive payments to your Trace.Pay ID.",fontSize=12.sp,color=Muted,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth())}
  ErrorText(message)
  Spacer(Modifier.height(100.dp))}}

@Composable fun ActivityScreen(profile:Profile,transfers:List<Transfer>){
 var filter by remember{mutableStateOf(0)}
 val filters=listOf("All","Sent","Received","Failed");val me=profile.vpa_id
 val items=when(filter){1->transfers.filter{it.sender_vpa==me&&it.status=="SUCCESS"};2->transfers.filter{it.receiver_vpa==me&&it.sender_vpa!=me};3->transfers.filter{it.status!="SUCCESS"};else->transfers}
 Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=18.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
  Text("Activity",fontSize=34.sp,fontWeight=FontWeight.ExtraBold,color=Ink)
  Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)){filters.forEachIndexed{i,f->Text(f,fontSize=13.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.clip(RoundedCornerShape(99.dp)).background(if(filter==i)Lime else Paper).border(1.dp,if(filter==i)Color.Transparent else Line,RoundedCornerShape(99.dp)).clickable{filter=i}.padding(horizontal=14.dp,vertical=9.dp))}}
  if(items.isEmpty())EmptyState(if(filter==0)"Nothing here yet" else "No ${filters[filter].lowercase()} transfers","Payments you send or receive appear here.") else items.forEach{TransferRow(it,me)}
  Spacer(Modifier.height(100.dp))}}

@Composable fun LockedSetting(title:String,detail:String){Row(Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(20.dp)).border(1.dp,Line,RoundedCornerShape(20.dp)).padding(14.dp),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(title,fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink);Text(detail,fontSize=12.sp,color=Muted)};Row(Modifier.background(Mint,RoundedCornerShape(99.dp)).padding(horizontal=10.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(4.dp)){Icon(Icons.Default.Lock,null,tint=Green,modifier=Modifier.size(12.dp));Text("Always on",fontSize=11.sp,fontWeight=FontWeight.ExtraBold,color=Green)}}}

@Composable fun ProfileMain(profile:Profile,email:String,onShowQr:()->Unit,onLogout:()->Unit){
 var confirm by remember{mutableStateOf(false)}
 Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=18.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
  Text("Profile",fontSize=34.sp,fontWeight=FontWeight.ExtraBold,color=Ink)
  Row(Modifier.fillMaxWidth().background(Brush.linearGradient(listOf(Coral,Color(0xFF7B57FF))),RoundedCornerShape(26.dp)).padding(18.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)){Image(painterResource(R.drawable.tracepay_mark),null,Modifier.size(56.dp).clip(RoundedCornerShape(16.dp)));Column{Text(profile.full_name,fontSize=20.sp,fontWeight=FontWeight.ExtraBold,color=Color.White);Text(profile.vpa_id,fontSize=13.sp,fontWeight=FontWeight.SemiBold,color=Color.White.copy(alpha=.85f))}}
  Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Paper).border(1.dp,Line,RoundedCornerShape(20.dp)).clickable{onShowQr()}.padding(14.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)){Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(CoralSoft),contentAlignment=Alignment.Center){Icon(Icons.Default.QrCode,null,tint=Ink)};Text("My QR code",fontSize=15.sp,fontWeight=FontWeight.Bold,color=Ink,modifier=Modifier.weight(1f));Text("Receive",fontSize=12.sp,color=Muted)}
  LockedSetting("Phone lock for payments","Fingerprint, face or screen lock, every payment")
  LockedSetting("Risk review before paying","Shown before every payment")
  TPCard{InfoLine("Gender",profile.gender);HorizontalDivider(color=Line);InfoLine("Face check",profile.selfie_status.replace('_',' '));HorizontalDivider(color=Line);InfoLine("Account",email.ifBlank{"—"});HorizontalDivider(color=Line);InfoLine("Wallet","Trace.Pay wallet")}
  Info("We never ask for your UPI PIN","Trace.Pay never collects a UPI PIN, OTP or bank password. Your fingerprint, face and screen lock stay on your phone.")
  TPSecondary("Log out",textColor=ErrorRed){confirm=true}
  Spacer(Modifier.height(100.dp))}
 if(confirm)AlertDialog(onDismissRequest={confirm=false},title={Text("Log out of Trace.Pay on this phone?")},confirmButton={TextButton(onClick={confirm=false;onLogout()}){Text("Log out",color=ErrorRed)}},dismissButton={TextButton(onClick={confirm=false}){Text("Cancel")}})}

@Composable fun TPTabBar(tab:MainTab,onSelect:(MainTab)->Unit,modifier:Modifier=Modifier){
 val items=listOf(Triple(MainTab.Home,Icons.Default.Home,"Home"),Triple(MainTab.Pay,Icons.Default.ArrowForward,"Pay"),Triple(MainTab.Qr,Icons.Default.QrCodeScanner,"Scan QR"),Triple(MainTab.Activity,Icons.Default.ShowChart,"Activity"),Triple(MainTab.Profile,Icons.Default.Person,"Profile"))
 Row(modifier.navigationBarsPadding().padding(horizontal=14.dp,vertical=8.dp).fillMaxWidth().shadow(18.dp,RoundedCornerShape(99.dp),ambientColor=Coral,spotColor=Coral).background(Paper,RoundedCornerShape(99.dp)).border(1.dp,Line,RoundedCornerShape(99.dp)).padding(6.dp)){
  items.forEach{(t,icon,label)->val sel=tab==t
   Box(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(99.dp)).clickable{onSelect(t)},contentAlignment=Alignment.Center){
    if(sel)Box(Modifier.size(54.dp).clip(CircleShape).background(Lime))
    Column(horizontalAlignment=Alignment.CenterHorizontally){Icon(icon,label,tint=Ink,modifier=Modifier.size(20.dp));Text(label,fontSize=10.sp,fontWeight=FontWeight.Bold,color=Ink)}}}}}

@Composable fun Info(title:String,text:String){Row(Modifier.fillMaxWidth().background(CoralSoft.copy(alpha=.65f),RoundedCornerShape(16.dp)).padding(14.dp),horizontalArrangement=Arrangement.spacedBy(9.dp)){Icon(Icons.Default.Shield,null,tint=Coral,modifier=Modifier.size(18.dp));Column{Text(title,fontSize=10.sp,fontWeight=FontWeight.Bold);Text(text,fontSize=9.sp,color=Muted,lineHeight=14.sp)}}}
@Composable fun EmptyState(title:String,text:String){Column(Modifier.fillMaxWidth().background(Paper,RoundedCornerShape(20.dp)).border(1.dp,Line,RoundedCornerShape(20.dp)).padding(32.dp),horizontalAlignment=Alignment.CenterHorizontally){Icon(Icons.Default.History,null,tint=Coral);Text(title,fontSize=13.sp,fontWeight=FontWeight.Bold,modifier=Modifier.padding(top=9.dp));Text(text,fontSize=9.sp,color=Muted,textAlign=androidx.compose.ui.text.style.TextAlign.Center,modifier=Modifier.padding(top=4.dp))}}
@Composable fun TPTextField(label:String,value:String,onChange:(String)->Unit,type:KeyboardType,password:Boolean=false){Column(verticalArrangement=Arrangement.spacedBy(7.dp)){Text(label.uppercase(),fontSize=9.sp,fontWeight=FontWeight.Bold,color=Muted);OutlinedTextField(value,onChange,singleLine=true,keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=type),visualTransformation=if(password)PasswordVisualTransformation() else VisualTransformation.None,colors=OutlinedTextFieldDefaults.colors(focusedBorderColor=Coral,unfocusedBorderColor=Line,focusedContainerColor=Paper,unfocusedContainerColor=Paper),shape=RoundedCornerShape(15.dp),modifier=Modifier.fillMaxWidth())}}
private fun activityScope(api:TraceApi,block:suspend()->Unit){GlobalScope.launch(Dispatchers.Main){block()}}
private fun scan(activity:MainActivity,onResult:(String)->Unit,onError:(String)->Unit={}){val options=GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).enableAutoZoom().build();GmsBarcodeScanning.getClient(activity,options).startScan().addOnSuccessListener{it.rawValue?.let(onResult)}.addOnFailureListener{onError(it.message?:"The QR scanner is unavailable on this device.")}}
private fun copyUri(context:Context,uri:Uri):File{val f=File(context.cacheDir,"profile_${UUID.randomUUID()}.jpg");context.contentResolver.openInputStream(uri)!!.use{input->f.outputStream().use{input.copyTo(it)}};return f}
