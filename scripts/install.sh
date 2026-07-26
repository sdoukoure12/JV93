#!/bin/bash

################################################################################
# JV93 Installation Script for Ubuntu
# Installs and configures the cryptocurrency mining & wallet system
# Usage: sudo bash install.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="/var/log/jv93_install.log"
PYTHON_VERSION="3.10"
SERVICE_USER="jv93"
SERVICE_GROUP="jv93"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

################################################################################
# Prerequisite Checks
################################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check Ubuntu version
    if ! grep -qi "ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu. Detected: $(cat /etc/os-release | grep PRETTY_NAME)"
        exit 1
    fi

    log_success "Prerequisites verified"
}

################################################################################
# System Updates
################################################################################

update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    log_success "System updated"
}

################################################################################
# Install Dependencies
################################################################################

install_dependencies() {
    log_info "Installing system dependencies..."

    apt-get install -y \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-dev \
        python3-pip \
        build-essential \
        libssl-dev \
        libffi-dev \
        git \
        wget \
        curl \
        sqlite3 \
        gnupg \
        gpg-agent \
        openssh-client \
        openssh-server \
        fail2ban \
        ufw \
        htop \
        tmux \
        supervisor \
        jq \
        net-tools \
        vim

    log_success "System dependencies installed"
}

################################################################################
# Setup Service User
################################################################################

setup_service_user() {
    log_info "Setting up service user..."

    # Create user if doesn't exist
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d /home/$SERVICE_USER -m $SERVICE_USER
        log_success "Service user '$SERVICE_USER' created"
    else
        log_info "Service user '$SERVICE_USER' already exists"
    fi

    # Set proper permissions
    chown -R $SERVICE_USER:$SERVICE_GROUP "$REPO_DIR"
    chmod 755 "$REPO_DIR"
}

################################################################################
# Setup Python Virtual Environment
################################################################################

setup_python_env() {
    log_info "Setting up Python virtual environment..."

    VENV_DIR="$REPO_DIR/venv"

    # Create virtual environment
    python${PYTHON_VERSION} -m venv "$VENV_DIR"
    log_success "Virtual environment created"

    # Activate and upgrade pip
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip setuptools wheel
    log_success "Pip upgraded"

    # Install Python dependencies
    if [ -f "$REPO_DIR/requirements.txt" ]; then
        log_info "Installing Python dependencies from requirements.txt..."
        pip install -r "$REPO_DIR/requirements.txt"
        log_success "Python dependencies installed"
    else
        log_warning "requirements.txt not found at $REPO_DIR/requirements.txt"
    fi

    # Set venv permissions
    chown -R $SERVICE_USER:$SERVICE_GROUP "$VENV_DIR"
    chmod -R 755 "$VENV_DIR"
}

################################################################################
# Setup Configuration
################################################################################

setup_configuration() {
    log_info "Setting up configuration..."

    # Create config directory if doesn't exist
    mkdir -p "$REPO_DIR/config"
    mkdir -p "$REPO_DIR/logs"
    mkdir -p "$REPO_DIR/data"
    mkdir -p "$REPO_DIR/ssh"
    mkdir -p "$REPO_DIR/gpg"

    # Check if .env exists
    if [ ! -f "$REPO_DIR/config/.env" ]; then
        log_warning ".env file not found. Creating template..."
        cat > "$REPO_DIR/config/.env.example" << 'EOF'
# Flask Configuration
FLASK_ENV=production
FLASK_DEBUG=false
FLASK_APP=src/api/app.py
SECRET_KEY=change-this-to-a-secure-random-string

# Mining Configuration
POOL_URL=stratum+tcp://pool.example.com:3333
WALLET_ADDRESS=your_wallet_address_here
MINER_THREADS=4
DIFFICULTY=default

# API Configuration
API_HOST=0.0.0.0
API_PORT=5000
API_WORKERS=4

# Database
DATABASE_URL=sqlite:////path/to/data/wallet.db

# Security
JWT_SECRET_KEY=change-this-to-a-secure-random-string
API_KEY_REQUIRED=true

# GPG & SSH
GPG_KEY_ID=your_gpg_key_id
SSH_KEY_PATH=/root/ssh/id_ed25519

# Logging
LOG_LEVEL=INFO
LOG_DIR=/var/log/jv93

# Services
ENABLE_MINER=true
ENABLE_API=true
ENABLE_WALLET=true
EOF
        log_warning "Created .env.example. Please configure .env with your settings"
    else
        log_success ".env configuration file exists"
    fi

    # Set configuration permissions
    chmod 600 "$REPO_DIR/config/.env" 2>/dev/null || true
    chown $SERVICE_USER:$SERVICE_GROUP "$REPO_DIR/config/.env" 2>/dev/null || true
}

