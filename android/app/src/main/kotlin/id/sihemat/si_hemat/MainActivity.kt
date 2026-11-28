package id.sihemat.si_hemat

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.rendering.ImageType
import com.tom_roush.pdfbox.rendering.PDFRenderer
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val pdfChannelName = "id.sihemat/pdf_renderer"
    private val pdfExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var pdfBoxReady = false

    private fun ensurePdfBoxInitialized() {
        if (!pdfBoxReady) {
            PDFBoxResourceLoader.init(applicationContext)
            pdfBoxReady = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pdfChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspectPdf" -> {
                        val path = call.argument<String>("path")
                        val password = call.argument<String>("password") ?: ""
                        if (path.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Path file PDF kosong.", null)
                            return@setMethodCallHandler
                        }
                        pdfExecutor.execute {
                            try {
                                ensurePdfBoxInitialized()
                                val file = File(path)
                                PDDocument.load(file, password).use { doc ->
                                    val count = doc.numberOfPages
                                    mainHandler.post {
                                        result.success(mapOf("pageCount" to count))
                                    }
                                }
                            } catch (e: InvalidPasswordException) {
                                mainHandler.post {
                                    result.error(
                                        "INVALID_PASSWORD",
                                        "File PDF memerlukan password yang benar.",
                                        null,
                                    )
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error(
                                        "PDF_ERROR",
                                        e.message ?: "Gagal membuka file PDF.",
                                        null,
                                    )
                                }
                            }
                        }
                    }

                    "renderPage" -> {
                        val path = call.argument<String>("path")
                        val password = call.argument<String>("password") ?: ""
                        val pageIndex = call.argument<Int>("pageIndex") ?: 0
                        val dpi = (call.argument<Number>("dpi")?.toFloat() ?: 150f)
                            .coerceIn(72f, 220f)
                        if (path.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "Path file PDF kosong.", null)
                            return@setMethodCallHandler
                        }
                        pdfExecutor.execute {
                            try {
                                ensurePdfBoxInitialized()
                                val file = File(path)
                                PDDocument.load(file, password).use { doc ->
                                    if (pageIndex < 0 || pageIndex >= doc.numberOfPages) {
                                        mainHandler.post {
                                            result.error(
                                                "OUT_OF_RANGE",
                                                "Indeks halaman PDF tidak valid.",
                                                null,
                                            )
                                        }
                                        return@execute
                                    }
                                    val renderer = PDFRenderer(doc)
                                    val bitmap = renderer.renderImageWithDPI(
                                        pageIndex,
                                        dpi,
                                        ImageType.RGB,
                                    )
                                    val jpegBytes = try {
                                        val baos = ByteArrayOutputStream()
                                        bitmap.compress(
                                            Bitmap.CompressFormat.JPEG,
                                            86,
                                            baos,
                                        )
                                        baos.toByteArray()
                                    } finally {
                                        bitmap.recycle()
                                    }
                                    mainHandler.post {
                                        result.success(jpegBytes)
                                    }
                                }
                            } catch (e: InvalidPasswordException) {
                                mainHandler.post {
                                    result.error(
                                        "INVALID_PASSWORD",
                                        "Password PDF salah.",
                                        null,
                                    )
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error(
                                        "PDF_RENDER_ERROR",
                                        e.message ?: "Gagal merender halaman PDF.",
                                        null,
                                    )
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        pdfExecutor.shutdownNow()
        super.onDestroy()
    }
}
