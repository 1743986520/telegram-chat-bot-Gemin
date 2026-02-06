#!/bin/bash
# Telegram Gemini Bot 簡化安裝器
# 純輪詢模式，無需Webhook/網頁功能
# 支持: Ubuntu/Debian/CentOS/Alpine/Docker/MacOS/Windows(WSL)

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
    exit 1
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
    echo "║      Telegram Gemini Bot 簡化版安裝器              ║"
    echo "║           純輪詢模式，無需Webhook                  ║"
    echo "║                                                    ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
}

# 檢測系統
detect_system() {
    log "檢測系統環境..."
    
    OS_NAME=$(uname -s)
    OS_ARCH=$(uname -m)
    
    case $OS_NAME in
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO_ID=$ID
                DISTRO_NAME=$NAME
            elif [ -f /etc/redhat-release ]; then
                DISTRO_ID="rhel"
                DISTRO_NAME="Red Hat"
            elif [ -f /etc/debian_version ]; then
                DISTRO_ID="debian"
                DISTRO_NAME="Debian"
            elif [ -f /etc/alpine-release ]; then
                DISTRO_ID="alpine"
                DISTRO_NAME="Alpine Linux"
            else
                DISTRO_ID="linux"
                DISTRO_NAME="Linux"
            fi
            ;;
        Darwin)
            DISTRO_ID="macos"
            DISTRO_NAME="macOS"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            DISTRO_ID="windows"
            DISTRO_NAME="Windows"
            ;;
        *)
            DISTRO_ID="unknown"
            DISTRO_NAME="Unknown"
            ;;
    esac
    
    # 檢測Python
    PYTHON_CMD=""
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
    fi
    
    info "系統信息:"
    echo "  系統: $OS_NAME ($OS_ARCH)"
    echo "  發行版: $DISTRO_NAME"
    echo "  Python: ${PYTHON_VERSION:-未安裝}"
    
    export OS_NAME DISTRO_ID DISTRO_NAME PYTHON_CMD PYTHON_VERSION
}

# 安裝系統依賴
install_dependencies() {
    log "安裝系統依賴..."
    
    case $DISTRO_ID in
        ubuntu|debian)
            apt update && apt install -y \
                python3 python3-pip python3-venv \
                curl wget git
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y python3 python3-pip curl wget git
            else
                yum install -y python3 python3-pip curl wget git
            fi
            ;;
        alpine)
            apk add --no-cache python3 py3-pip curl wget git
            ;;
        macos)
            if ! command -v brew >/dev/null 2>&1; then
                info "正在安裝Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install python curl wget git
            ;;
        *)
            warning "未知系統，嘗試通用安裝..."
            if command -v apt >/dev/null 2>&1; then
                apt update && apt install -y python3 python3-pip curl wget git
            elif command -v yum >/dev/null 2>&1; then
                yum install -y python3 python3-pip curl wget git
            elif command -v apk >/dev/null 2>&1; then
                apk add --no-cache python3 py3-pip curl wget git
            else
                error "無法自動安裝依賴，請手動安裝Python3和pip"
            fi
            ;;
    esac
    
    success "系統依賴安裝完成"
}

# 獲取配置信息
get_configuration() {
    echo ""
    info "配置機器人 (按Ctrl+C退出):"
    
    # BOT_TOKEN
    while true; do
        read -p "輸入BOT_TOKEN (從 @BotFather 獲取): " BOT_TOKEN
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
        read -p "輸入GEMINI_API_KEY (從 https://makersuite.google.com/app/apikey 獲取): " GEMINI_API_KEY
        if [[ -n "$GEMINI_API_KEY" ]]; then
            break
        else
            warning "GEMINI_API_KEY 不能為空"
        fi
    done
    
    # 創建配置文件
    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
# 簡化版無需DOMAIN和PORT
EOF
    
    success "配置已保存到 .env 文件"
}