################################################################################
# Setup GPG & SSH Keys
################################################################################

setup_security() {
    log_info "Setting up security infrastructure..."

    # Create GPG configuration
    mkdir -p "$REPO_DIR/gpg"
    chmod 700 "$REPO_DIR/gpg"

    # Create SSH directory
    mkdir -p "$REPO_DIR/ssh"
    chmod 700 "$REPO_DIR/ssh"

    log_warning "Please manually configure GPG keys and SSH keys in:"
    log_warning "  GPG: $REPO_DIR/gpg/"
    log_warning "  SSH: $REPO_DIR/ssh/"
    log_warning "Use: gpg --gen-key and ssh-keygen commands"
}

################################################################################
# Setup Firewall
################################################################################

setup_firewall() {
    log_info "Configuring UFW firewall..."

    # Enable UFW
    ufw --force enable

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (critical!)
    ufw allow 22/tcp
    log_success "SSH access allowed"

    # Allow API port (if using Flask)
    ufw allow 5000/tcp
    log_warning "API port 5000 opened. Restrict in production if needed."

    # Allow mining pool communication
    ufw allow out 3333/tcp
    log_info "Mining pool communication allowed"

    log_success "Firewall configured"
}

################################################################################
# Setup Systemd Service
################################################################################

setup_systemd_service() {
    log_info "Creating systemd service files..."

    # Main service
    cat > /etc/systemd/system/jv93.service << EOF
[Unit]
Description=JV93 Cryptocurrency Mining & Wallet Service
After=network.target
StartLimitIntervalSec=600
StartLimitBurst=3

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$REPO_DIR
Environment="PATH=$REPO_DIR/venv/bin"
EnvironmentFile=$REPO_DIR/config/.env

ExecStart=$REPO_DIR/venv/bin/python -m src.api.app
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$REPO_DIR/logs $REPO_DIR/data

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

StandardOutput=journal
StandardError=journal
SyslogIdentifier=jv93

[Install]
WantedBy=multi-user.target
EOF

    # Miner service
    cat > /etc/systemd/system/jv93-miner.service << EOF
[Unit]
Description=JV93 Mining Core Service
After=network.target jv93.service
Wants=jv93.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$REPO_DIR
Environment="PATH=$REPO_DIR/venv/bin"
EnvironmentFile=$REPO_DIR/config/.env

ExecStart=$REPO_DIR/venv/bin/python -m src.miner.core
Restart=always
RestartSec=10

# Security
NoNewPrivileges=true
CPUAccounting=yes

StandardOutput=journal
StandardError=journal
SyslogIdentifier=jv93-miner

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    log_success "Systemd services created"
}

################################################################################
# Setup Logging
################################################################################

setup_logging() {
    log_info "Setting up logging..."

    # Create log directory
    mkdir -p /var/log/jv93
    chown $SERVICE_USER:$SERVICE_GROUP /var/log/jv93
    chmod 755 /var/log/jv93

    # Create logrotate configuration
    cat > /etc/logrotate.d/jv93 << EOF
/var/log/jv93/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $SERVICE_USER $SERVICE_GROUP
    sharedscripts
    postrotate
        systemctl reload jv93 > /dev/null 2>&1 || true
    endscript
}
EOF

    log_success "Logging configured"
}

