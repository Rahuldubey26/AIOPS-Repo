import pandas as pd
import numpy as np
import os

def generate_metrics(filename="sample_metrics.csv"):
    """Generates a dummy metrics CSV file."""
    if not os.path.exists("dataset"):
        os.makedirs("dataset")

    filepath = os.path.join("dataset", filename)

    timestamps = pd.to_datetime(pd.date_range(start="2025-01-01", periods=1000, freq="5min"))
    
    # Normal behavior
    cpu_normal = np.random.normal(loc=20, scale=5, size=1000)
    mem_normal = np.random.normal(loc=40, scale=8, size=1000)

    # Inject anomalies
    cpu_normal[200:210] = np.random.normal(loc=90, scale=3, size=10)
    mem_normal[500:505] = np.random.normal(loc=95, scale=2, size=5)

    df = pd.DataFrame(data={"timestamp": timestamps, "cpu_utilization": cpu_normal, "memory_usage": mem_normal})
    df.to_csv(filepath, index=False)
    print(f"Generated dummy metrics at {filepath}")

if __name__ == "__main__":
    generate_metrics()