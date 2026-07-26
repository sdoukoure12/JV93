#!/bin/bash

################################################################################
# JV93 Installation Script for Termux (FIXED for Termux packages)
# Cryptocurrency Mining + Wallet + Free Tunnels
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Termux specific paths
if [[ -n "$TERMUX_VERSION" ]]; then
    REPO_DIR="$HOME/jv93"
    LOG_FILE="$HOME/jv93.log"
else
    log_error "This script is for Termux only!"
    log_info "Install Termux from Google Play Store or F-Droid"
    exit 1
fi

check_termux() {
    log_info "Checking Termux environment..."
    [[ -z "$TERMUX_VERSION" ]] && { log_error "Not running in Termux"; exit 1; }
    [[ -z "$HOME" ]] && { log_error "HOME not set"; exit 1; }
    log_success "Termux environment verified"
}

update_packages() {
    log_info "Updating Termux packages..."
    apt update
    apt upgrade -y
    log_success "Packages updated"
}

install_dependencies() {
    log_info "Installing dependencies (this may take a while)..."
    
    # Termux correct package names
    apt install -y \
        python \
        python-pip \
        git \
        wget \
        curl \
        vim \
        nano \
        openssh \
        openssl \
        sqlite \
        gnupg \
        tmux \
        htop \
        net-tools \
        jq \
        nodejs \
        npm \
        build-essential \
        pkg-config \
        libffi \
        libtool \
        autoconf \
        make
    
    log_success "Dependencies installed"
}

setup_directories() {
    log_info "Creating directory structure..."
    mkdir -p $REPO_DIR/{src/{miner,wallet,api,services,utils},config,scripts,logs,data/{wallets,transactions},ssh,gpg,tunnels}
    log_success "Directories created at: $REPO_DIR"
}

setup_python_env() {
    log_info "Setting up Python environment..."
    
    cd $REPO_DIR
    python -m pip install --upgrade pip setuptools wheel
    
    # Install Python packages
    pip install \
        flask \
        flask-cors \
        requests \
        pycryptodome \
        python-dotenv \
        pyyaml \
        cryptography \
        paramiko \
        redis \
        aiohttp
    
    log_success "Python environment ready"
}

install_tunnels() {
    log_info "Installing tunnel tools..."
    
    # Bore CLI
    log_info "Installing Bore..."
    npm install -g bore-cli
    
    # LocalTunnel
    log_info "Installing LocalTunnel..."
    npm install -g localtunnel
    
    # Cloudflare Tunnel (ARM64 or ARM)
    log_info "Downloading Cloudflare Tunnel..."
    ARCH=$(uname -m)
    
    if [[ "$ARCH" == "aarch64" ]]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    else
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
    fi
    
    if wget -q "$CLOUDFLARED_URL" -O $PREFIX/bin/cloudflared 2>/dev/null; then
        chmod +x $PREFIX/bin/cloudflared
        log_success "Cloudflared installed"
    else
        log_warning "Cloudflared download failed (optional)"
    fi
    
    log_success "Tunnels installed"
}

create_python_files() {
    log_info "Creating Python application files..."
    
    # Flask API
    cat > $REPO_DIR/src/api/app.py << 'FLASK_EOF'
#!/usr/bin/env python
from flask import Flask, jsonify
from flask_cors import CORS
import os
from dotenv import load_dotenv
import json
from datetime import datetime
import sys

# Load .env from config directory
config_path = os.path.join(os.path.dirname(__file__), '../../config/.env')
load_dotenv(config_path)

app = Flask(__name__)
CORS(app)

# In-memory stats
stats = {
    'miner_running': False,
    'hash_rate': 0,
    'shares_accepted': 0,
    'balance': 0,
    'uptime': 0
}

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'service': 'jv93-mining-api',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/stats', methods=['GET'])
def get_stats():
    return jsonify(stats)

@app.route('/api/wallet', methods=['GET'])
def wallet():
    return jsonify({
        'address': os.getenv('WALLET_ADDRESS', 'Not configured'),
        'balance': stats['balance'],
        'transactions': []
    })

@app.route('/api/miner/start', methods=['POST'])
def start_miner():
    stats['miner_running'] = True
    return jsonify({'status': 'started'})

@app.route('/api/miner/stop', methods=['POST'])
def stop_miner():
    stats['miner_running'] = False
    return jsonify({'status': 'stopped'})

if __name__ == '__main__':
    try:
        port = int(os.getenv('API_PORT', 5000))
        host = os.getenv('API_HOST', '0.0.0.0')
        print(f"Starting JV93 API on {host}:{port}")
        app.run(host=host, port=port, debug=False, threaded=True)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
FLASK_EOF

    # Miner
    cat > $REPO_DIR/src/miner/core.py << 'MINER_EOF'
#!/usr/bin/env python
import os
import time
from dotenv import load_dotenv
import sys

# Load .env from config directory
config_path = os.path.join(os.path.dirname(__file__), '../../config/.env')
load_dotenv(config_path)

class TermuxMiner:
    def __init__(self):
        self.pool_url = os.getenv('POOL_URL', 'stratum+tcp://pool.example.com:3333')
        self.wallet = os.getenv('WALLET_ADDRESS', 'default_wallet')
        self.threads = int(os.getenv('MINER_THREADS', 1))
        self.running = False
        
    def log(self, msg):
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] [MINER] {msg}")
        sys.stdout.flush()
    
    def start(self):
        self.running = True
        self.log(f"Starting miner with {self.threads} threads")
        self.log(f"Pool: {self.pool_url}")
        self.log(f"Wallet: {self.wallet}")
        self.log("Mining started. Press Ctrl+C to stop")
        
        try:
            counter = 0
            while self.running:
                counter += 1
                time.sleep(60)
                self.log(f"Mining... Cycle {counter} (hash rate: N/A)")
        except KeyboardInterrupt:
            self.log("Mining stopped by user")
            self.running = False

