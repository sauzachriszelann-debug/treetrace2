import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from app.core.config import settings


def _is_configured() -> bool:
    return bool(settings.GMAIL_USER and settings.GMAIL_APP_PASSWORD)


def _send(to_email: str, subject: str, html: str, text: str) -> bool:
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"TreeTrace <{settings.GMAIL_USER}>"
        msg["To"] = to_email
        msg.attach(MIMEText(text, "plain"))
        msg.attach(MIMEText(html, "html"))

        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
            server.login(settings.GMAIL_USER, settings.GMAIL_APP_PASSWORD)
            server.sendmail(settings.GMAIL_USER, to_email, msg.as_string())
        print(f"[Email] Sent to {to_email}")
        return True
    except Exception as e:
        print(f"[Email] Failed to send to {to_email}: {e}")
        return False


def send_welcome_email(to_email: str, full_name: str, temp_password: str, role: str) -> bool:
    if not _is_configured():
        print(f"[Email] Gmail not configured — skipping. Credentials: {to_email} / {temp_password}")
        return False

    login_url = f"{settings.FRONTEND_URL}/login"
    role_label = "Administrator" if "admin" in str(role).lower() else "Field Worker"

    html = f"""
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background:#f5f5f0;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:560px;margin:40px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
    <div style="background:#2d5a27;padding:32px 40px;">
      <span style="color:rgba(255,255,255,0.9);font-size:15px;font-weight:500;">🌿 TreeTrace · Panabo City</span>
      <h1 style="color:white;font-size:26px;font-weight:700;margin:16px 0 0;">Welcome to TreeTrace!</h1>
      <p style="color:rgba(255,255,255,0.75);margin:8px 0 0;font-size:14px;">Your account has been created by an administrator.</p>
    </div>
    <div style="padding:32px 40px;">
      <p style="color:#374151;font-size:15px;">Hi <strong>{full_name}</strong>,</p>
      <p style="color:#6b7280;font-size:14px;line-height:1.6;">
        You've been added to the <strong>Panabo City Tree Inventory</strong> system as a
        <strong style="color:#2d5a27;">{role_label}</strong>.
      </p>
      <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;padding:24px;margin:20px 0;">
        <p style="color:#374151;font-weight:600;font-size:13px;margin:0 0 16px;text-transform:uppercase;">Your Login Credentials</p>
        <table style="width:100%;border-collapse:collapse;">
          <tr>
            <td style="color:#6b7280;font-size:13px;padding:6px 0;width:90px;">Email</td>
            <td style="color:#111827;font-size:14px;font-weight:500;">{to_email}</td>
          </tr>
          <tr>
            <td style="color:#6b7280;font-size:13px;padding:6px 0;">Password</td>
            <td><code style="background:#fef3c7;color:#92400e;font-size:15px;font-weight:700;padding:4px 10px;border-radius:6px;">{temp_password}</code></td>
          </tr>
        </table>
      </div>
      <div style="text-align:center;margin-bottom:24px;">
        <a href="{login_url}" style="display:inline-block;background:#2d5a27;color:white;font-weight:600;font-size:15px;padding:14px 32px;border-radius:10px;text-decoration:none;">Log In to TreeTrace →</a>
      </div>
      <p style="color:#9ca3af;font-size:12px;text-align:center;">Please change your password after your first login.</p>
    </div>
    <div style="background:#f9fafb;border-top:1px solid #e5e7eb;padding:16px 40px;text-align:center;">
      <p style="color:#9ca3af;font-size:11px;margin:0;">TreeTrace · Panabo City Geo-Spatial Tree Inventory System<br>This is an automated message — please do not reply.</p>
    </div>
  </div>
</body>
</html>
"""
    text = f"Welcome {full_name}!\n\nEmail: {to_email}\nPassword: {temp_password}\n\nLogin: {login_url}"
    return _send(to_email, "Your TreeTrace Account — Login Credentials", html, text)


def send_password_reset_email(to_email: str, full_name: str, new_password: str) -> bool:
    if not _is_configured():
        print(f"[Email] Gmail not configured — password reset for {to_email}: {new_password}")
        return False

    login_url = f"{settings.FRONTEND_URL}/login"
    html = f"""
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#f5f5f0;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:560px;margin:40px auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
    <div style="background:#2d5a27;padding:32px 40px;">
      <h1 style="color:white;font-size:22px;font-weight:700;margin:0;">🔑 Password Reset</h1>
    </div>
    <div style="padding:32px 40px;">
      <p style="color:#374151;">Hi <strong>{full_name}</strong>,</p>
      <p style="color:#6b7280;font-size:14px;">An administrator has reset your TreeTrace password.</p>
      <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;padding:20px;margin:20px 0;">
        <p style="margin:0;color:#6b7280;font-size:13px;">New temporary password:</p>
        <code style="background:#fef3c7;color:#92400e;font-size:16px;font-weight:700;padding:6px 12px;border-radius:6px;display:inline-block;margin-top:8px;">{new_password}</code>
      </div>
      <div style="text-align:center;">
        <a href="{login_url}" style="display:inline-block;background:#2d5a27;color:white;font-weight:600;padding:12px 28px;border-radius:10px;text-decoration:none;">Log In →</a>
      </div>
    </div>
  </div>
</body>
</html>
"""
    text = f"Hi {full_name},\n\nYour password has been reset.\n\nNew password: {new_password}\n\nLogin: {login_url}"
    return _send(to_email, "TreeTrace — Your Password Has Been Reset", html, text)