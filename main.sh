#!/bin/bash
set -e

echo "=============================="
echo " 🤖 Telegram Gemini Bot 安裝器"
echo "=============================="

# 讀取必要參數
read -p "👉 請輸入 BOT_TOKEN: " BOT_TOKEN
read -p "👉 請輸入 GEMINI_API_KEY: " GEMINI_API_KEY
read -p "👉 請輸入 Webhook DOMAIN (不含 https://): " ZEABUR_URL

# 檢查輸入
if [[ -z "$BOT_TOKEN" || -z "$GEMINI_API_KEY" || -z "$ZEABUR_URL" ]]; then
    echo "❌ 有欄位是空的，安裝中止"
    exit 1
fi

# 建立工作目錄
WORKDIR="$HOME/tg-gemini"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 安裝必要依賴
echo "📦 安裝必要依賴..."
apt update && apt install -y curl unzip docker.io docker-compose

# 下載 GitHub ZIP (強制 IPv4)
echo "📥 下載 Telegram Gemini Bot repo..."
curl -4 -L -o bot.zip https://github.com/1743986520/telegram-chat-bot-Gemin/archive/refs/heads/main.zip

# 解壓
echo "🗜️ 解壓..."
unzip -o bot.zip
cd telegram-chat-bot-Gemin-main

# 建立 .env 文件
echo "🔧 建立環境變數文件..."
cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
GEMINI_API_KEY=$GEMINI_API_KEY
ZEABUR_URL=$ZEABUR_URL
EOF

# 建立 Dockerfile（如果不存在）
if [[ ! -f Dockerfile ]]; then
cat > Dockerfile <<'EOF'
FROM python:3.11-slim

WORKDIR /app
COPY . /app

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

CMD ["python", "main.py"]
EOF
fi

# 構建 Docker 映像
echo "📦 建立 Docker 映像..."
docker build -t tg-gemini .

# 啟動容器（host 模式）
echo "🚀 啟動容器（host 模式）..."
docker run -d --name tg-gemini \
  --network host \
  --env-file .env \
  tg-gemini

echo "✅ 安裝完成，容器已啟動！"
echo "Webhook URL: https://$ZEABUR_URL/webhook"fi

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
