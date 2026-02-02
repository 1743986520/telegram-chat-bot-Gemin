# main.py - 智能適配版
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
import socket
import logging
import sys
import random
from datetime import datetime

# ========== 智能環境檢測 ==========
def detect_environment():
    """檢測運行環境"""
    env_info = {
        "ipv4": False,
        "ipv6": False,
        "docker": False,
        "cloud": False,
        "public_ip": None,
        "local_ip": None
    }
    
    try:
        # 檢測IPv4
        s4 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s4.connect(("8.8.8.8", 80))
            env_info["local_ip"] = s4.getsockname()[0]
            env_info["ipv4"] = True
        except:
            pass
        finally:
            s4.close()
        
        # 檢測IPv6
        try:
            s6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
            try:
                s6.connect(("2001:4860:4860::8888", 80))
                env_info["ipv6"] = True
            except:
                pass
            finally:
                s6.close()
        except:
            pass
        
        # 檢測Docker
        env_info["docker"] = os.path.exists("/.dockerenv")
        
        # 檢測雲環境
        cloud_indicators = [
            "/proc/1/cgroup",  # Docker/cgroups
            "/sys/hypervisor/",  # AWS
            "/sys/class/dmi/id/chassis_vendor",  # 雲供應商
        ]
        for indicator in cloud_indicators:
            if os.path.exists(indicator):
                env_info["cloud"] = True
                break
        
        # 獲取公網IP
        try:
            # 嘗試多個IP查詢服務
            ip_services = [
                "https://api.ipify.org?format=json",
                "https://icanhazip.com",
                "https://ifconfig.me/ip",
                "https://checkip.amazonaws.com"
            ]
            
            for service in ip_services:
                try:
                    response = requests.get(service, timeout=3)
                    if response.status_code == 200:
                        if service.endswith("json"):
                            env_info["public_ip"] = response.json().get("ip", "").strip()
                        else:
                            env_info["public_ip"] = response.text.strip()
                        if env_info["public_ip"]:
                            break
                except:
                    continue
        except:
            pass
        
    except Exception as e:
        logging.warning(f"環境檢測失敗: {e}")
    
    return env_info

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

# 智能加載環境變數
def load_config():
    """智能加載配置"""
    config = {
        "BOT_TOKEN": None,
        "GEMINI_API_KEY": None,
        "DOMAIN": None,
        "PORT": 8080
    }
    
    # 優先級1: 環境變數
    for key in config:
        config[key] = os.getenv(key)
    
    # 優先級2: .env文件
    if not config["BOT_TOKEN"] or not config["GEMINI_API_KEY"]:
        env_files = ['.env', 'config.env', '/etc/telegram-bot/env']
        for env_file in env_files:
            if os.path.exists(env_file):
                try:
                    with open(env_file, 'r', encoding='utf-8') as f:
                        for line in f:
                            line = line.strip()
                            if line and not line.startswith('#'):
                                if '=' in line:
                                    key, value = line.split('=', 1)
                                    key = key.strip()
                                    value = value.strip().strip('"\'')
                                    if key in config:
                                        config[key] = value
                    logger.info(f"從 {env_file} 加載配置")
                    break
                except Exception as e:
                    logger.warning(f"讀取 {env_file} 失敗: {e}")
    
    # 優先級3: 命令行參數
    import argparse
    parser = argparse.ArgumentParser(description='Telegram Gemini Bot')
    parser.add_argument('--token', help='Bot Token')
    parser.add_argument('--key', help='Gemini API Key')
    parser.add_argument('--domain', help='Webhook Domain')
    parser.add_argument('--port', type=int, default=8080, help='Port')
    args = parser.parse_args()
    
    if args.token: config["BOT_TOKEN"] = args.token
    if args.key: config["GEMINI_API_KEY"] = args.key
    if args.domain: config["DOMAIN"] = args.domain
    if args.port: config["PORT"] = args.port
    
    return config

# 加載配置
config = load_config()
BOT_TOKEN = config["BOT_TOKEN"]
GEMINI_API_KEY = config["GEMINI_API_KEY"]
DOMAIN = config["DOMAIN"]
PORT = config["PORT"]

