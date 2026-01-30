#!/bin/bash

set -e

echo "=============================="
echo " 🤖 Telegram Gemini Bot 部署器"
echo "=============================="
echo

# ---- 檢查 Docker ----
if ! command -v docker &> /dev/null; then
  echo "❌ 未安裝 Docker，請先安裝 Docker"
  exit 1
fi

# ---- 使用者輸入 ----
read -rp "👉 請輸入 BOT_TOKEN: " BOT_TOKEN
read -rp "👉 請輸入 GEMINI_API_KEY: " GEMINI_API_KEY
read -rp "👉 請輸入 Webhook DOMAIN (不含 https://): " DOMAIN

if [[ -z "$BOT_TOKEN" || -z "$GEMINI_API_KEY" || -z "$DOMAIN" ]]; then
  echo "❌ 有欄位是空的，部署中止"
  exit 1
fi

IMAGE_NAME="tg-gemini-bot"
CONTAINER_NAME="tg-gemini-bot"

echo
echo "📦 建立 Docker 映像..."
docker build -t $IMAGE_NAME .

# ---- 如果容器已存在 ----
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "⚠️ 偵測到舊容器，正在移除..."
  docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
  docker rm $CONTAINER_NAME >/dev/null 2>&1 || true
fi

# ---- 啟動容器 ----
echo "🚀 啟動 Bot..."
docker run -d \
  --name $CONTAINER_NAME \
  -e BOT_TOKEN="$BOT_TOKEN" \
  -e GEMINI_API_KEY="$GEMINI_API_KEY" \
  -e DOMAIN="$DOMAIN" \
  -p 8080:8080 \
  --restart unless-stopped \
  $IMAGE_NAME

echo
echo "✅ 部署完成！"
echo "🌐 Webhook: https://$DOMAIN/webhook"
echo "📦 容器名稱: $CONTAINER_NAME"
echo
echo "👉 查看日誌：docker logs -f $CONTAINER_NAME"