if __name__ == '__main__':
    try:
        miner = TermuxMiner()
        miner.start()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
MINER_EOF

    # Config
    cat > $REPO_DIR/src/utils/config.py << 'CONFIG_EOF'
import os
from dotenv import load_dotenv

config_path = os.path.join(os.path.dirname(__file__), '../../config/.env')
load_dotenv(config_path)

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'termux-dev-key')
    API_HOST = os.getenv('API_HOST', '0.0.0.0')
    API_PORT = int(os.getenv('API_PORT', 5000))
    POOL_URL = os.getenv('POOL_URL')
    WALLET_ADDRESS = os.getenv('WALLET_ADDRESS')
    MINER_THREADS = int(os.getenv('MINER_THREADS', 1))
CONFIG_EOF

    chmod +x $REPO_DIR/src/api/app.py
    chmod +x $REPO_DIR/src/miner/core.py
    log_success "Python files created"
}

create_config() {
    log_info "Creating configuration..."
    
    cat > $REPO_DIR/config/.env << 'ENV_EOF'
# ===== TERMUX JV93 CONFIG =====

# API
FLASK_ENV=production
API_HOST=0.0.0.0
API_PORT=5000
SECRET_KEY=change-this-secret-key

# Mining
POOL_URL=stratum+tcp://pool.example.com:3333
WALLET_ADDRESS=your_wallet_address_here
MINER_THREADS=1

# Tunnels
LOCALTUNNEL_SUBDOMAIN=jv93-termux
BORE_PORT=8080

# Database
DATABASE_PATH=$HOME/jv93/data/wallet.db

# Logging
LOG_LEVEL=INFO
ENV_EOF

    chmod 600 $REPO_DIR/config/.env
    log_warning "Configure .env at: $REPO_DIR/config/.env"
}

create_scripts() {
    log_info "Creating management scripts..."
    
    # Start API
    cat > $REPO_DIR/scripts/start_api.sh << 'API_EOF'
#!/bin/bash
REPO_DIR=$HOME/jv93
cd $REPO_DIR

echo "[JV93] Starting API server..."
echo "[JV93] Access at: http://localhost:5000"
echo "[JV93] Health check: curl http://localhost:5000/health"
echo ""

python $REPO_DIR/src/api/app.py
API_EOF

    # Start Miner
    cat > $REPO_DIR/scripts/start_miner.sh << 'MINER_EOF'
#!/bin/bash
REPO_DIR=$HOME/jv93
cd $REPO_DIR

echo "[JV93] Starting miner..."
echo "[JV93] Press Ctrl+C to stop"
echo ""

python $REPO_DIR/src/miner/core.py
MINER_EOF

    # Tunnel manager
    cat > $REPO_DIR/scripts/tunnels.sh << 'TUNNEL_EOF'
#!/bin/bash

usage() {
    echo "╔════════════════════════════════════════╗"
    echo "║  JV93 Termux Tunnel Manager            ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "Usage: bash tunnels.sh [command]"
    echo ""
    echo "Commands:"
    echo "  bore              - Start Bore tunnel"
    echo "  localtunnel       - Start LocalTunnel"
    echo "  cloudflare        - Start Cloudflare tunnel"
    echo ""
    echo "Examples:"
    echo "  bash tunnels.sh bore"
    echo "  bash tunnels.sh localtunnel"
    exit 1
}

[[ -z "$1" ]] && usage

case "$1" in
    bore)
        echo "Starting Bore tunnel on port 8080..."
        echo "API at: http://localhost:5000"
        echo ""
        bore local 5000 --to bore.pub --port 8080
        ;;
    localtunnel)
        echo "Starting LocalTunnel..."
        echo "Random subdomain will be assigned"
        echo ""
        lt --port 5000
        ;;
    cloudflare)
        echo "Starting Cloudflare tunnel..."
        echo "First time: login at https://dash.cloudflare.com/"
        echo ""
        cloudflared tunnel run jv93-termux 2>/dev/null || echo "Configure Cloudflare first"
        ;;
    *)
        usage
        ;;
