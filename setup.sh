#!/bin/bash
# =============================================================================
#  BUTEGA360 — Script principale setup VPS
#  Ubuntu 24.04 LTS + HestiaCP + Node.js 20 + Redis + Brevo
#
#  NON eseguire manualmente — viene chiamato dal cloud-init
#  oppure eseguilo su un server PULITO e FRESCO:
#    sudo bash setup.sh
# =============================================================================

set -e

# ─── Variabili di configurazione ─────────────────────────────────────────────
# Le variabili arrivano dall'ambiente (impostate dal cloud-init via config.env)
# oppure usa i valori default qui sotto come fallback per esecuzione manuale.
# In esecuzione manuale: set -a; source /root/butega360-config.env; set +a; bash setup.sh

SERVER_TIMEZONE="${SERVER_TIMEZONE:-Europe/Rome}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-server.butega360.it}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@butega360.it}"
HESTIA_ADMIN_PASSWORD="${HESTIA_ADMIN_PASSWORD:-Butega360_Admin_Change_Me!}"
HESTIA_PORT="${HESTIA_PORT:-8083}"
DB_APP_NAME="${DB_APP_NAME:-butega360_db}"
DB_APP_USER="${DB_APP_USER:-butega360}"
DB_APP_PASSWORD="${DB_APP_PASSWORD:-Butega360_App_Change_Me!}"
NODE_VERSION="${NODE_VERSION:-20}"
API_PORT="${API_PORT:-3001}"
APP_PORT="${APP_PORT:-3000}"
REDIS_MAX_MEMORY="${REDIS_MAX_MEMORY:-128mb}"
BREVO_SMTP_HOST="${BREVO_SMTP_HOST:-smtp-relay.brevo.com}"
BREVO_SMTP_PORT="${BREVO_SMTP_PORT:-587}"
BREVO_SMTP_USER="${BREVO_SMTP_USER:-}"
BREVO_SMTP_PASSWORD="${BREVO_SMTP_PASSWORD:-}"
BREVO_FROM_EMAIL="${BREVO_FROM_EMAIL:-noreply@butega360.it}"
BREVO_FROM_NAME="${BREVO_FROM_NAME:-Butega360}"
DOMAIN_MAIN="${DOMAIN_MAIN:-butega360.it}"
DOMAIN_APP="${DOMAIN_APP:-app.butega360.it}"
DOMAIN_API="${DOMAIN_API:-api.butega360.it}"
DOMAIN_ADMIN="${DOMAIN_ADMIN:-admin.butega360.it}"

# ─── Colori e funzioni log ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✓] $(date '+%H:%M:%S')${NC} $1"; }
info()    { echo -e "${CYAN}[i] $(date '+%H:%M:%S')${NC} $1"; }
warn()    { echo -e "${YELLOW}[!] $(date '+%H:%M:%S')${NC} $1"; }
error()   { echo -e "${RED}[✗] $(date '+%H:%M:%S') ERRORE: $1${NC}"; exit 1; }
section() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  printf "${BLUE}║  %-44s║${NC}\n" "$1"
  echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
}

# Verifica root
[ "$EUID" -ne 0 ] && error "Esegui come root: sudo bash $0"

# Ottieni IP pubblico
SERVER_IP=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || \
            curl -s --max-time 10 api.ipify.org 2>/dev/null || \
            hostname -I | awk '{print $1}')

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     BUTEGA360 — Setup VPS Completo           ║${NC}"
echo -e "${BLUE}║     Ubuntu 24.04 LTS                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
info "IP Server: $SERVER_IP"
info "Inizio: $(date '+%d/%m/%Y %H:%M:%S')"
info "Log completo: /root/butega360-install.log"
echo ""
sleep 3

export DEBIAN_FRONTEND=noninteractive

# =============================================================================
section "1/7 — Preparazione sistema"
# =============================================================================
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git unzip zip nano \
  software-properties-common gnupg \
  ca-certificates openssl \
  lsb-release build-essential

# Timezone
timedatectl set-timezone "$SERVER_TIMEZONE"
locale-gen it_IT.UTF-8 en_US.UTF-8 > /dev/null 2>&1
update-locale LANG=it_IT.UTF-8 > /dev/null 2>&1

# Hostname
hostnamectl set-hostname "$SERVER_HOSTNAME"

log "Sistema preparato — Timezone: $SERVER_TIMEZONE"

# =============================================================================
section "2/7 — HestiaCP"
# =============================================================================
info "Download installer HestiaCP (questo richiede 10-15 minuti)..."

wget -q https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh \
  -O /root/hst-install.sh

chmod +x /root/hst-install.sh

