# Balam API

API REST para registro de clientes y agrupaciones musicales.

## Ejecución

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
uvicorn app.main:app --reload
```

La documentación interactiva queda en `http://127.0.0.1:8000/docs` y se desactiva automáticamente en producción.

## PostgreSQL y producción

Producción exige PostgreSQL, una clave JWT aleatoria de al menos 32 caracteres,
orígenes CORS explícitos, hosts permitidos y una cuenta SMTP para entregar por
correo los códigos de recuperación. Usa `.env.production.example` como referencia, nunca
lo copies con sus valores de muestra a un servidor real.

Antes de iniciar una versión nueva, aplica las migraciones:

```powershell
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
```

Para levantar PostgreSQL y la API localmente con contenedores, define
`POSTGRES_PASSWORD`, `SECRET_KEY`, `CORS_ORIGINS`, `ALLOWED_HOSTS`,
`SMTP_HOST`, `SMTP_FROM_EMAIL` y las credenciales SMTP, y ejecuta desde la raíz:

```powershell
docker compose up --build
```

El pool acepta `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW` y
`DATABASE_POOL_TIMEOUT`. `DATABASE_POOL_RECYCLE` renueva conexiones antiguas y
`DATABASE_CONNECT_TIMEOUT` limita intentos de conexión bloqueados. Ajusta esos
valores al límite de conexiones de tu proveedor. El endpoint `/health`
comprueba también la conexión a la base.

Para PostgreSQL administrado (por ejemplo AWS RDS), configura
`DATABASE_SSL_MODE=require`. Para validar también la identidad del servidor usa
`verify-full`, monta el certificado CA del proveedor y define
`DATABASE_SSL_ROOT_CERT` con su ruta dentro del contenedor. La contraseña debe
provenir del gestor de secretos del proveedor y nunca del repositorio.

El almacenamiento de `UPLOAD_DIR` debe montarse en un volumen persistente. Para
escalar horizontalmente a varias instancias, el siguiente paso es mover los
archivos a almacenamiento de objetos compatible con S3.

## Pagos con Stripe

La API crea sesiones de Stripe Checkout usando únicamente el total calculado y
congelado por el servidor en cada contratación. Configura `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `BILLING_SUCCESS_URL` y `BILLING_CANCEL_URL`. El webhook
público es `POST /api/billing/webhooks/stripe`; registra ese endpoint en Stripe
y nunca confirmes un pago desde el cliente móvil.

El precio público se calcula a partir del precio por hora que fija el músico.
Para contratos nuevos se agrega una proyección de 7.1%: 3% de comisión de Balam
al cliente, 3.6% de procesamiento Stripe y 0.5% de dispersión bancaria. El
músico recibe 97% de su precio base (su precio menos 3% de comisión de Balam).
Los contratos ya creados conservan el importe congelado originalmente.

### Regla de alta para recibir ganancias

El registro inicial del músico no solicita RFC, CLABE ni documentación bancaria
a Balam. Desde su perfil, la agrupación puede abrir **Completar datos en
Stripe** antes de recibir su primer contrato. La API crea una cuenta Connect
Express y un enlace de onboarding de un solo uso; Stripe recopila directamente
los datos de identidad, fiscales y bancarios.

Si el cliente califica antes de que la cuenta conectada esté lista, la
dispersión queda pendiente; no se pierde ni se marca como pagada. Cuando Stripe
confirma la cuenta, el sistema puede reintentar la transferencia. Balam debe
mostrar solamente el estado y los últimos cuatro dígitos del destino, sin
exponer RFC, CLABE completa ni documentos en el panel administrativo.

Configura también `CONNECT_REFRESH_URL` y `CONNECT_RETURN_URL` con URLs HTTPS
públicas del backend. En Stripe registra el webhook de plataforma y habilita
eventos de cuentas conectadas para `account.updated`, `payout.paid` y
`payout.failed`. `account.updated` habilita y reintenta transferencias que ya
fueron autorizadas; los eventos de payout permiten mostrar si Stripe confirmó o
rechazó el depósito bancario.

## Acceso con Google

Crea clientes OAuth en Google Cloud para las plataformas que vayas a publicar.
El backend debe incluir el client ID de tipo **Aplicación web**, porque es la
audiencia utilizada para validar los ID tokens:

```text
GOOGLE_CLIENT_IDS=1234567890-ejemplo.apps.googleusercontent.com
```

Se pueden aceptar varias audiencias separándolas con comas. Nunca envíes un
client secret a Flutter ni lo guardes en este repositorio. El endpoint
`POST /api/auth/google` valida la firma y los claims del token antes de crear la
sesión Balam.
