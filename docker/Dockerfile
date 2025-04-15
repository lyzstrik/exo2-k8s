FROM python:3.10-slim

RUN pip install flask

COPY app.py /app/app.py
WORKDIR /app

CMD ["python", "app.py"]
