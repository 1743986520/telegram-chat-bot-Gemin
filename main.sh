#!/bin/bash
# Telegram Gemini Bot 智能安裝器
# 支持: Ubuntu/Debian/CentOS/Alpine/Docker

set -e

# 顏色定義
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

# 日誌函數
log() {
    echo -e "${COLOR_BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${COLOR_RESET} $1"
}

success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}"
}

warning() {
    echo -e "${COLOR_YELLOW}⚠ $1${COLOR_RESET}"
}

error() {
    echo -e "${COLOR_RED}✗ $1${COLOR_RESET}"
}

info() {
    echo -e "${COLOR_CYAN}➜ $1${COLOR_RESET}"
}

# 標題
print_banner() {
    clear
    echo -e "${COLOR_MAGENTA}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                                                    ║"
    echo "║             Telegram Gemini Bot 安裝器             ║"
    echo "║                智能適配所有環境                    ║"
    echo "║                                                    ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
}

# 檢測系統
detect_system() {
    log "檢測系統環境..."
    
    # 基本系統信息
    OS_NAME=$(uname -s)
    OS_ARCH=$(uname -m)
    OS_KERNEL=$(uname -r)
    
    # 發行版信息
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME=$NAME
        DISTRO_ID=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO_NAME=$(cat /etc/redhat-release)
        DISTRO_ID="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO_NAME="Debian $(cat /etc/debian_version)"
        DISTRO_ID="debian"
    elif [ -f /etc/alpine-release ]; then
        DISTRO_NAME="Alpine Linux"
        DISTRO_ID="alpine"
        DISTRO_VERSION=$(cat /etc/alpine-release)
    else
        DISTRO_NAME="Unknown"
        DISTRO_ID="unknown"
    fi
    
    # 網絡檢測
    HAS_IPV4=false
    HAS_IPV6=false
    HAS_PUBLIC_IP=false
    
    # 檢測IPv4
    if ip -4 addr show 2>/dev/null | grep -q "inet "; then
        HAS_IPV4=true
    fi
    
    # 檢測IPv6
    if ip -6 addr show 2>/dev/null | grep -q "inet6 "; then
        HAS_IPV6=true
    fi
    
    # 檢測公網IP
    if curl -s --connect-timeout 3 https://api.ipify.org >/dev/null 2>&1; then
        HAS_PUBLIC_IP=true
        PUBLIC_IP=$(curl -s https://api.ipify.org)
    fi
    
    # 檢測容器運行時
    HAS_DOCKER=false
    HAS_PODMAN=false
    IN_CONTAINER=false
    
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        HAS_DOCKER=true
    fi
    
    if command -v podman >/dev/null 2>&1; then
        HAS_PODMAN=true
    fi
    
    # 檢測是否在容器內
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        IN_CONTAINER=true
    fi
    
    # 檢測Python版本
    PYTHON_VERSION=""
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    fi
    
    # 輸出系統信息
    info "系統信息:"
    echo "  OS: $OS_NAME $OS_ARCH"
    echo "  內核: $OS_KERNEL"
    echo "  發行版: $DISTRO_NAME"
    echo "  Python: $PYTHON_VERSION"
    echo ""
    info "網絡檢測:"
    echo "  IPv4: $HAS_IPV4"
    echo "  IPv6: $HAS_IPV6"
    echo "  公網IP: ${PUBLIC_IP:-未知}"
    echo ""
    info "運行環境:"
    echo "  Docker: $HAS_DOCKER"
    echo "  Podman: $HAS_PODMAN"
    echo "  容器內: $IN_CONTAINER"
    
    # 保存檢測結果
    cat > /tmp/system_info.txt <<EOF
OS_NAME=$OS_NAME
OS_ARCH=$OS_ARCH
DISTRO_ID=$DISTRO_ID
DISTRO_VERSION=$DISTRO_VERSION
HAS_IPV4=$HAS_IPV4
HAS_IPV6=$HAS_IPV6
HAS_PUBLIC_IP=$HAS_PUBLIC_IP
HAS_DOCKER=$HAS_DOCKER
HAS_PODMAN=$HAS_PODMAN
IN_CONTAINER=$IN_CONTAINER
PYTHON_VERSION=$PYTHON_VERSION
EOF
}

# 安裝系統依賴
install_dependencies() {
    log "安裝系統依賴..."
    
    case $DISTRO_ID in
        ubuntu|debian)
            apt update
            apt install -y curl wget git python3 python3-pip python3-venv \
                         python3-dev build-essential
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl wget git python3 python3-pip python3-devel
            else
                yum install -y curl wget git python3 python3-pip python3-devel
            fi
            ;;
        alpine)
            apk add --no-cache curl wget git python3 py3-pip \
                              python3-dev build-base
            ;;
        *)
            warning "未知發行版，嘗試通用安裝..."
            if command -v apt >/dev/null 2>&1; then
                apt update && apt install -y curl wget git python3 python3-pip
            elif command -v yum >/dev/null 2>&1; then
                yum install -y curl wget git python3 python3-pip
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache curl wget git python3 py3-pip
            else
                error "無法自動安裝依賴"
                exit 1
            fi
            ;;
    esac
    
    success "系統依賴安裝完成"
}

