package nz.stone_and_banner

import android.content.Intent
import android.os.Build
import java.net.Inet4Address
import java.net.NetworkInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stone_and_banner/lan")
            .setMethodCallHandler { call, result ->
                if (call.method != "subnets") {
                    result.notImplemented()
                } else {
                    try {
                        val networks = NetworkInterface.getNetworkInterfaces().toList()
                            .filter { it.isUp && !it.isLoopback && !it.isPointToPoint }
                            .flatMap { iface ->
                                iface.interfaceAddresses.filter {
                                    it.address is Inet4Address && it.broadcast != null
                                }.map {
                                    mapOf("name" to iface.name,
                                        "address" to it.address.hostAddress,
                                        "prefix" to it.networkPrefixLength.toInt())
                                }
                            }
                        result.success(networks)
                    } catch (error: Exception) {
                        result.error("LAN_NETWORKS", error.message, null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stone_and_banner/multiplayer")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val intent = Intent(this, MultiplayerService::class.java)
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                            else startService(intent)
                            result.success(null)
                        }
                        "stop" -> {
                            stopService(Intent(this, MultiplayerService::class.java))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("MULTIPLAYER_SERVICE", error.message, null)
                }
            }
    }
}
