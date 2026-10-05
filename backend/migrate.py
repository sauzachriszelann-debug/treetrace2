import os
from urllib.parse import parse_qs, unquote, urlparse

import pymysql
import psycopg2


def _required_environment(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"{name} must be set before running this migration.")
    return value


def _connect_source_database(url: str):
    parsed = urlparse(url)
    if parsed.scheme not in {"mysql", "mysql+pymysql"}:
        raise RuntimeError("MIGRATION_SOURCE_DATABASE_URL must be a MySQL URL.")

    query = parse_qs(parsed.query)
    return pymysql.connect(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        database=parsed.path.lstrip("/"),
        charset=query.get("charset", ["utf8mb4"])[0],
    )


def main() -> None:
    source_url = _required_environment("MIGRATION_SOURCE_DATABASE_URL")
    target_url = _required_environment("MIGRATION_TARGET_DATABASE_URL")
    mysql = _connect_source_database(source_url)
    pg = psycopg2.connect(target_url)

    try:
        mysql_cursor = mysql.cursor(pymysql.cursors.DictCursor)
        pg_cursor = pg.cursor()
        try:
            print("Migrating users...")
            mysql_cursor.execute("SELECT * FROM users")
            users = mysql_cursor.fetchall()
            for user in users:
                pg_cursor.execute(
                    """
                    INSERT INTO users (id, full_name, email, hashed_password, role, is_active, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (id) DO NOTHING
                    """,
                    (user["id"], user["full_name"], user["email"], user["hashed_password"],
                     user["role"], bool(user["is_active"]), user["created_at"]),
                )
            print(f"Migrated {len(users)} users.")

            print("Migrating trees...")
            mysql_cursor.execute("SELECT * FROM trees")
            trees = mysql_cursor.fetchall()
            for tree in trees:
                pg_cursor.execute(
                    """
                    INSERT INTO trees (id, common_name, scientific_name, dbh_cm, height_m,
                        carbon_kg, health_status, barangay, city, lat, lng,
                        photo_url, qr_code_url, notes, recorded_by_id, created_at, updated_at)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (id) DO NOTHING
                    """,
                    (tree["id"], tree["common_name"], tree["scientific_name"], tree["dbh_cm"],
                     tree["height_m"], tree["carbon_kg"], tree["health_status"], tree["barangay"],
                     tree["city"], tree["lat"], tree["lng"], tree["photo_url"], tree["qr_code_url"],
                     tree["notes"], tree["recorded_by_id"], tree["created_at"], tree["updated_at"]),
                )
            print(f"Migrated {len(trees)} trees.")

            print("Migrating health logs...")
            mysql_cursor.execute("SELECT * FROM health_logs")
            logs = mysql_cursor.fetchall()
            for log in logs:
                pg_cursor.execute(
                    """
                    INSERT INTO health_logs (id, tree_id, condition, notes, assessed_date,
                        dbh_cm, height_m, photo_url, assessed_by_id, created_at)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    ON CONFLICT (id) DO NOTHING
                    """,
                    (log["id"], log["tree_id"], log["condition"], log["notes"],
                     log["assessed_date"], log["dbh_cm"], log["height_m"],
                     log["photo_url"], log["assessed_by_id"], log["created_at"]),
                )
            print(f"Migrated {len(logs)} health logs.")
            pg.commit()
        except Exception:
            pg.rollback()
            raise
        finally:
            mysql_cursor.close()
            pg_cursor.close()
    finally:
        mysql.close()
        pg.close()


if __name__ == "__main__":
    main()
