FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOME=/home/agent
RUN useradd --create-home --uid 10001 agent
WORKDIR /opt/agent-reach
COPY pyproject.toml README.md ./
COPY agent_reach ./agent_reach
RUN pip install --no-cache-dir . "mcp>=1.10,<2"
COPY deploy/azure/server.py ./server.py
USER agent
EXPOSE 8080
CMD ["python", "server.py"]