################################################################################
# Setup Backup Script
################################################################################

setup_backup() {
    log_info "Setting up backup infrastructure..."

    cat > "$REPO_DIR/scripts/backup_secure.sh" << 'EOF'
#!/bin/bash
# Secure backup script for JV93 wallet data

BACKUP_DIR="/var/backups/jv93"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz.gpg"

mkdir -p "$BACKUP_DIR"

echo "Creating encrypted backup..."
tar czf - \
    "$REPO_DIR/data/wallet.db" \
    "$REPO_DIR/config/.env" \
    "$REPO_DIR/gpg/" \
    "$REPO_DIR/ssh/" | \
    gpg --symmetric --cipher-algo AES256 > "$BACKUP_FILE"

chmod 600 "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

# Keep only last 7 days
find "$BACKUP_DIR" -name "backup_*.tar.gz.gpg" -mtime +7 -delete
echo "Old backups cleaned up"
EOF

    chmod +x "$REPO_DIR/scripts/backup_secure.sh"
    log_success "Backup script created"
}

################################################################################
# Database Initialization
################################################################################

setup_database() {
    log_info "Initializing database..."

    mkdir -p "$REPO_DIR/data"
    chown $SERVICE_USER:$SERVICE_GROUP "$REPO_DIR/data"
    chmod 755 "$REPO_DIR/data"

    # Create SQLite database with initial schema (if needed)
    sqlite3 "$REPO_DIR/data/wallet.db" << 'EOF'
CREATE TABLE IF NOT EXISTS wallets (
    id TEXT PRIMARY KEY,
    address TEXT UNIQUE NOT NULL,
    public_key TEXT,
    balance REAL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount REAL NOT NULL,
    fee REAL DEFAULT 0,
    status TEXT DEFAULT 'pending',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mining_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hash_rate REAL,
    shares_accepted INTEGER,
    shares_rejected INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wallet_address ON wallets(address);
CREATE INDEX IF NOT EXISTS idx_transaction_timestamp ON transactions(timestamp);
EOF

    chown $SERVICE_USER:$SERVICE_GROUP "$REPO_DIR/data/wallet.db"
    chmod 600 "$REPO_DIR/data/wallet.db"
    log_success "Database initialized"
}

################################################################################
# Setup Monitoring & Health Checks
################################################################################

setup_monitoring() {
    log_info "Setting up monitoring..."

    cat > "$REPO_DIR/scripts/health_check.sh" << 'EOF'
#!/bin/bash

API_PORT=5000
MINER_LOG="/var/log/jv93/miner.log"
WALLET_LOG="/var/log/jv93/wallet.log"

echo "=== JV93 Health Check ==="
echo ""

# Check API service
echo "API Service:"
if systemctl is-active --quiet jv93; then
    echo "  Status: ✓ Running"
else
    echo "  Status: ✗ Stopped"
fi

if curl -s http://localhost:$API_PORT/health >/dev/null 2>&1; then
    echo "  Health: ✓ Responding"
else
    echo "  Health: ✗ Not responding"
fi

# Check Miner service
echo ""
echo "Miner Service:"
if systemctl is-active --quiet jv93-miner; then
    echo "  Status: ✓ Running"
else
    echo "  Status: ✗ Stopped"
fi

# System resources
echo ""
echo "System Resources:"
free -h | awk 'NR==2 {printf "  Memory: %s / %s (%.1f%%)\n", $3, $2, ($3/$2)*100}'
df -h "$REPO_DIR" | awk 'NR==2 {printf "  Disk: %s / %s (%.1f%%)\n", $3, $2, ($3/$2)*100}'

echo ""
echo "Recent Errors (last 10):"
[ -f "$MINER_LOG" ] && tail -n 10 "$MINER_LOG" | grep -i error || echo "  None"
EOF

    chmod +x "$REPO_DIR/scripts/health_check.sh"
    log_success "Monitoring setup complete"
}

################################################################################
# Setup Cron Jobs
################################################################################

setup_cron() {
    log_info "Setting up cron jobs..."

    # Backup every day at 2 AM
    cat > /etc/cron.d/jv93-backup << EOF
# JV93 Backup Schedule
0 2 * * * $SERVICE_USER $REPO_DIR/scripts/backup_secure.sh >> /var/log/jv93/backup.log 2>&1
EOF

    chmod 644 /etc/cron.d/jv93-backup
    log_success "Cron jobs configured"
}

################################################################################
# Fail2Ban Configuration
################################################################################

setup_fail2ban() {
    log_info "Configuring Fail2Ban..."

    cat > /etc/fail2ban/jail.d/jv93.conf << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[jv93-api]
enabled = true
port = 5000
logpath = /var/log/jv93/api.log
maxretry = 10
findtime = 600
bantime = 3600
EOF

    systemctl restart fail2ban
    log_success "Fail2Ban configured"
}

################################################################################
# Final Setup & Information
################################################################################

print_summary() {
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║          JV93 Installation Complete!                           ║${NC}
${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

${BLUE}📁 Directory Structure:${NC}
  Repository: $REPO_DIR
  Virtual Env: $REPO_DIR/venv
  Logs: /var/log/jv93
  Data: $REPO_DIR/data
  Backups: /var/backups/jv93

${BLUE}🔧 Next Steps:${NC}

  1. ${YELLOW}Configure Environment:${NC}
     cp $REPO_DIR/config/.env.example $REPO_DIR/config/.env
     nano $REPO_DIR/config/.env
     # Set your pool URL, wallet address, and API keys

  2. ${YELLOW}Setup Security Keys:${NC}
     sudo -u $SERVICE_USER gpg --gen-key
     sudo -u $SERVICE_USER ssh-keygen -t ed25519 -f $REPO_DIR/ssh/id_ed25519
     
  3. ${YELLOW}Start Services:${NC}
     sudo systemctl start jv93
     sudo systemctl start jv93-miner
     sudo systemctl enable jv93
     sudo systemctl enable jv93-miner

  4. ${YELLOW}Check Status:${NC}
     sudo systemctl status jv93
     sudo systemctl status jv93-miner
     $REPO_DIR/scripts/health_check.sh

  5. ${YELLOW}View Logs:${NC}
     journalctl -u jv93 -f
     journalctl -u jv93-miner -f

${BLUE}🔐 Security Reminders:${NC}
  ✓ SSH key added to authorized_hosts on remote pools
  ✓ .env file contains sensitive data - keep permissions 600
  ✓ Regular backups enabled (daily at 2 AM)
  ✓ Firewall configured with UFW
  ✓ Fail2Ban protecting API endpoints

${BLUE}📊 Monitoring:${NC}
  • Health check: $REPO_DIR/scripts/health_check.sh
  • Logs: journalctl -u jv93 -f
  • System: htop, df -h, free -h

${BLUE}🆘 Troubleshooting:${NC}
  Installation log: $LOG_FILE
  Service logs: journalctl -u jv93 -n 100
  Errors: journalctl -u jv93 --no-pager | grep ERROR

EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting JV93 Installation for Ubuntu"
    log_info "Repository: $REPO_DIR"
    log_info "Installation log: $LOG_FILE"

    check_prerequisites
    update_system
    install_dependencies
    setup_service_user
    setup_python_env
    setup_configuration
    setup_security
    setup_firewall
    setup_systemd_service
    setup_logging
    setup_backup
    setup_database
    setup_monitoring
    setup_cron
    setup_fail2ban

    log_success "Installation completed successfully!"
    print_summary
}

# Run main function
main "$@"
