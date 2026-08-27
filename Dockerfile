FROM --platform=linux/amd64 python:3.14-slim

WORKDIR /app

RUN groupadd --system app && useradd --system --gid app --create-home --home-dir /home/app app \
    && chown -R app:app /app

USER app

CMD ["python", "-u", "-c", "import time; \nwhile True:\n    print('Hello world')\n    time.sleep(10)\n"]
