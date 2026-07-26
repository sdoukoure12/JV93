#!/bin/bash

################################################################################
# JV93 Installation Script for Ubuntu - ALL-IN-ONE with Tunnels
# Includes: Bore, Cloudflared, Ngrok alternatives + Mining & Wallet
# Copy & paste this entire script into your terminal
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

REPO_DIR="/opt/jv93"
LOG_FILE="/var/log/jv93_install.log"
PYTHON_VERSION="3.10"
SERVICE_USER="jv93"

check_prerequisites() {
    log_info "Checking prerequisites..."
    [[ $EUID -ne 0 ]] && { log_error "Run with sudo"; exit 1; }
    grep -qi "ubuntu" /etc/os-release || { log_error "Ubuntu required"; exit 1; }
    log_success "Prerequisites verified"
}

update_system() {
    log_info "Updating system..."
    apt-get update && apt-get upgrade -y
    log_success "System updated"
}

install_dependencies() {
    log_info "Installing dependencies..."
    apt-get install -y \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev \
        python3-pip build-essential libssl-dev libffi-dev git wget curl sqlite3 \
        gnupg openssh-client openssh-server fail2ban ufw htop tmux supervisor jq \
        net-tools vim cargo rustc nodejs npm postgresql postgresql-contrib redis-server
    log_success "Dependencies installed"
}

setup_service_user() {
    log_info "Setting up service user..."
    id "$SERVICE_USER" &>/dev/null || useradd -r -s /bin/bash -d /home/$SERVICE_USER -m $SERVICE_USER
    log_success "Service user ready"
}

setup_directories() {
    log_info "Creating directory structure..."
    mkdir -p $REPO_DIR/{src/{miner,wallet,api,services,utils},config/seeds,scripts,logs,data/{wallets,transactions},ssh,gpg,tunnels}
    chown -R $SERVICE_USER:$SERVICE_USER $REPO_DIR
    chmod 755 $REPO_DIR
    log_success "Directories created"
}

setup_python_env() {
    log_info "Setting up Python virtual environment..."
    python${PYTHON_VERSION} -m venv $REPO_DIR/venv
    source $REPO_DIR/venv/bin/activate
    pip install --upgrade pip setuptools wheel
    
    # Install required Python packages
    pip install \
        flask flask-cors flask-jwt-extended \
        requests pycryptodome \
        web3 eth-keys eth-utils \
        sqlalchemy psycopg2-binary \
        redis celery \
        aiohttp asyncio \
        python-dotenv pyyaml \
        gunicorn \
        paramiko cryptography \
        pyserial \
        prometheus-client
    
    chown -R $SERVICE_USER:$SERVICE_USER $REPO_DIR/venv
    log_success "Python environment ready"
}

install_bore() {
    log_info "Installing Bore tunnel..."
    # Bore - Simple tunnel (free, no account needed)
    cat > $REPO_DIR/tunnels/bore_tunnel.sh << 'BORE_EOF'
#!/bin/bash
# Bore tunnel - Free, no registration needed
# Usage: ./bore_tunnel.sh <local_port> <public_port>

LOCAL_PORT=${1:-5000}
PUBLIC_PORT=${2:-8080}

echo "Starting Bore tunnel: localhost:$LOCAL_PORT -> bore.pub:$PUBLIC_PORT"
cargo install bore-cli 2>/dev/null || apt-get install -y bore 2>/dev/null

# Run bore
bore local $LOCAL_PORT --to bore.pub --port $PUBLIC_PORT
BORE_EOF
    
    chmod +x $REPO_DIR/tunnels/bore_tunnel.sh
    log_success "Bore tunnel script created"
}

install_cloudflared() {
    log_info "Installing Cloudflared tunnel..."
    # Download and install Cloudflared
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /tmp/cloudflared
    chmod +x /tmp/cloudflared
    mv /tmp/cloudflared /usr/local/bin/cloudflared
    
    # Create startup script
    cat > $REPO_DIR/tunnels/cloudflare_tunnel.sh << 'CF_EOF'
#!/bin/bash
# Cloudflare Tunnel - Free tunnel with custom domain
# https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/

LOCAL_PORT=${1:-5000}
TUNNEL_NAME=${2:-jv93-mining}

echo "Starting Cloudflare tunnel: localhost:$LOCAL_PORT"
echo "Tunnel name: $TUNNEL_NAME"

# Login first time only
cloudflared tunnel login

# Create and run tunnel
cloudflared tunnel run $TUNNEL_NAME
CF_EOF
    
    chmod +x $REPO_DIR/tunnels/cloudflare_tunnel.sh
    log_success "Cloudflared installed"
}

