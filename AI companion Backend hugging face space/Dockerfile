FROM python:3.11-slim
WORKDIR /code
# 建立靜態目錄並給予讀寫權限
RUN mkdir -p /code/static/audio && chmod -R 777 /code/static/audio
COPY ./requirements.txt /code/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt
COPY . .
# 確保所有檔案在 /code 下都有權限
RUN chmod -R 777 /code
EXPOSE 7860
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]