# Parametri installazione:
# --apache no       → solo Nginx, niente Apache (più leggero)
# --phpfpm yes      → PHP-FPM per siti PHP
# --multiphp no     → una sola versione PHP (più leggero)
# --vsftpd yes      → FTP (utile per upload file)
# --named yes       → DNS server
# --mysql8 yes      → MySQL 8 invece di MariaDB
# --exim yes        → mail server (relay verso Brevo)
# --dovecot no      → no IMAP/POP3 (usiamo Brevo)
# --clamav no       → no antivirus (risparmio RAM ~200MB)
# --spamassassin no → no spam filter (risparmio RAM ~100MB)
# --iptables yes    → firewall
# --fail2ban yes    → protezione brute force
# --api yes         → API HestiaCP attiva
# --port            → porta pannello

bash /root/hst-install.sh \
  --hostname "$SERVER_HOSTNAME" \
  --email "$ADMIN_EMAIL" \
  --password "$HESTIA_ADMIN_PASSWORD" \
  --apache no \
  --phpfpm yes \
  --multiphp no \
  --vsftpd yes \
  --named yes \
  --mysql8 yes \
  --exim yes \
  --dovecot no \
  --clamav no \
  --spamassassin no \
  --iptables yes \
  --fail2ban yes \
  --api yes \
  --port "$HESTIA_PORT" \
  --lang it \
  --interactive no \
  --force

log "HestiaCP installato"

# Apri porta HestiaCP nel firewall
/usr/local/hestia/bin/v-add-firewall-rule ACCEPT "" "$HESTIA_PORT" TCP "HestiaCP Panel"

# =============================================================================
section "3/7 — MySQL 8 — Database Butega360"
# =============================================================================
info "Attendo avvio MySQL..."
sleep 10

# Crea database e utente applicazione tramite HestiaCP CLI
/usr/local/hestia/bin/v-add-database admin "$DB_APP_NAME" "$DB_APP_USER" "$DB_APP_PASSWORD" mysql

# Ottimizzazioni MySQL per VPS piccolo
cat >> /etc/mysql/mysql.conf.d/mysqld.cnf << 'EOF'

# ── Butega360 ottimizzazioni ──────────────────────────
innodb_buffer_pool_size     = 256M
innodb_log_file_size        = 64M
max_connections             = 100
slow_query_log              = 1
slow_query_log_file         = /var/log/mysql/slow.log
long_query_time             = 2
character-set-server        = utf8mb4
collation-server            = utf8mb4_unicode_ci
EOF

systemctl restart mysql
log "MySQL 8 configurato — Database: $DB_APP_NAME / Utente: $DB_APP_USER"

# =============================================================================
section "4/7 — Node.js $NODE_VERSION LTS + PM2"
# =============================================================================
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - > /dev/null 2>&1
apt-get install -y -qq nodejs
npm install -g pm2 > /dev/null 2>&1

# PM2 avvio automatico al boot
pm2 startup systemd -u root --hp /root > /dev/null 2>&1
systemctl enable pm2-root > /dev/null 2>&1

# Template Nginx per Node.js in HestiaCP
# Crea template proxy per app Node sulla porta 3000
HESTIA_TPL="/usr/local/hestia/data/templates/web/nginx/php-fpm"

