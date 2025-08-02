# src/scripts/generate_dummy_metrics.py (Corrected Version)

import pandas as pd
import numpy as np
import os

def generate_metrics(filename="sample_metrics.csv"):
    """Generates a dummy metrics CSV file in the correct shared location."""
    
    # This line finds the project's root directory by going up two levels from the current script's location
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    
    # This line defines the correct target directory for the dataset
    dataset_dir = os.path.join(project_root, 'src', 'ml_models', 'dataset')
    
    # Create the target directory if it doesn't already exist
    if not os.path.exists(dataset_dir):
        os.makedirs(dataset_dir)

    # Define the full path for the output file
    filepath = os.path.join(dataset_dir, filename)

    # --- The rest of the script is the same ---
    timestamps = pd.to_datetime(pd.date_range(start="2025-01-01", periods=1000, freq="5min"))
    
    # Normal behavior
    cpu_normal = np.random.normal(loc=20, scale=5, size=1000)
    mem_normal = np.random.normal(loc=40, scale=8, size=1000)

    # Inject anomalies
    cpu_normal[200:210] = np.random.normal(loc=90, scale=3, size=10)
    mem_normal[500:505] = np.random.normal(loc=95, scale=2, size=5)

    df = pd.DataFrame(data={"timestamp": timestamps, "cpu_utilization": cpu_normal, "memory_usage": mem_normal})
    
    df.to_csv(filepath, index=False)
    print(f"Success! Generated dummy metrics at: {filepath}")

if __name__ == "__main__":
    generate_metrics()