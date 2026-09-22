package mx.balam.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "garibaldi_alerts_v2",
                "Avisos urgentes de Garibaldi",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Mensajes, contrataciones, pagos y actividad social"
                enableVibration(true)
                setShowBadge(true)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
