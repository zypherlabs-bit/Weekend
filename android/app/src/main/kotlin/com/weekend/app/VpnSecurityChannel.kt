package com.weekend.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android VPN detection for Weekend.
 *
 * Why this exists
 * ---------------
 * Weekend's security policy blocks protected content while the device routes
 * traffic through a VPN.  The only reliable local signal Android exposes is
 * [NetworkCapabilities.TRANSPORT_VPN], so this channel reads it from
 * ConnectivityManager.  There is no IP lookup, no third-party service and no
 * network identifier is sent anywhere.
 *
 * Detection is deliberately local and permission-light: `ACCESS_NETWORK_STATE`
 * is already declared for the Supabase client.  No accessibility, device-admin
 * or usage-access permission is requested.
 *
 * Limits (documented in the UI and privacy policy)
 * -----------------------------------------------
 * Android can only report transports the platform knows about.  OEM VPN
 * implementations, split tunnelling, per-app proxies, private DNS and some
 * always-on configurations may not be visible.  This is a strong, supported
 * signal - not a guarantee against every possible tunnel.
 */
class VpnSecurityChannel(
    context: Context,
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val connectivityManager =
        context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var disposed = false

    /** Debounce bursts of capability callbacks (a single network switch can
     *  emit several).  It is not a polling loop: nothing runs when idle. */
    private val pushState = Runnable {
        if (disposed) return@Runnable
        eventSink?.success(detect())
    }

    fun attach() {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" -> result.success(detect())
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Give Dart an immediate answer rather than waiting for the first
        // network callback.
        events?.success(detect())
        registerCallback()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        unregisterCallback()
    }

    fun dispose() {
        disposed = true
        mainHandler.removeCallbacksAndMessages(null)
        eventSink = null
        unregisterCallback()
    }

    private fun registerCallback() {
        if (networkCallback != null) return
        val manager = connectivityManager
        if (manager == null) {
            eventSink?.success(errorResult("connectivity_service_unavailable"))
            return
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = schedulePush()
            override fun onLost(network: Network) = schedulePush()
            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) = schedulePush()
        }
        try {
            // A broad request observes the default network and any VPN network
            // Android reports.  Registering once is cheaper and more accurate
            // than polling getActiveNetwork() on a timer.
            manager.registerNetworkCallback(NetworkRequest.Builder().build(), callback)
            networkCallback = callback
        } catch (error: SecurityException) {
            eventSink?.success(errorResult("network_state_permission_denied"))
        } catch (error: Exception) {
            eventSink?.success(errorResult("network_callback_unavailable"))
        }
    }

    private fun unregisterCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            connectivityManager?.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // Already unregistered or the process is shutting down.
        }
    }

    private fun schedulePush() {
        mainHandler.removeCallbacks(pushState)
        mainHandler.postDelayed(pushState, 350)
    }

    private fun detect(): Map<String, Any?> {
        val manager = connectivityManager
            ?: return errorResult("connectivity_service_unavailable")

        return try {
            val activeNetwork = manager.activeNetwork
                ?: return mapOf(
                    "status" to "no_network",
                    "reason" to "no_active_network",
                )

            val activeCapabilities = manager.getNetworkCapabilities(activeNetwork)
                ?: return errorResult("active_network_capabilities_unavailable")

            // Check the active network first, then every known network.  A VPN
            // that is present but not the default (for example a per-app VPN)
            // still violates Weekend's policy, so `allNetworks` is intentional.
            var vpnNetwork: Network? = null
            if (activeCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                vpnNetwork = activeNetwork
            } else {
                for (network in manager.allNetworks) {
                    val capabilities = manager.getNetworkCapabilities(network)
                    if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true) {
                        vpnNetwork = network
                        break
                    }
                }
            }

            if (vpnNetwork != null) {
                mapOf(
                    "status" to "vpn",
                    "transportVpn" to true,
                    // Do not leak a provider name, address or any identifier:
                    // only the boolean transport fact crosses the channel.
                    "validated" to (manager.getNetworkCapabilities(vpnNetwork)
                        ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                        ?: false),
                )
            } else {
                mapOf(
                    "status" to "clear",
                    "transportVpn" to false,
                    "validated" to activeCapabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_VALIDATED,
                    ),
                )
            }
        } catch (error: SecurityException) {
            errorResult("network_state_permission_denied")
        } catch (error: Exception) {
            errorResult("network_state_unavailable")
        }
    }

    private fun errorResult(reason: String): Map<String, Any?> = mapOf(
        "status" to "error",
        "reason" to reason,
    )

    companion object {
        const val METHOD_CHANNEL = "com.weekend.app/vpn_security"
        const val EVENT_CHANNEL = "com.weekend.app/vpn_security_events"
    }
}
