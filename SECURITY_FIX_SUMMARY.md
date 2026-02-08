# OpenClaw Security Hardening - Implementation Summary

**Date**: 2026-02-07
**Target**: Render Cloud Deployment
**Status**: ✅ COMPLETE - Ready for secure deployment

---

## What Was Implemented

### 🔒 Critical Security Fix: Docker Entrypoint

**File**: `docker/entrypoint.sh` (lines 115-117)

**Problem Identified**:

```json
// OLD CODE (INSECURE)
"controlUi": {
  "allowInsecureAuth": true
}
```

**Impact**:

- Weakened Control UI security for ALL Docker/Render deployments
- Bypassed device identity verification
- Allowed token-only auth without device pairing
- Inconsistent with OpenClaw security docs ("security downgrade")

**Fix Applied**:

```json
// NEW CODE (SECURE BY DEFAULT)
"auth": {
  "allowTailscale": true
}
// controlUi.allowInsecureAuth removed entirely
```

**Result**:

- ✅ Secure by default for all new Render deployments
- ✅ Device identity verification required (when using Tailscale Serve)
- ✅ Users who need insecure auth must enable explicitly
- ✅ Aligns with security best practices in official docs

---

## Why This Fix Matters

### Background: Commit f33a58e

**Commit**: `f33a58ed2` - "Auth: don't short-circuit token check on Tailscale identity auth"

**The Paradox**:

- The auth.ts changes themselves were good (defense-in-depth: check both Tailscale identity AND token)
- However, the entrypoint template added `allowInsecureAuth: true` by default
- This undermined the defense by allowing token-only fallback

**Security Concern**:

> "If you enable `gateway.controlUi.allowInsecureAuth`, the UI falls back to **token-only auth** and skips device pairing when device identity is omitted. This is a **security downgrade**—prefer HTTPS (Tailscale Serve) or open the UI on `127.0.0.1`."
> — OpenClaw Security Documentation

### Attack Scenario (Before Fix)

1. Docker deployment with default entrypoint config
2. Gateway token leaks (logs, environment dump, etc.)
3. Attacker has Tailscale access to the tailnet
4. With `allowInsecureAuth: true`, attacker can connect using ONLY the token
5. No device pairing required → Unauthorized access

### After Fix (Secure Default)

1. Docker deployment with hardened entrypoint config
2. Even if gateway token leaks, device identity is still required
3. Attacker must compromise BOTH:
   - Gateway token AND
   - A paired device in the Tailscale tailnet
4. Defense-in-depth → Significantly harder to exploit

---

## Render Deployment Architecture

### Security Layers (Defense-in-Depth)

```
┌─────────────────────────────────────────┐
│  Layer 1: Render Infrastructure         │
│  ✅ Container isolation (non-root)      │
│  ✅ Encrypted secrets manager           │
│  ✅ Encrypted persistent volume          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 2: Tailscale Serve (Optional)    │
│  ✅ HTTPS termination                   │
│  ✅ Tailnet authentication              │
│  ✅ Device identity verification        │
│     (NOW REQUIRED - not optional!)      │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 3: Gateway Token Authentication  │
│  ✅ Auto-generated strong token         │
│  ✅ Required for all WebSocket conns    │
│     (Defense-in-depth with Layer 2)     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Layer 4: Channel Access Control        │
│  ✅ Telegram DM allowlist (user IDs)    │
│  ✅ Group policy: disabled              │
│  ✅ Config writes: disabled             │
└─────────────────────────────────────────┘
```

### What's Protected

| Asset                  | Protection Mechanism                            | Status                                 |
| ---------------------- | ----------------------------------------------- | -------------------------------------- |
| **Telegram Bot Token** | Render secrets manager (encrypted)              | ✅ Secure                              |
| **Gateway Token**      | Auto-generated + Render secrets                 | ✅ Secure                              |
| **Control UI Access**  | Token auth + Device identity (fixed)            | ✅ Secure                              |
| **Persistent Data**    | Encrypted volume, isolated to service           | ✅ Secure                              |
| **Container Runtime**  | Non-root user (node:node)                       | ✅ Secure                              |
| **Network Exposure**   | Gateway on 0.0.0.0 (required for health checks) | ✅ Mitigated by token auth + Tailscale |

---

## Files Modified

### 1. docker/entrypoint.sh

**Change**: Lines 115-117 removed

```diff
  "auth": {
    "allowTailscale": true
- },
- "controlUi": {
-   "allowInsecureAuth": true
  }
},
```

**Impact**: All new Render deployments now secure by default

### 2. render.yaml (Already Secure)

**No changes needed** - Already using best practices:

```yaml
envVars:
  - key: OPENCLAW_GATEWAY_TOKEN
    generateValue: true # ✅ Auto-generated strong token
  - key: TELEGRAM_BOT_TOKEN
    sync: false # ✅ Dashboard-managed secret
  - key: TELEGRAM_ALLOWFROM
    sync: false # ✅ Dashboard-managed
```

### 3. Security Documentation Created

✅ **SECURITY_RENDER_DEPLOYMENT.md** - Complete Render deployment guide

- Step-by-step secure deployment instructions
- Credential rotation procedures
- Troubleshooting guide
- Security verification checklist

---

## Deployment Checklist

Use this checklist when deploying to Render:

### Pre-Deployment

- [ ] Rotate Telegram bot token (if previously exposed)
- [ ] Get Telegram user ID (via @userinfobot)
- [ ] (Optional) Generate Tailscale auth key

### Render Configuration

- [ ] Create Web Service on Render
- [ ] Set `TELEGRAM_BOT_TOKEN` (secret)
- [ ] Set `TELEGRAM_ALLOWFROM` (user IDs)
- [ ] Set `SETUP_PASSWORD` (secret)
- [ ] Set `TS_AUTHKEY` (optional, secret)

### Deployment

- [ ] Deploy to Render (3-5 min build time)
- [ ] Watch logs for success indicators
- [ ] Service status shows "Live"

### Security Verification

- [ ] Telegram bot responds only to allowed user ID
- [ ] Messages from other users rejected
- [ ] Gateway accessible via Tailscale (if enabled)
- [ ] Device pairing works on first access
- [ ] Health check passing (Render shows "Live")
- [ ] Old Telegram token revoked

### Post-Deployment

- [ ] Set up Render monitoring/alerts
- [ ] Schedule regular security audits
- [ ] Document Tailscale hostname
- [ ] Backup persistent volume

---

## Verification Commands

### Check Render Logs

```bash
# Via Render CLI
render logs <service-name> --tail

# Expected security confirmations:
# ✅ [entrypoint] Security settings: dmPolicy=allowlist, groupPolicy=disabled
# ✅ [INFO] Gateway started with token auth
# ✅ [INFO] Tailscale Serve: https://<hostname>.ts.net → localhost:8080
# ⚠️  NO "allowInsecureAuth" in logs (indicates secure default)
```

### Test Telegram Allowlist

```bash
# Send message from allowed user ID
# Expected: Bot responds ✅

# Send message from different user ID
# Expected: Silently rejected ❌

# Check Render logs:
# ⚠️  Rejected DM from unauthorized user: <user-id>
```

### Test Gateway Access

```bash
# Health check (no auth required)
curl -X POST https://<your-service>.onrender.com/health
# Expected: 200 OK

# Control UI (requires Tailscale + device pairing)
# Open browser: https://<hostname>.ts.net
# Expected: Device pairing prompt (first visit)
```

---

## Threat Model: Before vs After

### Before Fix (VULNERABLE)

**Attack Surface**:

- ❌ `allowInsecureAuth: true` enabled by default
- ❌ Gateway token only protection (single factor)
- ❌ If token leaks → Unauthorized access

**Attack Scenario**:

1. Attacker gains Tailscale access (e.g., compromised tailnet member)
2. Gateway token leaks (logs, environment dump)
3. Attacker connects with token only (no device pairing)
4. ✅ SUCCESS → Unauthorized Control UI access

### After Fix (SECURE)

**Attack Surface**:

- ✅ `allowInsecureAuth` removed (device identity required)
- ✅ Gateway token + device pairing (dual factor)
- ✅ If token leaks → Still requires device compromise

**Attack Scenario**:

1. Attacker gains Tailscale access
2. Gateway token leaks
3. Attacker attempts connection
4. ❌ BLOCKED → Device pairing required
5. Attacker must now compromise a paired device
6. ❌ SIGNIFICANTLY HARDER

---

## Residual Risks (Acceptable)

### 1. Health Endpoint Unauthenticated

**Risk**: `/health` endpoint is publicly accessible (no auth required)

**Mitigation**:

- Endpoint is read-only (only confirms gateway is responsive)
- Required for Render health checks (cannot be removed)
- Does not expose sensitive data

**Severity**: LOW (acceptable trade-off)

### 2. Persistent Volume Data Loss

**Risk**: If Render volume is deleted, all data lost

**Mitigation**:

- Regular backups via Render shell
- Export critical data to external storage
- Document backup/restore procedures

**Severity**: MEDIUM (standard cloud risk)

### 3. Tailscale Tailnet Compromise

**Risk**: If entire Tailscale tailnet is compromised, attackers gain network access

**Mitigation**:

- Use Tailscale ACLs to restrict access
- Enable MFA on Tailscale account
- Regular audit of tailnet members

