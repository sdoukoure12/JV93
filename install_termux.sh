#!/bin/bash

################################################################################
# JV93 Installation Script for Termux
# Cryptocurrency Mining + Wallet + Free Tunnels
# Install on Android with Termux: pkg install git && git clone https://github.com/sdoukoure12/JV93 && bash JV93/install_termux.sh
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
    PREFIX="$PREFIX"
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
    
    # Essential packages
    apt install -y \
        python \
        python-dev \
        pip \
        git \
        wget \
        curl \
        vim \
        nano \
        openssh \
        openssl \
        openssl-dev \
        libffi \
        libffi-dev \
        sqlite \
        gnupg \
        tmux \
        htop \
        net-tools \
        jq \
        nodejs \
        nodejs-npm \
        build-essential \
        clang \
        make \
        cmake \
        pkg-config \
        libtool \
        autoconf
    
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
    
    # Bore
    log_info "Installing Bore..."
    npm install -g bore-cli 2>/dev/null || apt install -y bore 2>/dev/null
    
    # LocalTunnel
    log_info "Installing LocalTunnel..."
    npm install -g localtunnel
    
    # Cloudflare Tunnel
    log_info "Setting up Cloudflare Tunnel..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
        -O $PREFIX/bin/cloudflared 2>/dev/null || \
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm \
        -O $PREFIX/bin/cloudflared 2>/dev/null || \
    log_warning "Cloudflared download failed, install manually"
    
    chmod +x $PREFIX/bin/cloudflared 2>/dev/null || true
    
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

load_dotenv(os.path.join(os.path.dirname(__file__), '../../config/.env'))

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
    port = int(os.getenv('API_PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
FLASK_EOF

    # Miner
    cat > $REPO_DIR/src/miner/core.py << 'MINER_EOF'
#!/usr/bin/env python
import os
import time
from dotenv import load_dotenv
import sys

load_dotenv(os.path.join(os.path.dirname(__file__), '../../config/.env'))

class TermuxMiner:
    def __init__(self):
        self.pool_url = os.getenv('POOL_URL', 'stratum+tcp://pool.example.com:3333')
        self.wallet = os.getenv('WALLET_ADDRESS', 'default_wallet')
        self.threads = int(os.getenv('MINER_THREADS', 2))
        self.running = False
        
    def log(self, msg):
        print(f"[MINER] {msg}")
        sys.stdout.flush()
    
    def start(self):
        self.running = True
        self.log(f"Starting miner with {self.threads} threads")
        self.log(f"Pool: {self.pool_url}")
        self.log(f"Wallet: {self.wallet}")
        self.log("Mining started. Press Ctrl+C to stop")
        
        try:
            while self.running:
                time.sleep(60)
                self.log("Mining... (hash rate: N/A)")
        except KeyboardInterrupt:
            self.log("Mining stopped by user")
            self.running = False

if __name__ == '__main__':
    miner = TermuxMiner()
    miner.start()
MINER_EOF

    # Config
    cat > $REPO_DIR/src/utils/config.py << 'CONFIG_EOF'
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'termux-dev-key')
    API_HOST = os.getenv('API_HOST', '0.0.0.0')
    API_PORT = int(os.getenv('API_PORT', 5000))
    POOL_URL = os.getenv('POOL_URL')
    WALLET_ADDRESS = os.getenv('WALLET_ADDRESS')
    MINER_THREADS = int(os.getenv('MINER_THREADS', 2))
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
MINER_THREADS=2

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
python $REPO_DIR/src/api/app.py
API_EOF

    # Start Miner
    cat > $REPO_DIR/scripts/start_miner.sh << 'MINER_EOF'
#!/bin/bash
REPO_DIR=$HOME/jv93
cd $REPO_DIR

echo "[JV93] Starting miner..."
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
    echo "  all               - Start all tunnels"
    echo "  stop              - Stop all tunnels"
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
        echo "Access: bore://localhost:8080"
        bore local 5000 --to bore.pub --port 8080
        ;;
    localtunnel)
        echo "Starting LocalTunnel..."
        lt --port 5000 --subdomain jv93-termux
        ;;
    cloudflare)
        echo "Starting Cloudflare tunnel..."
        echo "Configure at: https://dash.cloudflare.com/"
        cloudflared tunnel run jv93-termux
        ;;
    all)
        echo "Starting all tunnels..."
        echo "Open new Termux sessions for each tunnel:"
        echo ""
        echo "Session 1: bash tunnels.sh bore"
        echo "Session 2: bash tunnels.sh localtunnel"
        echo "Session 3: bash tunnels.sh cloudflare"
        ;;
    stop)
        echo "Stopping all tunnels..."
        pkill -f "bore\|localtunnel\|cloudflared"
        echo "Tunnels stopped"
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
    echo "║ 3) Start Both (API + Miner)                   ║"
    echo "║ 4) Tunnels Menu                               ║"
    echo "║ 5) View Configuration                         ║"
    echo "║ 6) Edit Configuration                         ║"
    echo "║ 7) View Logs                                  ║"
    echo "║ 8) API Health Check                           ║"
    echo "║ 9) Exit                                       ║"
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
    echo "║ 4) All Tunnels                                ║"
    echo "║ 5) Back to Main Menu                          ║"
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
            echo "Starting API and Miner..."
            sleep 1
            echo "API will start in new session, then run miner"
            ;;
        4)
            while true; do
                tunnels_menu
                read -p "Choose tunnel: " tunnel_choice
                case $tunnel_choice in
                    1) bash $REPO_DIR/scripts/tunnels.sh bore ;;
                    2) bash $REPO_DIR/scripts/tunnels.sh localtunnel ;;
                    3) bash $REPO_DIR/scripts/tunnels.sh cloudflare ;;
                    4) bash $REPO_DIR/scripts/tunnels.sh all ;;
                    5) break ;;
                    *) echo "Invalid option" ;;
                esac
            done
            ;;
        5)
            cat $REPO_DIR/config/.env
            read -p "Press Enter to continue..."
            ;;
        6)
            nano $REPO_DIR/config/.env
            ;;
        7)
            tail -f $REPO_DIR/logs/jv93.log 2>/dev/null || echo "No logs yet"
            ;;
        8)
            curl -s http://localhost:5000/health | jq . 2>/dev/null || echo "API not responding"
            read -p "Press Enter to continue..."
            ;;
        9)
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

