# Balam Flutter

1. Instala Flutter.
2. Ejecuta `flutter pub get`.
3. Inicia la API y después `flutter run`.

La URL predeterminada `http://10.0.2.2:8000` funciona en el emulador Android. Para iOS se usa `http://127.0.0.1:8000`. Para un teléfono físico puede pasarse la IP local sin editar código:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Compilación conectada

La aplicación siempre se conecta al backend. Para publicarla, la API debe estar
alojada en un servicio web HTTPS:

```powershell
flutter build apk --release `
  --dart-define=API_BASE_URL=https://api.tudominio.com
```

## Validación y release

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://API_PENDIENTE
flutter build appbundle --release --dart-define=API_BASE_URL=https://API_PENDIENTE
```

Los builds release rechazan una URL HTTP o una URL de API ausente. El identificador de aplicación para Android e iOS es `mx.balam.app`. Para publicar en tiendas todavía se deben proporcionar las credenciales privadas de firma de Google Play y el equipo de Apple; nunca deben guardarse en Git.

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
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 `
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