esac
TUNNEL_EOF

    # Main launcher
    cat > $REPO_DIR/scripts/launcher.sh << 'LAUNCH_EOF'
#!/bin/bash

show_menu() {
    clear
    echo "╔═══════════════════════════════════════════════╗"
    echo "║        JV93 Termux Launcher                   ║"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║ 1) Start API Server                           ║"
    echo "║ 2) Start Miner                                ║"
    echo "║ 3) Tunnels Menu                               ║"
    echo "║ 4) View Configuration                         ║"
    echo "║ 5) Edit Configuration                         ║"
    echo "║ 6) API Health Check                           ║"
    echo "║ 7) Exit                                       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

tunnels_menu() {
    clear
    echo "╔═══════════════════════════════════════════════╗"
    echo "║        Tunnels Menu                           ║"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║ 1) Bore (No account needed)                   ║"
    echo "║ 2) LocalTunnel (Simple)                       ║"
    echo "║ 3) Cloudflare (Professional)                  ║"
    echo "║ 4) Back to Main Menu                          ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

REPO_DIR=$HOME/jv93

while true; do
    show_menu
    read -p "Choose option: " choice
    
    case $choice in
        1)
            echo "Starting API server..."
            sleep 1
            bash $REPO_DIR/scripts/start_api.sh
            ;;
        2)
            echo "Starting Miner..."
            sleep 1
            bash $REPO_DIR/scripts/start_miner.sh
            ;;
        3)
            while true; do
                tunnels_menu
                read -p "Choose tunnel: " tunnel_choice
                case $tunnel_choice in
                    1) bash $REPO_DIR/scripts/tunnels.sh bore ;;
                    2) bash $REPO_DIR/scripts/tunnels.sh localtunnel ;;
                    3) bash $REPO_DIR/scripts/tunnels.sh cloudflare ;;
                    4) break ;;
                    *) echo "Invalid option" ;;
                esac
            done
            ;;
        4)
            cat $REPO_DIR/config/.env
            read -p "Press Enter to continue..."
            ;;
        5)
            nano $REPO_DIR/config/.env
            ;;
        6)
            echo "Checking API health..."
            curl -s http://localhost:5000/health 2>/dev/null | python -m json.tool 2>/dev/null || echo "API not responding. Start it first!"
            read -p "Press Enter to continue..."
            ;;
        7)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option"
            sleep 1
            ;;
    esac
