FROM python:3.13.3-bookworm

RUN pip install flask

COPY app.py /app/app.py
WORKDIR /app

CMD ["python", "app.py"]
