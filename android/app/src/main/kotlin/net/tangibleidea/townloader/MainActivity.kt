package net.tangibleidea.townloader

import android.content.Intent
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 다른 앱의 공유(ACTION_SEND, text/plain)로 들어온 링크를 Dart 로 넘기고,
// 사진의 글자를 ML Kit(한국어)으로 읽어 Dart 의 TextRecognizer 에 돌려준다.
class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null

    // Dart 가 준비되기 전에 들어온 공유 링크. `getInitialShare` 호출 때 한 번 넘기고 비운다.
    private var pendingShare: String? = null
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShare = sharedText(intent)

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .apply {
                setMethodCallHandler { call, result ->
                    if (call.method == "getInitialShare") {
                        dartReady = true
                        result.success(pendingShare)
                        pendingShare = null
                    } else {
                        result.notImplemented()
                    }
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL)
            .setMethodCallHandler { call, result ->
                val bytes = call.arguments as? ByteArray
                if (call.method != "recognize" || bytes == null) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                recognizeText(bytes, result)
            }
    }

    private val textRecognizer by lazy {
        TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
    }

    // 위치와 높이는 사진 크기에 대한 비율(0~1)로 넘겨 iOS(Vision) 와 같은 형식으로 맞춘다.
    private fun recognizeText(bytes: ByteArray, result: MethodChannel.Result) {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) {
            result.error("bad_image", "Couldn't decode the image.", null)
            return
        }
        val width = bitmap.width.toFloat()
        val height = bitmap.height.toFloat()
        textRecognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { text ->
                val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                    val box = line.boundingBox ?: return@mapNotNull null
                    mapOf(
                        "text" to line.text,
                        "left" to box.left / width,
                        "top" to box.top / height,
                        "height" to box.height() / height,
                    )
                }
                result.success(lines)
            }
            // Play 서비스가 한국어 모델을 아직 받는 중이면 여기로 온다. Dart 는 빈 목록으로 다룬다.
            .addOnFailureListener { error -> result.error("ocr_failed", error.message, null) }
    }

    // 앱이 이미 떠 있을 때(singleTop) 새 공유가 오면 여기로 들어온다.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        if (dartReady) {
            shareChannel?.invokeMethod("onShare", text)
        } else {
            pendingShare = text
        }
    }

    private fun sharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
    }

    private companion object {
        const val SHARE_CHANNEL = "townloader/share"
        const val OCR_CHANNEL = "townloader/ocr"
    }
}
