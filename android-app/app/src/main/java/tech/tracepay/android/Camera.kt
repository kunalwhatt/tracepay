package tech.tracepay.android

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FlashOff
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.delay
import java.io.File
import java.io.FileOutputStream

private val CamLime = Color(0xFFC6FF3D)
private val CamViolet = Color(0xFF5B2EFF)

/** Camera permission state plus a function that asks for it. */
@Composable
fun rememberCameraPermission(): Pair<Boolean, () -> Unit> {
    val ctx = LocalContext.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    return granted to { launcher.launch(Manifest.permission.CAMERA) }
}

@Composable
private fun PermissionPrompt(text: String, onAllow: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(84.dp).clip(CircleShape).background(CamViolet.copy(alpha = .25f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Default.CameraAlt, null, tint = Color.White, modifier = Modifier.size(38.dp))
        }
        Spacer(Modifier.height(18.dp))
        Text(text, color = Color.White, fontSize = 15.sp, textAlign = TextAlign.Center, lineHeight = 21.sp)
        Spacer(Modifier.height(18.dp))
        Text("Allow camera", color = Color(0xFF14092E), fontWeight = FontWeight.Bold,
            modifier = Modifier.clip(RoundedCornerShape(16.dp)).background(CamLime).clickable { onAllow() }.padding(horizontal = 22.dp, vertical = 13.dp))
    }
}

// ------------------------------------------------------------------------------------------
// QR scanner: opens straight into the camera
// ------------------------------------------------------------------------------------------

/**
 * Live QR scanner. [onCode] returns null when the code is accepted, or a message explaining why not
 * (scanning then resumes automatically). "Import from photos" reads a QR from a saved image.
 */
@Composable
fun QrCameraScreen(onCode: (String) -> String?, onClose: () -> Unit, onMyQr: () -> Unit) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val (granted, request) = rememberCameraPermission()
    LaunchedEffect(Unit) { if (!granted) request() }
    var locked by remember { mutableStateOf(false) }
    var torch by remember { mutableStateOf(false) }
    var camera by remember { mutableStateOf<androidx.camera.core.Camera?>(null) }
    var message by remember { mutableStateOf("") }
    var found by remember { mutableStateOf(false) }
    val scanner = remember {
        BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build())
    }
    DisposableEffect(Unit) { onDispose { scanner.close() } }

    fun deliver(raw: String) {
        if (locked) return
        locked = true
        val problem = onCode(raw)
        if (problem == null) found = true else message = problem
    }
    LaunchedEffect(message) {  // after a rejected code, show why, then resume scanning
        if (message.isNotEmpty()) { delay(2200); message = ""; locked = false }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            try {
                scanner.process(InputImage.fromFilePath(ctx, uri))
                    .addOnSuccessListener { list ->
                        val value = list.firstOrNull { it.rawValue != null }?.rawValue
                        if (value != null) deliver(value) else message = "No QR code found in that photo."
                    }
                    .addOnFailureListener { message = "Could not read that photo." }
            } catch (e: Exception) {
                message = "Could not open that photo."
            }
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (granted) {
            AndroidView(factory = { c ->
                val view = PreviewView(c).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
                val future = ProcessCameraProvider.getInstance(c)
                future.addListener({
                    val provider = future.get()
                    val preview = Preview.Builder().build()
                    preview.setSurfaceProvider(view.surfaceProvider)
                    val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                    analysis.setAnalyzer(ContextCompat.getMainExecutor(c)) { proxy -> analyzeQr(proxy, scanner) { deliver(it) } }
                    try {
                        provider.unbindAll()
                        camera = provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                    } catch (e: Exception) {
                        message = "The camera is busy. Close other camera apps and try again."
                    }
                }, ContextCompat.getMainExecutor(c))
                view
            }, modifier = Modifier.fillMaxSize())
            ScanOverlay(found = found)
        } else {
            PermissionPrompt("Trace.Pay needs the camera to scan payment QR codes.") { request() }
        }

        // top bar
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            RoundIcon(Icons.Default.Close, "Close") { onClose() }
            Spacer(Modifier.weight(1f))
            Text("Scan to pay", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Spacer(Modifier.weight(1f))
            RoundIcon(if (torch) Icons.Default.FlashOn else Icons.Default.FlashOff, "Torch") {
                torch = !torch; camera?.cameraControl?.enableTorch(torch)
            }
        }
        // bottom bar
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                when { message.isNotEmpty() -> message; found -> "Trace.Pay ID found"; else -> "Point at a Trace.Pay QR code" },
                color = if (message.isNotEmpty()) Color(0xFFFFB4A8) else Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(Color.Black.copy(alpha = .45f)).padding(horizontal = 14.dp, vertical = 8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                BottomPill(Icons.Default.PhotoLibrary, "Import from photos", CamLime, Color(0xFF14092E)) {
                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                BottomPill(Icons.Default.QrCode, "My QR", Color.White.copy(alpha = .16f), Color.White) { onMyQr() }
            }
        }
    }
}