install_localtunnel() {
    log_info "Installing LocalTunnel..."
    # Local Tunnel - npm based, very simple
    npm install -g localtunnel 2>/dev/null || apt-get install -y localtunnel
    
    cat > $REPO_DIR/tunnels/localtunnel.sh << 'LT_EOF'
#!/bin/bash
# LocalTunnel - Free, no registration needed
# Usage: ./localtunnel.sh <local_port>

LOCAL_PORT=${1:-5000}
SUBDOMAIN=${2:-jv93}

echo "Starting LocalTunnel: localhost:$LOCAL_PORT"
echo "Access at: https://$SUBDOMAIN.loca.lt"

lt --port $LOCAL_PORT --subdomain $SUBDOMAIN
LT_EOF
    
    chmod +x $REPO_DIR/tunnels/localtunnel.sh
    log_success "LocalTunnel installed"
}

install_exposed() {
    log_info "Installing Exposed tunnel..."
    # Exposed - Another free option
    pip install exposed 2>/dev/null || echo "Install exposed manually: pip install exposed"
    
    cat > $REPO_DIR/tunnels/exposed_tunnel.sh << 'EXP_EOF'
#!/bin/bash
# Exposed tunnel - Free tunnel service
LOCAL_PORT=${1:-5000}

echo "Starting Exposed tunnel on port $LOCAL_PORT"
python -m exposed --port $LOCAL_PORT
EXP_EOF
    
    chmod +x $REPO_DIR/tunnels/exposed_tunnel.sh
    log_success "Exposed tunnel script created"
}

setup_configuration() {
    log_info "Setting up configuration..."
    
    cat > $REPO_DIR/config/.env << 'ENV_EOF'
# ===== FLASK API =====
FLASK_ENV=production
FLASK_DEBUG=false
SECRET_KEY=your-secret-key-change-this
API_HOST=0.0.0.0
API_PORT=5000
API_WORKERS=4

# ===== MINING =====
POOL_URL=stratum+tcp://pool.example.com:3333
WALLET_ADDRESS=your_wallet_address
MINER_THREADS=4
DIFFICULTY=default

# ===== DATABASE =====
DATABASE_URL=sqlite:////opt/jv93/data/wallet.db
REDIS_URL=redis://localhost:6379/0
POSTGRES_URL=postgresql://jv93:password@localhost:5432/jv93_db

# ===== SECURITY =====
JWT_SECRET_KEY=your-jwt-secret-change-this
API_KEY_REQUIRED=true
GPG_KEY_ID=your_gpg_key_id
SSH_KEY_PATH=/home/jv93/ssh/id_ed25519

# ===== TUNNELS =====
USE_BORE=false
USE_CLOUDFLARE=false
USE_LOCALTUNNEL=false
BORE_PORT=8080
CLOUDFLARE_TUNNEL_NAME=jv93-mining
LOCALTUNNEL_SUBDOMAIN=jv93

# ===== LOGGING =====
LOG_LEVEL=INFO
LOG_DIR=/var/log/jv93

# ===== FEATURES =====
ENABLE_MINER=true
ENABLE_API=true
ENABLE_WALLET=true
ENABLE_REDIS=true
ENABLE_POSTGRES=true
ENV_EOF

    chmod 600 $REPO_DIR/config/.env
    chown $SERVICE_USER:$SERVICE_USER $REPO_DIR/config/.env
    log_warning "Configure .env at: $REPO_DIR/config/.env"
}

create_python_files() {
    log_info "Creating Python application files..."
    
    # Main Flask App
    cat > $REPO_DIR/src/api/app.py << 'FLASK_EOF'
from flask import Flask, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'service': 'jv93-mining-api'
    })

@app.route('/api/stats', methods=['GET'])
def stats():
    return jsonify({
        'miner_running': True,
        'hash_rate': '0 H/s',
        'shares_accepted': 0,
        'balance': 0
    })

@app.route('/api/wallet', methods=['GET'])
def wallet():
    return jsonify({
        'address': os.getenv('WALLET_ADDRESS'),
        'balance': 0,
        'transactions': []
    })

if __name__ == '__main__':
    app.run(
        host=os.getenv('API_HOST', '0.0.0.0'),
        port=int(os.getenv('API_PORT', 5000)),
        debug=os.getenv('FLASK_DEBUG', False) == 'true'
    )
FLASK_EOF

    # Miner Core
    cat > $REPO_DIR/src/miner/core.py << 'MINER_EOF'
import os
import time
from dotenv import load_dotenv