# 檢查必要配置
if not BOT_TOKEN:
    logger.error("❌ BOT_TOKEN 未設置")
    logger.info("設置方法:")
    logger.info("1. 環境變數: export BOT_TOKEN=your_token")
    logger.info("2. .env文件: BOT_TOKEN=your_token")
    logger.info("3. 命令行: python main.py --token your_token")
    sys.exit(1)

if not GEMINI_API_KEY:
    logger.error("❌ GEMINI_API_KEY 未設置")
    logger.info("獲取地址: https://makersuite.google.com/app/apikey")
    sys.exit(1)

# ========== 初始化 ==========
MODEL_POOL = [
    "gemini-1.5-flash",
    "models/gemini-1.5-flash",
    "gemini-1.5-pro"
]

MAX_CONTEXT = 6
MAX_RETRIES = 3

# 初始化AI
try:
    genai.configure(api_key=GEMINI_API_KEY)
    bot = telebot.TeleBot(BOT_TOKEN, parse_mode=None)
    app = Flask(__name__)
except Exception as e:
    logger.error(f"初始化失敗: {e}")
    sys.exit(1)

context_cache = {}
user_cooldown = {}  # 用戶冷卻時間

# ========== 工具函數 ==========
class NetworkUtils:
    @staticmethod
    def get_public_ip():
        """獲取公網IP（支持IPv4/IPv6）"""
        services = [
            ("https://api64.ipify.org?format=json", True),  # 支持IPv6
            ("https://api.ipify.org?format=json", False),   # IPv4
            ("https://icanhazip.com", False),
            ("https://ifconfig.me/ip", False)
        ]
        
        for url, prefer_ipv6 in services:
            try:
                if prefer_ipv6:
                    # 嘗試IPv6優先
                    response = requests.get(url, timeout=3)
                else:
                    response = requests.get(url, timeout=3)
                
                if response.status_code == 200:
                    if url.endswith("json"):
                        return response.json().get("ip", "").strip()
                    else:
                        return response.text.strip()
            except:
                continue
        
        return None
    
    @staticmethod
    def check_port(port):
        """檢查端口是否可用"""
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.bind(("0.0.0.0", port))
            return True
        except:
            return False
        finally:
            sock.close()
    
    @staticmethod
    def resolve_domain(domain):
        """解析域名獲取IP地址"""
        try:
            import socket
            # 獲取所有IP地址
            info = socket.getaddrinfo(domain, None)
            ips = []
            for result in info:
                ips.append(result[4][0])
            return list(set(ips))
        except:
            return []

class SecurityUtils:
    @staticmethod
    def is_safe_input(text):
        """檢查輸入是否安全"""
        # 防止過長輸入
        if len(text) > 2000:
            return False
        
        # 防止特殊攻擊
        dangerous_patterns = [
            r"<script.*?>",
            r"javascript:",
            r"onload=",
            r"onerror=",
            r"eval\(",
            r"alert\(",
            r"document\.cookie"
        ]
        
        for pattern in dangerous_patterns:
            if re.search(pattern, text, re.IGNORECASE):
                return False
        
        return True
    
    @staticmethod
    def sanitize_text(text):
        """清理文本"""
        if not text:
            return ""
        
        # 移除危險字符
        text = re.sub(r'[<>]', '', text)
        text = re.sub(r'javascript:', '', text, flags=re.IGNORECASE)
        
        # 限制長度
        if len(text) > 5000:
            text = text[:5000] + "...[截斷]"
        
        return text

