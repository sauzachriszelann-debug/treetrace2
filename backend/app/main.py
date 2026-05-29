from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from app.db.database import engine, Base
from app.core.config import settings
from app.api.routes import auth, trees, health_logs, users, storage, public, identify, evaluation, planting

# Import all models
from app.models import user, tree, health_log, evaluation_result, planting_recommendation
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


def sync_subscription_columns():
    if not settings.SQLALCHEMY_DATABASE_URL.startswith("postgresql"):
        return
    statements = (
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_plan VARCHAR(20) NOT NULL DEFAULT 'free'",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS upgrade_requested BOOLEAN NOT NULL DEFAULT FALSE",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_identifications_today INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS unknown_submissions_today INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_usage_date DATE",
    )
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))


# Move database creation to a startup event so it doesn't freeze the server
@app.on_event("startup")
def startup_event():
    print("Attempting to connect to Aiven Database...")
    try:
        # This will create tables if they don't exist
        Base.metadata.create_all(bind=engine)
        sync_subscription_columns()
        sync_postgres_sequences()
        print("Database connection successful and tables synchronized!")
    except Exception as e:
        print("DATABASE CONNECTION ERROR:")
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
app.include_router(evaluation.router,  prefix="/api/evaluation",  tags=["Evaluation"])
app.include_router(planting.router,    prefix="/api/planting",    tags=["Planting Recommendations"])


@app.get("/")
def root():
    return {"message": "TreeTrace API is running", "version": "1.0.0"}


@app.get("/api/health")
def health_check():
    return {"status": "ok"}
