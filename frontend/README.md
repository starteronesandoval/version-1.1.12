# Balam Flutter

1. Instala Flutter y ejecuta `flutter create .` dentro de esta carpeta para generar las carpetas nativas que falten.
2. Ejecuta `flutter pub get`.
3. Inicia la API y después `flutter run`.

La URL predeterminada `http://10.0.2.2:8000` funciona en el emulador Android. Para iOS usa `http://127.0.0.1:8000`; para un teléfono físico usa la IP local de la computadora y cambia `baseUrl` en `lib/api_service.dart`.

