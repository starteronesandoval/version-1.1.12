# Despliegue en Google Cloud Run

La aplicación ASGI es `app.main:app`. El contenedor escucha en `0.0.0.0` y usa
`PORT`; Cloud Run la define automáticamente (normalmente `8080`). Las migraciones
no se ejecutan durante el arranque de cada instancia: usa el Job descrito abajo
antes de enviar tráfico a una revisión nueva.

## Base de datos y archivos

Usa una instancia PostgreSQL de Cloud SQL y su nombre de conexión
`PROYECTO:REGION:INSTANCIA`. El valor de `DATABASE_URL`, guardado en Secret
Manager, debe usar el socket que monta Cloud Run:

```text
postgresql+psycopg://USUARIO:CONTRASENA@/NOMBRE_DB?host=/cloudsql/PROYECTO:REGION:INSTANCIA
```

La contraseña debe codificarse como URL si contiene caracteres reservados. Con el
conector de Cloud SQL, usa `DATABASE_SSL_MODE=disable`: el conector autentica y
cifra el canal hacia Cloud SQL. Para una conexión TCP directa configura TLS según
el proveedor y no incluyas su certificado o contraseña en la imagen.

`/tmp/uploads` es efímero en Cloud Run. Los avatares, fotos y vídeos no deben
considerarse persistentes allí: antes de producción con varias instancias hay que
moverlos a Cloud Storage y almacenar URLs públicas o firmadas. La API actual
conserva el directorio local para desarrollo y el volumen de docker-compose.

La API también ejecuta revisiones periódicas de pagos y notificaciones dentro del
proceso web. Por eso el comando recomendado mantiene una instancia mínima y CPU
sin throttling. Si se desea escalar a cero, esas revisiones deben trasladarse a
Cloud Run Jobs invocados por Cloud Scheduler.

## Variables de entorno

El archivo `cloud-run.env.yaml.example` contiene las variables no secretas. Define
en Secret Manager: `DATABASE_URL`, `SECRET_KEY`, `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `SMTP_HOST`, `SMTP_USERNAME` y `SMTP_PASSWORD`.

También son requeridas en producción: `APP_ENV=production`, `CORS_ORIGINS`,
`ALLOWED_HOSTS`, `BILLING_SUCCESS_URL`, `BILLING_CANCEL_URL`,
`CONNECT_REFRESH_URL`, `CONNECT_RETURN_URL`, `GOOGLE_CLIENT_IDS`,
`SMTP_FROM_EMAIL` y `UPLOAD_DIR`. Para notificaciones activa `FCM_PROJECT_ID`.
Cloud Run usará Application Default Credentials de su cuenta de servicio; no
definas `GOOGLE_APPLICATION_CREDENTIALS` ni `FCM_CREDENTIALS_FILE`.

Las variables opcionales de ajuste son: `ACCESS_TOKEN_MINUTES`, `EVENT_TIMEZONE`,
`DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW`, `DATABASE_POOL_TIMEOUT`,
`DATABASE_POOL_RECYCLE`, `DATABASE_CONNECT_TIMEOUT`, `DATABASE_SSL_MODE`,
`SMTP_PORT`, `SMTP_FROM_NAME`, `SMTP_STARTTLS`, `PAYOUT_AUTO_RELEASE_HOURS`,
`PAYOUT_RELEASE_SCAN_SECONDS`, `PUSH_SCAN_SECONDS`, los cuatro límites `MAX_*`,
`AUTH_RATE_LIMIT_PER_MINUTE`, `PASSWORD_RESET_RATE_LIMIT_PER_HOUR` y
`TRUST_CLOUDFLARE_HEADERS`.

## CORS y hosts

Autoriza en `CORS_ORIGINS` sólo las aplicaciones web que ejecuten JavaScript en
un navegador: por ejemplo `https://app.tudominio.com` y
`https://www.tudominio.com`. Las apps Android e iOS no envían el encabezado
`Origin`, por lo que no se añaden. Incluye el host de la API en `ALLOWED_HOSTS`:
`api.tudominio.com` y, mientras se usa, el dominio `*.run.app` exacto que Cloud
Run entregue. No incluyas rutas, comodines ni `http` en estas listas.

