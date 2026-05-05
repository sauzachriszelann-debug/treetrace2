import pymysql
import psycopg2

# MySQL connection (local)
mysql = pymysql.connect(
    host='localhost',
    user='root',
    password='',
    database='treetracecp',
    charset='utf8mb4'
)

# Aiven PostgreSQL connection
pg = psycopg2.connect(
    'postgresql://avnadmin:AVNS_6lrqT6vX1yxxJM5R2TT@treetrace-db-treetrace.d.aivencloud.com:28761/defaultdb?sslmode=require'
)

mysql_cursor = mysql.cursor(pymysql.cursors.DictCursor)
pg_cursor    = pg.cursor()

# ── Migrate users ─────────────────────────────────────────────────────────────
print("Migrating users...")
mysql_cursor.execute("SELECT * FROM users")
users = mysql_cursor.fetchall()
for u in users:
    pg_cursor.execute("""
        INSERT INTO users (id, full_name, email, hashed_password, role, is_active, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (id) DO NOTHING
    """, (u['id'], u['full_name'], u['email'], u['hashed_password'],
          u['role'], bool(u['is_active']), u['created_at']))
print(f"  Migrated {len(users)} users")

# ── Migrate trees ─────────────────────────────────────────────────────────────
print("Migrating trees...")
mysql_cursor.execute("SELECT * FROM trees")
trees = mysql_cursor.fetchall()
for t in trees:
    pg_cursor.execute("""
        INSERT INTO trees (id, common_name, scientific_name, dbh_cm, height_m,
            carbon_kg, health_status, barangay, city, lat, lng,
            photo_url, qr_code_url, notes, recorded_by_id, created_at, updated_at)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (id) DO NOTHING
    """, (t['id'], t['common_name'], t['scientific_name'], t['dbh_cm'],
          t['height_m'], t['carbon_kg'], t['health_status'], t['barangay'],
          t['city'], t['lat'], t['lng'], t['photo_url'], t['qr_code_url'],
          t['notes'], t['recorded_by_id'], t['created_at'], t['updated_at']))
print(f"  Migrated {len(trees)} trees")

# ── Migrate health_logs ───────────────────────────────────────────────────────
print("Migrating health logs...")
mysql_cursor.execute("SELECT * FROM health_logs")
logs = mysql_cursor.fetchall()
for l in logs:
    pg_cursor.execute("""
        INSERT INTO health_logs (id, tree_id, condition, notes, assessed_date,
            dbh_cm, height_m, photo_url, assessed_by_id, created_at)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        ON CONFLICT (id) DO NOTHING
    """, (l['id'], l['tree_id'], l['condition'], l['notes'],
          l['assessed_date'], l['dbh_cm'], l['height_m'],
          l['photo_url'], l['assessed_by_id'], l['created_at']))
print(f"  Migrated {len(logs)} health logs")

# ── Commit and close ──────────────────────────────────────────────────────────
pg.commit()
mysql_cursor.close()
pg_cursor.close()
mysql.close()
pg.close()

print("\n✅ Migration complete!")