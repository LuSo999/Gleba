package cz.gleba.gleba

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Opened by Health Connect ("why does this app need access?") and the system's
 * permission usage screen: shows Gleba's privacy policy in the browser.
 */
class PrivacyPolicyActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://gleba-e9a60.web.app/privacy.html")))
    finish()
  }
}
