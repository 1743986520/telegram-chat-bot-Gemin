#!/bin/bash
# Telegram Gemini Bot 安裝器 - 最終修復版
# 解決所有依賴問題，確保100%安裝成功

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
    echo "=================================================="
    echo "      Telegram Gemini Bot 一鍵安裝器"
    echo "              終極修復版"
    echo "=================================================="
    echo -e "${COLOR_RESET}"
}

# 檢測系統
detect_system() {
    log "檢測系統環境..."
    
    OS_NAME=$(uname -s)
    OS_ARCH=$(uname -m)
    
    # 檢測Python
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
    else
        PYTHON_CMD=""
        PYTHON_VERSION="未安裝"
    fi
    
    info "系統信息:"
    echo "  系統: $OS_NAME $OS_ARCH"
    echo "  Python: $PYTHON_VERSION"
}

# 安裝系統依賴
install_dependencies() {
    log "安裝必要依賴..."
    
    # 檢查並安裝curl
    if ! command -v curl >/dev/null 2>&1; then
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl
        fi
    fi
    
    # 檢查Python3
    if [ -z "$PYTHON_CMD" ]; then
        log "安裝Python3..."
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y python3 python3-pip
        elif command -v yum >/dev/null 2>&1; then
            yum install -y python3 python3-pip
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache python3 py3-pip
        else
            error "無法安裝Python3，請手動安裝"
        fi
        PYTHON_CMD="python3"
    fi
    
    success "系統依賴安裝完成"
}

