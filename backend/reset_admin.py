from app.db.database import SessionLocal
from app.models.user import User
from app.core.security import hash_password

db = SessionLocal()

user = db.query(User).filter(User.email == "sauzachriszelann@gmail.com").first()
if user:
    user.hashed_password = hash_password("sauzaCHRISZELann")
    db.commit()
    print(f"Password reset for {user.email}")
else:
    print("User not found — check the email")

db.close()