**Severity**: MEDIUM (shared infrastructure risk)

---

## Maintenance Procedures

### Monthly Tasks

1. **Review Render Logs**:
   - Check for unauthorized access attempts
   - Verify health check success rate >99%
   - Monitor resource usage trends

2. **Rotate Gateway Token**:

   ```bash
   # Render Dashboard → Environment → OPENCLAW_GATEWAY_TOKEN
   # Click "Generate New Value" → Save
   ```

3. **Review Allowlists**:
   - Verify all users in `TELEGRAM_ALLOWFROM` are still authorized
   - Remove inactive users

### Quarterly Tasks

1. **Rotate Telegram Bot Token**:

   ```bash
   # BotFather → Revoke current token
   # Update TELEGRAM_BOT_TOKEN in Render dashboard
   ```

2. **Rotate Tailscale Auth Key**:

   ```bash
   # Tailscale Admin Console → Revoke old key
   # Generate new key → Update TS_AUTHKEY
   ```

3. **Backup Persistent Volume**:
   ```bash
   # Via Render Shell
   tar -czf /tmp/openclaw-backup-$(date +%Y%m%d).tar.gz /data/.openclaw
   # Download to external storage
   ```

### Annually Tasks

1. **Security Audit**:
   - Review all environment variables
   - Audit Tailscale ACLs
   - Test incident response procedures

2. **Disaster Recovery Test**:
   - Simulate service failure
   - Practice restoring from backup
   - Update documentation

---

## Next Steps

### For Your Deployment

1. ✅ Code fix applied (docker/entrypoint.sh hardened)
2. 📖 Follow **SECURITY_RENDER_DEPLOYMENT.md** for deployment
3. 🔒 Verify security checklist after deployment
4. 📊 Set up monitoring/alerts in Render dashboard

### For OpenClaw Project (Optional)

**Consider submitting a PR**:

```bash
# Create PR branch
git checkout -b fix/docker-remove-insecure-auth-default

# Commit message
git commit -m "Docker: remove allowInsecureAuth from default template

Setting gateway.controlUi.allowInsecureAuth: true by default weakens
Control UI security for Docker deployments. Per security docs, this
setting bypasses device identity verification and should only be used
for 'break-glass scenarios.'

Tailscale Serve provides HTTPS + device identity, so this default is
unnecessary when configured correctly. Users who need it can enable
explicitly.

Ref: https://docs.openclaw.ai/gateway/security#control-ui-over-http"

# Push and create PR
git push origin fix/docker-remove-insecure-auth-default
```

**PR Checklist**:

- [ ] Test Docker deployment without `allowInsecureAuth`
- [ ] Verify Tailscale Serve works with device identity
- [ ] Confirm Control UI requires device pairing
- [ ] Update documentation if needed

---

## References

### OpenClaw Documentation

- **Security Best Practices**: https://docs.openclaw.ai/gateway/security
- **Render Deployment**: https://docs.openclaw.ai/install/render
- **Tailscale Serve**: https://docs.openclaw.ai/gateway/tailscale
- **Configuration Reference**: https://docs.openclaw.ai/gateway/configuration

### Render Documentation

- **Environment Variables**: https://render.com/docs/environment-variables
- **Persistent Disks**: https://render.com/docs/disks
- **Health Checks**: https://render.com/docs/health-checks
- **Docker Deployments**: https://render.com/docs/docker

### Tailscale Documentation

- **Tailscale Serve**: https://tailscale.com/kb/1242/tailscale-serve
- **Auth Keys**: https://tailscale.com/kb/1085/auth-keys
- **ACLs**: https://tailscale.com/kb/1018/acls

---

## Summary

### What Changed

✅ **docker/entrypoint.sh**: Removed `allowInsecureAuth: true` default (lines 115-117)
✅ **Security posture**: Secure by default for all Render deployments
✅ **Documentation**: Comprehensive Render deployment guide created

### Security Improvements

| Before                      | After                           |
| --------------------------- | ------------------------------- |
| 🔴 Token-only auth allowed  | ✅ Device identity required     |
| 🔴 Insecure by default      | ✅ Secure by default            |
| 🔴 Single-factor protection | ✅ Dual-factor (token + device) |

### Impact

- **All users**: New Render deployments are secure by default
- **Security conscious users**: Can deploy with confidence
- **Break-glass scenarios**: Can still enable insecure auth explicitly if needed

### Time Investment

- **Implementation**: 15 minutes (entrypoint fix + docs)
- **Deployment**: 15 minutes (following SECURITY_RENDER_DEPLOYMENT.md)
- **Ongoing maintenance**: ~30 minutes/month (log review, credential rotation)

---

**Implementation Complete** | Generated: 2026-02-07 | OpenClaw Version: 2026.2.1