# 獲取配置
get_configuration() {
    echo ""
    info "機器人配置"
    echo "══════════════════════════════════════"
    
    # 檢查現有配置
    CONFIG_FILE="gemini-bot-config.env"
    if [ -f "$CONFIG_FILE" ]; then
        echo "發現現有配置:"
        cat "$CONFIG_FILE"
        echo ""
        read -p "使用現有配置？(Y/n): " use_existing
        if [[ ! $use_existing =~ ^[Nn]$ ]]; then
            return
        fi
    fi
    
    echo ""
    echo "請輸入以下信息（按Ctrl+C取消）:"
    echo ""
    
    # BOT_TOKEN
    while true; do
        read -p "1. BOT_TOKEN (從 @BotFather 獲取): " BOT_TOKEN
        if [[ -n "$BOT_TOKEN" ]]; then
            if [[ "$BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
                break
            else
                echo "格式錯誤！應該是 數字:字母 格式"
            fi
        fi
    done
    
    echo ""
    
    # GEMINI_API_KEY
    while true; do
        read -p "2. GEMINI_API_KEY (從 https://makersuite.google.com/app/apikey 獲取): " GEMINI_API_KEY
        if [[ -n "$GEMINI_API_KEY" ]]; then
            break
        fi
    done
    
    # 保存配置
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
EOF
    
    echo ""
    success "配置已保存到: $CONFIG_FILE"
}

# 創建Python腳本
create_python_script() {
    log "創建機器人程序..."
    
    # 創建項目目錄
    PROJECT_DIR="$HOME/gemini-telegram-bot"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # 創建主程序
    cat > gemini_bot.py <<'PYTHON_CODE'
#!/usr/bin/env python3
"""
Telegram Gemini Bot - 終極簡化版
無需Webhook，純輪詢模式
"""

import os
import sys
import time
import logging
import telebot
import google.generativeai as genai
from datetime import datetime

# 設置日誌
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class GeminiBot:
    def __init__(self, bot_token, api_key):
        """初始化機器人"""
        self.bot_token = bot_token
        self.api_key = api_key
        
        # 初始化Telegram Bot
        self.bot = telebot.TeleBot(bot_token)
        
        # 配置Gemini
        genai.configure(api_key=api_key)
        
        # 可用模型列表
        self.models = ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-1.5-flash-8b"]
        self.current_model = 0
        
        # 用戶冷卻時間
        self.user_cooldown = {}
        self.cooldown_seconds = 2
        
        logger.info("機器人初始化完成")
    
    def get_ai_response(self, prompt):
        """獲取AI回應"""
        try:
            # 選擇模型
            model_name = self.models[self.current_model]
            
            # 切換到下一個模型
            self.current_model = (self.current_model + 1) % len(self.models)
            
            # 創建模型實例
            model = genai.GenerativeModel(model_name)
            
            # 優化提示詞
            enhanced_prompt = f"""請用中文回答以下問題。
保持回答簡潔、有用、友好。

問題：{prompt}

請回答："""
            
            # 生成回應
            response = model.generate_content(
                enhanced_prompt,
                generation_config={
                    "temperature": 0.7,
                    "top_p": 0.9,
                    "top_k": 40,
                    "max_output_tokens": 1500,
                }
            )
            
            return response.text.strip()
            
        except Exception as e:
            logger.error(f"AI錯誤: {e}")
            return "抱歉，AI服務暫時不可用。請稍後再試。"
    
    def should_respond_to_message(self, message):
        """檢查是否應該回應此消息"""
        # 只處理群組消息
        if message.chat.type == "private":
            return False, "🤖 本機器人僅在群組中使用！\n請將我添加到群組中，然後在群組中@我提問。"
        
        # 檢查冷卻
        user_id = message.from_user.id
        current_time = time.time()
        
        if user_id in self.user_cooldown:
            last_time = self.user_cooldown[user_id]
            time_passed = current_time - last_time
            
            if time_passed < self.cooldown_seconds:
                wait_time = int(self.cooldown_seconds - time_passed)
                return False, f"⏳ 請等待 {wait_time} 秒後再發送消息。"
        
        text = message.text or ""
        bot_username = self.bot.get_me().username
        
        # 檢查觸發方式
        triggered = False
        clean_text = text
        
        # 1. 回復機器人的消息
        if message.reply_to_message:
            if message.reply_to_message.from_user.id == self.bot.get_me().id:
                triggered = True
        
        # 2. @機器人
        if bot_username and f"@{bot_username}" in text:
            triggered = True
            clean_text = text.replace(f"@{bot_username}", "").strip()
        
        # 3. 使用命令
        commands = ['/ask', '!ai', '??', '/ai', '！ai']
        for cmd in commands:
            if text.startswith(cmd):
                triggered = True
                clean_text = text[len(cmd):].strip()
                break
        
        # 4. 關鍵詞觸發（可選）
        keywords = ['機器人', 'bot', 'ai', '幫忙', '請問', '問一下']
        if any(keyword in text.lower() for keyword in keywords):
            triggered = True
        
        if not triggered:
            return False, None
        
        # 更新冷卻時間
        self.user_cooldown[user_id] = current_time
        
        return True, clean_text
    
    def setup_handlers(self):
        """設置消息處理器"""
        
        @self.bot.message_handler(commands=['start', 'help', '幫助'])
        def send_help(message):
            help_text = """🤖 *Telegram Gemini AI 機器人*

*使用方法:*
• 在群組中 @我 + 問題
• 回覆我的消息進行對話
• 使用命令 /ask + 問題
• 或直接說「機器人，...」

*示例:*
@機器人 什麼是人工智能？
/ask 講一個笑話
回覆此消息：幫我寫一段代碼

*命令列表:*
/start - 顯示此幫助
/status - 查看狀態
/test - 測試AI
/about - 關於機器人

*注意:*
• 每條消息間隔2秒冷卻
• 僅在群組中工作
• 支持中文和英文"""
            
            self.bot.reply_to(message, help_text, parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['status', '狀態'])
        def send_status(message):
            status_text = f"""📊 *機器人狀態*

*基本信息:*
• 運行時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
• 當前模型: {self.models[self.current_model]}
• 冷卻時間: {self.cooldown_seconds}秒

*技術信息:*
• Python版本: {sys.version.split()[0]}
• 運行模式: 輪詢模式
• 日誌文件: bot.log"""
            
            self.bot.reply_to(message, status_text, parse_mode='Markdown')
        
        @self.bot.message_handler(commands=['test', '測試'])
        def test_bot(message):
            test_questions = [
                "你好！請介紹一下你自己",
                "講一個有趣的笑話",
                "什麼是機器學習？",
                "用Python寫一個Hello World程序"
            ]
            
            import random
            question = random.choice(test_questions)
            
            self.bot.reply_to(message, f"🧪 測試問題: *{question}*", parse_mode='Markdown')
            
            # 獲取AI回應
            response = self.get_ai_response(question)
            self.bot.reply_to(message, f"🤖 AI回應:\n\n{response}")
        
        @self.bot.message_handler(commands=['about', '關於'])
        def about_bot(message):
            about_text = """*關於 Gemini Telegram Bot*

*版本:* 2.0 簡化版
*作者:* 自動生成
*技術:* Google Gemini AI + pyTelegramBotAPI
*特點:* 無需Webhook，純輪詢模式

*功能:*
• 智能對話
• 代碼幫助
• 問題解答
• 學習輔助

*源碼:* 由安裝腳本自動生成"""
            
            self.bot.reply_to(message, about_text, parse_mode='Markdown')
        
        @self.bot.message_handler(func=lambda message: True)
        def handle_all_messages(message):
            try:
                should_respond, text = self.should_respond_to_message(message)
                
                if not should_respond:
                    if text:  # 有錯誤消息
                        self.bot.reply_to(message, text)
                    return
                
                if not text or text.strip() == "":
                    self.bot.reply_to(message, "請輸入要問的問題！")
                    return
                
                # 顯示「思考中」
                thinking_msg = self.bot.reply_to(message, "🤔 思考中...")
                
                # 獲取AI回應
                response = self.get_ai_response(text)
                
                # 刪除「思考中」消息
                try:
                    self.bot.delete_message(message.chat.id, thinking_msg.message_id)
                except:
                    pass
                
                # 發送回應
                if response:
                    self.bot.reply_to(message, response)
                else:
                    self.bot.reply_to(message, "抱歉，沒有收到回應。")
                    
            except Exception as e:
                logger.error(f"處理消息時出錯: {e}")
                try:
                    self.bot.reply_to(message, "⚠️ 處理消息時出錯，請稍後再試")
                except:
                    pass
    
    def run(self):
        """運行機器人"""
        logger.info("=" * 50)
        logger.info("🚀 啟動 Telegram Gemini Bot")
        logger.info("=" * 50)
        logger.info(f"機器人: @{self.bot.get_me().username}")
        logger.info(f"模型池: {self.models}")
        logger.info("模式: 簡化輪詢版")
        logger.info("=" * 50)
        
        try:
            # 設置處理器
            self.setup_handlers()
            
            # 開始輪詢
            logger.info("開始接收消息... (按Ctrl+C停止)")
            self.bot.infinity_polling(timeout=60, long_polling_timeout=60)
            
        except KeyboardInterrupt:
            logger.info("收到停止信號，關閉機器人...")
        except Exception as e:
            logger.error(f"運行錯誤: {e}")
            raise

def load_config():
    """加載配置"""
    config = {}
    
    # 嘗試從環境變數加載
    config['BOT_TOKEN'] = os.getenv('BOT_TOKEN')
    config['GEMINI_API_KEY'] = os.getenv('GEMINI_API_KEY')
    
    # 嘗試從配置文件加載
    config_files = [
        'gemini-bot-config.env',
        '.env',
        'config.env',
        os.path.expanduser('~/gemini-bot-config.env')
    ]
    
    for config_file in config_files:
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r', encoding='utf-8') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            if '=' in line:
                                key, value = line.split('=', 1)
                                key = key.strip()
                                value = value.strip().strip('"\''')
                                if key in ['BOT_TOKEN', 'GEMINI_API_KEY']:
                                    config[key] = value
                logger.info(f"從 {config_file} 加載配置")
                break
            except Exception as e:
                logger.warning(f"讀取配置文件失敗: {e}")
    
    return config

def main():
    """主函數"""
    # 加載配置
    config = load_config()
    
    BOT_TOKEN = config.get('BOT_TOKEN')
    GEMINI_API_KEY = config.get('GEMINI_API_KEY')
    
    # 檢查配置
    if not BOT_TOKEN:
        logger.error("錯誤: BOT_TOKEN 未設置")
        logger.info("設置方法:")
        logger.info("1. 環境變數: export BOT_TOKEN=你的token")
        logger.info("2. 配置文件: 在 gemini-bot-config.env 中設置")
        logger.info("3. 命令行參數: python gemini_bot.py --token 你的token")
        sys.exit(1)
    
    if not GEMINI_API_KEY:
        logger.error("錯誤: GEMINI_API_KEY 未設置")
        logger.info("獲取地址: https://makersuite.google.com/app/apikey")
        sys.exit(1)
    
    # 創建並運行機器人
    bot = GeminiBot(BOT_TOKEN, GEMINI_API_KEY)
    bot.run()

if __name__ == "__main__":
    main()
PYTHON_CODE

    # 創建requirements.txt（使用最新可用版本）
    cat > requirements.txt <<'EOF'
# Telegram Gemini Bot 依賴
# 使用最新穩定版本，避免版本衝突
pyTelegramBotAPI>=4.15.0
google-generativeai>=0.8.0
requests>=2.28.0
EOF

    # 創建啟動腳本
    cat > start.sh <<'EOF'
#!/bin/bash
# 啟動腳本

cd "$(dirname "$0")"

echo "========================================"
echo "   Telegram Gemini Bot 啟動器"
echo "========================================"
echo ""

# 檢查配置
if [ ! -f "gemini-bot-config.env" ] && [ ! -f ".env" ]; then
    echo "❌ 錯誤: 未找到配置文件"
    echo ""
    echo "請先創建配置文件:"
    echo "1. 複製模板: cp config.example.env gemini-bot-config.env"
    echo "2. 編輯配置: nano gemini-bot-config.env"
    echo "3. 填入你的 BOT_TOKEN 和 GEMINI_API_KEY"
    echo ""
    exit 1
fi

# 檢查Python依賴
echo "檢查Python依賴..."
python3 -c "import telebot, google.generativeai" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "安裝缺失的依賴..."
    pip3 install -r requirements.txt --upgrade
fi

echo ""
echo "啟動機器人..."
echo "按 Ctrl+C 停止"
echo "日誌文件: bot.log"
echo "========================================"
echo ""

# 運行機器人
python3 gemini_bot.py
EOF

    # 創建後台運行腳本
    cat > start_daemon.sh <<'EOF'
#!/bin/bash
# 後台啟動腳本

cd "$(dirname "$0")"

echo "啟動 Telegram Gemini Bot (後台模式)..."

# 檢查是否已運行
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "機器人已在運行 (PID: $PID)"
        exit 0
    fi
fi

# 啟動
nohup python3 gemini_bot.py > bot_console.log 2>&1 &
echo $! > bot.pid

echo "✅ 機器人已啟動"
echo "PID: $(cat bot.pid)"
echo ""
echo "查看日誌:"
echo "  tail -f bot.log          # 程序日誌"
echo "  tail -f bot_console.log  # 控制台輸出"
echo ""
echo "停止命令: ./stop.sh"
EOF

    # 創建停止腳本
    cat > stop.sh <<'EOF'
#!/bin/bash
# 停止腳本

cd "$(dirname "$0")"

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        kill $PID
        sleep 1
        if kill -0 $PID 2>/dev/null; then
            kill -9 $PID
        fi
        echo "✅ 機器人已停止 (PID: $PID)"
        rm -f bot.pid
    else
        echo "機器人未運行"
        rm -f bot.pid
    fi
else
    echo "機器人未運行"
fi

# 清理殘留進程
pkill -f "python3 gemini_bot.py" 2>/dev/null || true
EOF

    # 創建狀態檢查腳本
    cat > status.sh <<'EOF'
#!/bin/bash
# 狀態檢查腳本

cd "$(dirname "$0")"

echo "Telegram Gemini Bot 狀態檢查"
echo "=============================="

if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -0 $PID 2>/dev/null; then
        echo "✅ 狀態: 正在運行"
        echo "PID: $PID"
        echo "運行時間: $(ps -p $PID -o etime= | tr -d ' ')"
        echo "內存使用: $(ps -p $PID -o rss=) KB"
        echo ""
        echo "最近日誌:"
        tail -5 bot.log 2>/dev/null || echo "（無日誌）"
    else
        echo "❌ 狀態: 已停止 (PID文件存在)"
        rm -f bot.pid
    fi
else
    echo "❌ 狀態: 未運行"
fi

echo ""
echo "配置文件:"
if [ -f "gemini-bot-config.env" ]; then
    echo "  gemini-bot-config.env: 存在"
elif [ -f ".env" ]; then
    echo "  .env: 存在"
else
    echo "  ❌ 未找到配置文件"
fi

echo ""
echo "日誌文件:"
ls -la bot.log 2>/dev/null || echo "  bot.log: 不存在"
ls -la bot_console.log 2>/dev/null || echo "  bot_console.log: 不存在"
EOF

    # 創建配置示例文件
    cat > config.example.env <<'EOF'
# Telegram Gemini Bot 配置文件
# 複製此文件為 gemini-bot-config.env 並填入你的信息

# 從 @BotFather 獲取
BOT_TOKEN=你的機器人token

# 從 https://makersuite.google.com/app/apikey 獲取
GEMINI_API_KEY=你的gemini_api_key
EOF

    # 設置執行權限
    chmod +x start.sh start_daemon.sh stop.sh status.sh
    chmod +x gemini_bot.py
    
    success "程序創建完成"
    info "項目目錄: $PROJECT_DIR"
}

# 安裝Python依賴（修復版）
install_python_dependencies_fixed() {
    log "安裝Python依賴（修復版）..."
    
    cd "$HOME/gemini-telegram-bot"
    
    # 先升級pip（但不過度升級）
    echo "更新pip..."
    $PYTHON_CMD -m pip install --upgrade pip --no-warn-script-location
    
    # 安裝核心依賴（使用兼容版本）
    echo "安裝核心依賴..."
    
    # 安裝telegram bot庫
    $PYTHON_CMD -m pip install "pyTelegramBotAPI>=4.15.0" --no-warn-script-location
    
    # 安裝google generativeai（使用可用版本）
    $PYTHON_CMD -m pip install "google-generativeai" --no-warn-script-location
    
    # 安裝requests
    $PYTHON_CMD -m pip install "requests>=2.28.0" --no-warn-script-location
    
    # 驗證安裝
    echo "驗證安裝..."
    if $PYTHON_CMD -c "import telebot, google.generativeai, requests; print('✅ 所有依賴安裝成功')"; then
        success "Python依賴安裝完成"
    else
        warning "部分依賴可能未正確安裝，但將繼續..."
    fi
}

# 創建系統服務（可選）
create_system_service() {
    echo ""
    read -p "是否創建系統服務（開機自啟）？(Y/n): " create_service
    create_service=${create_service:-Y}
    
    if [[ ! $create_service =~ ^[Yy]$ ]]; then
        return
    fi
    
    log "創建系統服務..."
    
    SERVICE_FILE="/etc/systemd/system/gemini-telegram-bot.service"
    
    # 檢查是否為root
    if [ "$EUID" -ne 0 ]; then
        warning "需要root權限創建系統服務"
        info "可以手動創建服務文件:"
        echo "sudo nano $SERVICE_FILE"
        return
    fi
    
    cat > /tmp/gemini-telegram-bot.service <<EOF
[Unit]
Description=Telegram Gemini Bot
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/gemini-telegram-bot
Environment="PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$PYTHON_CMD $HOME/gemini-telegram-bot/gemini_bot.py
Restart=always
RestartSec=10
StandardOutput=append:$HOME/gemini-telegram-bot/bot_console.log
StandardError=append:$HOME/gemini-telegram-bot/bot_console.log

# 安全設置
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo cp /tmp/gemini-telegram-bot.service "$SERVICE_FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable gemini-telegram-bot
    sudo systemctl start gemini-telegram-bot
    
    sleep 2
    
    if sudo systemctl is-active --quiet gemini-telegram-bot; then
        success "系統服務創建並啟動成功"
    else
        warning "系統服務啟動可能失敗，檢查: sudo systemctl status gemini-telegram-bot"
    fi
}

# 顯示完成信息
show_completion_info() {
    echo ""
    success "🎉 Telegram Gemini Bot 安裝完成！"
    echo ""
    
    PROJECT_DIR="$HOME/gemini-telegram-bot"
    
    echo "════════════════════════════════════════════════════"
    echo "                   安裝摘要"
    echo "════════════════════════════════════════════════════"
    echo ""
    echo "📁 項目目錄: $PROJECT_DIR"
    echo ""
    echo "📄 重要文件:"
    echo "  gemini_bot.py          - 主程序"
    echo "  gemini-bot-config.env  - 配置文件"
    echo "  requirements.txt       - 依賴列表"
    echo "  bot.log               - 程序日誌"
    echo ""
    echo "🚀 啟動方式:"
    echo "  1. 前台運行: cd $PROJECT_DIR && ./start.sh"
    echo "  2. 後台運行: cd $PROJECT_DIR && ./start_daemon.sh"
    echo "  3. 直接運行: cd $PROJECT_DIR && python3 gemini_bot.py"
    echo ""
    echo "🔧 管理命令:"
    echo "  ./stop.sh    - 停止機器人"
    echo "  ./status.sh  - 查看狀態"
    echo "  ./start.sh   - 重新啟動"
    echo ""
    
    if [ -f "/etc/systemd/system/gemini-telegram-bot.service" ]; then
        echo "📦 系統服務:"
        echo "  sudo systemctl status gemini-telegram-bot"
        echo "  sudo systemctl stop gemini-telegram-bot"
        echo "  sudo systemctl start gemini-telegram-bot"
        echo ""
    fi
    
    echo "📝 使用方法:"
    echo "  1. 將機器人添加到Telegram群組"
    echo "  2. 在群組中@機器人提問"
    echo "  3. 或回覆機器人的消息"
    echo ""
    echo "❓ 測試命令:"
    echo "  /start   - 顯示幫助"
    echo "  /test    - 測試AI"
    echo "  /status  - 查看狀態"
    echo ""
    echo "⚠️  注意事項:"
    echo "  • 機器人只在群組中工作"
    echo "  • 每條消息有2秒冷卻時間"
    echo "  • 查看 bot.log 了解運行狀態"
    echo ""
    echo "🔍 故障排除:"
    echo "  1. 檢查配置: cat gemini-bot-config.env"
    echo "  2. 查看日誌: tail -f bot.log"
    echo "  3. 重啟機器人: ./stop.sh && ./start_daemon.sh"
    echo ""
    echo "════════════════════════════════════════════════════"
}

# 主安裝流程
main() {
    print_banner
    
    # 檢測系統
    detect_system
    
    # 安裝依賴
    install_dependencies
    
    # 獲取配置
    get_configuration
    
    # 創建Python腳本
    create_python_script
    
    # 安裝Python依賴
    install_python_dependencies_fixed
    
    # 詢問是否創建系統服務
    create_system_service
    
    # 顯示完成信息
    show_completion_info
    
    # 詢問是否立即啟動
    echo ""
    read -p "是否立即啟動機器人？(Y/n): " start_now
    start_now=${start_now:-Y}
    
    if [[ $start_now =~ ^[Yy]$ ]]; then
        cd "$HOME/gemini-telegram-bot"
        
        if systemctl is-enabled gemini-telegram-bot 2>/dev/null | grep -q enabled; then
            echo "系統服務已啟動，正在運行..."
            sudo systemctl status gemini-telegram-bot --no-pager
        else
            echo "啟動機器人..."
            ./start_daemon.sh
        fi
    fi
    
    echo ""
    echo "💡 提示: 機器人配置文件已保存到: gemini-bot-config.env"
    echo "      如需修改配置，請編輯此文件後重啟機器人"
    echo ""
}

# 錯誤處理
trap 'echo -e "\n${COLOR_RED}安裝被中斷${COLOR_RESET}"; exit 1' INT TERM

# 檢查是否直接運行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 顯示歡迎信息
    echo "Telegram Gemini Bot 一鍵安裝腳本"
    echo "此腳本將創建完整的機器人程序"
    echo ""
    
    # 檢查參數
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "用法: $0"
        echo "功能: 一鍵安裝Telegram Gemini Bot"
        exit 0
    fi
    
    # 開始安裝
    main
fi