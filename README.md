# Telegram Gemini AI 機器人 🤖

一個基於 Google Gemini AI 的 Telegram 群組聊天機器人，支援數學計算和智能對話。

## ✨ 功能特色

- 🤖 支援多個 Gemini 模型自動切換
- 🧮 內建數學表達式計算
- 💬 上下文記憶（最近6條對話）
- 🔗 支援 Webhook 模式
- 📝 長訊息自動上傳到 Hastebin
- 🛡️ 自動修復 Markdown 格式問題
- 🌐 自動處理 IPv6 問題

## 🚀 快速部署

### 方法一：使用安裝腳本（推薦）

```bash
# 下載安裝腳本
curl -L -o install.sh https://raw.githubusercontent.com/1743986520/telegram-chat-bot-Gemin/main/main.sh
chmod +x install.sh

# 執行安裝（需要root權限）
sudo ./install.sh