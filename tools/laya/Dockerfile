# Laya-Dienst, nur CPU. Die Gewichte kommen als Volume (vorher download_model.py laufen lassen):
#   docker build -t pocketra-laya tools/laya
#   docker run --rm -p 8765:8765 -v "$PWD/build/laya/multilingual-int8:/models:ro" pocketra-laya
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY laya_core.py service.py kommandeur_format.py ./
ENV LAYA_MODEL_DIR=/models \
    LAYA_HOST=0.0.0.0 \
    LAYA_PORT=8765
EXPOSE 8765
CMD ["python", "service.py"]