# ========== 數學計算 ==========
class MathCalculator:
    SAFE_OPS = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
        ast.Pow: operator.pow,
        ast.USub: operator.neg,
        ast.FloorDiv: operator.floordiv,
        ast.Mod: operator.mod
    }
    
    @classmethod
    def safe_eval(cls, expr):
        """安全計算數學表達式"""
        try:
            # 清理表達式
            expr = expr.replace('^', '**').replace('×', '*').replace('÷', '/')
            
            # 解析和計算
            tree = ast.parse(expr, mode='eval')
            
            def _eval(node):
                if isinstance(node, ast.Constant):
                    return node.value
                elif isinstance(node, ast.Num):
                    return node.n
                elif isinstance(node, ast.BinOp):
                    return cls.SAFE_OPS[type(node.op)](_eval(node.left), _eval(node.right))
                elif isinstance(node, ast.UnaryOp):
                    return cls.SAFE_OPS[type(node.op)](_eval(node.operand))
                elif isinstance(node, ast.Name):
                    # 支持簡單的常量
                    if node.id == 'pi':
                        return 3.141592653589793
                    elif node.id == 'e':
                        return 2.718281828459045
                    else:
                        raise ValueError(f"未知變量: {node.id}")
                else:
                    raise ValueError("不支援的運算")
            
            result = _eval(tree.body)
            
            # 格式化結果
            if isinstance(result, float):
                if result.is_integer():
                    result = int(result)
                else:
                    # 保留6位小數
                    result = round(result, 6)
            
            return str(result)
            
        except Exception as e:
            raise ValueError(f"計算錯誤: {str(e)}")

# ========== AI 服務 ==========
class AIService:
    def __init__(self, api_key):
        self.api_key = api_key
        self.models = MODEL_POOL
        self.current_model_index = 0
        
    def get_response(self, prompt, chat_id=None):
        """獲取AI回應"""
        for attempt in range(MAX_RETRIES):
            try:
                model_name = self.models[self.current_model_index]
                model = genai.GenerativeModel(model_name)
                
                # 優化提示詞
                optimized_prompt = f"""請用中文回答以下問題。注意：
1. 保持回答簡潔明了
2. 使用自然的對話語氣
3. 如果需要強調，可以使用*強調*或_斜體_
4. 代碼請使用```包裹
5. 避免使用複雜的Markdown

問題：{prompt}

請回答："""
                
                response = model.generate_content(
                    optimized_prompt,
                    generation_config={
                        "temperature": 0.7,
                        "top_p": 0.9,
                        "top_k": 40,
                        "max_output_tokens": 2000,
                    }
                )
                
                text = response.text.strip()
                
                # 清理回應
                text = self.clean_response(text)
                
                # 切換到下一個模型（循環）
                self.current_model_index = (self.current_model_index + 1) % len(self.models)
                
                return text
                
            except Exception as e:
                error_msg = str(e).lower()
                
                if "quota" in error_msg or "429" in error_msg:
                    logger.warning(f"模型配額不足，嘗試下一個模型")
                    self.current_model_index = (self.current_model_index + 1) % len(self.models)
                    time.sleep(1)
                    continue
                elif "unavailable" in error_msg or "500" in error_msg:
                    logger.warning(f"模型暫時不可用")
                    time.sleep(2)
                    continue
                else:
                    logger.error(f"AI錯誤: {e}")
                    
                if attempt == MAX_RETRIES - 1:
                    return "抱歉，AI服務暫時不可用，請稍後再試。"
    
    @staticmethod
    def clean_response(text):
        """清理AI回應"""
        if not text:
            return ""
        
        # 移除多餘的換行
        lines = [line.strip() for line in text.split('\n') if line.strip()]
        text = '\n'.join(lines)
        
        # 修復常見的Markdown問題
        text = re.sub(r'\*\*(.+?)\*\*', r'*\1*', text)  # **粗體** -> *粗體*
        text = re.sub(r'\*{3,}', '*', text)  # 多個* -> 單個*
        
        # 確保代碼塊正確
        code_blocks = re.findall(r'```[a-z]*\n.*?\n```', text, re.DOTALL)
        for block in code_blocks:
            cleaned = re.sub(r'\n{3,}', '\n\n', block)
            text = text.replace(block, cleaned)
        
        return text

