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

La documentación interactiva queda en `http://127.0.0.1:8000/docs`. SQLite funciona sin instalar un servidor; para producción se puede usar PostgreSQL cambiando `DATABASE_URL`.