done
LAUNCH_EOF

    chmod +x $REPO_DIR/scripts/*.sh
    log_success "Scripts created"
}

create_docs() {
    log_info "Creating documentation..."
    
    cat > $REPO_DIR/README_TERMUX.md << 'README_EOF'
# JV93 - Termux Edition

Cryptocurrency Mining + Wallet Management on Android with Termux

## Installation

```bash
pkg install git
git clone https://github.com/sdoukoure12/JV93
cd JV93
bash install_termux.sh
```

## Quick Start

### Method 1: Interactive Launcher
```bash
bash $HOME/jv93/scripts/launcher.sh
```

### Method 2: Manual Start (Recommended)

**Terminal 1 - API Server:**
```bash
bash $HOME/jv93/scripts/start_api.sh
```

**Terminal 2 - Mining:**
```bash
bash $HOME/jv93/scripts/start_miner.sh
```

**Terminal 3 - Tunnel:**
```bash
bash $HOME/jv93/scripts/tunnels.sh localtunnel
```

## Configuration

Edit the config:
```bash
nano $HOME/jv93/config/.env
```

Set your:
- **WALLET_ADDRESS** - Your crypto wallet address (from your seed)
- **POOL_URL** - Mining pool (e.g., stratum+tcp://pool.example.com:3333)
- **MINER_THREADS** - CPU threads (1-2 for phones)

## Tunnels (Choose One)

Run in separate Termux session:

**Bore (Simplest):**
```bash
bash $HOME/jv93/scripts/tunnels.sh bore
```

**LocalTunnel (Easy):**
```bash
bash $HOME/jv93/scripts/tunnels.sh localtunnel
```

**Cloudflare (Professional):**
```bash
bash $HOME/jv93/scripts/tunnels.sh cloudflare
```

## Multiple Sessions

Method 1: Use Termux menu
- Tap the terminal icon at bottom
- Tap "+" to open new session

Method 2: Use tmux
```bash
tmux new-session -d -s api bash $HOME/jv93/scripts/start_api.sh
tmux new-session -d -s miner bash $HOME/jv93/scripts/start_miner.sh
tmux list-sessions
```

## API Endpoints

```bash
# Health check
curl http://localhost:5000/health

# Stats
curl http://localhost:5000/api/stats

# Wallet info
curl http://localhost:5000/api/wallet
```

## Power & Battery Tips

1. **Use WiFi** - Faster and cheaper than mobile data
2. **Reduce threads** - Set MINER_THREADS=1 for battery
3. **Keep screen off** - Saves significant battery
4. **Monitor temperature** - Android throttles if too hot
5. **Short sessions** - Don't leave mining on 24/7

## Troubleshooting

### Port already in use
```bash
pkill -f "python.*app.py"
pkill -f "python.*core.py"
```

### API not responding
```bash
# Check if running
ps aux | grep python

# Start API again
bash $HOME/jv93/scripts/start_api.sh
```

### Can't install packages
```bash
apt update
apt upgrade -y
```

## Directories

```
$HOME/jv93/
├── src/          - Application code
├── config/       - .env configuration
├── scripts/      - Management scripts
├── data/         - Wallet database
├── logs/         - Log files
└── tunnels/      - Tunnel helpers
```

README_EOF

    log_success "Documentation created"
}

print_summary() {
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════╗${NC}
${GREEN}║  JV93 Termux Installation Complete! ✓             ║${NC}
${GREEN}╚════════════════════════════════════════════════════╝${NC}

${CYAN}📱 Installation Complete at:${NC}
  $HOME/jv93

${CYAN}🚀 Start Mining Now:${NC}

  ${YELLOW}Option 1 - Interactive Launcher:${NC}
     bash $HOME/jv93/scripts/launcher.sh

  ${YELLOW}Option 2 - Open 3 Termux Sessions:${NC}
     
     Session 1 - API Server:
     bash $HOME/jv93/scripts/start_api.sh
     
     Session 2 - Miner:
     bash $HOME/jv93/scripts/start_miner.sh
     
     Session 3 - Tunnel:
     bash $HOME/jv93/scripts/tunnels.sh localtunnel

${CYAN}⚙️  Configure First:${NC}
  nano $HOME/jv93/config/.env
  
  Set:
  • WALLET_ADDRESS - Your wallet from seed
  • POOL_URL - Mining pool stratum address
  • MINER_THREADS - 1 or 2 (not more on phones)

${CYAN}🌐 Tunnels Available:${NC}
  • Bore: bash $HOME/jv93/scripts/tunnels.sh bore
  • LocalTunnel: bash $HOME/jv93/scripts/tunnels.sh localtunnel
  • Cloudflare: bash $HOME/jv93/scripts/tunnels.sh cloudflare

${CYAN}📊 Check API Health:${NC}
  curl http://localhost:5000/health
  curl http://localhost:5000/api/stats
  curl http://localhost:5000/api/wallet

${CYAN}📱 How to Open Multiple Sessions:${NC}
  1. In Termux, tap terminal icon at bottom
  2. Tap + button to add new session
  3. Repeat for each service (API, Miner, Tunnel)

${CYAN}💡 Tips for Termux:${NC}
  ✓ Use WiFi (better than mobile data)
  ✓ Keep screen off to save battery
  ✓ Monitor device temperature
  ✓ Don't mine 24/7 (battery drain)
  ✓ Set threads to 1-2 max

${YELLOW}⚠️  Important:${NC}
  • Keep your seed phrase SAFE - never share!
  • Edit .env with YOUR wallet address
  • Configure pool URL correctly
  • Monitor temperature during mining

${CYAN}📁 Locations:${NC}
  Config: $HOME/jv93/config/.env
  Logs: $HOME/jv93/logs/
  Data: $HOME/jv93/data/

${CYAN}📖 Full Guide:${NC}
  cat $HOME/jv93/README_TERMUX.md

EOF
}

main() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  JV93 Termux Installation                ║${NC}"
    echo -e "${CYAN}║  Fixed for Termux Packages               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    check_termux
    update_packages
    install_dependencies
    setup_directories
    setup_python_env
    install_tunnels
    create_python_files
    create_config
    create_scripts
    create_docs
    
    echo ""
    log_success "Installation completed!"
    print_summary
}

main "$@"