# ========== 消息處理 ==========
class MessageHandler:
    def __init__(self, bot, ai_service):
        self.bot = bot
        self.ai = ai_service
        self.cooldown_time = 3  # 冷卻時間（秒）
    
    def should_respond(self, msg):
        """檢查是否應該回應"""
        chat_id = msg.chat.id
        user_id = msg.from_user.id if msg.from_user else 0
        
        # 檢查私聊
        if msg.chat.type == "private":
            return False, "本機器人僅在群組中使用，請將我添加到群組中！"
        
        # 檢查冷卻
        current_time = time.time()
        if chat_id in user_cooldown:
            last_time = user_cooldown[chat_id]
            if current_time - last_time < self.cooldown_time:
                return False, f"請等待 {int(self.cooldown_time - (current_time - last_time))} 秒後再試"
        
        # 檢查觸發條件
        text = msg.text.strip()
        triggered = False
        
        # 1. 回復機器人
        if msg.reply_to_message and msg.reply_to_message.from_user.id == self.bot.get_me().id:
            triggered = True
        
        # 2. @機器人
        bot_username = self.bot.get_me().username
        if bot_username and f"@{bot_username}" in text:
            text = text.replace(f"@{bot_username}", "").strip()
            triggered = True
        
        # 3. 命令觸發
        triggers = ['!', '/ask', '/ai', '/gemini', '??']
        for trigger in triggers:
            if text.startswith(trigger):
                text = text[len(trigger):].strip()
                triggered = True
                break
        
        # 4. 關鍵詞觸發（可選）
        keywords = ['機器人', 'bot', 'ai', '幫忙', '請問']
        if any(keyword in text.lower() for keyword in keywords):
            triggered = True
        
        if not triggered:
            return False, None
        
        # 更新冷卻時間
        user_cooldown[chat_id] = current_time
        
        return True, text
    
    def process_message(self, msg):
        """處理消息"""
        should_respond, text = self.should_respond(msg)
        
        if not should_respond:
            if text:  # 有錯誤消息
                self.bot.reply_to(msg, text)
            return
        
        # 安全檢查
        if not SecurityUtils.is_safe_input(text):
            self.bot.reply_to(msg, "⚠️ 輸入內容不安全，請勿嘗試注入攻擊")
            return
        
        # 清理文本
        text = SecurityUtils.sanitize_text(text)
        
        # 嘗試數學計算
        if self.is_math_expression(text):
            try:
                result = MathCalculator.safe_eval(text)
                self.bot.reply_to(msg, f"🧮 計算結果: {result}")
                return
            except:
                pass  # 不是數學表達式，繼續AI處理
        
        # 顯示"思考中"
        thinking_msg = self.bot.reply_to(msg, "🤔 思考中...")
        
        # 獲取AI回應
        response = self.ai.get_response(text, msg.chat.id)
        
        # 刪除"思考中"消息
        try:
            self.bot.delete_message(msg.chat.id, thinking_msg.message_id)
        except:
            pass
        
        # 發送回應
        self.send_safe_reply(msg, response)
    
    @staticmethod
    def is_math_expression(text):
        """檢查是否為數學表達式"""
        # 移除空格
        clean_text = text.replace(' ', '')
        
        # 檢查是否包含數學運算符
        math_chars = set('0123456789+-*/.()^×÷%πe ')
        if not clean_text:
            return False
        
        # 至少包含一個運算符和數字
        has_operator = any(c in '+-*/.^×÷%' for c in clean_text)
        has_number = any(c.isdigit() for c in clean_text)
        
        return has_operator and has_number and all(c in math_chars for c in clean_text)
    
    def send_safe_reply(self, msg, text):
        """安全發送回應"""
        if not text:
            return
        
        # 分割長消息
        if len(text) <= 4000:
            try:
                self.bot.reply_to(msg, text, parse_mode='Markdown')
            except:
                # 如果Markdown失敗，嘗試純文本
                try:
                    self.bot.reply_to(msg, text)
                except Exception as e:
                    logger.error(f"發送消息失敗: {e}")
                    self.bot.reply_to(msg, "抱歉，消息發送出錯")
        else:
            # 長消息處理
            parts = [text[i:i+4000] for i in range(0, len(text), 4000)]
            for i, part in enumerate(parts):
                try:
                    if i == 0:
                        self.bot.reply_to(msg, part + "\n\n(第1部分)")
                    else:
                        self.bot.send_message(msg.chat.id, f"(第{i+1}部分)\n\n{part}")
                    time.sleep(0.5)
                except:
                    pass

