package ee.nekoko.nlpa2

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.*

class CertificatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ee.nekoko.certificate_plugin")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "getCertificateHashes") {
            try {
                val sha256Hashes = mutableListOf<String>()
                val sha1Hashes = mutableListOf<String>()
                val signatures =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val info =
                                    context.packageManager.getPackageInfo(
                                            context.packageName,
                                            PackageManager.GET_SIGNING_CERTIFICATES
                                    )
                            info.signingInfo?.apkContentsSigners
                        } else {
                            @Suppress("DEPRECATION")
                            val info =
                                    context.packageManager.getPackageInfo(
                                            context.packageName,
                                            PackageManager.GET_SIGNATURES
                                    )
                            info.signatures
                        }

                signatures?.forEach { signature ->
                    val cert = signature.toByteArray()
                    sha256Hashes.add(getHash(cert, "SHA-256"))
                    sha1Hashes.add(getHash(cert, "SHA-1"))
                }

                result.success(mapOf("sha256" to sha256Hashes, "sha1" to sha1Hashes))
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        } else if (call.method == "getAbi") {
            try {
                result.success(Build.SUPPORTED_ABIS.toList())
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        } else {
            result.notImplemented()
        }
    }

    private fun getHash(cert: ByteArray, algorithm: String): String {
        val md = MessageDigest.getInstance(algorithm)
        val digest = md.digest(cert)
        return digest.joinToString("") { "%02X".format(it) }
    }
}
