package app.mom.mom_native

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "mom/plasma_orb",
            PlasmaOrbViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }
}

private class PlasmaOrbViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val initialState = (args as? Map<*, *>)?.get("state") as? String
        val orb = PlasmaOrbView(context).apply { setOrbState(initialState) }
        val channel = MethodChannel(messenger, "mom/plasma_orb/$viewId")

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setState" -> {
                    orb.setOrbState(call.argument<String>("state"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        return object : PlatformView {
            override fun getView() = orb

            override fun dispose() {
                channel.setMethodCallHandler(null)
                orb.dispose()
            }
        }
    }
}
