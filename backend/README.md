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
`DATABASE_POOL_TIMEOUT`. Ajusta esos valores al límite de conexiones de tu
proveedor. El endpoint `/health` comprueba también la conexión a la base.

El almacenamiento de `UPLOAD_DIR` debe montarse en un volumen persistente. Para
escalar horizontalmente a varias instancias, el siguiente paso es mover los
archivos a almacenamiento de objetos compatible con S3.

## Pagos con Stripe

La API crea sesiones de Stripe Checkout usando únicamente el total calculado y
congelado por el servidor en cada contratación. Configura `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `BILLING_SUCCESS_URL` y `BILLING_CANCEL_URL`. El webhook
público es `POST /api/billing/webhooks/stripe`; registra ese endpoint en Stripe
y nunca confirmes un pago desde el cliente móvil.

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
