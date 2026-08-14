package app.mom.mom_native

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private lateinit var speechChannel: MethodChannel
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeGeneration = 0
    private var recognizerBusy = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speechChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        speechChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(onDeviceRecognitionAvailable())
                "start" -> {
                    val generation = (call.argument<Number>("generation") ?: 0).toInt()
                    val partialResults = call.argument<Boolean>("partial_results") ?: true
                    val locale = call.argument<String>("locale")
                    startOnDeviceRecognition(generation, partialResults, locale, result)
                }
                "stop" -> {
                    val generation = (call.argument<Number>("generation") ?: -1).toInt()
                    if (generation == activeGeneration && recognizerBusy) {
                        speechRecognizer?.stopListening()
                    }
                    result.success(null)
                }
                "cancel" -> {
                    val generation = (call.argument<Number>("generation") ?: -1).toInt()
                    if (generation == activeGeneration && recognizerBusy) {
                        activeGeneration++
                        recognizerBusy = false
                        speechRecognizer?.cancel()
                        emitStatus(generation, "cancelled")
                    }
                    result.success(null)
                }
                "destroy" -> {
                    destroyOnDeviceRecognizer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun onDeviceRecognitionAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)

    private fun startOnDeviceRecognition(
        generation: Int,
        partialResults: Boolean,
        locale: String?,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.error(
                "unsupported_android_version",
                "Strict on-device speech recognition requires Android 12 or newer.",
                null,
            )
            return
        }
        if (!onDeviceRecognitionAvailable()) {
            result.error(
                "on_device_recognizer_unavailable",
                "No on-device recognition service is installed on this phone.",
                null,
            )
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "microphone_permission_denied",
                "Microphone permission is required for local speech recognition.",
                null,
            )
            return
        }
        if (recognizerBusy) {
            result.error("recognizer_busy", "The on-device recognizer is busy.", null)
            return
        }

        try {
            if (speechRecognizer == null) {
                speechRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            }
            activeGeneration = generation
            recognizerBusy = true
            speechRecognizer!!.setRecognitionListener(listenerFor(generation))
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, partialResults)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE,
                    locale?.takeIf { it.isNotBlank() }
                        ?: Locale.getDefault().toLanguageTag(),
                )
            }
            speechRecognizer!!.startListening(intent)
            result.success(null)
        } catch (error: UnsupportedOperationException) {
            recognizerBusy = false
            result.error(
                "on_device_recognizer_unavailable",
                error.message ?: "On-device recognition is unavailable.",
                null,
            )
        } catch (error: RuntimeException) {
            recognizerBusy = false
            result.error(
                "recognizer_start_failed",
                error.message ?: "On-device recognition failed to start.",
                null,
            )
        }
    }

    private fun listenerFor(generation: Int) = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            emitStatus(generation, "listening")
        }

        override fun onBeginningOfSpeech() {
            emitStatus(generation, "listening")
        }

        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
            emitStatus(generation, "processing")
        }

        override fun onError(error: Int) {
            if (generation != activeGeneration) return
            recognizerBusy = false
            speechChannel.invokeMethod(
                "speechError",
                mapOf(
                    "generation" to generation,
                    "code" to errorName(error),
                    "message" to errorMessage(error),
                    "permanent" to isPermanent(error),
                ),
            )
            emitStatus(generation, "done")
        }

        override fun onResults(results: Bundle) {
            if (generation != activeGeneration) return
            recognizerBusy = false
            emitResult(generation, results, true)
            emitStatus(generation, "done")
        }

        override fun onPartialResults(partialResults: Bundle) {
            if (generation != activeGeneration) return
            emitResult(generation, partialResults, false)
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun emitResult(generation: Int, bundle: Bundle, finalResult: Boolean) {
        val text = bundle
            .getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            .orEmpty()
        if (text.isEmpty()) return
        val confidence = bundle
            .getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
            ?.firstOrNull()
            ?.takeIf { it >= 0f }
        speechChannel.invokeMethod(
            "speechResult",
            mapOf(
                "generation" to generation,
                "text" to text,
                "final" to finalResult,
                "confidence" to confidence,
            ),
        )
    }

    private fun emitStatus(generation: Int, status: String) {
        speechChannel.invokeMethod(
            "speechStatus",
            mapOf("generation" to generation, "status" to status),
        )
    }

    private fun errorName(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "audio_error"
        SpeechRecognizer.ERROR_CLIENT -> "client_error"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "microphone_permission_denied"
        SpeechRecognizer.ERROR_NETWORK -> "local_recognizer_network_error"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "local_recognizer_network_timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "recognizer_busy"
        SpeechRecognizer.ERROR_SERVER -> "local_recognizer_service_error"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "speech_timeout"
        12 -> "language_not_supported"
        13 -> "language_model_unavailable"
        else -> "recognizer_error_$error"
    }

    private fun errorMessage(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_NO_MATCH -> "I couldn't match that speech locally."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was heard before the local timeout."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The on-device recognizer is busy."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
            "Microphone permission is required for local recognition."
        12 -> "The selected language is not supported by the on-device recognizer."
        13 -> "The selected on-device language model is not downloaded."
        else -> "On-device speech recognition failed with code $error."
    }

    private fun isPermanent(error: Int): Boolean =
        error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS || error == 12

    private fun destroyOnDeviceRecognizer() {
        activeGeneration++
        recognizerBusy = false
        speechRecognizer?.cancel()
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    override fun onDestroy() {
        destroyOnDeviceRecognizer()
        if (::speechChannel.isInitialized) {
            speechChannel.setMethodCallHandler(null)
        }
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_NAME =
            "app.mom.mom_native/on_device_speech_recognizer"
    }
}
