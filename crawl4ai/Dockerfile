# Use NVIDIA CUDA base image
FROM nvidia/cuda:12.6.3-devel-ubuntu24.04 as base

# Set environment variables for cuDNN
ENV NV_CUDNN_VERSION 9.5.1.17-1
ENV NV_CUDNN_PACKAGE_NAME libcudnn9-cuda-12
ENV NV_CUDNN_PACKAGE libcudnn9-cuda-12=${NV_CUDNN_VERSION}
ENV NV_CUDNN_PACKAGE_DEV libcudnn9-dev-cuda-12=${NV_CUDNN_VERSION}

# Set other environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV NVIDIA_VISIBLE_DEVICES=all
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Create and set working directory
RUN mkdir -p /app
WORKDIR /app

# Install system dependencies, cuDNN, and Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    curl \
    gnupg \
    ${NV_CUDNN_PACKAGE} \
    ${NV_CUDNN_PACKAGE_DEV} \
    && apt-mark hold ${NV_CUDNN_PACKAGE_NAME} \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.13 \
    python3.13-venv \
    python3.13-dev \
    python3-pip \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
RUN python3.13 -m venv venv
ENV PATH="/app/venv/bin:$PATH"
ENV VIRTUAL_ENV="/app/venv"
ENV PYTHONPATH="/app:${PYTHONPATH}"

# Upgrade pip and install dependencies
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright dependencies
RUN playwright install-deps
RUN playwright install chromium

# Download model
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Copy application code
COPY . .

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:11235/health || exit 1

# Run FastAPI server using module syntax
CMD ["uvicorn", "app.server:app", "--host", "0.0.0.0", "--port", "11235", "--log-level", "info"] 