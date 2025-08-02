import pandas as pd
from sklearn.ensemble import IsolationForest
import joblib
import os

def train_model(data_path, model_dir):
    """Trains and saves an Isolation Forest model."""
    if not os.path.exists(model_dir):
        os.makedirs(model_dir)

    model_path = os.path.join(model_dir, "isolation_forest_model.pkl")
    
    # Load data
    try:
        data = pd.read_csv(data_path)
    except FileNotFoundError:
        print(f"Error: Data file not found at {data_path}")
        return

    # Prepare features
    features = ['cpu_utilization', 'memory_usage']
    X = data[features]

    # Train model
    model = IsolationForest(n_estimators=100, contamination='auto', random_state=42)
    model.fit(X)

    # Save model
    joblib.dump(model, model_path)
    print(f"Model trained and saved to {model_path}")

if __name__ == "__main__":
    train_model(
        data_path="dataset/sample_metrics.csv", 
        model_dir="trained_models"
    )