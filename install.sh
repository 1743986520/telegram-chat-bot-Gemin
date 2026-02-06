#!/bin/bash
# Telegram Gemini Bot 智能安裝器 - 修復版
# 修復GitHub下載問題，支援公開倉庫下載

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
    echo "║                (GitHub下載修復版)                  ║"
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
    
    # 檢測Python
    PYTHON_CMD=""
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
    else
        PYTHON_VERSION="未安裝"
    fi
    
    # 輸出系統信息
    info "系統信息:"
    echo "  OS: $OS_NAME $OS_ARCH"
    echo "  發行版: $DISTRO_NAME"
    echo "  Python: $PYTHON_VERSION"
    
    export OS_NAME OS_ARCH DISTRO_ID DISTRO_NAME PYTHON_CMD PYTHON_VERSION
}

# 安裝系統依賴
install_dependencies() {
    log "安裝系統依賴..."
    
    case $DISTRO_ID in
        ubuntu|debian)
            apt update
            apt install -y curl wget python3 python3-pip python3-venv
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl wget python3 python3-pip
            else
                yum install -y curl wget python3 python3-pip
            fi
            ;;
        alpine)
            apk add --no-cache curl wget python3 py3-pip
            ;;
        *)
            warning "未知發行版，嘗試通用安裝..."
            if command -v apt >/dev/null 2>&1; then
                apt update && apt install -y curl wget python3 python3-pip
            elif command -v yum >/dev/null 2>&1; then
                yum install -y curl wget python3 python3-pip
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache curl wget python3 py3-pip
            else
                error "無法自動安裝依賴，請手動安裝Python3和pip"
            fi
            ;;
    esac
    
    success "系統依賴安裝完成"
}

