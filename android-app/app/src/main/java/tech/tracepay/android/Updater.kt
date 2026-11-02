package tech.tracepay.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

data class AppUpdate(val version: String, val apkUrl: String, val notes: String)

/** Checks GitHub Releases for a newer APK, downloads it and opens Android's installer (the person confirms). */
object Updater {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).build()

    /** "6.0.10" > "6.0.9" */
    fun isNewer(remote: String, local: String): Boolean {
        val r = remote.removePrefix("v").split(".", "-").map { it.toIntOrNull() ?: 0 }
        val l = local.removePrefix("v").split(".", "-").map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(r.size, l.size)) { val a = r.getOrElse(i) { 0 }; val b = l.getOrElse(i) { 0 }; if (a != b) return a > b }
        return false
    }

    suspend fun check(): AppUpdate? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url("https://api.github.com/repos/${BuildConfig.UPDATE_REPO}/releases/latest").header("Accept", "application/vnd.github+json").build()
            client.newCall(req).execute().use { r ->
                if (!r.isSuccessful) return@withContext null
                val o = JSONObject(r.body?.string().orEmpty())
                val tag = o.optString("tag_name")
                val assets = o.optJSONArray("assets") ?: return@withContext null
                val apk = (0 until assets.length()).map { assets.getJSONObject(it) }.firstOrNull { it.optString("name").endsWith(".apk") } ?: return@withContext null
                if (!isNewer(tag, BuildConfig.VERSION_NAME)) return@withContext null
                AppUpdate(tag.removePrefix("v"), apk.optString("browser_download_url"), o.optString("body").take(400))
            }
        } catch (_: Exception) { null }
    }

    /** Downloads the APK into the app's cache, reporting progress 0..1. */
    suspend fun download(ctx: Context, update: AppUpdate, progress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(ctx.cacheDir, "updates").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val out = File(dir, "tracepay-${update.version}.apk")
        client.newCall(Request.Builder().url(update.apkUrl).build()).execute().use { r ->
            if (!r.isSuccessful) throw Exception("Download failed (${r.code}). Try again.")
            val body = r.body ?: throw Exception("Download failed. Try again.")
            val total = body.contentLength().takeIf { it > 0 } ?: -1L
            body.byteStream().use { input -> out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024); var done = 0L
                while (true) { val n = input.read(buf); if (n < 0) break; output.write(buf, 0, n); done += n; if (total > 0) progress(done.toFloat() / total) }
            } }
        }
        out
    }

    /** True if Android will let trace.pay open the installer; otherwise opens the one-time "Install unknown apps" setting. */
    fun canInstall(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ctx.packageManager.canRequestPackageInstalls()) return true
        ctx.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return false
    }

    fun install(ctx: Context, apk: File) {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", apk)
        ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