# ========== Webhook 管理 ==========
class WebhookManager:
    def __init__(self, bot, domain):
        self.bot = bot
        self.domain = domain
        self.env_info = detect_environment()
    
    def setup_webhook(self):
        """智能設置webhook"""
        if not self.domain:
            logger.warning("未設置DOMAIN，跳過webhook設置")
            return False
        
        try:
            # 等待避免API限制
            time.sleep(5)
            
            # 移除現有webhook
            self.bot.remove_webhook()
            time.sleep(2)
            
            # 構建webhook URL
            if not self.domain.startswith(("http://", "https://")):
                webhook_url = f"https://{self.domain}/webhook"
            else:
                webhook_url = f"{self.domain}/webhook"
            
            logger.info(f"設置webhook到: {webhook_url}")
            
            # 根據環境選擇策略
            webhook_params = {
                "url": webhook_url,
                "max_connections": 40,
                "allowed_updates": ["message", "callback_query"],
                "drop_pending_updates": True
            }
            
            # IPv6-only環境特殊處理
            if self.env_info["ipv6"] and not self.env_info["ipv4"]:
                logger.warning("檢測到IPv6-only環境，嘗試特殊配置")
                
                # 嘗試獲取公網IP
                public_ip = NetworkUtils.get_public_ip()
                if public_ip and ':' not in public_ip:  # IPv4地址
                    webhook_params["ip_address"] = public_ip
                    logger.info(f"使用IPv4地址: {public_ip}")
                else:
                    logger.warning("無法獲取IPv4地址，嘗試不使用ip_address參數")
            
            # 設置webhook
            for attempt in range(3):
                try:
                    success = self.bot.set_webhook(**webhook_params)
                    
                    if success:
                        logger.info("✅ Webhook設置成功")
                        
                        # 驗證webhook
                        time.sleep(2)
                        webhook_info = self.bot.get_webhook_info()
                        logger.info(f"Webhook信息: {webhook_info.url}")
                        logger.info(f"待處理更新: {webhook_info.pending_update_count}")
                        
                        return True
                    else:
                        logger.warning("Webhook設置失敗，重試...")
                        time.sleep(3)
                        
                except Exception as e:
                    error_msg = str(e)
                    if "429" in error_msg:
                        wait_time = 10 * (attempt + 1)
                        logger.warning(f"API限制，等待{wait_time}秒")
                        time.sleep(wait_time)
                    else:
                        logger.error(f"設置webhook錯誤: {e}")
                        break
            
            logger.error("❌ Webhook設置失敗")
            return False
            
        except Exception as e:
            logger.error(f"Webhook設置過程出錯: {e}")
            return False
    
    def get_webhook_info(self):
        """獲取webhook信息"""
        try:
            return self.bot.get_webhook_info()
        except:
            return None

# ========== Flask 路由 ==========
# 初始化服務
ai_service = AIService(GEMINI_API_KEY)
message_handler = MessageHandler(bot, ai_service)
webhook_manager = WebhookManager(bot, DOMAIN)

@app.route("/")
def index():
    """首頁"""
    env_info = detect_environment()
    
    info = {
        "status": "running",
        "timestamp": datetime.now().isoformat(),
        "environment": env_info,
        "config": {
            "has_token": bool(BOT_TOKEN),
            "has_key": bool(GEMINI_API_KEY),
            "domain": DOMAIN,
            "port": PORT
        }
    }
    
    return json.dumps(info, indent=2, ensure_ascii=False)

@app.route("/health")
def health():
    """健康檢查"""
    return json.dumps({"status": "healthy", "time": datetime.now().isoformat()})