load_dotenv()

class Miner:
    def __init__(self):
        self.pool_url = os.getenv('POOL_URL')
        self.wallet = os.getenv('WALLET_ADDRESS')
        self.threads = int(os.getenv('MINER_THREADS', 4))
        self.running = False
    
    def start(self):
        self.running = True
        print(f"Miner starting with {self.threads} threads")
        print(f"Pool: {self.pool_url}")
        print(f"Wallet: {self.wallet}")
        
        while self.running:
            time.sleep(60)
            print("Mining...")
    
    def stop(self):
        self.running = False
        print("Miner stopped")

if __name__ == '__main__':
    miner = Miner()
    miner.start()
MINER_EOF

    # Config module
    cat > $REPO_DIR/src/utils/config.py << 'CONFIG_EOF'
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    # Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-key-change-this')
    FLASK_ENV = os.getenv('FLASK_ENV', 'production')
    
    # API
    API_HOST = os.getenv('API_HOST', '0.0.0.0')
    API_PORT = int(os.getenv('API_PORT', 5000))
    
    # Mining
    POOL_URL = os.getenv('POOL_URL')
    WALLET_ADDRESS = os.getenv('WALLET_ADDRESS')
    MINER_THREADS = int(os.getenv('MINER_THREADS', 4))
    
    # Database
    DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:////opt/jv93/data/wallet.db')
    REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379/0')
    
    # Security
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'jwt-secret-change-this')
    
CONFIG_EOF

    chmod +x $REPO_DIR/src/api/app.py
    chmod +x $REPO_DIR/src/miner/core.py
    chown -R $SERVICE_USER:$SERVICE_USER $REPO_DIR/src
    log_success "Python application files created"
}

create_scripts() {
    log_info "Creating management scripts..."
    
    # Start script
    cat > $REPO_DIR/scripts/start.sh << 'START_EOF'
#!/bin/bash
REPO_DIR=/opt/jv93
source $REPO_DIR/venv/bin/activate
cd $REPO_DIR

echo "Starting JV93 services..."
systemctl start jv93 jv93-miner
sleep 2
systemctl status jv93 jv93-miner
echo "Services started!"
START_EOF

    # Stop script
    cat > $REPO_DIR/scripts/stop.sh << 'STOP_EOF'
#!/bin/bash
echo "Stopping JV93 services..."
systemctl stop jv93 jv93-miner
echo "Services stopped!"
STOP_EOF

    # Status script
    cat > $REPO_DIR/scripts/status.sh << 'STATUS_EOF'
#!/bin/bash
echo "=== JV93 Services Status ==="
echo ""
echo "API Service:"
systemctl status jv93 --no-pager
echo ""
echo "Miner Service:"
systemctl status jv93-miner --no-pager
echo ""
echo "Recent logs:"
journalctl -u jv93 -n 20 --no-pager
STATUS_EOF

    # Tunnel manager
    cat > $REPO_DIR/scripts/tunnels.sh << 'TUNNEL_EOF'
#!/bin/bash
REPO_DIR=/opt/jv93

usage() {
    echo "Usage: ./tunnels.sh [bore|cloudflare|localtunnel|all|stop]"
    echo ""
    echo "Examples:"
    echo "  ./tunnels.sh bore          - Start Bore tunnel"
    echo "  ./tunnels.sh cloudflare    - Start Cloudflare tunnel"
    echo "  ./tunnels.sh localtunnel   - Start LocalTunnel"
    echo "  ./tunnels.sh all           - Start all tunnels"
    exit 1
}

[[ -z "$1" ]] && usage

case "$1" in
    bore)
        echo "Starting Bore tunnel..."
        $REPO_DIR/tunnels/bore_tunnel.sh 5000 8080
        ;;
    cloudflare)
        echo "Starting Cloudflare tunnel..."
        $REPO_DIR/tunnels/cloudflare_tunnel.sh 5000
        ;;
    localtunnel)
        echo "Starting LocalTunnel..."
        $REPO_DIR/tunnels/localtunnel.sh 5000 jv93
        ;;
    all)
        echo "Starting all tunnels in background..."
        $REPO_DIR/tunnels/bore_tunnel.sh 5000 8080 &
        sleep 1
        $REPO_DIR/tunnels/localtunnel.sh 5000 jv93 &
        echo "Tunnels running in background"
        ;;
    stop)
        pkill -f "bore\|cloudflared\|localtunnel"
        echo "All tunnels stopped"
        ;;
    *)
        usage
        ;;
