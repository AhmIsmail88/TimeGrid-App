package com.example.timegrid

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth,
// which hosts the biometric prompt in a fragment.
class MainActivity : FlutterFragmentActivity()