@app.route("/webhook", methods=["POST"])
def webhook():
    """Telegram webhook"""
    if request.headers.get("content-type") == "application/json":
        try:
            json_str = request.get_data().decode('utf-8')
            update = telebot.types.Update.de_json(json_str)
            bot.process_new_updates([update])
            return "ok"
        except Exception as e:
            logger.error(f"處理webhook錯誤: {e}")
            return "error", 500
    abort(403)

@app.route("/setwebhook", methods=["GET", "POST"])
def set_webhook():
    """手動設置webhook"""
    try:
        success = webhook_manager.setup_webhook()
        info = webhook_manager.get_webhook_info()
        
        response = {
            "success": success,
            "timestamp": datetime.now().isoformat(),
            "webhook_info": {
                "url": info.url if info else None,
                "pending_updates": info.pending_update_count if info else 0,
                "last_error": info.last_error_message if info else None
            },
            "environment": detect_environment()
        }
        
        return json.dumps(response, indent=2, ensure_ascii=False)
        
    except Exception as e:
        return json.dumps({"error": str(e)}, indent=2)

@app.route("/clearwebhook", methods=["GET"])
def clear_webhook():
    """清除webhook"""
    try:
        result = bot.remove_webhook()
        return json.dumps({"success": result, "message": "Webhook已清除"})
    except Exception as e:
        return json.dumps({"error": str(e)})

@app.route("/sendtest", methods=["GET"])
def send_test():
    """發送測試消息（僅管理員）"""
    try:
        # 簡單的權限檢查
        auth = request.args.get("auth")
        if auth != "test123":
            return "未授權", 403
        
        chat_id = request.args.get("chat_id")
        if not chat_id:
            return "缺少chat_id", 400
        
        bot.send_message(chat_id, "🤖 測試消息: 機器人運行正常!")
        return "測試消息已發送"
    except Exception as e:
        return str(e), 500

# ========== Telegram 命令處理 ==========
@bot.message_handler(commands=['start', 'help', '幫助'])
def send_help(msg):
    """幫助命令"""
    help_text = """🤖 *Telegram Gemini AI 機器人*

*使用方法:*
• 在群組中 @我 + 問題
• 回覆我的消息進行對話
• 使用命令 /ask + 問題
• 直接輸入數學表達式計算

*可用命令:*
/start, /help - 顯示此幫助
/status - 查看機器人狀態
/clear - 清除對話歷史
/test - 測試AI回應
/math 2+2 - 數學計算

*注意事項:*
• 本機器人僅在群組中工作
• 支持上下文記憶（最近6條）
• 自動處理長消息
• 內置數學計算器

*開發者:*
@yourusername (修改為你的用戶名)"""
    
    bot.reply_to(msg, help_text, parse_mode='Markdown')

@bot.message_handler(commands=['status', '狀態'])
def send_status(msg):
    """狀態命令"""
    env_info = detect_environment()
    
    status_text = f"""📊 *機器人狀態*

*基本信息:*
• 運行時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
• 對話緩存: {len(context_cache)} 個聊天
• 當前模型: {MODEL_POOL[ai_service.current_model_index]}

*網絡環境:*
• IPv4: {'✅ 可用' if env_info['ipv4'] else '❌ 不可用'}
• IPv6: {'✅ 可用' if env_info['ipv6'] else '❌ 不可用'}
• 公網IP: {env_info['public_ip'] or '未知'}
• Docker: {'✅ 是' if env_info['docker'] else '❌ 否'}

*配置信息:*
• Webhook域名: {DOMAIN or '未設置'}
• 服務端口: {PORT}
• 冷卻時間: {message_handler.cooldown_time}秒"""
    
    bot.reply_to(msg, status_text, parse_mode='Markdown')

@bot.message_handler(commands=['clear', '清除'])
def clear_history(msg):
    """清除歷史"""
    chat_id = msg.chat.id
    if chat_id in context_cache:
        del context_cache[chat_id]
        bot.reply_to(msg, "✅ 對話歷史已清除")
    else:
        bot.reply_to(msg, "ℹ️ 沒有對話歷史需要清除")

