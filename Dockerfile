# 使用官方 Python 3.11 slim 作為基礎映像
FROM python:3.11-slim

# 設置工作目錄
WORKDIR /app

# 複製必要文件
COPY main.py requirements.txt ./

# 升級 pip 並安裝依賴
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
       pyTelegramBotAPI \
       google-generativeai \
       flask \
       --trusted-host pypi.org \
       --trusted-host files.pythonhosted.org

# 對外暴露端口（Flask 默認 5000，可根據需要改）
EXPOSE 5000

# 設置容器啟動命令
CMD ["python", "main.py"]
