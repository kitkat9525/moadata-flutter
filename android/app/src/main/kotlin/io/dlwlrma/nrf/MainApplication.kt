package io.dlwlrma.nrf

import android.app.Application
import android.util.Log

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        suppressRxJavaUndeliverableException()
    }

    // flutter_reactive_ble가 내부적으로 RxJava2를 사용하므로
    // 직접 의존성 추가 없이 리플렉션으로 에러 핸들러 등록
    private fun suppressRxJavaUndeliverableException() {
        try {
            val pluginsClass = Class.forName("io.reactivex.plugins.RxJavaPlugins")
            val setErrorHandler = pluginsClass.getMethod(
                "setErrorHandler",
                Class.forName("io.reactivex.functions.Consumer")
            )
            val consumer = java.lang.reflect.Proxy.newProxyInstance(
                javaClass.classLoader,
                arrayOf(Class.forName("io.reactivex.functions.Consumer"))
            ) { _, _, args ->
                val throwable = args[0] as? Throwable
                Log.w("RxJava", "Suppressed undeliverable: ${throwable?.cause ?: throwable}")
                null
            }
            setErrorHandler.invoke(null, consumer)
        } catch (e: Exception) {
            Log.w("RxJava", "Failed to set RxJava error handler: $e")
        }
    }
}
