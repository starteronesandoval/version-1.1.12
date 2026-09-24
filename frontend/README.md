# Balam Flutter

1. Instala Flutter.
2. Ejecuta `flutter pub get`.
3. Ejecuta `flutter run`.

La aplicación utiliza siempre `https://api.garibaldi.app`, tanto en teléfonos
como en emuladores y builds de publicación.

## Compilación conectada

La aplicación siempre se conecta al backend. Para publicarla, la API debe estar
alojada en un servicio web HTTPS:

```powershell
flutter build apk --release `
  --dart-define=GOOGLE_WEB_CLIENT_ID=TU_CLIENT_ID_WEB.apps.googleusercontent.com
```

## Validación y release

```powershell
flutter analyze
flutter test
flutter build web --release
flutter build appbundle --release
```

El identificador de aplicación para Android e iOS es `mx.balam.app`. Para publicar en tiendas todavía se deben proporcionar las credenciales privadas de firma de Google Play y el equipo de Apple; nunca deben guardarse en Git.

## Acceso con Google

1. Configura la pantalla de consentimiento OAuth en Google Cloud.
2. Crea un cliente OAuth **Aplicación web** y registra como orígenes JavaScript
   `http://localhost:7357` para desarrollo y el dominio HTTPS de producción.
3. Crea un cliente Android para `mx.balam.app` con los SHA-1 de desarrollo y
   producción.
4. Si publicarás iOS, crea también el cliente iOS para `mx.balam.app` y agrega
   su URL scheme invertido a `ios/Runner/Info.plist` según la consola de Google.

Para probar en Chrome usa un puerto fijo:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357 `
  --dart-define=GOOGLE_WEB_CLIENT_ID=TU_CLIENT_ID_WEB.apps.googleusercontent.com
```

Para Android, `GOOGLE_WEB_CLIENT_ID` sigue siendo el cliente web que recibe el
backend como audiencia. Para iOS proporciona también su client ID propio:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=TU_CLIENT_ID_WEB.apps.googleusercontent.com `
  --dart-define=GOOGLE_IOS_CLIENT_ID=TU_CLIENT_ID_IOS.apps.googleusercontent.com
```

Los builds release deben recibir las mismas variables `--dart-define`. Los
client IDs identifican públicamente a la aplicación; el client secret de Google
no se usa ni debe incluirse en Flutter.
