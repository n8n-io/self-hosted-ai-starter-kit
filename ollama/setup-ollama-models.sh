#!/bin/bash
set -euo pipefail

# Enhanced Ollama Model Setup Script for T4 GPU Optimization
# Downloads and configures: DeepSeek-R1:8B, Qwen2.5-VL:7B, Snowflake-Arctic-Embed2:568M
# Optimized for NVIDIA T4 GPUs on g4dn.xlarge instances

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OLLAMA_MODELS_DIR="$PROJECT_ROOT/ollama-models"
LOG_FILE="/var/log/ollama-model-setup.log"
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
OLLAMA_API_URL="http://${OLLAMA_HOST}"

# Model configurations
MODELS=(
    "deepseek-r1:8b"
    "qwen2.5-vl:7b" 
    "snowflake-arctic-embed2:568m"
)

MODEL_ALIASES=(
    "deepseek-r1-8b-optimized"
    "qwen2.5-vl-7b-optimized"
    "snowflake-arctic-embed2-568m-optimized"
)

MODELFILES=(
    "Modelfile.deepseek-r1-8b"
    "Modelfile.qwen2.5-vl-7b"
    "Modelfile.snowflake-arctic-embed2-568m"
)

# Performance monitoring
PERFORMANCE_LOG="/var/log/ollama-performance.log"
GPU_MONITORING_SCRIPT="/usr/local/bin/gpu-performance-monitor.py"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" >&2
    exit 1
}

# Check GPU availability
check_gpu() {
    log "Checking NVIDIA GPU availability..."
    if ! command -v nvidia-smi &> /dev/null; then
        error_exit "nvidia-smi not found. Ensure NVIDIA drivers are installed."
    fi
    
    # Check for T4 GPU specifically
    if nvidia-smi | grep -q "Tesla T4\|T4"; then
        log "✅ NVIDIA T4 GPU detected"
        T4_COUNT=$(nvidia-smi -L | grep -c "T4")
        log "Found $T4_COUNT T4 GPU(s)"
    else
        log "⚠️  Warning: T4 GPU not detected. Optimizations may not be optimal."
        nvidia-smi -L | head -5
    fi
    
    # Check GPU memory
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    log "GPU Memory: ${GPU_MEMORY}MB"
    
    if [ "$GPU_MEMORY" -lt "15000" ]; then
        log "⚠️  Warning: GPU memory (${GPU_MEMORY}MB) is less than expected for T4 (16GB)"
    fi
}

# Check Ollama availability
check_ollama() {
    log "Checking Ollama service availability..."
    local retries=30
    local count=0
    
    while [ $count -lt $retries ]; do
        if curl -s "$OLLAMA_API_URL/api/tags" > /dev/null 2>&1; then
            log "✅ Ollama service is available at $OLLAMA_API_URL"
            return 0
        fi
        log "Waiting for Ollama service... (attempt $((count + 1))/$retries)"
        sleep 10
        count=$((count + 1))
    done
    
    error_exit "Ollama service not available at $OLLAMA_API_URL after $retries attempts"
}

# Get GPU temperature and utilization
get_gpu_stats() {
    local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)
    local util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
    local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
    local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    
    echo "GPU: ${temp}°C, ${util}% util, ${mem_used}/${mem_total}MB memory"
}

# =============================================================================
# MODEL DOWNLOAD AND CONFIGURATION
# =============================================================================

# Download base models
download_models() {
    log "Starting model downloads..."
    
    for i in "${!MODELS[@]}"; do
        local model="${MODELS[$i]}"
        log "Downloading model: $model"
        
        # Record start time and GPU stats
        local start_time=$(date +%s)
        log "GPU Stats before download: $(get_gpu_stats)"
        
        # Download with progress monitoring
        if ollama pull "$model"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "✅ Successfully downloaded $model in ${duration}s"
        else
            error_exit "Failed to download model: $model"
        fi
        
        # Check GPU stats after download
        log "GPU Stats after download: $(get_gpu_stats)"
        
        # Brief cooldown between downloads
        sleep 5
    done
}

# Create optimized models from Modelfiles
create_optimized_models() {
    log "Creating optimized model configurations..."
    
    # Ensure models directory exists
    mkdir -p "$OLLAMA_MODELS_DIR"
    
    for i in "${!MODELS[@]}"; do
        local base_model="${MODELS[$i]}"
        local optimized_alias="${MODEL_ALIASES[$i]}"
        local modelfile="${MODELFILES[$i]}"
        local modelfile_path="$OLLAMA_MODELS_DIR/$modelfile"
        
        log "Creating optimized model: $optimized_alias from $base_model"
        
        if [ ! -f "$modelfile_path" ]; then
            error_exit "Modelfile not found: $modelfile_path"
        fi
        
        # Record start time
        local start_time=$(date +%s)
        log "GPU Stats before optimization: $(get_gpu_stats)"
        
        # Create optimized model
        if ollama create "$optimized_alias" -f "$modelfile_path"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "✅ Successfully created optimized model $optimized_alias in ${duration}s"
        else
            error_exit "Failed to create optimized model: $optimized_alias"
        fi
        
        # Check GPU stats after optimization
        log "GPU Stats after optimization: $(get_gpu_stats)"
        
        # Brief cooldown
        sleep 3
    done
}

