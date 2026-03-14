#!/bin/bash
# =============================================================================
#  BUTEGA360 — Template configurazione
#
#  ⚠️  QUESTO FILE E' UN ESEMPIO — non contiene valori reali
#  ⚠️  NON inserire mai password reali in questo file su GitHub
#
#  Le credenziali reali vanno nel cloud-init.yml di Hetzner
#  (che non viene caricato su GitHub)
#
#  Per esecuzione manuale su server già esistente:
#    1. Copia questo file: cp config.example.sh config.sh
#    2. Compila tutti i valori
#    3. Esegui: set -a; source config.sh; set +a; bash setup.sh
#    4. Cancella config.sh dopo l'installazione: shred -u config.sh
# =============================================================================

# ── Server ────────────────────────────────────────────
SERVER_TIMEZONE="Europe/Rome"
SERVER_HOSTNAME="server.butega360.it"
ADMIN_EMAIL="admin@tuodominio.it"

# ── HestiaCP ──────────────────────────────────────────
HESTIA_ADMIN_PASSWORD=""        # min 8 caratteri, lettere+numeri+simboli
HESTIA_PORT="8083"

# ── Database MySQL 8 ──────────────────────────────────
DB_APP_NAME="butega360_db"
DB_APP_USER="butega360"
DB_APP_PASSWORD=""              # min 12 caratteri

# ── Node.js ───────────────────────────────────────────
NODE_VERSION="20"
API_PORT="3001"
APP_PORT="3000"

# ── Redis ─────────────────────────────────────────────
REDIS_MAX_MEMORY="128mb"        # aumenta a 256mb su CX32

# ── Brevo SMTP ────────────────────────────────────────
# Recupera da: Brevo → SMTP & API → SMTP
BREVO_SMTP_HOST="smtp-relay.brevo.com"
BREVO_SMTP_PORT="587"
BREVO_SMTP_USER=""              # email account Brevo
BREVO_SMTP_PASSWORD=""          # API key SMTP da Brevo
BREVO_FROM_EMAIL="noreply@butega360.it"
BREVO_FROM_NAME="Butega360"

# ── Domini ────────────────────────────────────────────
DOMAIN_MAIN="butega360.it"
DOMAIN_APP="app.butega360.it"
DOMAIN_API="api.butega360.it"
DOMAIN_ADMIN="admin.butega360.it"
