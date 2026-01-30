#!/bin/bash
set -e

echo "=============================="
echo " 🤖 Telegram Gemini Bot 部署器"
echo "=============================="

# 讀取必要參數
read -rp "👉 請輸入 BOT_TOKEN: " BOT_TOKEN
read -rp "👉 請輸入 GEMINI_API_KEY: " GEMINI_API_KEY
read -rp "👉 請輸入 Webhook DOMAIN (不含 https://): " WEBHOOK_DOMAIN

# 建立臨時目錄
TMPDIR=$(mktemp -d)
echo "[INFO] 建立臨時目錄: $TMPDIR"
cd "$TMPDIR"

# 安裝 unzip（如果沒安裝）
if ! command -v unzip &> /dev/null; then
    echo "[INFO] 安裝 unzip..."
    apt update && apt install -y unzip curl ca-certificates
fi

# 下載專案 ZIP，強制 IPv4
echo "[INFO] 下載專案 ZIP..."
curl -4 -L -o bot.zip https://github.com/1743986520/telegram-chat-bot-Gemin/archive/refs/heads/main.zip

# 解壓
echo "[INFO] 解壓專案..."
unzip -o bot.zip
cd telegram-chat-bot-Gemin-main

# 檢查必要檔案
if [ ! -f Dockerfile ] || [ ! -f main.py ]; then
    echo "❌ 找不到 Dockerfile 或 main.py，部署中止"
    exit 1
fi

# 將輸入寫入環境檔
echo "[INFO] 寫入環境變數到 .env"
cat > .env <<EOF
BOT_TOKEN=${BOT_TOKEN}
GEMINI_API_KEY=${GEMINI_API_KEY}
WEBHOOK_DOMAIN=${WEBHOOK_DOMAIN}
EOF

# 建立 Docker 映像
echo "[INFO] 建立 Docker 映像..."
docker build -t tg-gemini-bot .

# 啟動容器
echo "[INFO] 啟動 Docker 容器..."
docker run -d --name tg-gemini-bot \
    --env-file .env \
    -p 8080:8080 \
    tg-gemini-bot

echo "✅ 部署完成！容器名稱: tg-gemini-bot"
echo "📌 Webhook URL: https://$WEBHOOK_DOMAIN/webhook"