# 下載源代碼
download_source() {
    log "下載機器人源代碼..."
    
    # 創建項目目錄
    PROJECT_DIR="$HOME/telegram-gemini-bot"
    if [ ! -d "$PROJECT_DIR" ]; then
        mkdir -p "$PROJECT_DIR"
    fi
    cd "$PROJECT_DIR"
    
    # 創建簡化的Python代碼（無Webhook/Flask）
    cat > bot.py <<'EOF'
#!/usr/bin/env python3
# Telegram Gemini Bot - 簡化版（純輪詢模式）
import os
import telebot
import google.generativeai as genai
import time
import re
import logging
import sys
import random
from datetime import datetime

# ========== 配置和日誌 ==========
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('bot.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

# 加載環境變數
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
                        config[key.strip()] = value.strip().strip('"\'')

    # 從環境變數加載
    env_keys = ['BOT_TOKEN', 'GEMINI_API_KEY']
    for key in env_keys:
        env_value = os.getenv(key)
        if env_value and key not in config:
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

# ========== 初始化 ==========
MODEL_POOL = ["gemini-1.5-flash", "gemini-1.5-pro"]
MAX_RETRIES = 3

# 初始化
genai.configure(api_key=GEMINI_API_KEY)
bot = telebot.TeleBot(BOT_TOKEN, parse_mode=None)

# 緩存和冷卻
user_cooldown = {}
cooldown_time = 2  # 秒

# ========== AI 服務 ==========
class AIService:
    def __init__(self, api_key):
        self.api_key = api_key
        self.models = MODEL_POOL
        self.current_model_index = 0
    
    def get_response(self, prompt):
        for attempt in range(MAX_RETRIES):
            try:
                model_name = self.models[self.current_model_index]
                model = genai.GenerativeModel(model_name)
                
                optimized_prompt = f"""請用中文回答以下問題。
保持回答簡潔明了，使用自然的對話語氣。

問題：{prompt}

請回答："""
                
                response = model.generate_content(
                    optimized_prompt,
                    generation_config={
                        "temperature": 0.7,
                        "max_output_tokens": 1500,
                    }
                )
                
                text = response.text.strip()
                
                # 切換到下一個模型（循環）
                self.current_model_index = (self.current_model_index + 1) % len(self.models)
                
                return text
                
            except Exception as e:
                error_msg = str(e).lower()
                if attempt == MAX_RETRIES - 1:
                    return "抱歉，AI服務暫時不可用，請稍後再試。"
                time.sleep(1)

# ========== 消息處理 ==========
ai_service = AIService(GEMINI_API_KEY)

def should_respond(msg):
    """檢查是否應該回應"""
    # 只處理群組消息
    if msg.chat.type == "private":
        return False, "本機器人僅在群組中使用，請將我添加到群組中！"
    
    # 冷卻檢查
    user_id = msg.from_user.id
    current_time = time.time()
    if user_id in user_cooldown:
        last_time = user_cooldown[user_id]
        if current_time - last_time < cooldown_time:
            return False, f"請等待 {int(cooldown_time - (current_time - last_time))} 秒後再試"
    
    text = msg.text.strip()
    triggered = False
    
    # 1. 回復機器人
    if msg.reply_to_message and msg.reply_to_message.from_user.id == bot.get_me().id:
        triggered = True
    
    # 2. @機器人
    bot_username = bot.get_me().username
    if bot_username and f"@{bot_username}" in text:
        text = text.replace(f"@{bot_username}", "").strip()
        triggered = True
    
    # 3. 命令觸發
    triggers = ['!ai', '/ask', '??', '！ai']
    for trigger in triggers:
        if text.startswith(trigger):
            text = text[len(trigger):].strip()
            triggered = True
            break
    
    if not triggered:
        return False, None
    
    # 更新冷卻時間
    user_cooldown[user_id] = current_time
    return True, text

# ========== 命令處理 ==========
@bot.message_handler(commands=['start', 'help'])
def send_welcome(msg):
    help_text = """🤖 Telegram Gemini AI 機器人

*使用方法:*
• 在群組中 @我 + 問題
• 回復我的消息進行對話
• 使用命令 /ask + 問題

*可用命令:*
/start, /help - 顯示幫助
/status - 查看狀態
/test - 測試AI回應
/clear - 清除冷卻

*注意:*
• 機器人僅在群組中工作
• 每條消息間隔2秒冷卻"""
    
    bot.reply_to(msg, help_text, parse_mode='Markdown')

@bot.message_handler(commands=['status'])
def send_status(msg):
    status_text = f"""📊 機器人狀態
• 運行時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
• 當前模型: {MODEL_POOL[ai_service.current_model_index]}
• 冷卻時間: {cooldown_time}秒
• 版本: 簡化輪詢版"""
    
    bot.reply_to(msg, status_text)

@bot.message_handler(commands=['test'])
def test_ai(msg):
    test_prompts = [
        "你好！請介紹一下你自己",
        "講一個笑話",
        "什麼是人工智能？"
    ]
    
    prompt = random.choice(test_prompts)
    bot.reply_to(msg, f"🧪 測試問題: {prompt}")
    
    response = ai_service.get_response(prompt)
    bot.reply_to(msg, f"🤖 AI回應: {response}")

@bot.message_handler(commands=['clear'])
def clear_cooldown(msg):
    user_id = msg.from_user.id
    if user_id in user_cooldown:
        del user_cooldown[user_id]
        bot.reply_to(msg, "✅ 冷卻時間已重置")
    else:
        bot.reply_to(msg, "ℹ️ 你沒有冷卻限制")

@bot.message_handler(func=lambda message: True)
def handle_all_messages(msg):
    try:
        should, text = should_respond(msg)
        
        if not should:
            if text:  # 有錯誤消息
                bot.reply_to(msg, text)
            return
        
        # 顯示"思考中"
        thinking_msg = bot.reply_to(msg, "🤔 思考中...")
        
        # 獲取AI回應
        response = ai_service.get_response(text)
        
        # 刪除"思考中"消息
        try:
            bot.delete_message(msg.chat.id, thinking_msg.message_id)
        except:
            pass
        
        # 發送回應
        if response:
            bot.reply_to(msg, response)
        
    except Exception as e:
        logger.error(f"處理消息錯誤: {e}")

# ========== 主程序 ==========
def main():
    logger.info("=" * 50)
    logger.info("🚀 啟動 Telegram Gemini Bot (簡化版)")
    logger.info("=" * 50)
    logger.info(f"BOT_TOKEN: {'*' * len(BOT_TOKEN) if BOT_TOKEN else '未設置'}")
    logger.info(f"模型池: {MODEL_POOL}")
    logger.info("模式: 純輪詢 (無Webhook)")
    logger.info("=" * 50)
    
    try:
        logger.info("開始輪詢... (按Ctrl+C停止)")
        bot.infinity_polling(timeout=60, long_polling_timeout=60)
    except KeyboardInterrupt:
        logger.info("收到停止信號，關閉機器人...")
    except Exception as e:
        logger.error(f"運行錯誤: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    # 創建requirements.txt
    cat > requirements.txt <<'EOF'
# Telegram Gemini Bot 依賴
pyTelegramBotAPI==4.15.2
google-generativeai==0.6.2

# 其他必要依賴
requests==2.31.0
EOF

    success "源代碼已下載到: $PROJECT_DIR"
}

# 安裝Python依賴
install_python_deps() {
    log "安裝Python依賴..."
    
    cd "$HOME/telegram-gemini-bot"
    
    # 創建虛擬環境（可選）
    if [ "$1" = "venv" ]; then
        info "創建Python虛擬環境..."
        $PYTHON_CMD -m venv venv
        
        if [ "$OS_NAME" = "Darwin" ] || [ "$OS_NAME" = "Linux" ]; then
            source venv/bin/activate
        else
            source venv/Scripts/activate
        fi
    fi
    
    # 升級pip
    $PYTHON_CMD -m pip install --upgrade pip
    
    # 安裝依賴
    if [ -f "requirements.txt" ]; then
        $PYTHON_CMD -m pip install -r requirements.txt
    else
        $PYTHON_CMD -m pip install pyTelegramBotAPI google-generativeai requests
    fi
    
    success "Python依賴安裝完成"
}

# 創建啟動腳本
create_startup_scripts() {
    log "創建啟動腳本..."
    
    cd "$HOME/telegram-gemini-bot"
    
    # Linux/Mac啟動腳本
    cat > start.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "啟動 Telegram Gemini Bot..."
echo "按 Ctrl+C 停止"

# 檢查虛擬環境
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
elif [ -f "venv/Scripts/activate" ]; then
    source venv/Scripts/activate
fi

# 運行機器人
python bot.py
EOF
    
    # Windows批處理文件
    cat > start.bat <<'EOF'
@echo off
cd /d "%~dp0"
echo 啟動 Telegram Gemini Bot...
echo 按 Ctrl+C 停止

REM 檢查虛擬環境
if exist "venv\Scripts\activate.bat" (
    call venv\Scripts\activate.bat
)

REM 運行機器人
python bot.py
pause
EOF
    
    # 守護進程模式腳本（Linux/Mac）
    cat > start_daemon.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 檢查是否已運行
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "機器人已在運行 (PID: $PID)"
        exit 0
    fi
fi

# 激活虛擬環境
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi

# 後台運行
nohup python bot.py > bot_console.log 2>&1 &
echo $! > bot.pid

echo "機器人已啟動 (PID: $(cat bot.pid))"
echo "查看日誌: tail -f bot.log"
echo "控制台輸出: tail -f bot_console.log"
EOF
    
    # 停止腳本
    cat > stop.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if ps -p $PID > /dev/null 2>&1; then
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

# 殺死所有相關進程
pkill -f "python bot.py" 2>/dev/null || true
EOF
    
    # 重啟腳本
    cat > restart.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 2
./start_daemon.sh
EOF
    
    # 狀態檢查腳本
    cat > status.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ 機器人正在運行 (PID: $PID)"
        echo "運行時間: $(ps -p $PID -o etime=)"
        echo "內存使用: $(ps -p $PID -o rss=) KB"
        echo "查看日誌: tail -n 20 bot.log"
    else
        echo "❌ 機器人已停止 (PID文件存在但進程不存在)"
        rm -f bot.pid
    fi
else
    echo "❌ 機器人未運行"
fi
EOF
    
    # 設置執行權限
    chmod +x *.sh
    
    success "啟動腳本創建完成"
}

# 創建Systemd服務（僅Linux）
create_systemd_service() {
    if [ "$OS_NAME" != "Linux" ]; then
        return
    fi
    
    log "創建Systemd服務..."
    
    SERVICE_FILE="/etc/systemd/system/telegram-gemini.service"
    
    if [ ! -w "/etc/systemd/system" ]; then
        warning "需要sudo權限創建systemd服務"
        info "手動創建方法:"
        echo "sudo cp telegram-gemini.service /etc/systemd/system/"
        return
    fi
    
    cat > telegram-gemini.service <<EOF
[Unit]
Description=Telegram Gemini Bot
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/telegram-gemini-bot
Environment="PATH=$HOME/telegram-gemini-bot/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$HOME/telegram-gemini-bot/venv/bin/python $HOME/telegram-gemini-bot/bot.py
Restart=always
RestartSec=10
StandardOutput=append:$HOME/telegram-gemini-bot/bot_console.log
StandardError=append:$HOME/telegram-gemini-bot/bot_console.log

[Install]
WantedBy=multi-user.target
EOF
    
    sudo mv telegram-gemini.service $SERVICE_FILE
    
    # 啟用和啟動服務
    sudo systemctl daemon-reload
    sudo systemctl enable telegram-gemini
    sudo systemctl start telegram-gemini
    
    success "Systemd服務已創建並啟動"
}

# 安裝完成提示
show_completion() {
    echo ""
    success "🎉 Telegram Gemini Bot 安裝完成！"
    echo ""
    
    info "📁 安裝目錄:"
    echo "  $HOME/telegram-gemini-bot"
    
    echo ""
    info "🚀 啟動方式:"
    
    case $OS_NAME in
        Linux|Darwin)
            echo "  1. 前台運行: cd ~/telegram-gemini-bot && ./start.sh"
            echo "  2. 後台運行: cd ~/telegram-gemini-bot && ./start_daemon.sh"
            echo "  3. Systemd服務: sudo systemctl status telegram-gemini"
            ;;
        *)
            echo "  雙擊 start.bat 或運行: python bot.py"
            ;;
    esac
    
    echo ""
    info "🔧 管理命令:"
    echo "  停止: ./stop.sh"
    echo "  重啟: ./restart.sh"
    echo "  狀態: ./status.sh"
    echo "  查看日誌: tail -f bot.log"
    echo "  編輯配置: nano .env"
    
    echo ""
    info "📝 配置文件:"
    echo "  .env - 包含BOT_TOKEN和API_KEY"
    
    echo ""
    info "⚠️  重要提示:"
    echo "  1. 確保已將機器人添加到群組"
    echo "  2. 機器人需要在群組中被@或回復才會響應"
    echo "  3. 查看 bot.log 了解運行狀態"
    
    echo ""
    info "🔄 測試機器人:"
    echo "  1. 將機器人添加到群組"
    echo "  2. 在群組中發送: /test"
    echo "  3. 或@機器人提問"
    
    echo ""
    echo "📞 問題反饋或幫助:"
    echo "  查看日誌文件: bot.log"
    echo ""
    echo "=" * 50
}