# =============================================================================
# PERFORMANCE TESTING AND VALIDATION
# =============================================================================

# Test model performance
test_model_performance() {
    local model="$1"
    local test_prompt="$2"
    local expected_response_time="$3"
    
    log "Testing performance for model: $model"
    
    # Record baseline GPU stats
    local gpu_stats_before=$(get_gpu_stats)
    log "GPU stats before test: $gpu_stats_before"
    
    # Test model response time
    local start_time=$(date +%s%3N)  # milliseconds
    
    # Send test prompt and capture response
    local response=$(curl -s -X POST "$OLLAMA_API_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"prompt\": \"$test_prompt\",
            \"stream\": false,
            \"options\": {
                \"temperature\": 0.1,
                \"max_tokens\": 100
            }
        }" | jq -r '.response // "ERROR"')
    
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    # Record GPU stats after test
    local gpu_stats_after=$(get_gpu_stats)
    
    # Log results
    log "Model: $model"
    log "Response time: ${response_time}ms (expected: <${expected_response_time}ms)"
    log "GPU before: $gpu_stats_before"
    log "GPU after: $gpu_stats_after"
    log "Response preview: ${response:0:100}..."
    
    # Performance validation
    if [ "$response_time" -lt "$expected_response_time" ]; then
        log "✅ Performance test PASSED for $model"
        return 0
    else
        log "⚠️  Performance test WARNING for $model (slower than expected)"
        return 1
    fi
}

# Run comprehensive performance tests
run_performance_tests() {
    log "Running comprehensive performance tests..."
    
    # Test prompts for each model type
    local reasoning_prompt="Solve this step by step: What is 15% of 240?"
    local vision_prompt="Describe what you would see in a typical office environment."
    local embedding_prompt="artificial intelligence machine learning deep learning neural networks"
    
    # Expected response times (milliseconds) for T4 GPU
    local deepseek_expected=3000     # 3 seconds for reasoning tasks
    local qwen_expected=4000         # 4 seconds for vision-language
    local arctic_expected=500        # 0.5 seconds for embeddings
    
    # Test each optimized model
    test_model_performance "deepseek-r1-8b-optimized" "$reasoning_prompt" "$deepseek_expected"
    test_model_performance "qwen2.5-vl-7b-optimized" "$vision_prompt" "$qwen_expected"
    test_model_performance "snowflake-arctic-embed2-568m-optimized" "$embedding_prompt" "$arctic_expected"
    
    log "Performance testing completed"
}

# =============================================================================
# MONITORING SETUP
# =============================================================================

# Create GPU performance monitoring script
create_monitoring_script() {
    log "Creating GPU performance monitoring script..."
    
    cat > "$GPU_MONITORING_SCRIPT" << 'EOF'
#!/usr/bin/env python3
"""
Enhanced GPU Performance Monitor for Ollama Models
Tracks GPU usage, temperature, memory, and model performance
"""

import json
import time
import subprocess
import logging
import requests
from datetime import datetime
import nvidia_ml_py3 as nvml

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/ollama-performance.log'),
        logging.StreamHandler()
    ]
)

class OllamaGPUMonitor:
    def __init__(self):
        nvml.nvmlInit()
        self.device_count = nvml.nvmlDeviceGetCount()
        self.ollama_url = "http://localhost:11434"
        
    def get_gpu_metrics(self):
        metrics = []
        for i in range(self.device_count):
            handle = nvml.nvmlDeviceGetHandleByIndex(i)
            
            # Memory info
            mem_info = nvml.nvmlDeviceGetMemoryInfo(handle)
            memory_used_gb = mem_info.used / 1024**3
            memory_total_gb = mem_info.total / 1024**3
            memory_util = (memory_used_gb / memory_total_gb) * 100
            
            # Utilization and temperature
            util = nvml.nvmlDeviceGetUtilizationRates(handle)
            temp = nvml.nvmlDeviceGetTemperature(handle, nvml.NVML_TEMPERATURE_GPU)
            
            # Power usage
            try:
                power_draw = nvml.nvmlDeviceGetPowerUsage(handle) / 1000.0
            except:
                power_draw = 0
            
            metrics.append({
                'device_id': i,
                'timestamp': datetime.utcnow().isoformat(),
                'memory_used_gb': round(memory_used_gb, 2),
                'memory_total_gb': round(memory_total_gb, 2),
                'memory_utilization_percent': round(memory_util, 2),
                'gpu_utilization_percent': util.gpu,
                'temperature_celsius': temp,
                'power_draw_watts': round(power_draw, 2)
            })
        
        return metrics
    
    def get_ollama_models(self):
        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                return response.json().get('models', [])
        except:
            pass
        return []
    
    def test_model_latency(self, model_name, test_prompt="Hello"):
        try:
            start_time = time.time()
            response = requests.post(
                f"{self.ollama_url}/api/generate",
                json={
                    "model": model_name,
                    "prompt": test_prompt,
                    "stream": False,
                    "options": {"max_tokens": 10}
                },
                timeout=30
            )
            end_time = time.time()
            
            if response.status_code == 200:
                return {
                    'model': model_name,
                    'latency_ms': round((end_time - start_time) * 1000, 2),
                    'success': True
                }
        except Exception as e:
            logging.error(f"Error testing {model_name}: {e}")
        
        return {'model': model_name, 'success': False}
    
    def monitor_performance(self, duration_minutes=5):
        """Monitor performance for specified duration"""
        end_time = time.time() + (duration_minutes * 60)
        
        while time.time() < end_time:
            # Get GPU metrics
            gpu_metrics = self.get_gpu_metrics()
            
            # Get loaded models
            models = self.get_ollama_models()
            
            # Test model latencies
            model_tests = []
            for model in models[:3]:  # Test first 3 models only
                model_name = model.get('name', '')
                if 'optimized' in model_name:
                    test_result = self.test_model_latency(model_name)
                    model_tests.append(test_result)
            
            # Log comprehensive metrics
            performance_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'gpu_metrics': gpu_metrics,
                'loaded_models': len(models),
                'model_tests': model_tests
            }
            
            logging.info(f"Performance snapshot: {json.dumps(performance_data, indent=2)}")
            
            # Alert on high GPU temperature
            for gpu in gpu_metrics:
                if gpu['temperature_celsius'] > 80:
                    logging.warning(f"High GPU temperature: {gpu['temperature_celsius']}°C")
                
                if gpu['memory_utilization_percent'] > 95:
                    logging.warning(f"High GPU memory usage: {gpu['memory_utilization_percent']}%")
            
            time.sleep(30)  # Monitor every 30 seconds

