# ☁️ Cloud Deployment Guide — upay Voice Guard

Production deployment instructions for **Render** and **Railway**.

---

## Pre-requisites

1. Push this project to a **GitHub** (or GitLab) repository.
2. Make sure the following files are at the repository root (`upay_voice_guard/`):
   - `Dockerfile`
   - `Procfile`
   - `render.yaml`
   - `railway.json`
   - `requirements.txt`

---

## Option A: Deploy to Render (Recommended — Free Tier)

### 1. Create a Render account
Go to [render.com](https://render.com) and sign up (GitHub login works).

### 2. New → Web Service
- Connect your GitHub repo
- **Root Directory**: `upay_voice_guard` (or leave blank if repo root = project root)
- Render auto-detects `render.yaml` — click **Apply**

### 3. Environment Variables
In the Render dashboard → Environment tab, add any optional secrets:

| Variable               | Required? | Description                          |
|------------------------|-----------|--------------------------------------|
| `GEMINI_API_KEY`       | Optional  | Gemini LLM for smart intent parsing  |
| `TELEGRAM_BOT_TOKEN`   | Optional  | Telegram bot (from @BotFather)       |
| `OPENAI_API_KEY`       | Optional  | Whisper STT for voice transcription  |
| `WHATSAPP_TOKEN`       | Optional  | Meta WhatsApp Business access token  |
| `WHATSAPP_PHONE_ID`    | Optional  | WhatsApp phone number ID             |
| `WHATSAPP_VERIFY_TOKEN`| Optional  | Custom webhook verify token           |

### 4. Deploy
Click **Manual Deploy → Deploy latest commit**.  
Your app will be live at: `https://upay-voice-guard.onrender.com`

### 5. Verify
```bash
curl https://upay-voice-guard.onrender.com/health
# → {"status":"healthy","service":"upay-voice-guard","whatsapp_configured":false}
```

---

## Option B: Deploy to Railway

### 1. Create a Railway account
Go to [railway.app](https://railway.app) and sign up.

### 2. New Project → Deploy from GitHub
- Select your repository
- Railway auto-detects the `Dockerfile`

### 3. Environment Variables
In the project dashboard, add the same variables from the table above.

### 4. Generate Domain
Settings → Networking → Generate Domain  
Your app will be live at: `https://your-project.up.railway.app`

---

## WhatsApp Webhook Setup

If you're using the WhatsApp Bot:

1. Go to [Meta Developer Portal](https://developers.facebook.com)
2. Create an App → Business → WhatsApp
3. In the WhatsApp settings, configure the Webhook:
   - **Callback URL**: `https://your-domain.com/whatsapp/webhook`
   - **Verify Token**: Your `WHATSAPP_VERIFY_TOKEN` value
   - **Subscriptions**: `messages`
4. Get a **Permanent Access Token** and **Phone Number ID** from the API Setup page
5. Set the environment variables on your cloud platform

---

## Telegram Bot Webhook (Optional)

For production, switch the Telegram bot from polling to webhook:

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-domain.com/telegram/webhook"
```

> Note: The current Telegram bot uses polling mode (standalone script).
> For cloud deployment, you can run it as a separate worker process or convert to webhook mode.

---

## SQLite Notes for Cloud

The demo uses **SQLite** which stores data in a local file (`voice_guard.db`).  
This works fine because:
- All data is **fake/demo** data
- The DB is auto-seeded on first run
- Data resets on each redeploy (which is fine for a hackathon demo)

For production, migrate to **PostgreSQL** (both Render and Railway offer managed Postgres).

---

## Quick Verification Checklist

After deployment, test these endpoints:

```bash
# Health check
curl https://YOUR_DOMAIN/health

# Start a session
curl -X POST https://YOUR_DOMAIN/session/start

# Web UI
open https://YOUR_DOMAIN/

# Check transaction limit
curl https://YOUR_DOMAIN/limit
```