esac
TUNNEL_EOF

    chmod +x $REPO_DIR/scripts/*.sh
    chown -R $SERVICE_USER:$SERVICE_USER $REPO_DIR/scripts
    log_success "Management scripts created"
}

setup_systemd_services() {
    log_info "Creating systemd services..."
    
    cat > /etc/systemd/system/jv93.service << EOF
[Unit]
Description=JV93 API Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$REPO_DIR
Environment="PATH=$REPO_DIR/venv/bin"
EnvironmentFile=$REPO_DIR/config/.env
ExecStart=$REPO_DIR/venv/bin/python -m src.api.app
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=jv93-api

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/jv93-miner.service << EOF
[Unit]
Description=JV93 Mining Service
After=network.target jv93.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$REPO_DIR
Environment="PATH=$REPO_DIR/venv/bin"
EnvironmentFile=$REPO_DIR/config/.env
ExecStart=$REPO_DIR/venv/bin/python -m src.miner.core
Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=jv93-miner

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Systemd services created"
}

setup_firewall() {
    log_info "Configuring firewall..."
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 5000/tcp
    ufw allow 8080/tcp
    ufw allow out 3333/tcp
    log_success "Firewall configured"
}

create_requirements() {
    log_info "Creating requirements.txt..."
    cat > $REPO_DIR/requirements.txt << 'REQ_EOF'
Flask==2.3.2
Flask-CORS==4.0.0
Flask-JWT-Extended==4.4.4
requests==2.31.0
pycryptodome==3.18.0
web3==6.8.0
eth-keys==0.4.0
eth-utils==2.0.0
sqlalchemy==2.0.19
psycopg2-binary==2.9.6
redis==4.6.0
celery==5.3.1
aiohttp==3.8.5
asyncio==3.4.3
python-dotenv==1.0.0
pyyaml==6.0
gunicorn==21.2.0
paramiko==3.3.1
cryptography==41.0.2
pyserial==3.5
prometheus-client==0.17.1
REQ_EOF

    log_success "requirements.txt created"
}

print_summary() {
    cat << EOF

${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}
${GREEN}║     JV93 Mining + Tunnels Installation Complete! ✓            ║${NC}
${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}

${BLUE}📍 Installation Path:${NC}
  Repository: $REPO_DIR
  Config: $REPO_DIR/config/.env
  Scripts: $REPO_DIR/scripts/
  Tunnels: $REPO_DIR/tunnels/

${BLUE}🚀 Quick Start:${NC}
  1. ${YELLOW}Edit configuration:${NC}
     nano $REPO_DIR/config/.env

  2. ${YELLOW}Start services:${NC}
     sudo $REPO_DIR/scripts/start.sh

  3. ${YELLOW}Check status:${NC}
     sudo $REPO_DIR/scripts/status.sh

${BLUE}🌐 Tunnel Options (Choose one or more):${NC}

  ${YELLOW}Bore (Simple, no registration):${NC}
     sudo $REPO_DIR/scripts/tunnels.sh bore

  ${YELLOW}Cloudflare (Professional, free):${NC}
     sudo $REPO_DIR/scripts/tunnels.sh cloudflare

  ${YELLOW}LocalTunnel (Easy, no account):${NC}
     sudo $REPO_DIR/scripts/tunnels.sh localtunnel

  ${YELLOW}All tunnels:${NC}
     sudo $REPO_DIR/scripts/tunnels.sh all

${BLUE}📊 Monitoring:${NC}
  • Live logs: journalctl -u jv93 -f
  • API health: curl http://localhost:5000/health
  • All status: sudo $REPO_DIR/scripts/status.sh

${BLUE}🔒 Security:${NC}
  • Configure .env with your wallet and pool
  • Keep .env permissions at 600
  • Add SSH keys: ssh-keygen -t ed25519 -f $REPO_DIR/ssh/id_ed25519

${BLUE}📝 Available Commands:${NC}
  Start:    sudo $REPO_DIR/scripts/start.sh
  Stop:     sudo $REPO_DIR/scripts/stop.sh
  Status:   sudo $REPO_DIR/scripts/status.sh
  Tunnels:  sudo $REPO_DIR/scripts/tunnels.sh [bore|cloudflare|localtunnel]

EOF
}

main() {
    echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  JV93 Installation Started               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    update_system
    install_dependencies
    setup_service_user
    setup_directories
    setup_python_env
    install_bore
    install_cloudflared
    install_localtunnel
    install_exposed
    setup_configuration
    create_python_files
    create_scripts
    setup_systemd_services
    setup_firewall
    create_requirements
    
    echo ""
    log_success "Installation completed!"
    print_summary
}

main "$@"
