# Balam

## Conexión de la aplicación

Todas las compilaciones de Flutter, incluidas las de desarrollo y emulador, se
conectan exclusivamente al backend de Oracle mediante
`https://api.garibaldi.app`. No existe un lanzador ni un túnel local para la
aplicación.

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

Configura esos valores a partir de `backend/.env.production.example`. La URL
de la API móvil está fijada en el código a `https://api.garibaldi.app`. No
guardes secretos ni archivos de firma en Git.

Para las dispersiones, activa Stripe Connect y configura las variables
`CONNECT_REFRESH_URL` y `CONNECT_RETURN_URL` con endpoints HTTPS del backend.
El músico completa su identidad, información fiscal y cuenta bancaria en el
onboarding alojado por Stripe; Balam no captura nuevas CLABE o tarjetas.
