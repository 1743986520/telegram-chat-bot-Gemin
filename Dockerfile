FROM python:3.11-slim

WORKDIR /app

COPY main.py requirements.txt ./

# 升級 pip 並安裝依賴，使用官方 CDN
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir \
       pyTelegramBotAPI \
       google-generativeai \
       flask \
       -i https://pypi.org/simple \
       --trusted-host pypi.org \
       --trusted-host files.pythonhosted.org
