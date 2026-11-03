FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# TraceID face models (OpenCV Zoo, Apache-2.0). If the download fails, the engine falls back to review-only matching.
RUN mkdir -p /app/models && python -c "import urllib.request as u; \
u.urlretrieve('https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx','/app/models/yunet.onnx'); \
u.urlretrieve('https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx','/app/models/sface.onnx')" || echo "TraceID models not downloaded"
COPY app ./app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