if __name__ == "__main__":
    monitor = OllamaGPUMonitor()
    logging.info("Starting Ollama GPU performance monitoring...")
    monitor.monitor_performance(duration_minutes=60)  # Monitor for 1 hour
EOF
    
    chmod +x "$GPU_MONITORING_SCRIPT"
    log "✅ GPU monitoring script created at $GPU_MONITORING_SCRIPT"
}

# =============================================================================
# MODEL MANAGEMENT FUNCTIONS
# =============================================================================

# List installed models
list_models() {
    log "Listing installed Ollama models..."
    ollama list | tee -a "$LOG_FILE"
}

# Clean up old or unused models
cleanup_models() {
    log "Cleaning up unused models to free GPU memory..."
    
    # Remove any models not in our optimized list
    local all_models=$(ollama list | tail -n +2 | awk '{print $1}')
    
    for model in $all_models; do
        local is_optimized=false
        for optimized in "${MODEL_ALIASES[@]}"; do
            if [[ "$model" == "$optimized" ]]; then
                is_optimized=true
                break
            fi
        done
        
        # Keep base models we need, but remove others
        if [[ ! "$is_optimized" == "true" ]] && [[ ! "$model" =~ ^(deepseek-r1|qwen2.5-vl|snowflake-arctic-embed2) ]]; then
            log "Removing unused model: $model"
            ollama rm "$model" || true
        fi
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "=== Starting Enhanced Ollama Model Setup for T4 GPU ==="
    log "Target models: ${MODELS[*]}"
    log "Optimized aliases: ${MODEL_ALIASES[*]}"
    
    # Pre-flight checks
    check_gpu
    check_ollama
    
    # Create monitoring infrastructure
    create_monitoring_script
    
    # Model setup process
    log "Phase 1: Downloading base models..."
    download_models
    
    log "Phase 2: Creating optimized configurations..."
    create_optimized_models
    
    log "Phase 3: Performance testing..."
    run_performance_tests
    
    log "Phase 4: Model management..."
    list_models
    cleanup_models
    
    # Final validation
    log "=== Final Model Configuration ==="
    ollama list
    
    log "=== GPU Status After Setup ==="
    get_gpu_stats
    
    log "=== Setup Complete ==="
    log "Optimized models are ready for use:"
    for alias in "${MODEL_ALIASES[@]}"; do
        log "  - $alias"
    done
    
    log ""
    log "Usage examples:"
    log "  # Test reasoning model:"
    log "  curl -X POST http://localhost:11434/api/generate -d '{\"model\":\"deepseek-r1-8b-optimized\",\"prompt\":\"Solve: 2+2*3\"}'"
    log ""
    log "  # Test vision model:"
    log "  curl -X POST http://localhost:11434/api/generate -d '{\"model\":\"qwen2.5-vl-7b-optimized\",\"prompt\":\"Describe an office\"}'"
    log ""
    log "  # Test embedding model:"
    log "  curl -X POST http://localhost:11434/api/embeddings -d '{\"model\":\"snowflake-arctic-embed2-568m-optimized\",\"prompt\":\"sample text\"}'"
    log ""
    log "Monitor performance: python3 $GPU_MONITORING_SCRIPT"
    log "Performance logs: tail -f $PERFORMANCE_LOG"
}

# Error handling
trap 'error_exit "Script interrupted"' INT TERM

# Execute main function
main "$@" 