# 主安裝流程
main_installation() {
    print_banner
    detect_system
    
    # 檢查Python
    if [ -z "$PYTHON_CMD" ]; then
        info "Python未安裝，開始安裝..."
        install_dependencies
        detect_system  # 重新檢測
    fi
    
    # 創建項目目錄和獲取配置
    get_configuration
    download_source
    
    # 詢問是否使用虛擬環境
    echo ""
    read -p "是否使用Python虛擬環境？(推薦) [Y/n]: " use_venv
    use_venv=${use_venv:-Y}
    
    if [[ $use_venv =~ ^[Yy]$ ]]; then
        install_python_deps "venv"
    else
        install_python_deps
    fi
    
    # 創建啟動腳本
    create_startup_scripts
    
    # 詢問是否創建Systemd服務（僅Linux）
    if [ "$OS_NAME" = "Linux" ] && [ "$DISTRO_ID" != "alpine" ]; then
        echo ""
        read -p "是否創建Systemd服務（開機自啟）？ [Y/n]: " use_systemd
        use_systemd=${use_systemd:-Y}
        
        if [[ $use_systemd =~ ^[Yy]$ ]]; then
            create_systemd_service
        fi
    fi
    
    # 顯示完成信息
    show_completion
    
    # 詢問是否立即啟動
    echo ""
    read -p "是否立即啟動機器人？ [Y/n]: " start_now
    start_now=${start_now:-Y}
    
    if [[ $start_now =~ ^[Yy]$ ]]; then
        cd "$HOME/telegram-gemini-bot"
        
        if [ "$OS_NAME" = "Linux" ] && systemctl is-enabled telegram-gemini 2>/dev/null | grep -q enabled; then
            info "Systemd服務已啟動"
            sudo systemctl status telegram-gemini
        else
            info "啟動機器人..."
            if [ "$use_venv" = "Y" ] || [ "$use_venv" = "y" ]; then
                ./start_daemon.sh
            else
                echo "請手動運行: python bot.py"
                echo "或使用: ./start.sh"
            fi
        fi
    fi
}

# 錯誤處理
trap 'echo -e "\n${COLOR_RED}安裝被中斷${COLOR_RESET}"; exit 1' INT TERM

# 檢查是否直接運行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 檢查參數
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "使用方法: $0"
        echo "簡化版Telegram Gemini Bot安裝腳本"
        echo "特點: 純輪詢模式，無需Webhook/域名"
        exit 0
    fi
    
    # 開始安裝
    main_installation
fi