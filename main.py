import telebot
import google.generativeai as genai
from flask import Flask, request, abort
from apscheduler.schedulers.background import BackgroundScheduler
import datetime
import os
import pytz

# === Token 和 Key ===
BOT_TOKEN = os.getenv('BOT_TOKEN'）

GEMINI_API_KEY = os.getenv('GEMINI_API_KEY')

# 初始化 Gemini
genai.configure(api_key=GEMINI_API_KEY)
model = genai.GenerativeModel('gemini-3-flash')

bot = telebot.TeleBot(BOT_TOKEN)
app = Flask(__name__)

ADMIN_USER_ID = None

# 排程器（台灣時區）
scheduler = BackgroundScheduler(timezone=pytz.timezone('Asia/Taipei'))
scheduler.start()

# 儲存排程任務
scheduled_tasks = []

# 儲存 Bot 所在的群組（自動記錄，給編號）
group_list = {}  # {chat_id: {'title': str, 'number': int}}

# AI 開關
ai_enabled = True

def ai_response(user_message):
    if not ai_enabled:
        return None
    try:
        response = model.generate_content(user_message)
        return response.text.strip() if response.text else "（AI 沒話說，再試一次～）"
    except Exception as e:
        return f"AI 出問題：{str(e)}"

# 自動記錄 Bot 被加入的群組
@bot.message_handler(content_types=['group_chat_created', 'supergroup_chat_created', 'new_chat_members'])
def handle_new_group(message):
    global group_list
    if message.chat.type in ['group', 'supergroup']:
        chat_id = message.chat.id
        title = message.chat.title or "未知群組"
        if chat_id not in group_list:
            number = len(group_list) + 1
            group_list[chat_id] = {'title': title, 'number': number}
            # 可選：發歡迎訊息
            # bot.send_message(chat_id, f"帝ACG AI 已加入！群組編號：{number}\n管理員私聊我用 /groups 查看")

@bot.message_handler(content_types=['text'])
def handle_text(message):
    global ADMIN_USER_ID, scheduled_tasks, ai_enabled, group_list

    # 自動更新群組名稱（如果改名）
    if message.chat.type in ['group', 'supergroup']:
        chat_id = message.chat.id
        title = message.chat.title or "未知群組"
        if chat_id in group_list:
            group_list[chat_id]['title'] = title
        else:
            # 新群組自動加入
            number = len(group_list) + 1
            group_list[chat_id] = {'title': title, 'number': number}

    # 自動設定管理員
    if ADMIN_USER_ID is None and message.chat.type == 'private':
        ADMIN_USER_ID = message.from_user.id
        bot.reply_to(message, f"🎉 歡迎使用帝ACG AI！\n你是管理員（ID：{ADMIN_USER_ID}）\n發 /help 查看指令～")

    # 群組 AI 觸發（所有人一樣規則）
    if message.chat.type in ['group', 'supergroup'] and ai_enabled:
        triggered = False
        user_input = message.text
        if message.entities:
            for entity in message.entities:
                if entity.type == 'mention':
                    mention_text = message.text[entity.offset:entity.offset + entity.length]
                    bot_username = f"@{bot.get_me().username}"
                    if mention_text.lower() == bot_username.lower():
                        user_input = message.text.replace(mention_text, '').strip() or "(只提到我)"
                        triggered = True
                        break
        if message.reply_to_message and message.reply_to_message.from_user.is_bot:
            if message.reply_to_message.from_user.id == bot.get_me().id:
                triggered = True
        if triggered:
            bot.reply_to(message, "🤔 思考中⋯")
            response = ai_response(user_input)
            if response:
                bot.reply_to(message, response)
        return

    # 私聊處理
    if message.chat.type == 'private':
        if message.from_user.id == ADMIN_USER_ID:
            text = message.text.strip()

            if text in ['/help', '/start']:
                help_msg = f"""
🤖 **帝ACG AI 使用說明**（2026 版）

**一般功能**：
• 群組 @我 或回覆我 → Gemini AI 回覆
• 私聊我 → 直接聊天

**管理員指令**：
/groups → 查看我所在的所有群組 + 編號
/schedule <群組編號> YYYY-MM-DD HH:MM 訊息內容 → 定時發到指定群組（台灣時間）
  範例：/schedule 1 2026-01-02 09:00 早安大家！

/schedules → 查看所有排程
/cancel 編號 → 取消排程
/enable /disable → AI 開關
/help → 這份說明

**AI 狀態**：{"🟢 開啟" if ai_enabled else "🔴 關閉"}
                """
                bot.reply_to(message, help_msg, parse_mode='Markdown')
                return

            if text == '/groups':
                if not group_list:
                    bot.reply_to(message, "📭 我目前還沒被加進任何群組")
                    return
                msg = "📋 我目前在這些群組（編號用來定時發訊息）:\n\n"
                for chat_id, info in sorted(group_list.items(), key=lambda x: x[1]['number']):
                    msg += f"{info['number']}. {info['title']} (ID: {chat_id})\n"
                bot.reply_to(message, msg)
                return

            if text == '/schedules':
                if not scheduled_tasks:
                    bot.reply_to(message, "📭 目前沒有任何排程")
                    return
                msg = "📅 已設定的排程（台灣時間）:\n\n"
                for i, task in enumerate(scheduled_tasks):
                    group_name = group_list.get(task['chat_id'], {}).get('title', '未知群組')
                    msg += f"{i+1}. [{group_name}] {task['time'].strftime('%Y-%m-%d %H:%M')}\n   內容：{task['msg']}\n\n"
                bot.reply_to(message, msg)
                return

            if text == '/enable':
                ai_enabled = True
                bot.reply_to(message, "🔊 AI 回答已開啟")
                return

            if text == '/disable':
                ai_enabled = False
                bot.reply_to(message, "🔇 AI 回答已關閉")
                return

            if text.startswith('/cancel'):
                # 同之前
                parts = text.split(' ')
                if len(parts) != 2 or not parts[1].isdigit():
                    bot.reply_to(message, "❌ 用法：/cancel 編號")
                    return
                idx = int(parts[1]) - 1
                if 0 <= idx < len(scheduled_tasks):
                    job_id = scheduled_tasks[idx]['id']
                    scheduler.remove_job(job_id)
                    del scheduled_tasks[idx]
                    bot.reply_to(message, f"✅ 已取消第 {idx+1} 個排程")
                else:
                    bot.reply_to(message, "❌ 編號不存在")
                return

            if text.startswith('/schedule'):
                parts = text.split(' ', 4)
                if len(parts) >= 5:
                    try:
                        group_num = int(parts[1])
                        time_str = f"{parts[2]} {parts[3]}"
                        msg_content = parts[4]
                    except ValueError:
                        bot.reply_to(message, "❌ 群組編號必須是數字！")
                        return

                    # 找對應 chat_id
                    target_chat_id = None
                    for cid, info in group_list.items():
                        if info['number'] == group_num:
                            target_chat_id = cid
                            break
                    if not target_chat_id:
                        bot.reply_to(message, f"❌ 找不到編號 {group_num} 的群組！用 /groups 查看")
                        return

                    try:
                        taiwan_tz = pytz.timezone('Asia/Taipei')
                        send_time = taiwan_tz.localize(datetime.datetime.strptime(time_str, "%Y-%m-%d %H:%M"))
                        if send_time < datetime.datetime.now(taiwan_tz):
                            bot.reply_to(message, "❌ 時間不能是過去的喔！")
                            return
                        job = scheduler.add_job(
                            func=lambda cid=target_chat_id, msg=msg_content: bot.send_message(cid, f"🕐 【定時訊息】\n{msg}"),
                            trigger='date',
                            run_date=send_time
                        )
                        group_name = group_list[target_chat_id]['title']
                        scheduled_tasks.append({
                            'id': job.id,
                            'time': send_time,
                            'msg': msg_content,
                            'chat_id': target_chat_id
                        })
                        bot.reply_to(message, f"✅ 已成功排程！\n群組：{group_name} (編號 {group_num})\n台灣時間：{time_str}\n內容：{msg_content}")
                    except ValueError:
                        bot.reply_to(message, "❌ 時間格式錯誤！正確格式：YYYY-MM-DD HH:MM")
                else:
                    bot.reply_to(message, "📌 用法：/schedule <群組編號> YYYY-MM-DD HH:MM 訊息內容\n先用 /groups 看編號")
                return

        # 私聊 AI（所有人可用）
        if ai_enabled:
            bot.reply_to(message, "🤔 思考中⋯")
            response = ai_response(message.text)
            if response:
                bot.reply_to(message, response)

# 其餘 Webhook 部分不變
@app.route('/webhook', methods=['POST'])
def webhook():
    if request.headers.get('content-type') == 'application/json':
        json_string = request.get_data().decode('utf-8')
        update = telebot.types.Update.de_json(json_string)
        bot.process_new_updates([update])
        return '', 200
    abort(403)

@app.route('/')
def index():
    return "TG_bot is running"

if __name__ == '__main__':
    bot.remove_webhook()
    domain = os.getenv('ZEABUR_URL', 'telegram-bot-ai.xn--acg-4i2f.xyz')
    bot.set_webhook(url=f"https://{domain}/webhook")
    print(f"Webhook 已設定：https://{domain}/webhook")
    app.run(host='0.0.0.0', port=8080)