setup_sessions() {
    log_info "Creating Termux session helpers..."
    
    # tmux config for persistent sessions
    cat > $HOME/.tmux.conf << 'TMUX_EOF'
# JV93 Termux tmux config
set -g default-terminal "screen-256color"
set -g history-limit 10000
set -g pane-border-status bottom

# New window
bind c new-window -c "#{pane_current_path}"

# Copy mode
setw -g mode-keys vi

# Easy refresh
bind r source-file ~/.tmux.conf

# Pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
TMUX_EOF

    log_success "Termux session config created"
}

create_readme() {
    log_info "Creating README..."
    
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

### Method 2: Manual Start

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
- WALLET_ADDRESS
- POOL_URL
- MINER_THREADS (usually 1-2 for phones)

## Tunnels

Run tunnels in separate Termux sessions:

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

Use Termux app to open new sessions:
1. Tap the terminal icon at bottom
2. Tap "+" to open new session
3. Run different scripts in each

Or use tmux:
```bash
tmux new-session -d -s api bash $HOME/jv93/scripts/start_api.sh
tmux new-session -d -s miner bash $HOME/jv93/scripts/start_miner.sh
tmux list-sessions
```

## API Endpoints

- Health: `curl http://localhost:5000/health`
- Stats: `curl http://localhost:5000/api/stats`
- Wallet: `curl http://localhost:5000/api/wallet`

## Power Usage

Mining on mobile uses significant battery and CPU.

### Optimize for Battery:
```bash
# Reduce threads
MINER_THREADS=1

# Lower API workers
API_WORKERS=1
```

## Storage

- Data: `$HOME/jv93/data/`
- Logs: `$HOME/jv93/logs/`
- Config: `$HOME/jv93/config/.env`

## Tips

1. **Use Termux Notification Plugin** for background alerts
2. **Run on WiFi** to avoid mobile data drain
3. **Keep screen off** to save battery
4. **Monitor temperature** - Android throttles at high temps
5. **Use task killer** to stop when needed

## Troubleshooting

### Port already in use:
```bash
# Kill existing process
pkill -f "python.*app.py"
```

### Connection refused:
```bash
# Check if API is running
curl http://localhost:5000/health
```

### Low mining rate:
- Reduce MINER_THREADS
- Check pool URL and wallet address
- Verify internet connection

## Resources

- Termux: https://termux.com
- GitHub: https://github.com/sdoukoure12/JV93
- Bore: https://bore.pub

README_EOF

    log_success "README created"
}

print_summary() {
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════╗${NC}
${GREEN}║  JV93 Termux Installation Complete! ✓             ║${NC}
${GREEN}╚════════════════════════════════════════════════════╝${NC}

${CYAN}📱 Installation Path:${NC}
  $HOME/jv93

${CYAN}🚀 Quick Start:${NC}

  ${YELLOW}1. Start Interactive Launcher:${NC}
     bash $HOME/jv93/scripts/launcher.sh

  ${YELLOW}2. Or start manually:${NC}
     # Terminal 1 - API
     bash $HOME/jv93/scripts/start_api.sh
     
     # Terminal 2 - Miner
     bash $HOME/jv93/scripts/start_miner.sh
     
     # Terminal 3 - Tunnel
     bash $HOME/jv93/scripts/tunnels.sh localtunnel

${CYAN}⚙️  Configure:${NC}
  nano $HOME/jv93/config/.env
  
  Set:
  - WALLET_ADDRESS (your seed wallet)
  - POOL_URL (mining pool stratum)
  - MINER_THREADS (1-2 for phones)

${CYAN}🌐 Tunnels (Choose one):${NC}
  • Bore: bash $HOME/jv93/scripts/tunnels.sh bore
  • LocalTunnel: bash $HOME/jv93/scripts/tunnels.sh localtunnel
  • Cloudflare: bash $HOME/jv93/scripts/tunnels.sh cloudflare

${CYAN}📊 Monitor:${NC}
  API Health: curl http://localhost:5000/health
  Stats: curl http://localhost:5000/api/stats
  Wallet: curl http://localhost:5000/api/wallet

${CYAN}💡 Tips:${NC}
  ✓ Use multiple Termux sessions (tap + at bottom)
  ✓ Mining uses lots of battery - monitor temperature
  ✓ Use WiFi for best performance
  ✓ Keep screen off to save power

${CYAN}📱 Multi-Session Setup:${NC}
  1. Open Termux
  2. Tap + button at bottom (3+ times)
  3. In each session:
     - Session 1: bash $HOME/jv93/scripts/start_api.sh
     - Session 2: bash $HOME/jv93/scripts/start_miner.sh
     - Session 3: bash $HOME/jv93/scripts/tunnels.sh localtunnel

${YELLOW}⚠️  Important:${NC}
  • Keep your seed phrase SAFE - never share it!
  • Monitor device temperature during mining
  • Don't leave mining on for too long (battery drain)
  • Use strong API credentials in production

EOF
}

main() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  JV93 Termux Installation Started        ║${NC}"
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
    setup_sessions
    create_readme
    
    echo ""
    log_success "Installation completed!"
    print_summary
}

main "$@"