## Comandos de PowerShell

Ejecuta los siguientes comandos desde `backend`, sustituyendo los valores entre
comillas. Crean recursos y preparan un despliegue, pero el último comando queda
documentado para cuando decidas desplegar.

```powershell
$ProjectId = "TU_PROYECTO"
$Region = "us-central1"
$Service = "garibaldi-api"
$Repository = "garibaldi"
$ImageTag = "v1"
$CloudSqlInstance = "$ProjectId`:$Region`:TU_INSTANCIA"
$ServiceAccount = "garibaldi-api@$ProjectId.iam.gserviceaccount.com"
$Image = "$Region-docker.pkg.dev/$ProjectId/$Repository/garibaldi-api:$ImageTag"

gcloud config set project $ProjectId
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com
gcloud artifacts repositories create $Repository --repository-format=docker --location=$Region
gcloud iam service-accounts create garibaldi-api --display-name="Garibaldi API Cloud Run"
gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:$ServiceAccount" --role="roles/cloudsql.client"
Copy-Item cloud-run.env.yaml.example cloud-run.env.yaml
```

Crea los secretos sin escribir valores en código, archivos versionados ni el
historial del terminal. Para cada nombre, el comando solicita el valor de forma
oculta:

```powershell
$Secrets = "database-url","secret-key","stripe-secret-key","stripe-webhook-secret","smtp-host","smtp-username","smtp-password"
foreach ($Secret in $Secrets) { gcloud secrets create $Secret --replication-policy=automatic }
foreach ($Secret in $Secrets) { $Value = Read-Host "Valor para $Secret" -AsSecureString; $Plain = [System.Net.NetworkCredential]::new("", $Value).Password; [System.Text.Encoding]::UTF8.GetBytes($Plain) | gcloud secrets versions add $Secret --data-file=-; Remove-Variable Plain }
foreach ($Secret in $Secrets) { gcloud secrets add-iam-policy-binding $Secret --member="serviceAccount:$ServiceAccount" --role="roles/secretmanager.secretAccessor" }
```

Construye la imagen, aplica primero las migraciones como un Job de una tarea y
después despliega el servicio. Reemplaza las cuatro URLs de pago en
`cloud-run.env.yaml` antes de continuar.

```powershell
gcloud builds submit . --tag $Image
$SecretBindings = "DATABASE_URL=database-url:latest,SECRET_KEY=secret-key:latest,STRIPE_SECRET_KEY=stripe-secret-key:latest,STRIPE_WEBHOOK_SECRET=stripe-webhook-secret:latest,SMTP_HOST=smtp-host:latest,SMTP_USERNAME=smtp-username:latest,SMTP_PASSWORD=smtp-password:latest"
gcloud run jobs create "$Service-migrate" --image $Image --region $Region --service-account $ServiceAccount --tasks 1 --max-retries 0 --task-timeout 10m --set-cloudsql-instances $CloudSqlInstance --env-vars-file cloud-run.env.yaml --set-secrets $SecretBindings --command alembic --args upgrade,head
gcloud run jobs execute "$Service-migrate" --region $Region --wait
gcloud run deploy $Service --image $Image --region $Region --allow-unauthenticated --port 8080 --service-account $ServiceAccount --set-cloudsql-instances $CloudSqlInstance --env-vars-file cloud-run.env.yaml --set-secrets $SecretBindings --memory 1Gi --cpu 1 --no-cpu-throttling --min-instances 1 --concurrency 40 --max-instances 5
```

El Job se crea una vez. Para versiones posteriores usa `gcloud run jobs update`
con los mismos argumentos antes de `gcloud run jobs execute`; para el servicio,
vuelve a ejecutar `gcloud run deploy` con la nueva imagen. La cuenta de servicio
también necesita el rol de envío de Firebase Cloud Messaging en el proyecto de
Firebase si se activan notificaciones push.
