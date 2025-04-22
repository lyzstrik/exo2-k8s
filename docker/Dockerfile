FROM python:3.13.3-bookworm

# Install sudo
RUN apt update && apt install -y sudo

# Add NOPASSWD rule for all users for python
RUN echo "ALL ALL=(ALL) NOPASSWD: /usr/local/bin/python3" >> /etc/sudoers

# Create unprivileged user
RUN useradd -m -s /bin/bash flaskuser

RUN pip install flask paramiko

COPY app.py /app/app.py
WORKDIR /app

# Switch to unprivileged user
USER flaskuser

CMD ["python", "app.py"]
