# Balam

MVP de marketplace para conectar clientes con agrupaciones musicales.

- `backend/`: FastAPI, autenticación JWT, SQLAlchemy/SQLite, perfiles, búsqueda y multimedia.
- `frontend/`: Flutter con alta por modalidad, formularios de perfil y catálogo de agrupaciones.

Consulta las instrucciones específicas en `backend/README.md` y `frontend/README.md`.

## Estado de despliegue

El código está preparado para construir la API y el cliente en modo release. Los únicos valores de infraestructura deliberadamente pendientes son:

- dominio público del cliente;
- URL HTTPS de la API;
- URL HTTPS y token del servicio que enviará códigos de recuperación;
- credenciales del PostgreSQL del proveedor.

Configura esos valores a partir de `backend/.env.production.example` y compila Flutter con `--dart-define=API_BASE_URL=https://...`. No guardes secretos ni archivos de firma en Git.
