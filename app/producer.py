"""Producer: publica N mensajes en la cola para generar carga.

Uso: python producer.py 300
"""
import os
import sys

import pika

HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
USER = os.getenv("RABBITMQ_USER", "guest")
PASSWORD = os.getenv("RABBITMQ_PASSWORD", "guest")
QUEUE = os.getenv("QUEUE_NAME", "tareas")


def main() -> None:
    total = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host=HOST, credentials=pika.PlainCredentials(USER, PASSWORD))
    )
    channel = connection.channel()
    channel.queue_declare(queue=QUEUE, durable=True)
    for i in range(1, total + 1):
        channel.basic_publish(
            exchange="",
            routing_key=QUEUE,
            body=f"tarea-{i}".encode(),
            properties=pika.BasicProperties(delivery_mode=pika.DeliveryMode.Persistent),
        )
    print(f"Publicados {total} mensajes en '{QUEUE}'", flush=True)
    connection.close()


if __name__ == "__main__":
    main()
