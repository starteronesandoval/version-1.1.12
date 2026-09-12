# Balam

## Inicio local en un paso (Windows)

Ejecuta `INICIAR-GARIBALDI.cmd`. El lanzador:

1. comprueba el acceso a los certificados publicos de Google;
2. inicia el backend si el puerto local todavia no responde;
3. valida el endpoint `/health`; y
4. abre la app en un teléfono físico autorizado mediante ADB, si está conectado.

El lanzador no inicia emuladores: QEMU es inestable en esta computadora. Si no
hay un teléfono conectado por ADB, deja el backend listo para abrir Garibaldi
manualmente en el teléfono.

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
