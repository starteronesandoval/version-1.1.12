# Balam Flutter

1. Instala Flutter.
2. Ejecuta `flutter pub get`.
3. Inicia la API y después `flutter run`.

La URL predeterminada `http://10.0.2.2:8000` funciona en el emulador Android. Para iOS se usa `http://127.0.0.1:8000`. Para un teléfono físico puede pasarse la IP local sin editar código:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Validación y release

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://API_PENDIENTE
flutter build appbundle --release --dart-define=API_BASE_URL=https://API_PENDIENTE
```

Los builds release rechazan una URL HTTP o una URL de API ausente. El identificador de aplicación para Android e iOS es `mx.balam.app`. Para publicar en tiendas todavía se deben proporcionar las credenciales privadas de firma de Google Play y el equipo de Apple; nunca deben guardarse en Git.