@bot.message_handler(commands=['test', '測試'])
def test_ai(msg):
    """測試AI"""
    test_prompts = [
        "你好！請介紹一下你自己",
        "今天天氣如何？",
        "講一個笑話",
        "什麼是人工智能？"
    ]
    
    prompt = random.choice(test_prompts)
    thinking = bot.reply_to(msg, f"🧪 測試中: {prompt}")
    
    response = ai_service.get_response(prompt, msg.chat.id)
    
    try:
        bot.delete_message(msg.chat.id, thinking.message_id)
    except:
        pass
    
    bot.reply_to(msg, f"*測試問題:* {prompt}\n\n*AI回應:* {response}", parse_mode='Markdown')

@bot.message_handler(commands=['math', '計算'])
def calculate_math(msg):
    """數學計算命令"""
    try:
        # 提取表達式
        text = msg.text.strip()
        parts = text.split(' ', 1)
        if len(parts) < 2:
            bot.reply_to(msg, "用法: /math 表達式\n例如: /math 2+2*3")
            return
        
        expression = parts[1].strip()
        result = MathCalculator.safe_eval(expression)
        
        bot.reply_to(msg, f"🧮 計算: `{expression}`\n\n結果: **{result}**", parse_mode='Markdown')
        
    except ValueError as e:
        bot.reply_to(msg, f"❌ 計算錯誤: {str(e)}")
    except Exception as e:
        bot.reply_to(msg, f"❌ 發生錯誤: {str(e)}")

@bot.message_handler(func=lambda message: True)
def handle_all_messages(msg):
    """處理所有消息"""
    try:
        message_handler.process_message(msg)
    except Exception as e:
        logger.error(f"處理消息錯誤: {e}")
        try:
            bot.reply_to(msg, "⚠️ 處理消息時出錯，請稍後再試")
        except:
            pass

# ========== 主程序 ==========
def main():
    """主程序入口"""
    logger.info("=" * 50)
    logger.info("🚀 啟動 Telegram Gemini Bot")
    logger.info("=" * 50)
    
    # 顯示配置信息（安全）
    logger.info(f"BOT_TOKEN: {'*' * len(BOT_TOKEN) if BOT_TOKEN else '未設置'}")
    logger.info(f"GEMINI_API_KEY: {'*' * len(GEMINI_API_KEY) if GEMINI_API_KEY else '未設置'}")
    logger.info(f"DOMAIN: {DOMAIN or '未設置'}")
    logger.info(f"PORT: {PORT}")
    
    # 檢測環境
    env_info = detect_environment()
    logger.info(f"環境檢測: IPv4={env_info['ipv4']}, IPv6={env_info['ipv6']}, Docker={env_info['docker']}")
    logger.info(f"公網IP: {env_info['public_ip'] or '未知'}")
    
    # 檢查端口
    if not NetworkUtils.check_port(PORT):
        logger.warning(f"端口 {PORT} 可能被佔用，嘗試使用其他端口")
        for alt_port in [8081, 8088, 8888, 3000]:
            if NetworkUtils.check_port(alt_port):
                PORT = alt_port
                logger.info(f"改用端口: {PORT}")
                break
    
    # 設置webhook
    if DOMAIN:
        logger.info("設置Webhook...")
        if webhook_manager.setup_webhook():
            logger.info("✅ Webhook設置完成")
        else:
            logger.warning("⚠️ Webhook設置失敗，機器人可能無法接收消息")
    else:
        logger.warning("⚠️ 未設置DOMAIN，使用輪詢模式（不推薦）")
    
    # 啟動Flask
    logger.info(f"啟動Flask服務在 0.0.0.0:{PORT}")
    logger.info("=" * 50)
    
    try:
        # 根據環境選擇運行模式
        if DOMAIN:
            # Webhook模式
            app.run(host="0.0.0.0", port=PORT, debug=False)
        else:
            # 輪詢模式（測試用）
            logger.warning("使用輪詢模式（僅測試）")
            bot.remove_webhook()
            bot.polling(none_stop=True, interval=1, timeout=30)
            
    except KeyboardInterrupt:
        logger.info("收到停止信號，關閉機器人...")
    except Exception as e:
        logger.error(f"運行錯誤: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()