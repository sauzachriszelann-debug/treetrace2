from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from app.db.database import engine, Base
from app.core.config import settings
from app.api.routes import auth, trees, health_logs, users, storage, public, identify

# Import all models
from app.models import user, tree, health_log
from app.models.unknown_species import UnknownSpecies

# --- REMOVED THE BLOCKING LINE FROM HERE ---
# Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="TreeTrace API",
    description="Geo-Spatial Tree Inventory System for Panabo City",
    version="1.0.0",
    redirect_slashes=False,
)


def sync_postgres_sequences():
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return

    tables = ("users", "trees", "health_logs")
    with engine.begin() as conn:
        for table in tables:
            conn.execute(
                text(
                    f"""
                    SELECT setval(
                        pg_get_serial_sequence('{table}', 'id'),
                        COALESCE((SELECT MAX(id) FROM {table}), 1),
                        (SELECT COUNT(*) > 0 FROM {table})
                    )
                    """
                )
            )


# Move database creation to a startup event so it doesn't freeze the server
@app.on_event("startup")
def startup_event():
    print("📡 Attempting to connect to Aiven Database...")
    try:
        # This will create tables if they don't exist
        Base.metadata.create_all(bind=engine)
        sync_postgres_sequences()
        print("✅ Database connection successful and tables synchronized!")
    except Exception as e:
        print("❌ DATABASE CONNECTION ERROR:")
        print(e)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "https://treetrace-1o7l.onrender.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(auth.router,        prefix="/api/auth",        tags=["Auth"])
app.include_router(users.router,       prefix="/api/users",       tags=["Users"])
app.include_router(trees.router,       prefix="/api/trees",       tags=["Trees"])
app.include_router(health_logs.router, prefix="/api/health-logs", tags=["Health Logs"])
app.include_router(storage.router,     prefix="/api/storage",     tags=["Storage"])
app.include_router(public.router,      prefix="/api/public",      tags=["Public"])
app.include_router(identify.router,    prefix="/api/ai",          tags=["AI Identification"])


@app.get("/")
def root():
    return {"message": "TreeTrace API is running", "version": "1.0.0"}


@app.get("/api/health")
def health_check():
    return {"status": "ok"}
