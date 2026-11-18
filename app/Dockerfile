FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1
WORKDIR /app

RUN pip install --no-cache-dir pika==1.3.2

COPY consumer.py producer.py ./

# Por defecto la imagen actúa como consumer; el producer se lanza sobreescribiendo el comando.
CMD ["python", "consumer.py"]
