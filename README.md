# Balam

## Inicio local en un paso (Windows)

Ejecuta `INICIAR-GARIBALDI.cmd`. El lanzador:

1. comprueba el acceso a los certificados publicos de Google;
2. inicia el backend si el puerto local todavia no responde;
3. valida el endpoint `/health`; y
4. abre la app mediante ADB en un teléfono físico autorizado o en un emulador
   que ya esté encendido.

El lanzador no inicia emuladores: QEMU es inestable en esta computadora. Si no
hay un dispositivo conectado por ADB, deja el backend listo para abrir
Garibaldi cuando se conecte un teléfono o se encienda el emulador. En el
emulador, la compilación de desarrollo usa `http://10.0.2.2:8000` para acceder
al backend local.

El backend queda ejecutandose en segundo plano. Sus registros se guardan en
`backend/runtime-api.log` y `backend/runtime-api-error.log`.

MVP de marketplace para conectar clientes con agrupaciones musicales.

- `backend/`: FastAPI, autenticación JWT, SQLAlchemy/SQLite, perfiles, búsqueda y multimedia.
- `frontend/`: Flutter con alta por modalidad, formularios de perfil y catálogo de agrupaciones.

Consulta las instrucciones específicas en `backend/README.md` y `frontend/README.md`.

## Estado de despliegue

El código está preparado para construir la API y el cliente en modo release. Los únicos valores de infraestructura deliberadamente pendientes son:

- dominio público del cliente;
- URL HTTPS de la API;
- servidor y credenciales SMTP para enviar códigos de recuperación por correo;
- credenciales del PostgreSQL del proveedor.
- clientes OAuth de Google para web y las plataformas móviles publicadas.

Configura esos valores a partir de `backend/.env.production.example` y compila Flutter con `--dart-define=API_BASE_URL=https://...`. No guardes secretos ni archivos de firma en Git.

## Publicación segura mediante Cloudflare Tunnel

El origen está configurado para escuchar únicamente en `127.0.0.1:8000`. No
abras el puerto 8000 en Windows Firewall ni en el router. Cloudflare Tunnel debe
ser la única entrada pública.

1. Copia `cloudflare/config.yml.example` fuera del repositorio y reemplaza el
   UUID, la ruta de credenciales y `api.tudominio.com`.
2. Define `ALLOWED_HOSTS=api.tudominio.com`, los orígenes HTTPS exactos en
   `CORS_ORIGINS` y todos los secretos de `backend/.env.production.example`.
3. Ejecuta la API y confirma que responde en `http://127.0.0.1:8000/health`,
   pero no en `http://IP-DE-LA-PC:8000/health` desde otro dispositivo.
4. Ejecuta `cloudflared tunnel --config RUTA_CONFIG run UUID_DEL_TUNEL` como
   un usuario sin privilegios. El token o JSON de credenciales nunca debe
   guardarse en Git ni copiarse a la aplicación Flutter.
5. En Cloudflare configura WAF y rate limiting para `/api/auth/*`; no habilites
   reglas de cache para `/api/*`. Mantén el webhook de Stripe público, limitado
   a `POST`, ya que el backend valida su firma.

Los endpoints administrativos deben protegerse adicionalmente mediante una
aplicación de Cloudflare Access o reglas equivalentes. No protejas todo el
hostname con Access porque bloquearía la aplicación móvil y el webhook de
Stripe.

Para las dispersiones, activa Stripe Connect y configura las variables
`CONNECT_REFRESH_URL` y `CONNECT_RETURN_URL` con endpoints HTTPS del backend.
El músico completa su identidad, información fiscal y cuenta bancaria en el
onboarding alojado por Stripe; Balam no captura nuevas CLABE o tarjetas.
