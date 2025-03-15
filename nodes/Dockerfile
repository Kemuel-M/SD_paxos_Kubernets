FROM python:3.9-slim

WORKDIR /app

# Install curl and other utilities
RUN apt-get update && \
    apt-get install -y curl dnsutils iputils-ping && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements.txt and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all Python files
COPY *.py .

# Expose ports for application and monitoring
EXPOSE 3000-6999 8000

# Command to start the node
CMD ["python", "main.py"]