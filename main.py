# main.py
import os
import telebot
import google.generativeai as genai
from flask import Flask, request, abort
import ast
import operator
import time
import requests
import json
import re

BOT_TOKEN = os.getenv("BOT_TOKEN")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

MODEL_POOL = [
    "gemini-1.5-flash",
    "models/gemini-1.5-flash"
]

MAX_CONTEXT = 6

genai.configure(api_key=GEMINI_API_KEY)
bot = telebot.TeleBot(BOT_TOKEN, parse_mode=None)
app = Flask(__name__)

context_cache = {}

# ---------- Hastebin 支持 ----------
HASTEBIN_URL = "https://hastebin.com"

def upload_to_hastebin(text):
    """上傳文本到 hastebin 並返回 URL"""
    try:
        response = requests.post(
            f"{HASTEBIN_URL}/documents",
            data=text.encode('utf-8'),
            timeout=10
        )
        if response.status_code == 200:
            key = response.json()["key"]
            return f"{HASTEBIN_URL}/{key}"
    except Exception as e:
        print(f"Hastebin 上傳失敗: {e}")
    return None

# ---------- 本地數學計算 ----------
SAFE_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Pow: operator.pow,
    ast.USub: operator.neg
}

def safe_eval(expr):
    def _eval(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Num):
            return node.n
        if isinstance(node, ast.BinOp):
            return SAFE_OPS[type(node.op)](_eval(node.left), _eval(node.right))
        if isinstance(node, ast.UnaryOp):
            return SAFE_OPS[type(node.op)](_eval(node.operand))
        raise ValueError("不支援的運算")

    try:
        return _eval(ast.parse(expr, mode='eval').body)
    except:
        raise ValueError("無法解析數學表達式")

# ---------- 智能清理AI回覆 ----------
def clean_ai_response(text):
    """清理AI回覆，修復Markdown格式問題"""
    if not text:
        return text
    
    # 1. 修復常見的Markdown格式問題
    # 修復斜體 *text* -> _text_
    text = re.sub(r'\*(.+?)\*', r'_\1_', text)
    
    # 修復粗體 **text** -> *text*
    text = re.sub(r'\*\*(.+?)\*\*', r'*\1*', text)
    
    # 2. 移除孤立的Markdown標記
    # 移除單獨的星號（前後沒有空格或標點）
    text = re.sub(r'(?<!\s)\*(?!\s)', '', text)
    text = re.sub(r'(?<!\s)_(?!\s)', '', text)
    text = re.sub(r'(?<!\s)`(?!\s)', '', text)
    
    # 3. 修復可能的多重標記
    # 例如 ***text*** -> *text*
    text = re.sub(r'\*{3,}(.+?)\*{3,}', r'*\1*', text)
    text = re.sub(r'_{3,}(.+?)_{3,}', r'_\1_', text)
    
    # 4. 確保代碼塊格式正確
    # 將三個反引號的格式標準化
    text = re.sub(r'```(\w*)\n?(.*?)\n?```', r'```\1\n\2\n```', text, flags=re.DOTALL)
    
    # 5. 清理多餘的空格和換行
    lines = [line.strip() for line in text.split('\n')]
    text = '\n'.join(line for line in lines if line)
    
    return text

# ---------- AI 回覆（自動換模型） ----------
def ai_reply(chat_id, user_text):
    history = context_cache.setdefault(chat_id, [])
    history.append({"role": "user", "parts": [user_text]})
    history[:] = history[-MAX_CONTEXT:]

    for model_name in MODEL_POOL:
        try:
            model = genai.GenerativeModel(model_name)
            
            # 給AI明確的提示，避免使用過多Markdown
            prompt = f"""請用清晰、簡潔的語言回答以下問題。請注意：
1. 盡量使用純文本，避免過多的格式
2. 如果需要強調，可以使用單個星號或下劃線，但不要嵌套使用
3. 代碼請使用三個反引號包裹
4. 避免使用複雜的Markdown格式

問題：{user_text}

回答："""
            
            res = model.generate_content(prompt)
            text = res.text.strip()
            
            # 清理回覆
            cleaned_text = clean_ai_response(text)
            
            history.append({"role": "model", "parts": [cleaned_text]})
            return cleaned_text
        except Exception as e:
            error_msg = str(e).lower()
            if "quota" in error_msg or "429" in error_msg:
                continue
            print(f"Model {model_name} error: {e}")
            return "⚠️ AI 發生錯誤，請稍後再試"
    return "🚫 AI 目前忙線中，請稍後再試"

# ---------- 安全發送訊息 ----------
def safe_reply(msg, text):
    """安全地發送訊息，處理格式問題和長度限制"""
    if not text:
        return
    
    # 清理文本
    text = clean_ai_response(text)
    
    try:
        # Telegram 消息長度限制為 4096 字符
        if len(text) <= 4096:
            bot.reply_to(msg, text, parse_mode='Markdown')
            return
        
        # 如果消息太長，分割發送
        if len(text) <= 10000:
            # 嘗試分割成段落
            parts = []
            current_part = ""
            
            for line in text.split('\n'):
                if len(current_part) + len(line) + 1 < 4000:
                    current_part += line + '\n'
                else:
                    if current_part:
                        parts.append(current_part.strip())
                    current_part = line + '\n'
            
            if current_part:
                parts.append(current_part.strip())
            
            # 發送分割後的消息
            for i, part in enumerate(parts):
                if i == 0:
                    bot.reply_to(msg, part, parse_mode='Markdown')
                else:
                    bot.send_message(msg.chat.id, part, parse_mode='Markdown')
                time.sleep(0.5)  # 避免發送過快
            return
        
        # 如果消息非常長，上傳到 hastebin
        hastebin_url = upload_to_hastebin(text)
        if hastebin_url:
            reply_text = f"📝 回覆過長，已上傳到 hastebin:\n{hastebin_url}"
            bot.reply_to(msg, reply_text)
        else:
            # 上傳失敗，發送前4000字符並提示
            preview = text[:4000] + "\n\n...（完整內容因過長已截斷）"
            bot.reply_to(msg, preview, parse_mode='Markdown')
            
    except Exception as e:
        print(f"發送訊息錯誤: {e}")
        # 嘗試不帶格式發送
        try:
            simple_text = text[:3000].replace('`', '').replace('*', '').replace('_', '')
            bot.reply_to(msg, f"🤖 {simple_text}")
        except:
            bot.reply_to(msg, "⚠️ 訊息發送失敗，請稍後再試")