@SuppressLint("UnsafeOptInUsageError")
@androidx.annotation.OptIn(markerClass = [ExperimentalGetImage::class])
private fun analyzeQr(proxy: ImageProxy, scanner: BarcodeScanner, onValue: (String) -> Unit) {
    val media = proxy.image
    if (media == null) { proxy.close(); return }
    scanner.process(InputImage.fromMediaImage(media, proxy.imageInfo.rotationDegrees))
        .addOnSuccessListener { list -> list.firstOrNull { it.rawValue != null }?.rawValue?.let(onValue) }
        .addOnCompleteListener { proxy.close() }
}

/** Dimmed camera with a clear square, lime corners and an animated scan line. */
@Composable
private fun ScanOverlay(found: Boolean) {
    val line by rememberInfiniteTransition(label = "scan").animateFloat(0f, 1f,
        infiniteRepeatable(tween(1700, easing = LinearEasing), RepeatMode.Reverse), label = "line")
    val corner by animateColorAsState(if (found) Color(0xFF7CFF8A) else CamLime, label = "corner")
    Canvas(Modifier.fillMaxSize().graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)) {
        val side = size.minDimension * 0.68f
        val left = (size.width - side) / 2
        val top = (size.height - side) / 2 - size.height * 0.04f
        drawRect(Color.Black.copy(alpha = .55f))
        drawRoundRect(Color.Transparent, Offset(left, top), Size(side, side), CornerRadius(36f, 36f), blendMode = BlendMode.Clear)
        val l = side * 0.16f
        val w = 9.dp.toPx()
        val r = left + side
        val b = top + side
        listOf(
            Offset(left, top + l) to Offset(left, top), Offset(left, top) to Offset(left + l, top),
            Offset(r - l, top) to Offset(r, top), Offset(r, top) to Offset(r, top + l),
            Offset(r, b - l) to Offset(r, b), Offset(r, b) to Offset(r - l, b),
            Offset(left + l, b) to Offset(left, b), Offset(left, b) to Offset(left, b - l),
        ).forEach { (s, e) -> drawLine(corner, s, e, w, StrokeCap.Round) }
        if (!found) {
            val y = top + side * (0.08f + 0.84f * line)
            drawLine(CamLime.copy(alpha = .9f), Offset(left + side * .1f, y), Offset(r - side * .1f, y), 4.dp.toPx(), StrokeCap.Round)
        }
    }
}

@Composable
private fun RoundIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(Color.Black.copy(alpha = .4f)).clickable { onClick() }, contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White)
    }
}