# 選擇安裝模式
choose_installation_mode() {
    echo ""
    info "選擇安裝模式:"
    echo "  1. Docker容器模式 (推薦)"
    echo "  2. Python虛擬環境模式"
    echo "  3. 系統級安裝模式"
    echo "  4. 開發模式"
    echo ""
    
    while true; do
        read -p "請選擇模式 (1-4): " mode
        case $mode in
            1)
                if [ "$HAS_DOCKER" = true ] || [ "$HAS_PODMAN" = true ]; then
                    INSTALL_MODE="docker"
                    break
                else
                    warning "未檢測到容器運行時，請選擇其他模式"
                fi
                ;;
            2)
                INSTALL_MODE="python"
                break
                ;;
            3)
                INSTALL_MODE="system"
                break
                ;;
            4)
                INSTALL_MODE="dev"
                break
                ;;
            *)
                warning "無效選擇，請重新輸入"
                ;;
        esac
    done
    
    info "選擇模式: $INSTALL_MODE"
}

# 獲取配置信息
get_configuration() {
    echo ""
    info "配置機器人:"
    
    # 檢查現有配置
    if [ -f .env ]; then
        warning "發現現有配置"
        source .env 2>/dev/null || true
        echo "當前配置:"
        echo "  BOT_TOKEN: ${BOT_TOKEN:0:10}..."
        echo "  GEMINI_API_KEY: ${GEMINI_API_KEY:0:10}..."
        echo "  DOMAIN: ${DOMAIN:-未設置}"
        echo ""
        read -p "是否使用現有配置？(y/N): " use_existing
        if [[ $use_existing =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # 獲取新配置
    echo ""
    info "請輸入以下信息:"
    
    # BOT_TOKEN
    while true; do
        read -p "BOT_TOKEN (從 @BotFather 獲取): " BOT_TOKEN
        if [[ -n "$BOT_TOKEN" ]]; then
            break
        fi
        warning "BOT_TOKEN 不能為空"
    done
    
    # GEMINI_API_KEY
    while true; do
        read -p "GEMINI_API_KEY (從 Google AI Studio 獲取): " GEMINI_API_KEY
        if [[ -n "$GEMINI_API_KEY" ]]; then
            break
        fi
        warning "GEMINI_API_KEY 不能為空"
    done
    
    # DOMAIN
    read -p "DOMAIN (回調域名，留空使用IP): " DOMAIN
    
    # 清理域名
    if [[ -n "$DOMAIN" ]]; then
        DOMAIN=$(echo "$DOMAIN" | sed 's|https://||g' | sed 's|http://||g' | sed 's|/.*||g')
    else
        # 使用公網IP
        if [ "$HAS_PUBLIC_IP" = true ]; then
            DOMAIN=$PUBLIC_IP
            info "使用公網IP: $DOMAIN"
        else
            warning "無法獲取公網IP，請手動設置域名"
            read -p "請輸入域名或IP: " DOMAIN
        fi
    fi
    
    # PORT
    read -p "端口 (默認: 8080): " PORT
    PORT=${PORT:-8080}
    
    # 保存配置
    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
DOMAIN=$DOMAIN
PORT=$PORT
EOF
    
    success "配置已保存到 .env"
}

# 下載源代碼
download_source() {
    log "下載源代碼..."
    
    # 創建項目目錄
    PROJECT_DIR="/opt/telegram-gemini-bot"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # 下載最新版本
    REPO_URL="https://github.com/1743988127hax/telegram-chat-bot-Gemin"
    
    if command -v git >/dev/null 2>&1; then
        if [ -d ".git" ]; then
            log "更新現有代碼庫..."
            git pull origin main
        else
            log "克隆代碼庫..."
            git clone "$REPO_URL.git" .
        fi
    else
        log "使用curl下載..."
        curl -L -o bot.zip "$REPO_URL/archive/main.zip"
        unzip -o bot.zip
        cp -r telegram-chat-bot-Gemin-main/* .
        rm -rf bot.zip telegram-chat-bot-Gemin-main
    fi
    
    success "代碼下載完成: $PROJECT_DIR"
}

# Docker安裝模式
install_docker() {
    log "使用Docker模式安裝..."
    
    # 檢查docker-compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        log "安裝docker-compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
             -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    # 創建docker-compose.yml
    cat > docker-compose.yml <<EOF
version: '3.8'

services:
  telegram-bot:
    image: python:3.11-slim
    container_name: telegram-gemini-bot
    restart: unless-stopped
    working_dir: /app
    volumes:
      - .:/app
      - ./data:/data
      - ./logs:/logs
    env_file:
      - .env
    ports:
      - "${PORT}:8080"
    environment:
      - TZ=Asia/Shanghai
    command: >
      sh -c "pip install --no-cache-dir -r requirements.txt &&
             python main.py"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # 可選: 添加Nginx反向代理
  nginx:
    image: nginx:alpine
    container_name: telegram-bot-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - telegram-bot
EOF
    
    # 創建Nginx配置（可選）
    cat > nginx.conf <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream telegram_bot {
        server telegram-bot:8080;
    }

    server {
        listen 80;
        server_name _;
        
        location / {
            proxy_pass http://telegram_bot;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF
    
    # 啟動服務
    log "啟動Docker容器..."
    docker-compose up -d
    
    # 等待啟動
    sleep 10
    
    # 檢查狀態
    if docker ps | grep -q telegram-gemini-bot; then
        success "Docker容器啟動成功"
        
        # 顯示日誌
        log "容器日誌:"
        docker logs --tail 20 telegram-gemini-bot
    else
        error "Docker容器啟動失敗"
        docker-compose logs
        exit 1
    fi
}

# Python虛擬環境模式
install_python_venv() {
    log "使用Python虛擬環境模式..."
    
    # 創建虛擬環境
    python3 -m venv venv
    source venv/bin/activate
    
    # 安裝依賴
    pip install --upgrade pip
    pip install -r requirements.txt
    
    # 創建啟動腳本
    cat > start.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 激活虛擬環境
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi

# 加載環境變數
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# 設置Python路徑
export PYTHONPATH="$PWD:$PYTHONPATH"

# 啟動服務
exec python main.py
EOF
    
    chmod +x start.sh
    
    # 創建停止腳本
    cat > stop.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
pkill -f "python main.py" 2>/dev/null || true
echo "服務已停止"
EOF
    chmod +x stop.sh
    
    # 創建重啟腳本
    cat > restart.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 2
./start.sh
EOF
    chmod +x restart.sh
    
    success "Python虛擬環境安裝完成"
    
    # 測試運行
    log "測試啟動..."
    ./start.sh &
    sleep 5
    
    if curl -s http://localhost:$PORT >/dev/null; then
        success "服務啟動成功"
        pkill -f "python main.py"
    else
        error "服務啟動失敗"
        exit 1
    fi
}

# 系統級安裝模式
install_system() {
    log "使用系統級安裝模式..."
    
    # 全局安裝依賴
    pip3 install --upgrade pip
    pip3 install -r requirements.txt
    
    # 創建系統服務
    if [ -d /etc/systemd/system ]; then
        cat > /etc/systemd/system/telegram-gemini.service <<EOF
[Unit]
Description=Telegram Gemini Bot
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PWD
EnvironmentFile=$PWD/.env
ExecStart=/usr/bin/python3 $PWD/main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=telegram-gemini

# 安全設置
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
        
        # 啟用服務
        systemctl daemon-reload
        systemctl enable telegram-gemini
        systemctl start telegram-gemini
        
        sleep 3
        
        if systemctl is-active --quiet telegram-gemini; then
            success "系統服務啟動成功"
        else
            error "系統服務啟動失敗"
            systemctl status telegram-gemini
            exit 1
        fi
    else
        warning "未檢測到systemd，創建簡單的啟動腳本"
        
        cat > /etc/init.d/telegram-gemini <<'EOF'
#!/bin/bash
# chkconfig: 2345 90 10
# description: Telegram Gemini Bot

case "$1" in
    start)
        cd /opt/telegram-gemini-bot
        nohup python3 main.py > /var/log/telegram-bot.log 2>&1 &
        echo $! > /var/run/telegram-bot.pid
        ;;
    stop)
        kill -9 $(cat /var/run/telegram-bot.pid) 2>/dev/null || true
        rm -f /var/run/telegram-bot.pid
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
        
        chmod +x /etc/init.d/telegram-gemini
        /etc/init.d/telegram-gemini start
        
        success "啟動腳本創建完成"
    fi
}

# 開發模式
install_dev() {
    log "使用開發模式..."
    
    # 創建開發環境
    python3 -m venv venv
    source venv/bin/activate
    
    # 安裝開發依賴
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install pytest black flake8
    
    # 創建開發配置
    cat > .env.dev <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
DOMAIN=localhost
PORT=8080
DEBUG=true
EOF
    
    # 創建開發腳本
    cat > dev.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 激活虛擬環境
source venv/bin/activate

# 使用開發配置
export $(cat .env.dev | grep -v '^#' | xargs)

# 啟動開發服務
python main.py
EOF
    chmod +x dev.sh
    
    # 創建測試腳本
    cat > test.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate

echo "運行代碼檢查..."
flake8 main.py --max-line-length=120

echo "運行測試..."
python -m pytest tests/ -v

echo "格式化代碼..."
black main.py
EOF
    chmod +x test.sh
    
    success "開發環境設置完成"
    info "啟動開發服務: ./dev.sh"
    info "運行測試: ./test.sh"
}

# 設置IPv6支持（如果需要）
setup_ipv6_support() {
    if [ "$HAS_IPV6" = true ] && [ "$HAS_IPV4" = false ]; then
        warning "檢測到IPv6-only環境，設置特殊支持..."
        
        echo ""
        info "IPv6-only 環境選項:"
        echo "  1. 使用Cloudflare Tunnel (推薦)"
        echo "  2. 使用ngrok (測試用)"
        echo "  3. 手動配置"
        echo "  4. 跳過"
        echo ""
        
        read -p "請選擇 (1-4): " ipv6_choice
        
        case $ipv6_choice in
            1)
                setup_cloudflare_tunnel
                ;;
            2)
                setup_ngrok
                ;;
            3)
                info "請手動配置以下項目:"
                echo "1. 確保域名AAAA記錄指向你的IPv6地址"
                echo "2. 確保防火牆開放端口 $PORT"
                echo "3. 可能需要設置NAT64/DNS64"
                ;;
            *)
                info "跳過IPv6特殊設置"
                ;;
        esac
    fi
}

# 設置Cloudflare Tunnel
setup_cloudflare_tunnel() {
    log "設置Cloudflare Tunnel..."
    
    # 下載cloudflared
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) ARCH="amd64" ;;
    esac
    
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH"
    curl -L -o cloudflared $CLOUDFLARED_URL
    chmod +x cloudflared
    sudo mv cloudflared /usr/local/bin/
    
    info "請訪問: https://dash.cloudflare.com/"
    info "1. 進入 Zero Trust → Access → Tunnels"
    info "2. 創建新隧道，選擇 'cloudflared'"
    info "3. 複製令牌"
    echo ""
    
    read -p "請輸入Cloudflare Tunnel令牌: " tunnel_token
    
    if [[ -n "$tunnel_token" ]]; then
        # 安裝隧道服務
        sudo cloudflared service install $tunnel_token
        
        # 創建配置文件
        sudo mkdir -p /etc/cloudflared
        cat | sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: telegram-bot
credentials-file: /root/.cloudflared/telegram-bot.json

ingress:
  - hostname: \${DOMAIN}
    service: http://localhost:$PORT
  - service: http_status:404
EOF
        
        # 啟動服務
        sudo systemctl enable cloudflared
        sudo systemctl start cloudflared
        
        success "Cloudflare Tunnel 設置完成"
        info "狀態檢查: sudo cloudflared tunnel list"
    else
        warning "未提供令牌，跳過Cloudflare Tunnel設置"
    fi
}

# 設置ngrok
setup_ngrok() {
    log "設置ngrok..."
    
    # 下載ngrok
    curl -L -o ngrok.tgz https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
    tar -xzf ngrok.tgz
    chmod +x ngrok
    sudo mv ngrok /usr/local/bin/
    rm ngrok.tgz
    
    info "請訪問: https://dashboard.ngrok.com/get-started/your-authtoken"
    read -p "請輸入ngrok authtoken: " ngrok_token
    
    if [[ -n "$ngrok_token" ]]; then
        ngrok config add-authtoken $ngrok_token
        
        # 創建ngrok服務
        cat > /etc/systemd/system/ngrok.service <<EOF
[Unit]
Description=Ngrok Tunnel
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/ngrok http $PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable ngrok
        systemctl start ngrok
        
        sleep 5
        
        # 獲取公共URL
        NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o '"public_url":"[^"]*"' | cut -d'"' -f4)
        
        if [[ -n "$NGROK_URL" ]]; then
            success "ngrok設置完成"
            info "公共URL: $NGROK_URL"
            
            # 更新配置
            NEW_DOMAIN=$(echo $NGROK_URL | sed 's|https://||')
            sed -i "s|DOMAIN=.*|DOMAIN=$NEW_DOMAIN|" .env
            info "已更新DOMAIN為: $NEW_DOMAIN"
        fi
    else
        warning "未提供令牌，跳過ngrok設置"
    fi
}

# 防火牆設置
setup_firewall() {
    log "設置防火牆..."
    
    # 檢測防火牆
    if command -v ufw >/dev/null 2>&1; then
        # Ubuntu/Debian
        ufw allow $PORT/tcp
        ufw reload
        success "UFW防火牆已設置"
        
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # CentOS/Fedora
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --reload
        success "Firewalld已設置"
        
    elif command -v iptables >/dev/null 2>&1; then
        # 通用iptables
        iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
        iptables-save > /etc/iptables/rules.v4
        success "iptables已設置"
        
    else
        warning "未檢測到防火牆管理工具，請手動開放端口 $PORT"
    fi
}

# 健康檢查
health_check() {
    log "執行健康檢查..."
    
    # 等待服務啟動
    sleep 15
    
    local_health=false
    webhook_health=false
    
    # 檢查本地服務
    if curl -s --max-time 5 http://localhost:$PORT/health >/dev/null; then
        local_health=true
        success "本地服務正常"
    else
        error "本地服務無法訪問"
    fi
    
    # 檢查Webhook（如果有域名）
    if [[ -n "$DOMAIN" && ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if curl -s --max-time 10 "https://$DOMAIN/health" >/dev/null; then
            webhook_health=true
            success "Webhook可訪問"
        else
            warning "Webhook暫時無法訪問，可能是DNS未生效"
        fi
    fi
    
    # 顯示總結
    echo ""
    info "健康檢查結果:"
    echo "  ✅ 本地服務: $local_health"
    echo "  🌐 Webhook: $webhook_health"
    
    if [ "$local_health" = true ]; then
        success "✅ 安裝成功！"
    else
        error "❌ 安裝有問題，請檢查日誌"
        exit 1
    fi
}

# 顯示完成信息
show_completion() {
    echo ""
    success "🎉 Telegram Gemini Bot 安裝完成！"
    echo ""
    info "📋 安裝摘要:"
    echo "  模式: $INSTALL_MODE"
    echo "  目錄: $(pwd)"
    echo "  端口: $PORT"
    echo "  域名: ${DOMAIN:-未設置}"
    echo ""
    
    info "🚀 啟動命令:"
    case $INSTALL_MODE in
        docker)
            echo "  查看日誌: docker logs telegram-gemini-bot"
            echo "  重啟: docker-compose restart"
            echo "  停止: docker-compose down"
            ;;
        python)
            echo "  啟動: ./start.sh"
            echo "  停止: ./stop.sh"
            echo "  重啟: ./restart.sh"
            ;;
        system)
            echo "  狀態: systemctl status telegram-gemini"
            echo "  日誌: journalctl -u telegram-gemini -f"
            echo "  重啟: systemctl restart telegram-gemini"
            ;;
        dev)
            echo "  開發模式: ./dev.sh"
            echo "  測試: ./test.sh"
            ;;
    esac
    
    echo ""
    info "🔧 管理命令:"
    echo "  查看日誌: tail -f bot.log"
    echo "  編輯配置: nano .env"
    echo "  測試服務: curl http://localhost:$PORT"
    
    echo ""
    info "🌐 網絡信息:"
    if [ "$HAS_PUBLIC_IP" = true ]; then
        echo "  公網IP: $PUBLIC_IP"
    fi
    if [ "$HAS_IPV6" = true ]; then
        echo "  IPv6: 已啟用"
    fi
    
    echo ""
    info "📝 下一步:"
    echo "  1. 在Telegram中測試機器人"
    echo "  2. 檢查bot.log確認運行正常"
    echo "  3. 配置SSL證書（如果需要）"
    
    if [ "$HAS_IPV6" = true ] && [ "$HAS_IPV4" = false ]; then
        echo ""
        warning "⚠️  IPv6-only環境注意:"
        echo "  • Telegram可能無法直接訪問IPv6地址"
        echo "  • 建議使用Cloudflare Tunnel或反向代理"
    fi
    
    echo ""
    echo "📞 問題反饋: https://github.com/1743988127hax/telegram-chat-bot-Gemin/issues"
    echo ""
    echo "=" * 50
}

# 主函數
main() {
    print_banner
    
    # 檢測系統
    detect_system
    
    # 安裝依賴
    install_dependencies
    
    # 下載源代碼
    download_source
    
    # 獲取配置
    get_configuration
    
    # 選擇安裝模式
    choose_installation_mode
    
    # 執行安裝
    case $INSTALL_MODE in
        docker) install_docker ;;
        python) install_python_venv ;;
        system) install_system ;;
        dev) install_dev ;;
    esac
    
    # 設置IPv6支持
    setup_ipv6_support
    
    # 設置防火牆
    setup_firewall
    
    # 健康檢查
    health_check
    
    # 顯示完成信息
    show_completion
}

# 錯誤處理
trap 'error "安裝被中斷"; exit 1' INT TERM

# 檢查root權限
if [ "$EUID" -ne 0 ]; then
    warning "建議使用root權限運行，某些功能可能需要sudo"
    read -p "是否繼續？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 運行主程序
main "$@"