# 選擇安裝模式
choose_installation_mode() {
    echo ""
    info "選擇安裝模式:"
    echo "  1. 完整版 (含Webhook/Flask)"
    echo "  2. 簡化版 (純輪詢，無Webhook)"
    echo "  3. 僅主程序"
    echo ""
    
    while true; do
        read -p "請選擇模式 (1-3): " mode
        case $mode in
            1)
                INSTALL_MODE="full"
                break
                ;;
            2)
                INSTALL_MODE="simple"
                break
                ;;
            3)
                INSTALL_MODE="core"
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
        echo "當前配置:"
        grep -E "BOT_TOKEN|GEMINI_API_KEY|DOMAIN|PORT" .env || true
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
            if [[ "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
                break
            else
                warning "BOT_TOKEN格式不正確，應該是 數字:字母 格式"
            fi
        else
            warning "BOT_TOKEN 不能為空"
        fi
    done
    
    # GEMINI_API_KEY
    while true; do
        read -p "GEMINI_API_KEY (從 Google AI Studio 獲取): " GEMINI_API_KEY
        if [[ -n "$GEMINI_API_KEY" ]]; then
            break
        else
            warning "GEMINI_API_KEY 不能為空"
        fi
    done
    
    # 完整版需要DOMAIN
    if [ "$INSTALL_MODE" = "full" ]; then
        read -p "DOMAIN (回調域名，留空使用IP): " DOMAIN
        
        # 清理域名
        if [[ -n "$DOMAIN" ]]; then
            DOMAIN=$(echo "$DOMAIN" | sed 's|https://||g' | sed 's|http://||g' | sed 's|/.*||g')
        fi
        
        # PORT
        read -p "端口 (默認: 8080): " PORT
        PORT=${PORT:-8080}
        
        # 保存完整配置
        cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
DOMAIN=$DOMAIN
PORT=$PORT
EOF
    else
        # 簡化版配置
        cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
EOF
    fi
    
    success "配置已保存到 .env"
}

# 下載源代碼（修復版）
download_source_fixed() {
    log "下載源代碼 (修復版)..."
    
    # 創建項目目錄
    PROJECT_DIR="/opt/telegram-gemini-bot"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # 方法1: 使用GitHub API下載（推薦）
    REPO_USER="1743988127hax"
    REPO_NAME="telegram-chat-bot-Gemin"
    
    info "嘗試方法1: 使用GitHub API下載..."
    
    # 創建簡化版代碼
    if [ "$INSTALL_MODE" = "simple" ] || [ "$INSTALL_MODE" = "core" ]; then
        create_simple_version
        return
    fi
    
    # 下載完整版
    if command -v curl >/dev/null 2>&1; then
        log "通過curl下載代碼..."
        
        # 下載主文件
        for file in main.py requirements.txt README.md; do
            if curl -s -L -o "$file" "https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/main/$file"; then
                success "下載 $file 成功"
            else
                warning "下載 $file 失敗，創建基本版本"
                create_basic_files
            fi
        done
        
        # 下載安裝腳本
        if curl -s -L -o main.sh "https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/main/main.sh"; then
            chmod +x main.sh
            success "下載安裝腳本成功"
        fi
        
    elif command -v wget >/dev/null 2>&1; then
        log "通過wget下載代碼..."
        
        # 下載主文件
        for file in main.py requirements.txt README.md; do
            if wget -q -O "$file" "https://raw.githubusercontent.com/$REPO_USER/$REPO_NAME/main/$file"; then
                success "下載 $file 成功"
            else
                warning "下載 $file 失敗，創建基本版本"
                create_basic_files
            fi
        done
        
    else
        warning "curl和wget都不可用，創建基本版本"
        create_basic_files
    fi
    
    success "代碼下載完成: $PROJECT_DIR"
}

# 創建基本文件
create_basic_files() {
    log "創建基本文件..."
    
    # 創建requirements.txt
    cat > requirements.txt <<'EOF'
# Telegram Gemini Bot 依賴
pyTelegramBotAPI==4.15.2
google-generativeai==0.6.2
flask==3.0.2
requests==2.31.0
EOF
    
    # 創建README.md
    cat > README.md <<'EOF'
# Telegram Gemini Bot

基於Google Gemini AI的Telegram機器人

## 功能
- AI對話
- 數學計算
- 群組聊天
EOF
}

# 創建簡化版本
create_simple_version() {
    log "創建簡化版本..."
    
    # 創建簡化版主程序
    cat > main.py <<'EOF'
#!/usr/bin/env python3
# Telegram Gemini Bot - 簡化版
import os
import telebot
import google.generativeai as genai
import time
import logging
import sys
import random
from datetime import datetime

# 配置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('bot.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

# 加載配置
def load_config():
    config = {}
    
    # 從.env文件加載
    if os.path.exists('.env'):
        with open('.env', 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        config[key.strip()] = value.strip()
    
    # 從環境變數加載
    for key in ['BOT_TOKEN', 'GEMINI_API_KEY']:
        env_value = os.getenv(key)
        if env_value:
            config[key] = env_value
    
    return config

config = load_config()
BOT_TOKEN = config.get('BOT_TOKEN')
GEMINI_API_KEY = config.get('GEMINI_API_KEY')

if not BOT_TOKEN:
    logger.error("❌ BOT_TOKEN 未設置")
    sys.exit(1)

if not GEMINI_API_KEY:
    logger.error("❌ GEMINI_API_KEY 未設置")
    sys.exit(1)

# 初始化
genai.configure(api_key=GEMINI_API_KEY)
bot = telebot.TeleBot(BOT_TOKEN)

# AI服務類
class AIService:
    def __init__(self, api_key):
        self.api_key = api_key
        self.models = ["gemini-1.5-flash", "gemini-1.5-pro"]
        self.current_model = 0
    
    def get_response(self, prompt):
        try:
            model = genai.GenerativeModel(self.models[self.current_model])
            response = model.generate_content(prompt)
            self.current_model = (self.current_model + 1) % len(self.models)
            return response.text.strip()
        except Exception as e:
            logger.error(f"AI錯誤: {e}")
            return "抱歉，AI服務暫時不可用。"

# 初始化AI
ai = AIService(GEMINI_API_KEY)

# 命令處理
@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    help_text = """🤖 Telegram Gemini Bot
    
使用方法:
• 在群組中 @我 + 問題
• 回復我的消息進行對話
• 使用命令 /ask + 問題

命令:
/start, /help - 顯示幫助
/test - 測試AI
/status - 狀態信息"""
    
    bot.reply_to(message, help_text)

@bot.message_handler(commands=['test'])
def test_ai(message):
    prompts = ["你好！", "講個笑話", "什麼是AI？"]
    prompt = random.choice(prompts)
    
    bot.reply_to(message, f"測試: {prompt}")
    response = ai.get_response(prompt)
    bot.reply_to(message, f"回應: {response}")

@bot.message_handler(commands=['status'])
def show_status(message):
    status = f"""狀態信息
時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
模型: {ai.models[ai.current_model]}
模式: 簡化輪詢版"""
    
    bot.reply_to(message, status)

@bot.message_handler(func=lambda message: True)
def handle_all_messages(message):
    # 檢查是否@機器人或回復機器人
    text = message.text or ""
    bot_username = bot.get_me().username
    
    should_respond = False
    
    # 1. 回復機器人
    if message.reply_to_message and message.reply_to_message.from_user.id == bot.get_me().id:
        should_respond = True
    
    # 2. @機器人
    if bot_username and f"@{bot_username}" in text:
        should_respond = True
    
    # 3. 命令
    if text.startswith(('/ask', '!ai', '??')):
        should_respond = True
    
    if should_respond:
        # 清理文本
        if bot_username:
            text = text.replace(f"@{bot_username}", "").strip()
        
        # 移除命令前綴
        for prefix in ['/ask', '!ai', '??']:
            if text.startswith(prefix):
                text = text[len(prefix):].strip()
                break
        
        if text:
            try:
                response = ai.get_response(text)
                bot.reply_to(message, response)
            except Exception as e:
                logger.error(f"處理錯誤: {e}")
                bot.reply_to(message, "處理消息時出錯")

# 主函數
def main():
    logger.info("=" * 50)
    logger.info("啟動 Telegram Gemini Bot (簡化版)")
    logger.info("=" * 50)
    
    try:
        logger.info("開始輪詢...")
        bot.infinity_polling()
    except KeyboardInterrupt:
        logger.info("機器人已停止")
    except Exception as e:
        logger.error(f"錯誤: {e}")

if __name__ == "__main__":
    main()
EOF

    # 創建requirements.txt (簡化版)
    cat > requirements.txt <<'EOF'
pyTelegramBotAPI==4.15.2
google-generativeai==0.6.2
requests==2.31.0
EOF
    
    success "創建簡化版成功"
}

# 安裝Python依賴
install_python_dependencies() {
    log "安裝Python依賴..."
    
    cd "/opt/telegram-gemini-bot"
    
    # 升級pip
    $PYTHON_CMD -m pip install --upgrade pip
    
    # 安裝依賴
    if [ -f "requirements.txt" ]; then
        $PYTHON_CMD -m pip install -r requirements.txt
    else
        $PYTHON_CMD -m pip install pyTelegramBotAPI google-generativeai
    fi
    
    success "Python依賴安裝完成"
}

# 創建啟動腳本
create_startup_scripts() {
    log "創建啟動腳本..."
    
    cd "/opt/telegram-gemini-bot"
    
    # 主啟動腳本
    cat > start.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "啟動 Telegram Gemini Bot..."
echo "模式: $1"
echo "按 Ctrl+C 停止"

# 檢查配置
if [ ! -f ".env" ]; then
    echo "錯誤: .env 配置文件不存在"
    echo "請先運行: ./setup.sh"
    exit 1
fi

# 設置Python路徑
export PYTHONPATH="$PWD:$PYTHONPATH"

# 運行
python3 main.py
EOF
    
    # 後台運行腳本
    cat > start_daemon.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 檢查是否已運行
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "機器人已在運行 (PID: $PID)"
        exit 0
    fi
fi

echo "啟動機器人 (後台模式)..."
nohup python3 main.py > bot_console.log 2>&1 &
echo $! > bot.pid
echo "啟動成功 (PID: $(cat bot.pid))"
echo "日誌: tail -f bot.log"
echo "控制台: tail -f bot_console.log"
EOF
    
    # 停止腳本
    cat > stop.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        echo "已停止機器人 (PID: $PID)"
        rm -f bot.pid
    else
        echo "機器人未運行"
        rm -f bot.pid
    fi
else
    echo "機器人未運行"
fi

# 清理
pkill -f "python3 main.py" 2>/dev/null || true
EOF
    
    # 狀態腳本
    cat > status.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "✅ 機器人正在運行"
        echo "PID: $PID"
        echo "運行時間: $(ps -p $PID -o etime=)"
        echo "內存: $(ps -p $PID -o rss=) KB"
        echo ""
        echo "最近日誌:"
        tail -10 bot.log 2>/dev/null || echo "日誌文件不存在"
    else
        echo "❌ 機器人已停止"
        rm -f bot.pid
    fi
else
    echo "❌ 機器人未運行"
fi
EOF
    
    # 配置腳本
    cat > setup.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "設置 Telegram Gemini Bot"
echo ""
echo "請輸入配置信息:"

# 讀取現有配置
if [ -f .env ]; then
    source .env 2>/dev/null || true
fi

read -p "BOT_TOKEN [${BOT_TOKEN:-未設置}]: " input_token
read -p "GEMINI_API_KEY [${GEMINI_API_KEY:-未設置}]: " input_key

BOT_TOKEN=${input_token:-$BOT_TOKEN}
GEMINI_API_KEY=${input_key:-$GEMINI_API_KEY}

# 檢查必要配置
if [ -z "$BOT_TOKEN" ]; then
    echo "錯誤: BOT_TOKEN 不能為空"
    exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo "錯誤: GEMINI_API_KEY 不能為空"
    exit 1
fi

# 保存配置
cat > .env <<CONFIG
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
CONFIG

echo "✅ 配置已保存到 .env"
EOF
    
    # 設置執行權限
    chmod +x *.sh
    
    success "啟動腳本創建完成"
}

# 創建Systemd服務
create_systemd_service() {
    log "創建Systemd服務..."
    
    if [ ! -d "/etc/systemd/system" ]; then
        warning "未檢測到systemd，跳過服務創建"
        return
    fi
    
    SERVICE_FILE="/etc/systemd/system/telegram-gemini.service"
    
    cat > telegram-gemini.service <<EOF
[Unit]
Description=Telegram Gemini Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/telegram-gemini-bot
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/python3 /opt/telegram-gemini-bot/main.py
Restart=always
RestartSec=10
StandardOutput=append:/opt/telegram-gemini-bot/bot_console.log
StandardError=append:/opt/telegram-gemini-bot/bot_console.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 複製服務文件
    cp telegram-gemini.service "$SERVICE_FILE"
    rm -f telegram-gemini.service
    
    # 重新加載並啟用
    systemctl daemon-reload
    systemctl enable telegram-gemini
    
    success "Systemd服務創建完成"
}

# 顯示完成信息
show_completion() {
    echo ""
    success "🎉 Telegram Gemini Bot 安裝完成！"
    echo ""
    
    info "📋 安裝信息:"
    echo "  模式: $INSTALL_MODE"
    echo "  目錄: /opt/telegram-gemini-bot"
    echo "  配置: .env"
    
    echo ""
    info "🚀 啟動命令:"
    echo "  前台運行: cd /opt/telegram-gemini-bot && ./start.sh"
    echo "  後台運行: cd /opt/telegram-gemini-bot && ./start_daemon.sh"
    echo "  停止: ./stop.sh"
    echo "  狀態: ./status.sh"
    echo "  重新配置: ./setup.sh"
    
    if [ -f "/etc/systemd/system/telegram-gemini.service" ]; then
        echo ""
        info "📦 Systemd服務:"
        echo "  啟動: systemctl start telegram-gemini"
        echo "  停止: systemctl stop telegram-gemini"
        echo "  狀態: systemctl status telegram-gemini"
        echo "  日誌: journalctl -u telegram-gemini -f"
    fi
    
    echo ""
    info "📝 配置文件 (.env):"
    cat /opt/telegram-gemini-bot/.env
    
    echo ""
    info "🔧 下一步:"
    echo "  1. 將機器人添加到Telegram群組"
    echo "  2. 在群組中測試: /test"
    echo "  3. 查看日誌: tail -f /opt/telegram-gemini-bot/bot.log"
    
    echo ""
    echo "=" * 50
}

# 主安裝流程
main_installation() {
    print_banner
    detect_system
    
    # 檢查Python
    if [ -z "$PYTHON_CMD" ]; then
        install_dependencies
        detect_system  # 重新檢測
    fi
    
    # 選擇安裝模式
    choose_installation_mode
    
    # 獲取配置
    get_configuration
    
    # 下載源代碼
    download_source_fixed
    
    # 安裝Python依賴
    install_python_dependencies
    
    # 創建啟動腳本
    create_startup_scripts
    
    # 創建Systemd服務
    read -p "是否創建Systemd服務？(Y/n): " create_service
    create_service=${create_service:-Y}
    
    if [[ $create_service =~ ^[Yy]$ ]]; then
        create_systemd_service
    fi
    
    # 顯示完成信息
    show_completion
    
    # 詢問是否啟動
    echo ""
    read -p "是否立即啟動機器人？(Y/n): " start_now
    start_now=${start_now:-Y}
    
    if [[ $start_now =~ ^[Yy]$ ]]; then
        cd "/opt/telegram-gemini-bot"
        
        if systemctl is-enabled telegram-gemini 2>/dev/null; then
            systemctl start telegram-gemini
            sleep 2
            systemctl status telegram-gemini --no-pager
        else
            ./start_daemon.sh
        fi
    fi
}

# 直接下載和安裝的快速腳本
quick_install() {
    echo "使用快速安裝模式..."
    
    # 下載簡化版本
    mkdir -p /tmp/telegram-bot
    cd /tmp/telegram-bot
    
    cat > install_quick.sh <<'QUICK_EOF'
#!/bin/bash
# 快速安裝腳本

set -e

echo "快速安裝 Telegram Gemini Bot..."
echo ""

# 安裝依賴
if command -v apt >/dev/null 2>&1; then
    apt update
    apt install -y python3 python3-pip curl
elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 python3-pip curl
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3 py3-pip curl
fi

# 創建目錄
mkdir -p ~/telegram-bot
cd ~/telegram-bot

# 下載最簡版本
cat > bot.py <<'PY_EOF'
import os, telebot, google.generativeai as genai, logging, sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

# 手動配置
BOT_TOKEN = input("請輸入BOT_TOKEN: ").strip()
GEMINI_API_KEY = input("請輸入GEMINI_API_KEY: ").strip()

if not BOT_TOKEN or not GEMINI_API_KEY:
    print("錯誤: 必須提供BOT_TOKEN和GEMINI_API_KEY")
    sys.exit(1)

# 初始化
genai.configure(api_key=GEMINI_API_KEY)
bot = telebot.TeleBot(BOT_TOKEN)

@bot.message_handler(commands=['start'])
def start(message):
    bot.reply_to(message, "🤖 機器人已啟動！@我提問")

@bot.message_handler(func=lambda m: True)
def echo_all(message):
    if bot.get_me().username and f"@{bot.get_me().username}" in (message.text or ""):
        try:
            model = genai.GenerativeModel("gemini-1.5-flash")
            response = model.generate_content(message.text)
            bot.reply_to(message, response.text)
        except Exception as e:
            bot.reply_to(message, f"錯誤: {str(e)}")

if __name__ == "__main__":
    logger.info("啟動機器人...")
    bot.infinity_polling()
PY_EOF

cat > requirements.txt <<'REQ_EOF'
pyTelegramBotAPI==4.15.2
google-generativeai==0.6.2
REQ_EOF

# 安裝Python包
pip3 install -r requirements.txt

echo ""
echo "✅ 安裝完成！"
echo "啟動命令: cd ~/telegram-bot && python3 bot.py"
QUICK_EOF
    
    chmod +x install_quick.sh
    ./install_quick.sh
}

# 命令行參數處理
if [ "$1" = "--quick" ] || [ "$1" = "-q" ]; then
    quick_install
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "使用方法: $0 [選項]"
    echo "選項:"
    echo "  --quick, -q    快速安裝模式"
    echo "  --help, -h     顯示幫助"
    echo "  無參數         完整安裝模式"
    exit 0
fi

# 檢查root權限
if [ "$EUID" -ne 0 ]; then
    warning "建議使用root權限運行"
    read -p "是否繼續？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 運行主安裝
main_installation