@Composable
private fun BottomPill(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, fill: Color, content: Color, onClick: () -> Unit) {
    Row(Modifier.clip(RoundedCornerShape(99.dp)).background(fill).clickable { onClick() }.padding(horizontal = 18.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = content, modifier = Modifier.size(19.dp))
        Text(text, color = content, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

// ------------------------------------------------------------------------------------------
// Live selfie with face detection (no gallery)
// ------------------------------------------------------------------------------------------

private data class FaceCheck(val ok: Boolean, val text: String)

private fun checkFace(faces: List<Face>, imageWidth: Int): FaceCheck {
    if (faces.isEmpty()) return FaceCheck(false, "Looking for your face…")
    if (faces.size > 1) return FaceCheck(false, "Only one face, please")
    val face = faces[0]
    if (face.boundingBox.width() < imageWidth * 0.32f) return FaceCheck(false, "Move a little closer")
    if (face.boundingBox.width() > imageWidth * 0.85f) return FaceCheck(false, "Move a little further away")
    val yaw = face.headEulerAngleY
    if (yaw > 18 || yaw < -18) return FaceCheck(false, "Look straight at the camera")
    val left = face.leftEyeOpenProbability
    val right = face.rightEyeOpenProbability
    if (left != null && right != null && (left < 0.35f || right < 0.35f)) return FaceCheck(false, "Keep your eyes open")
    return FaceCheck(true, "Perfect, hold still")
}

@SuppressLint("UnsafeOptInUsageError")
@androidx.annotation.OptIn(markerClass = [ExperimentalGetImage::class])
private fun analyzeFace(proxy: ImageProxy, detector: FaceDetector, onResult: (FaceCheck) -> Unit) {
    val media = proxy.image
    if (media == null) { proxy.close(); return }
    val rotation = proxy.imageInfo.rotationDegrees
    val width = if (rotation == 90 || rotation == 270) proxy.height else proxy.width
    detector.process(InputImage.fromMediaImage(media, rotation))
        .addOnSuccessListener { faces -> onResult(checkFace(faces, width)) }
        .addOnCompleteListener { proxy.close() }
}

/**
 * Front camera with live face guidance. When exactly one face is steady and well framed for about a
 * second, the photo is taken automatically (the shutter button also works). The JPEG is rotated
 * upright, mirrored like a selfie and resized before it is returned.
 */
@Composable
fun FaceCaptureScreen(onCaptured: (File) -> Unit, onCancel: () -> Unit) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val (granted, request) = rememberCameraPermission()
    LaunchedEffect(Unit) { if (!granted) request() }
    var check by remember { mutableStateOf(FaceCheck(false, "Looking for your face…")) }
    var taking by remember { mutableStateOf(false) }
    val detector = remember {
        FaceDetection.getClient(FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setMinFaceSize(0.2f).build())
    }
    DisposableEffect(Unit) { onDispose { detector.close() } }
    val capture = remember { ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }

    fun take() {
        if (taking) return
        taking = true
        val file = File(ctx.cacheDir, "selfie_${System.currentTimeMillis()}.jpg")
        capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(ctx),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    onCaptured(normalizeSelfie(ctx, file))
                }
                override fun onError(exception: ImageCaptureException) {
                    taking = false
                    check = FaceCheck(false, "Could not take the photo. Try again.")
                }
            })
    }
    LaunchedEffect(check.ok) {  // auto-capture once the face stays good for a moment
        if (check.ok && !taking) { delay(1100); if (check.ok) take() }
    }
    val ring by animateColorAsState(if (check.ok) CamLime else Color.White.copy(alpha = .85f), label = "ring")
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(0.97f, 1.03f,
        infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "p")

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (granted) {
            AndroidView(factory = { c ->
                val view = PreviewView(c).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
                val future = ProcessCameraProvider.getInstance(c)
                future.addListener({
                    val provider = future.get()
                    val preview = Preview.Builder().build()
                    preview.setSurfaceProvider(view.surfaceProvider)
                    val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                    analysis.setAnalyzer(ContextCompat.getMainExecutor(c)) { proxy -> analyzeFace(proxy, detector) { if (!taking) check = it } }
                    try {
                        provider.unbindAll()
                        provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis, capture)
                    } catch (e: Exception) {
                        check = FaceCheck(false, "The front camera is not available.")
                    }
                }, ContextCompat.getMainExecutor(c))
                view
            }, modifier = Modifier.fillMaxSize())
            // oval guide
            Canvas(Modifier.fillMaxSize().graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)) {
                val w = size.width * 0.72f * (if (check.ok) 1f else pulse)
                val h = w * 1.3f
                val tl = Offset((size.width - w) / 2, size.height * 0.42f - h / 2)
                drawRect(Color.Black.copy(alpha = .5f))
                drawOval(Color.Transparent, tl, Size(w, h), blendMode = BlendMode.Clear)
                drawOval(ring, tl, Size(w, h), style = Stroke(width = 6.dp.toPx()))
            }
        } else {
            PermissionPrompt("Take a live selfie to create your Trace.Pay profile. Your photo is encrypted and checked for one clear face.") { request() }
        }
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            RoundIcon(Icons.Default.Close, "Cancel") { onCancel() }
            Spacer(Modifier.weight(1f))
            Text("Live selfie", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.width(44.dp))
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text(if (taking) "Capturing…" else check.text, color = if (check.ok) Color(0xFF14092E) else Color.White,
                fontWeight = FontWeight.Bold, fontSize = 14.sp,
                modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(if (check.ok) CamLime else Color.Black.copy(alpha = .5f))
                    .padding(horizontal = 18.dp, vertical = 10.dp))
            Box(Modifier.size(78.dp).clip(CircleShape).border(5.dp, if (check.ok) CamLime else Color.White.copy(alpha = .5f), CircleShape)
                .clickable(enabled = check.ok && !taking) { take() }.padding(9.dp).clip(CircleShape)
                .background(if (check.ok) Color.White else Color.White.copy(alpha = .3f)))
            Text("No gallery uploads: the photo must be live.", color = Color.White.copy(alpha = .7f), fontSize = 11.sp)
        }
    }
}

/** Rotate upright, mirror (selfie view) and resize to at most 1280 px, saved as JPEG 88%. */
fun normalizeSelfie(ctx: Context, file: File): File {
    return try {
        val raw = BitmapFactory.decodeFile(file.absolutePath) ?: return file
        val degrees = when (ExifInterface(file.absolutePath).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        val scale = minOf(1f, 1280f / maxOf(raw.width, raw.height))
        val matrix = Matrix().apply { postRotate(degrees); postScale(-scale, scale) }
        val upright = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
        val out = File(ctx.cacheDir, "selfie_ready_${System.currentTimeMillis()}.jpg")
        FileOutputStream(out).use { upright.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        out
    } catch (e: Exception) {
        file
    }
}
