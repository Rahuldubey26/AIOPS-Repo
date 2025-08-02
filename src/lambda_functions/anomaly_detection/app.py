import boto3
import os
import joblib
import pandas as pd
from io import BytesIO

s3 = boto3.client('s3')

# Load model from S3 during Lambda initialization (cold start)
BUCKET_NAME = os.environ.get('S3_BUCKET')
MODEL_KEY = os.environ.get('MODEL_KEY')
model_path = "/tmp/model.pkl"

try:
    s3.download_file(BUCKET_NAME, MODEL_KEY, model_path)
    model = joblib.load(model_path)
except Exception as e:
    print(f"Error loading model: {e}")
    model = None

def handler(event, context):
    if not model:
        return {"error": "Model not loaded."}
        
    # In a real system, you'd get these metrics from the event (e.g., from CloudWatch)
    # For this demo, we use dummy data.
    cpu = float(event.get('cpu_utilization', 85.0))
    memory = float(event.get('memory_usage', 50.0))
    
    # Create a DataFrame for the model
    data = pd.DataFrame([[cpu, memory]], columns=['cpu_utilization', 'memory_usage'])
    
    # Predict
    prediction = model.predict(data)
    
    is_anomaly = prediction[0] == -1
    
    return {
        "is_anomaly": bool(is_anomaly),
        "cpu_utilization": cpu,
        "memory_usage": memory
    }