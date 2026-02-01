#!/bin/bash
set -e

echo "=============================="
echo " 🤖 Telegram Gemini Bot 安裝器"
echo "=============================="

# 讀取必要參數
read -p "👉 請輸入 BOT_TOKEN: " BOT_TOKEN
read -p "👉 請輸入 GEMINI_API_KEY: " GEMINI_API_KEY
read -p "👉 請輸入 Webhook DOMAIN (例如: your-domain.zeabur.app): " DOMAIN

# 檢查輸入
if [[ -z "$BOT_TOKEN" || -z "$GEMINI_API_KEY" || -z "$DOMAIN" ]]; then
    echo "❌ 有欄位是空的，安裝中止"
    exit 1
fi

# 確保域名不包含協議前綴
DOMAIN=$(echo "$DOMAIN" | sed 's|https://||g' | sed 's|http://||g')

# 建立工作目錄
WORKDIR="$HOME/tg-gemini"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 安裝必要依賴
echo "📦 安裝必要依賴..."
apt update && apt install -y curl unzip python3 python3-pip

# 下載最新代碼
echo "📥 下載最新代碼..."
curl -L -o bot-main.zip https://github.com/1743986520/telegram-chat-bot-Gemin/archive/refs/heads/main.zip

# 解壓
echo "🗜️ 解壓..."
unzip -o bot-main.zip
cd telegram-chat-bot-Gemin-main

# 建立 .env 文件
echo "🔧 建立環境變數文件..."
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
DOMAIN=$DOMAIN
EOF

echo "📋 環境變數內容:"
cat .env

# 安裝Python依賴
echo "📦 安裝Python依賴..."
pip3 install -r requirements.txt

# 測試運行
echo "🧪 測試運行..."
if python3 -c "import telebot, flask, google.generativeai, requests; print('✅ 依賴檢查通過')"; then
    echo "✅ 所有依賴已正確安裝"
else
    echo "❌ 依賴安裝有問題"
    exit 1
fi

# 建立啟動腳本
echo "📜 建立啟動腳本..."
cat > start.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# 設置環境變數
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# 運行機器人
python3 main.py
EOF
chmod +x start.sh

# 建立 systemd 服務
echo "🚀 建立 systemd 服務..."
SERVICE_FILE="/etc/systemd/system/tg-gemini.service"

sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Telegram Gemini Bot
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PWD
EnvironmentFile=$PWD/.env
ExecStart=$PWD/start.sh
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=tg-gemini

[Install]
WantedBy=multi-user.target
EOF

# 啟動服務
echo "🔧 啟動服務..."
sudo systemctl daemon-reload
sudo systemctl enable tg-gemini
sudo systemctl start tg-gemini

echo "⏳ 等待服務啟動..."
sleep 5

# 檢查服務狀態
if sudo systemctl is-active --quiet tg-gemini; then
    echo "✅ 服務運行正常"
else
    echo "❌ 服務啟動失敗，查看日誌: sudo journalctl -u tg-gemini -f"
    exit 1
fi

# 測試webhook
echo "🔗 測試webhook設置..."
WEBHOOK_URL="https://$DOMAIN/setwebhook"
echo "訪問: $WEBHOOK_URL"

echo ""
echo "🎉 安裝完成！"
echo "========================================"
echo "📌 Webhook URL: https://$DOMAIN/webhook"
echo "📌 檢查服務狀態: sudo systemctl status tg-gemini"
echo "📌 查看日誌: sudo journalctl -u tg-gemini -f"
echo "📌 測試webhook: curl https://$DOMAIN/setwebhook"
echo "========================================"