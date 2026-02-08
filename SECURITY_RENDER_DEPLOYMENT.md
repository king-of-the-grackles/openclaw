# OpenClaw Security - Render Cloud Deployment Guide

**Status**: ✅ Docker entrypoint hardened | 🚀 Ready for secure Render deployment

---

## 🚀 Quick Deploy to Render (15 minutes)

This guide deploys OpenClaw securely to Render Cloud with proper credential management and defense-in-depth security.

### Prerequisites

- ✅ GitHub account
- ✅ [Render account](https://render.com) (free tier works)
- ✅ Telegram bot created via [@BotFather](https://t.me/BotFather)
- ✅ (Optional) [Tailscale account](https://tailscale.com) for HTTPS access

---

## Step 1: Prepare Telegram Credentials (2 min)

### Get Fresh Bot Token

**Important**: If you've ever committed config with tokens, rotate immediately.

1. Open Telegram → [@BotFather](https://t.me/BotFather)
2. Send: `/mybots` → Select your bot → "API Token"
3. Click "Revoke current token" (invalidates old token)
4. **Copy the new token** (starts with a number like `8359492041:...`)
5. Save securely (you'll add to Render dashboard next)

### Get Your Telegram User ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Copy your numeric ID (e.g., `5177091981`)
3. Save for next step

---

## Step 2: Deploy to Render (5 min)

### Create Web Service

1. Go to [Render Dashboard](https://dashboard.render.com/)
2. Click **New** → **Web Service**
3. Connect your GitHub repository:
   - **Repository**: `openclaw/openclaw` (or your fork)
   - **Branch**: `main`
4. Render auto-detects `render.yaml` configuration
5. Click **Create Web Service** (don't deploy yet!)

### Configure Environment Variables

Before first deploy, go to **Environment** tab and add:

| Variable Name | Value | Mark as Secret? | Notes |
|---------------|-------|-----------------|-------|
| `TELEGRAM_BOT_TOKEN` | `<paste-token-from-step-1>` | ✅ Yes | **Required** - Rotated token |
| `TELEGRAM_ALLOWFROM` | `5177091981` | ❌ No | Your Telegram user ID(s) |
| `SETUP_PASSWORD` | `<strong-password>` | ✅ Yes | **Required** - For initial setup |
| `TS_AUTHKEY` | `tskey-auth-...` | ✅ Yes | **Optional** - See Step 3 |

**Auto-Generated Variables** (already in render.yaml):
- ✅ `PORT=8080` (health check port)
- ✅ `OPENCLAW_GATEWAY_TOKEN` (auto-generated, don't set manually)
- ✅ `OPENCLAW_STATE_DIR=/data/.openclaw` (persistent volume)

### Multiple Allowed Users

To allow multiple Telegram users, use comma-separated IDs:
```
TELEGRAM_ALLOWFROM=5177091981,123456789,987654321
```

---

## Step 3: (Optional) Enable Tailscale HTTPS (3 min)

**Why**: Provides secure HTTPS access with device identity verification.

**Without Tailscale**: Gateway only accessible via health check endpoint (not practical for Control UI)

**With Tailscale**: Gateway accessible via `https://<hostname>.ts.net` with full security

### Generate Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure:
   - ✅ **Reusable**: Yes (survives container restarts)
   - ❌ **Ephemeral**: No (persistent device)
   - ✅ **Preauthorized**: Yes
   - **Tags**: `tag:openclaw` (optional, for ACL rules)
4. Copy auth key (starts with `tskey-auth-...`)
5. Add to Render Environment tab as `TS_AUTHKEY` (**mark as secret**)

---

## Step 4: Deploy Service (5 min)

1. Render Dashboard → Your service → **Manual Deploy**
2. Click **Deploy latest commit**
3. Watch deployment logs for success indicators:

```log
✅ [entrypoint] Installing bundled plugins (first boot)...
✅ [entrypoint] Creating secure Telegram configuration...
✅ [entrypoint] Starting Tailscale daemon (userspace networking)...
✅ [entrypoint] Tailscale Serve: https://openclaw-render.<tailnet>.ts.net → localhost:8080
✅ [INFO] Gateway listening on 0.0.0.0:8080
✅ [INFO] Telegram bot started, dmPolicy=allowlist
```

**Expected deploy time**: 3-5 minutes for first deploy (includes bundled plugin installation)

**Service Status**: Should show "Live" with green indicator

---

## Step 5: Verify Security (5 min)

### Test 1: Telegram Bot Allowlist

1. Open Telegram and message your bot (from allowed user ID)
2. **Expected**: Bot responds ✅
3. Message bot from different Telegram account
4. **Expected**: Silently rejected ❌ (check Render logs)

**Render Logs** should show:
```log
✅ Message received from user 5177091981 (allowed)
⚠️  Rejected DM from unauthorized user: 123456789
```

### Test 2: Gateway Access via Tailscale

**Find your Tailscale hostname**:
- Render Logs → Search for "Tailscale Serve"
- Or [Tailscale Admin Console](https://login.tailscale.com/admin/machines) → Find "openclaw-render"

**Access Control UI**:
1. Open browser: `https://<hostname>.ts.net`
2. **First visit**: Device pairing prompt (Tailscale provides device identity)
3. **Subsequent visits**: Direct access (device remembered)

**Without device pairing**: Connection rejected (secure by default)

### Test 3: Health Check

```bash
# Render exposes health check on public URL (no auth required)
curl -X POST https://<your-service>.onrender.com/health

# Expected: 200 OK
{"status":"ok"}
```

### Test 4: Security Audit Logs

Render Dashboard → **Logs** tab → Look for:

```log
✅ Security settings: dmPolicy=allowlist, groupPolicy=disabled, configWrites=false
✅ Tailscale connected: https://<hostname>.ts.net
✅ Gateway started with token auth
⚠️  allowInsecureAuth NOT present (secure default)
```

---

## Security Architecture

### Defense-in-Depth Layers

```
┌─────────────────────────────────────────┐
│  Layer 1: Render Infrastructure         │
│  - Container isolation (non-root user)  │
│  - Encrypted environment variables      │
│  - Encrypted persistent volume          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 2: Tailscale Serve (Optional)    │
│  - HTTPS termination                    │
│  - Tailnet authentication               │
│  - Device identity verification         │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 3: Gateway Token Authentication  │
│  - Auto-generated 40+ char token        │
│  - Required for all WebSocket conns     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 4: Channel Access Control        │
│  - Telegram DM allowlist (user IDs)     │
│  - Group policy: disabled               │
│  - Config writes: disabled              │
└─────────────────────────────────────────┘
```

### What's Protected

✅ **Credentials**: Stored in Render secrets (encrypted at rest)
✅ **Gateway Access**: Token auth + optional Tailscale device identity
✅ **Telegram Bot**: Only allowlisted user IDs can message
✅ **Container**: Non-root user (`node:node`), isolated filesystem
✅ **Network**: Gateway bound to `0.0.0.0` for health checks, secured by token auth
✅ **Persistent Data**: `/data` volume encrypted, isolated to service

---

## Post-Deployment Checklist

After Step 5, verify:

- [ ] Telegram bot responds only to your user ID
- [ ] Messages from other users rejected (visible in logs)
- [ ] Gateway accessible via Tailscale HTTPS (if enabled)
- [ ] Device pairing works on first Control UI access
- [ ] Health check passing: Render shows "Live" status
- [ ] Old Telegram token revoked in BotFather
- [ ] No credentials in render.yaml (all use `sync: false`)
- [ ] Render logs show no errors or security warnings

---

## Managing Your Deployment

### View Live Logs

**Via Render Dashboard**:
- Dashboard → Your service → **Logs** tab
- Real-time streaming, searchable

**Via Render CLI** (if installed):
```bash
render logs <service-name> --tail
```

### Restart Service

**Manual restart**:
- Dashboard → Your service → **Manual Deploy** → "Deploy latest commit"

**Auto-restart on health check failure**:
- Render automatically restarts if health checks fail 3+ times

### Rotate Credentials

**Telegram Bot Token**:
1. BotFather → Revoke current token
2. Copy new token
3. Render Dashboard → Environment → `TELEGRAM_BOT_TOKEN` → Update value
4. Save → Triggers automatic redeploy

**Gateway Token**:
1. Render Dashboard → Environment → `OPENCLAW_GATEWAY_TOKEN`
2. Click "Generate New Value"
3. Save → Triggers automatic redeploy

**Tailscale Auth Key**:
1. [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys) → Revoke old key
2. Generate new key (same settings as Step 3)
3. Render Dashboard → Environment → `TS_AUTHKEY` → Update value
4. Save → Triggers automatic redeploy

### Add More Telegram Users

1. Get their Telegram user ID (via @userinfobot)
2. Render Dashboard → Environment → `TELEGRAM_ALLOWFROM`
3. Update to comma-separated list: `5177091981,123456789,987654321`
4. Save → Triggers redeploy

### Backup Persistent Volume

**Via Render Shell** (Dashboard → Shell tab):
```bash
# Create timestamped backup
tar -czf /tmp/openclaw-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  /data/.openclaw/openclaw.json \
  /data/.openclaw/credentials/ \
  /data/.openclaw/agents/

# Download backup (copy output or use external storage)
cat /tmp/openclaw-backup-*.tar.gz | base64
```

**Schedule automated backups**: Use Render cron jobs or external backup service (S3, Google Cloud Storage, etc.)

---

## Troubleshooting

### Bot Not Responding

**Check logs**:
```bash
# Render Dashboard → Logs tab → Search for "telegram"
```

**Expected log messages**:
```log
✅ [INFO] Telegram bot started, dmPolicy=allowlist
✅ [INFO] Connected to Telegram API
```

**Common issues**:
- ❌ `TELEGRAM_BOT_TOKEN` not set → Add in Environment tab
- ❌ `TELEGRAM_ALLOWFROM` missing/incorrect → Verify your user ID
- ❌ Old token still in use → Verify new token in Render dashboard

### Can't Access Gateway

**Without Tailscale**:
- Gateway is only accessible via health check endpoint (`/health`)
- Control UI not accessible without Tailscale
- **Solution**: Add `TS_AUTHKEY` environment variable (Step 3)

**With Tailscale**:
1. Check logs for "Tailscale Serve" confirmation
2. Verify auth key is valid (not expired/revoked)
3. Check [Tailscale Machines](https://login.tailscale.com/admin/machines) for device status
4. Ensure device has "Serve" enabled

### Health Check Failing

**Check Render logs**:
```bash
# Look for startup errors
[ERROR] Gateway failed to start: ...
```

**Common issues**:
- ❌ `PORT` not set to `8080` → Verify in render.yaml
- ❌ Persistent disk not mounted → Check render.yaml disk config
- ❌ Environment variables missing → Verify required vars in Environment tab

**Verify health endpoint**:
```bash
curl -X POST https://<your-service>.onrender.com/health
# Expected: 200 OK
```

### Deployment Fails

**Build logs show errors**:
- Check Dockerfile.skills syntax
- Verify bundled plugins list (docker/plugins-install-bundled.txt)
- Check for missing dependencies

**Deployment timeout**:
- First deploy takes longer (bundled plugin installation)
- Check Render plan limits (free tier has build time limits)

---

## Security Best Practices

### Regular Maintenance

✅ **Weekly**: Check Render logs for security events
✅ **Monthly**: Rotate gateway token
✅ **Quarterly**: Rotate Telegram bot token
✅ **Annually**: Review and update allowlists

### Monitoring

**Set up Render alerts**:
- Dashboard → Your service → Settings → Notifications
- Enable alerts for: Deploy failures, health check failures, high memory usage

**Key metrics to watch**:
- Health check success rate (should be >99%)
- Response time (should be <500ms)
- Memory usage (should stay under 80%)
- Error rate in logs

### Backup Strategy

**What to backup**:
- `/data/.openclaw/openclaw.json` (gateway config)
- `/data/.openclaw/credentials/` (WhatsApp credentials, if used)
- `/data/.openclaw/agents/` (agent configs, session history)

**Backup frequency**:
- **Daily**: If actively using (automate via cron)
- **Weekly**: For periodic use
- **Before upgrades**: Always backup before OpenClaw version updates

**Backup retention**: Keep last 30 days

---

## Upgrading OpenClaw

### When New Version Released

1. **Backup first** (see Backup Strategy above)
2. Update GitHub repository to latest OpenClaw version
3. Render auto-deploys on git push (or manual deploy)
4. Watch logs for successful startup
5. Test all channels (Telegram, WhatsApp, etc.)

### Rollback If Needed

1. Render Dashboard → **Deploys** tab
2. Find last successful deployment
3. Click **Rollback**
4. Verify service is back online

---

## Advanced Configuration

### Custom Domain (Optional)

1. Render Dashboard → Your service → Settings → Custom Domain
2. Add your domain (e.g., `openclaw.yourdomain.com`)
3. Update DNS records (Render provides instructions)
4. Render provides free SSL certificate

### Tailscale ACLs (Optional)

Restrict gateway access to specific Tailscale users/devices:

```json
// Tailscale ACL (tailscale.com/admin/acls)
{
  "acls": [
    {
      "action": "accept",
      "src": ["user@example.com"],
      "dst": ["tag:openclaw:*"]
    }
  ],
  "tagOwners": {
    "tag:openclaw": ["user@example.com"]
  }
}
```

### Autoscaling (Render Pro+)

For high-traffic deployments:

```yaml
# Add to render.yaml
autoscaling:
  enabled: true
  minInstances: 1
  maxInstances: 3
  targetCPUPercent: 70
```

---

## Files Modified in This Hardening

✅ **docker/entrypoint.sh** (lines 115-117)
- **Before**: `"allowInsecureAuth": true` (insecure default)
- **After**: Removed (secure by default, device identity required)

✅ **render.yaml** (already secure)
- All secrets use `sync: false` (dashboard-managed)
- Gateway token auto-generated (`generateValue: true`)

✅ **Security Documentation**
- SECURITY_RENDER_DEPLOYMENT.md (this file)
- Docker entrypoint now secure by default for all users

---

## Code-Level Security Fix

### What Was Fixed

**File**: `docker/entrypoint.sh` (lines 115-117)

**Issue**: Docker entrypoint set `allowInsecureAuth: true` by default, weakening Control UI security for all Docker/Render deployments.

**Impact**:
- Bypassed device identity verification
- Allowed token-only auth (no device pairing)
- Inconsistent with security docs ("security downgrade")

**Fix**: Removed `allowInsecureAuth` from default config template.

**Benefit**: All new Render deployments now secure by default. Users who need insecure auth must enable explicitly (break-glass scenarios only).

---

## Emergency Contacts

- **Render Support**: https://render.com/support
- **OpenClaw Docs**: https://docs.openclaw.ai
- **Tailscale Support**: https://tailscale.com/contact/support
- **Telegram Support**: [@BotSupport](https://t.me/BotSupport)

---

## Summary

Your Render deployment is secure when following this guide:

✅ **Credentials**: Managed via Render secrets (encrypted)
✅ **Gateway**: Token auth + optional Tailscale device identity
✅ **Telegram**: DM allowlist (only approved users)
✅ **Container**: Non-root user, isolated filesystem
✅ **Network**: Gateway secured by token auth + Tailscale
✅ **Monitoring**: Health checks, logs, metrics

**Deployment Time**: ~15 minutes
**Security Posture**: Defense-in-depth (4 layers)
**Maintenance**: Low (automated restarts, managed secrets)

---

**Render Deployment Guide** | Generated: 2026-02-07 | OpenClaw Version: 2026.2.1
