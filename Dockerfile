FROM python:3.13-slim

WORKDIR /srv
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
# The Module 3 prompt-lifecycle demo (Clip 2) reads the real prompt repository
# at /srv/prompts (registry.yaml + version files). Bake it into the image so
# /lifecycle/prompts/run works even without a bind mount; the compose file also
# mounts it for live edits.
COPY prompts ./prompts

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