# ---------- 群組訊息 ----------
@bot.message_handler(content_types=['text'])
def handle_msg(msg):
    if msg.chat.type == "private":
        bot.reply_to(msg, "❌ 本機器人僅在群組中使用，請將我添加到群組中！")
        return

    triggered = False
    text = msg.text.strip()

    # 檢查是否是回覆機器人的訊息
    if msg.reply_to_message and msg.reply_to_message.from_user.id == bot.get_me().id:
        triggered = True

    # 檢查是否@了機器人
    if bot.get_me().username and f"@{bot.get_me().username}" in text:
        text = text.replace(f"@{bot.get_me().username}", "").strip()
        triggered = True

    # 檢查是否直接呼叫機器人（以!或/開頭）
    if text.startswith(('!', '/gemini', '/ai', '/ask')):
        triggered = True
        text = text.lstrip('!/gemini/aiask ')

    if not triggered:
        return

    # 先嘗試數學計算
    try:
        # 只處理純數學表達式（數字和運算符）
        math_chars = set('0123456789+-*/.()^×÷ ')
        cleaned_text = text.replace(' ', '')
        if cleaned_text and all(c in math_chars for c in cleaned_text):
            result = safe_eval(text)
            bot.reply_to(msg, f"🧮 計算結果：{result}")
            return
    except Exception as e:
        pass  # 不是數學表達式，繼續使用AI

    # 使用AI回覆
    typing_msg = bot.reply_to(msg, "🤔 思考中…")
    reply = ai_reply(msg.chat.id, text)
    
    # 刪除"思考中"訊息
    try:
        bot.delete_message(msg.chat.id, typing_msg.message_id)
    except:
        pass
    
    safe_reply(msg, reply)

# ---------- 命令處理 ----------
@bot.message_handler(commands=['start', 'help'])
def send_welcome(msg):
    welcome_text = """🤖 *Gemini AI 機器人*

*使用方式：*
1. 在群組中 @我 + 問題
2. 回覆我的訊息
3. 使用命令 /ask + 問題

*支援功能：*
• AI 對話（多模型自動切換）
• 數學計算（直接輸入數學表達式）
• 上下文記憶（最近6條對話）

*注意：* 本機器人僅在群組中使用"""
    
    if msg.chat.type == "private":
        bot.send_message(msg.chat.id, welcome_text, parse_mode='Markdown')
    else:
        bot.reply_to(msg, welcome_text, parse_mode='Markdown')

@bot.message_handler(commands=['clear'])
def clear_context(msg):
    if msg.chat.id in context_cache:
        del context_cache[msg.chat.id]
        bot.reply_to(msg, "✅ 對話上下文已清除")
    else:
        bot.reply_to(msg, "ℹ️ 沒有對話上下文需要清除")

@bot.message_handler(commands=['status'])
def show_status(msg):
    status_text = f"""📊 *機器人狀態*

*模型池：* {', '.join(MODEL_POOL)}
*上下文長度：* {MAX_CONTEXT} 條消息
*記憶對話數：* {len(context_cache)}
*群組ID：* {msg.chat.id}
"""
    bot.reply_to(msg, status_text, parse_mode='Markdown')

# ---------- Webhook ----------
@app.route("/webhook", methods=["POST"])
def webhook():
    if request.headers.get("content-type") == "application/json":
        json_str = request.get_data().decode('utf-8')
        update = telebot.types.Update.de_json(json_str)
        bot.process_new_updates([update])
        return "ok"
    abort(403)

@app.route("/")
def index():
    return "Telegram Gemini Bot is running!"

@app.route("/setwebhook", methods=["GET"])
def set_webhook():
    """手動設置webhook的端點"""
    try:
        domain = os.getenv("DOMAIN")
        if domain and not domain.startswith(("http://", "https://")):
            domain = f"https://{domain}"
        
        bot.remove_webhook()
        time.sleep(1)
        
        result = bot.set_webhook(
            url=f"{domain}/webhook",
            max_connections=50,
            allowed_updates=["message", "callback_query"]
        )
        
        webhook_info = bot.get_webhook_info()
        
        return {
            "success": result,
            "webhook_url": webhook_info.url,
            "pending_updates": webhook_info.pending_update_count,
            "last_error": webhook_info.last_error_message
        }
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    # 獲取域名，確保是完整的URL
    domain = os.getenv("DOMAIN")
    
    # 確保域名是完整的URL格式
    if domain and not domain.startswith(("http://", "https://")):
        domain = f"https://{domain}"
    
    print(f"設置 webhook 到: {domain}/webhook")
    
    # 移除現有webhook並設置新的
    bot.remove_webhook()
    time.sleep(1)
    
    success = bot.set_webhook(
        url=f"{domain}/webhook",
        max_connections=50,
        allowed_updates=["message", "callback_query"]
    )
    
    print(f"Webhook 設置: {'成功' if success else '失敗'}")
    
    # 啟動Flask應用
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)