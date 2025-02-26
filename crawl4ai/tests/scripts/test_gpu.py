#!/usr/bin/env python3

import torch
from sentence_transformers import SentenceTransformer
import time
import sys

def test_gpu():
    print("\n=== GPU Information ===")
    print(f"CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"CUDA version: {torch.version.cuda}")
        print(f"GPU device: {torch.cuda.get_device_name(0)}")
        print(f"GPU count: {torch.cuda.device_count()}")
        print(f"Current device: {torch.cuda.current_device()}")

def test_model():
    print("\n=== Model Test ===")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Using device: {device}")
    
    # Load model
    print("Loading model...")
    start_time = time.time()
    model = SentenceTransformer('all-MiniLM-L6-v2', device=device)
    load_time = time.time() - start_time
    print(f"Model loaded in {load_time:.2f} seconds")
    
    # Test encoding
    sentences = [
        "This is a test sentence for GPU acceleration.",
        "Let's see how fast we can encode text.",
        "GPU processing should be significantly faster than CPU."
    ] * 100  # Create a larger batch for better comparison
    
    print(f"\nEncoding {len(sentences)} sentences...")
    start_time = time.time()
    embeddings = model.encode(sentences)
    encode_time = time.time() - start_time
    print(f"Encoding completed in {encode_time:.2f} seconds")
    print(f"Average time per sentence: {(encode_time/len(sentences))*1000:.2f} ms")
    print(f"Embedding shape: {embeddings.shape}")

def main():
    try:
        test_gpu()
        test_model()
        print("\n✅ All tests completed successfully!")
    except Exception as e:
        print(f"\n❌ Test failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 