cat > /usr/local/hestia/data/templates/web/nginx/nodejs_app.tpl << 'EOF'
server {
    listen      %ip%:%web_port%;
    server_name %domain_idn% %alias_idn%;
    error_log   /var/log/%web_system%/domains/%domain%.error.log error;

    location / {
        proxy_pass         http://127.0.0.1:%proxy_port%;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    location ~ /\.ht    { return 404; }
    location ~ /\.git   { return 404; }

    include %home%/%user%/conf/web/nginx.%domain%.conf*;
}
EOF

cat > /usr/local/hestia/data/templates/web/nginx/nodejs_app.stpl << 'EOF'
server {
    listen      %ip%:%web_ssl_port% ssl http2;
    server_name %domain_idn% %alias_idn%;
    error_log   /var/log/%web_system%/domains/%domain%.error.log error;

    ssl_certificate     %ssl_pem%;
    ssl_certificate_key %ssl_key%;
    ssl_stapling        on;
    ssl_stapling_verify on;

    location / {
        proxy_pass         http://127.0.0.1:%proxy_port%;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    location ~ /\.ht    { return 404; }
    location ~ /\.git   { return 404; }

    include %home%/%user%/conf/web/nginx.%domain%.conf*;
}
EOF

log "Node.js $(node --version) + PM2 installati"
log "Template Nginx per Node.js creati in HestiaCP"

# =============================================================================
section "5/7 — Redis"
# =============================================================================
apt-get install -y -qq redis-server

# Configurazione sicura e ottimizzata
cat > /etc/redis/redis.conf << EOF
# Butega360 Redis config
bind 127.0.0.1
port 6379
daemonize yes
supervised systemd
loglevel notice
logfile /var/log/redis/redis-server.log
databases 4
maxmemory $REDIS_MAX_MEMORY
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly no
EOF

systemctl enable redis-server > /dev/null 2>&1
systemctl restart redis-server
log "Redis installato — max memoria: $REDIS_MAX_MEMORY"

# =============================================================================
section "6/7 — Configurazione Brevo (email)"
# =============================================================================

# Configura Exim (già installato da HestiaCP) come relay verso Brevo
cat > /etc/exim4/exim4.conf.localmacros << EOF
# Relay SMTP verso Brevo
MAIN_TLS_ENABLE = true
AUTH_CLIENT_ALLOW_NOTLS_PASSWORDS = false
EOF

# Configurazione relay Brevo in Exim
cat >> /etc/exim4/conf.d/transport/30_exim4-config_remote_smtp_smarthost << EOF

# ── Brevo SMTP relay ──────────────────────────────────
butega360_brevo_smtp:
  driver = smtp
  hosts = $BREVO_SMTP_HOST
  port = $BREVO_SMTP_PORT
  hosts_require_auth = *
  hosts_require_tls = *
EOF

# Credenziali Brevo per Exim
cat >> /etc/exim4/passwd.client << EOF
$BREVO_SMTP_HOST:$BREVO_SMTP_USER:$BREVO_SMTP_PASSWORD
EOF

chmod 640 /etc/exim4/passwd.client
chown root:Debian-exim /etc/exim4/passwd.client

# Aggiorna configurazione Exim
update-exim4.conf 2>/dev/null || true
systemctl restart exim4 2>/dev/null || true

# Crea file .env per Node.js con config Brevo
mkdir -p /var/www/butega360
cat > /var/www/butega360/.env.example << EOF
# ══════════════════════════════════════════════
#  BUTEGA360 — Variabili d'ambiente
#  Copia in .env e compila i valori mancanti
# ══════════════════════════════════════════════

# App
NODE_ENV=production
PORT=$API_PORT
APP_URL=https://$DOMAIN_APP
API_URL=https://$DOMAIN_API

# Database
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$DB_APP_NAME
DB_USER=$DB_APP_USER
DB_PASSWORD=$DB_APP_PASSWORD

# Redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379

# JWT
JWT_SECRET=genera_una_stringa_casuale_lunga_almeno_64_caratteri
JWT_EXPIRES_IN=7d
JWT_REFRESH_EXPIRES_IN=30d

# Email Brevo
BREVO_SMTP_HOST=$BREVO_SMTP_HOST
BREVO_SMTP_PORT=$BREVO_SMTP_PORT
BREVO_SMTP_USER=$BREVO_SMTP_USER
BREVO_SMTP_PASSWORD=$BREVO_SMTP_PASSWORD
BREVO_FROM_EMAIL=$BREVO_FROM_EMAIL
BREVO_FROM_NAME=$BREVO_FROM_NAME

# Stripe (abbonamenti)
STRIPE_PUBLIC_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Satispay
SATISPAY_KEY_ID=
SATISPAY_PRIVATE_KEY=

# Anthropic API (agente IA fatture)
ANTHROPIC_API_KEY=sk-ant-...

# Google Vision API (OCR fatture)
GOOGLE_VISION_KEY=

# Storage immagini (locale o S3-compatible)
STORAGE_DRIVER=local
STORAGE_PATH=/var/www/butega360/uploads
# Per Hetzner Object Storage:
# STORAGE_DRIVER=s3
# STORAGE_ENDPOINT=https://fsn1.your-objectstorage.com
# STORAGE_BUCKET=butega360-uploads
# STORAGE_KEY=
# STORAGE_SECRET=
EOF

chown -R www-data:www-data /var/www/butega360
log "Brevo configurato come relay SMTP"
log "File .env.example creato in /var/www/butega360/"

# =============================================================================
section "7/7 — Struttura progetto + backup automatico"
# =============================================================================

# Directory struttura
mkdir -p /var/www/butega360/{api,app,uploads,backups,logs}
chown -R www-data:www-data /var/www/butega360

# Script backup giornaliero
cat > /usr/local/bin/butega360-backup.sh << BACKUP
#!/bin/bash
BACKUP_DIR="/var/www/butega360/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG="/var/www/butega360/logs/backup.log"

echo "[\$DATE] Avvio backup..." >> \$LOG

# Backup database
mysqldump -u root $DB_APP_NAME | gzip > "\$BACKUP_DIR/db_\$DATE.sql.gz"
echo "[\$DATE] DB backup OK" >> \$LOG

# Backup uploads
tar -czf "\$BACKUP_DIR/uploads_\$DATE.tar.gz" /var/www/butega360/uploads/ 2>/dev/null
echo "[\$DATE] Uploads backup OK" >> \$LOG

# Mantieni solo gli ultimi 7 backup
ls -t "\$BACKUP_DIR"/db_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
ls -t "\$BACKUP_DIR"/uploads_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "[\$DATE] Backup completato" >> \$LOG
BACKUP

chmod +x /usr/local/bin/butega360-backup.sh

# Cron backup ogni notte alle 02:30
(crontab -l 2>/dev/null; echo "30 2 * * * /usr/local/bin/butega360-backup.sh") | crontab -

# Logrotate
cat > /etc/logrotate.d/butega360 << 'EOF'
/var/www/butega360/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data www-data
}
EOF

log "Struttura progetto creata"
log "Backup automatico configurato (02:30 ogni notte)"

# =============================================================================
# Salva riepilogo credenziali
# =============================================================================
SUMMARY="/root/butega360-credentials.txt"
cat > "$SUMMARY" << EOF
╔══════════════════════════════════════════════════════════════════╗
║          BUTEGA360 — Credenziali e Accessi                       ║
║          Generato: $(date '+%d/%m/%Y %H:%M:%S')
╚══════════════════════════════════════════════════════════════════╝

── SERVER ────────────────────────────────────────────────────────
  IP:               $SERVER_IP
  Hostname:         $SERVER_HOSTNAME
  OS:               Ubuntu 24.04 LTS
  Timezone:         $SERVER_TIMEZONE

── HESTIACP ──────────────────────────────────────────────────────
  URL:              https://$SERVER_IP:$HESTIA_PORT
  Utente:           admin
  Password:         $HESTIA_ADMIN_PASSWORD

── DATABASE MySQL 8 ──────────────────────────────────────────────
  Database:         $DB_APP_NAME
  Utente app:       $DB_APP_USER
  Password app:     $DB_APP_PASSWORD
  Host:             localhost:3306

── EMAIL (Brevo) ─────────────────────────────────────────────────
  SMTP Host:        $BREVO_SMTP_HOST:$BREVO_SMTP_PORT
  Utente:           $BREVO_SMTP_USER
  From:             $BREVO_FROM_EMAIL

── DOMINI (configurare DNS dopo) ─────────────────────────────────
  Principale:       $DOMAIN_MAIN    → $SERVER_IP
  PWA:              $DOMAIN_APP     → $SERVER_IP
  API:              $DOMAIN_API     → $SERVER_IP
  Admin:            $DOMAIN_ADMIN   → $SERVER_IP

── PERCORSI IMPORTANTI ───────────────────────────────────────────
  Progetto:         /var/www/butega360/
  Config .env:      /var/www/butega360/.env.example
  Backup:           /var/www/butega360/backups/
  Log:              /var/www/butega360/logs/
  Install log:      /root/butega360-install.log

── SSL — DA ATTIVARE DOPO AVER CONFIGURATO I DNS ─────────────────
  v-add-letsencrypt-domain admin $DOMAIN_APP
  v-add-letsencrypt-domain admin $DOMAIN_API
  v-add-letsencrypt-domain admin $DOMAIN_ADMIN

── COMANDI UTILI ─────────────────────────────────────────────────
  Stato servizi:    systemctl status nginx mysql redis exim4
  Log Nginx:        tail -f /var/log/nginx/error.log
  Log MySQL:        tail -f /var/log/mysql/error.log
  Processi PM2:     pm2 list
  Log installaz.:   tail -f /root/butega360-install.log
  Backup manuale:   /usr/local/bin/butega360-backup.sh
  Test email:       echo "Test" | mail -s "Test Brevo" $ADMIN_EMAIL

══════════════════════════════════════════════════════════════════
  ⚠  IMPORTANTE: Elimina questo file dopo averlo messo al sicuro
     rm /root/butega360-credentials.txt
══════════════════════════════════════════════════════════════════
EOF

chmod 600 "$SUMMARY"

# =============================================================================
# Output finale
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓  INSTALLAZIONE BUTEGA360 COMPLETATA                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}HestiaCP:${NC}   https://$SERVER_IP:$HESTIA_PORT"
echo -e "  ${CYAN}Utente:${NC}     admin / $HESTIA_ADMIN_PASSWORD"
echo ""
echo -e "  ${YELLOW}Prossimi passi:${NC}"
echo -e "  1. Accedi a HestiaCP e cambia la password admin"
echo -e "  2. Punta i record DNS al server IP: $SERVER_IP"
echo -e "  3. Attiva SSL: v-add-letsencrypt-domain admin $DOMAIN_APP"
echo -e "  4. Copia .env.example in .env e compila le API key"
echo -e "  5. Elimina /root/butega360-credentials.txt"
echo ""
echo -e "  ${YELLOW}Credenziali complete in:${NC} /root/butega360-credentials.txt"
echo -e "  ${YELLOW}Log installazione in:${NC}   /root/butega360-install.log"
echo ""
echo -e "  Fine: $(date '+%d/%m/%Y %H:%M:%S')"
echo ""
