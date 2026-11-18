"""Consumer de la cola RabbitMQ.

Cada mensaje simula un trabajo lento (PROCESS_SECONDS). Como cada réplica
procesa un mensaje a la vez (prefetch_count=1), la única forma de vaciar la
cola más rápido es tener MÁS réplicas: ese es el trabajo de KEDA.
"""
import os
import socket
import time

import pika

HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
USER = os.getenv("RABBITMQ_USER", "guest")
PASSWORD = os.getenv("RABBITMQ_PASSWORD", "guest")
QUEUE = os.getenv("QUEUE_NAME", "tareas")
PROCESS_SECONDS = float(os.getenv("PROCESS_SECONDS", "2"))
POD = socket.gethostname()


def connect() -> pika.BlockingConnection:
    params = pika.ConnectionParameters(
        host=HOST,
        credentials=pika.PlainCredentials(USER, PASSWORD),
        heartbeat=30,
    )
    while True:
        try:
            return pika.BlockingConnection(params)
        except pika.exceptions.AMQPConnectionError:
            print(f"[{POD}] RabbitMQ no disponible, reintentando en 3s...", flush=True)
            time.sleep(3)


def main() -> None:
    connection = connect()
    channel = connection.channel()
    channel.queue_declare(queue=QUEUE, durable=True)
    # Un mensaje por réplica a la vez: el paralelismo lo da el número de pods.
    channel.basic_qos(prefetch_count=1)

    def on_message(ch, method, _props, body):
        print(f"[{POD}] procesando {body.decode()}", flush=True)
        time.sleep(PROCESS_SECONDS)
        # ACK solo al terminar: si el pod muere a mitad, el mensaje vuelve a la cola.
        ch.basic_ack(delivery_tag=method.delivery_tag)

    channel.basic_consume(queue=QUEUE, on_message_callback=on_message)
    print(f"[{POD}] esperando mensajes en '{QUEUE}' ({PROCESS_SECONDS}s por mensaje)", flush=True)
    channel.start_consuming()


if __name__ == "__main__":
    main()
