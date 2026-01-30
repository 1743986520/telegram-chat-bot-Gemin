# main.py
import os
import telebot
import google.generativeai as genai
from flask import Flask, request, abort
import ast
import operator

BOT_TOKEN = os.getenv("BOT_TOKEN")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

MODEL_POOL = [
    "gemini-3-flash",
    "gemini-2.5-flash",
    "gemini-1.5-flash"
]

MAX_CONTEXT = 6

genai.configure(api_key=GEMINI_API_KEY)
bot = telebot.TeleBot(BOT_TOKEN)
app = Flask(__name__)

context_cache = {}

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
        if isinstance(node, ast.Num):
            return node.n
        if isinstance(node, ast.BinOp):
            return SAFE_OPS[type(node.op)](_eval(node.left), _eval(node.right))
        if isinstance(node, ast.UnaryOp):
            return SAFE_OPS[type(node.op)](_eval(node.operand))
        raise ValueError("不支援的運算")

    return _eval(ast.parse(expr, mode='eval').body)

# ---------- AI 回覆（自動換模型） ----------
def ai_reply(chat_id, user_text):
    history = context_cache.setdefault(chat_id, [])
    history.append({"role": "user", "parts": [user_text]})
    history[:] = history[-MAX_CONTEXT:]

    for model_name in MODEL_POOL:
        try:
            model = genai.GenerativeModel(model_name)
            res = model.generate_content(history)
            text = res.text.strip()
            history.append({"role": "model", "parts": [text]})
            return text
        except Exception as e:
            if "quota" in str(e).lower():
                continue
            return "⚠️ AI 發生錯誤"
    return "🚫 AI 目前忙線中，請稍後再試"

# ---------- 群組訊息 ----------
@bot.message_handler(content_types=['text'])
def handle_msg(msg):
    if msg.chat.type == "private":
        return  # 禁止私聊

    triggered = False
    text = msg.text.strip()

    if msg.reply_to_message and msg.reply_to_message.from_user.id == bot.get_me().id:
        triggered = True

    if f"@{bot.get_me().username}" in text:
        text = text.replace(f"@{bot.get_me().username}", "").strip()
        triggered = True

    if not triggered:
        return

    # 本地數學
    try:
        result = safe_eval(text)
        bot.reply_to(msg, f"🧮 結果：{result}")
        return
    except:
        pass

    bot.reply_to(msg, "🤔 思考中…")
    reply = ai_reply(msg.chat.id, text)
    bot.reply_to(msg, reply)

# ---------- Webhook ----------
@app.route("/webhook", methods=["POST"])
def webhook():
    if request.headers.get("content-type") == "application/json":
        update = telebot.types.Update.de_json(request.data.decode())
        bot.process_new_updates([update])
        return "ok"
    abort(403)

@app.route("/")
def index():
    return "Bot running"

if __name__ == "__main__":
    bot.remove_webhook()
    domain = os.getenv("DOMAIN")
    bot.set_webhook(url=f"https://{domain}/webhook")
    app.run(host="0.0.0.0", port=8080)