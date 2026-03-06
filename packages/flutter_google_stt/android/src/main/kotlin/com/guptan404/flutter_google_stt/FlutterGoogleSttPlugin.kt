package com.guptan404.flutter_google_stt

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.*
import com.google.gson.Gson
import android.util.Base64

/** FlutterGoogleSttPlugin */
class FlutterGoogleSttPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  
  // Audio recording variables
  private var audioRecord: AudioRecord? = null
  private var isRecording = false
  private var recordingJob: Job? = null
  
  // Google Speech variables
  private val gson = Gson()
  private var accessToken: String? = null
  private var languageCode: String = "en-US"
  private var sampleRateHertz: Int = 16000
  
  // Audio recording parameters
  private val channelConfig = AudioFormat.CHANNEL_IN_MONO
  private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
  private val bufferSize = AudioRecord.getMinBufferSize(16000, channelConfig, audioFormat)
  
  // Permission request code
  private val MICROPHONE_PERMISSION_REQUEST_CODE = 1001
  private var pendingResult: Result? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_google_stt")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "initialize" -> handleInitialize(call, result)
      "startListening" -> handleStartListening(result)
      "stopListening" -> handleStopListening(result)
      "isListening" -> result.success(isRecording)
      "hasMicrophonePermission" -> result.success(hasMicrophonePermission())
      "requestMicrophonePermission" -> handleRequestMicrophonePermission(result)
      else -> result.notImplemented()
    }
  }

  private fun handleInitialize(call: MethodCall, result: Result) {
    try {
      accessToken = call.argument<String>("accessToken")
      languageCode = call.argument<String>("languageCode") ?: "en-US"
      sampleRateHertz = call.argument<Int>("sampleRateHertz") ?: 16000
      
      if (accessToken.isNullOrEmpty()) {
        result.error("INVALID_TOKEN", "Access token is required", null)
        return
      }
      
      result.success(true)
    } catch (e: Exception) {
      result.error("INITIALIZATION_ERROR", "Failed to initialize: ${e.message}", null)
    }
  }

  private fun handleStartListening(result: Result) {
    Log.d("FlutterGoogleStt", "handleStartListening called")
    if (!hasMicrophonePermission()) {
      Log.e("FlutterGoogleStt", "Microphone permission denied")
      result.error("PERMISSION_DENIED", "Microphone permission is required", null)
      return
    }
    
    if (isRecording) {
      Log.w("FlutterGoogleStt", "Already recording")
      result.error("ALREADY_LISTENING", "Already listening", null)
      return
    }
    
    try {
      Log.d("FlutterGoogleStt", "Starting audio recording")
      startAudioRecording()
      Log.d("FlutterGoogleStt", "Audio recording started successfully")
      result.success(true)
    } catch (e: Exception) {
      Log.e("FlutterGoogleStt", "Failed to start listening: ${e.message}", e)
      result.error("START_ERROR", "Failed to start listening: ${e.message}", null)
    }
  }

  private fun handleStopListening(result: Result) {
    try {
      stopAudioRecording()
      result.success(true)
    } catch (e: Exception) {
      result.error("STOP_ERROR", "Failed to stop listening: ${e.message}", null)
    }
  }

  private fun startAudioRecording() {
    Log.d("FlutterGoogleStt", "startAudioRecording called")
    try {
      Log.d("FlutterGoogleStt", "Creating AudioRecord with sampleRate: $sampleRateHertz, bufferSize: $bufferSize")
      audioRecord = AudioRecord(
        MediaRecorder.AudioSource.MIC,
        sampleRateHertz,
        channelConfig,
        audioFormat,
        bufferSize * 2
      )
      
      if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
        Log.e("FlutterGoogleStt", "AudioRecord initialization failed")
        throw Exception("AudioRecord initialization failed")
      }
      
      Log.d("FlutterGoogleStt", "AudioRecord initialized successfully")
      isRecording = true
      audioRecord?.startRecording()
      Log.d("FlutterGoogleStt", "AudioRecord started recording")
      
      // Start recording in a coroutine
      Log.d("FlutterGoogleStt", "Starting recording coroutine")
      recordingJob = CoroutineScope(Dispatchers.IO).launch {
        recordAudioData()
      }
    } catch (e: Exception) {
      Log.e("FlutterGoogleStt", "Error in startAudioRecording: ${e.message}", e)
      throw e
    }
  }

  private suspend fun recordAudioData() {
    Log.d("FlutterGoogleStt", "recordAudioData started")
    val buffer = ByteArray(bufferSize)
    
    try {
      while (isRecording && audioRecord != null) {
        val bytesRead = audioRecord!!.read(buffer, 0, buffer.size)
        if (bytesRead > 0) {
          Log.d("FlutterGoogleStt", "Read $bytesRead bytes of audio data")
          // Send audio data to Dart side for streaming
          val audioData = buffer.copyOf(bytesRead)
          withContext(Dispatchers.Main) {
            Log.d("FlutterGoogleStt", "Sending audio data to Dart via method channel")
            channel.invokeMethod("onAudioData", audioData.toList())
          }
        } else {
          Log.w("FlutterGoogleStt", "No audio data read, bytesRead: $bytesRead")
        }
        delay(10) // Small delay to prevent overwhelming
      }
      Log.d("FlutterGoogleStt", "Recording loop ended - isRecording: $isRecording, audioRecord: $audioRecord")
    } catch (e: Exception) {
      Log.e("FlutterGoogleStt", "Error in recordAudioData: ${e.message}", e)
      withContext(Dispatchers.Main) {
        channel.invokeMethod("onError", "Audio recording error: ${e.message}")
      }
    }
  }

  private fun stopAudioRecording() {
    isRecording = false
    recordingJob?.cancel()
    recordingJob = null
    
    audioRecord?.stop()
    audioRecord?.release()
    audioRecord = null
  }

  private fun hasMicrophonePermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.RECORD_AUDIO
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun handleRequestMicrophonePermission(result: Result) {
    if (hasMicrophonePermission()) {
      result.success(true)
      return
    }
    
    if (activity == null) {
      result.error("NO_ACTIVITY", "Activity is required to request permissions", null)
      return
    }
    
    pendingResult = result
    ActivityCompat.requestPermissions(
      activity!!,
      arrayOf(Manifest.permission.RECORD_AUDIO),
      MICROPHONE_PERMISSION_REQUEST_CODE
    )
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode == MICROPHONE_PERMISSION_REQUEST_CODE) {
      val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
      pendingResult?.success(granted)
      pendingResult = null
      return true
    }
    return false
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    stopAudioRecording()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
  }
}
