package com.example.ar_ai_girl_friend

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    volumeControlStream = AudioManager.STREAM_MUSIC
  }
}
