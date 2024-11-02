from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pandas as pd
import pickle
import uvicorn
from sklearn.ensemble import RandomForestClassifier
import requests
import json
from datetime import datetime
from typing import List, Optional

# Initialize FastAPI app
app = FastAPI(title="Crop Prediction API")

# ThingSpeak configuration
THINGSPEAK_CHANNEL_ID = "2716041"  # Replace with your channel ID
THINGSPEAK_READ_API_KEY = "3DBY1HP84DH873TM"  # Replace with your read API key
THINGSPEAK_BASE_URL = f"https://api.thingspeak.com/channels/{THINGSPEAK_CHANNEL_ID}/feeds.json"

# Data models
class PredictionRequest(BaseModel):
    temperature: float
    humidity: float

class PredictionResponse(BaseModel):
    predicted_crop: str
    confidence: float

class SensorData(BaseModel):
    timestamp: str
    temperature: float
    humidity: float

class SensorDataResponse(BaseModel):
    latest_reading: SensorData
    predictions: PredictionResponse

def train_model():
    # Load the dataset
    data = pd.read_csv('/home/beastnova/Downloads/final_try/final try to integrate/data/Crop_recommendation.csv')
    
    # Features and target
    X = data[['temperature', 'humidity']]
    y = data['label']
    
    # Train the model
    model = RandomForestClassifier(random_state=42)
    model.fit(X, y)
    
    return model

# Initialize model
model = train_model()

def fetch_thingspeak_data() -> Optional[SensorData]:
    """Fetch the latest sensor data from ThingSpeak"""
    try:
        params = {
            'api_key': THINGSPEAK_READ_API_KEY,
            'results': 1  # Get only the latest reading
        }
        
        response = requests.get(THINGSPEAK_BASE_URL, params=params)
        response.raise_for_status()
        
        data = response.json()
        
        if not data['feeds']:
            raise HTTPException(status_code=404, detail="No sensor data available")
            
        latest_feed = data['feeds'][0]
        
        # Assuming field1 is temperature and field2 is humidity
        # Modify these field numbers according to your ThingSpeak channel configuration
        return SensorData(
            timestamp=latest_feed['created_at'],
            temperature=float(latest_feed['field1']),
            humidity=float(latest_feed['field2'])
        )
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch sensor data: {str(e)}")
    except (KeyError, ValueError) as e:
        raise HTTPException(status_code=500, detail=f"Invalid sensor data format: {str(e)}")

def make_prediction(temperature: float, humidity: float) -> PredictionResponse:
    """Make a crop prediction based on temperature and humidity"""
    try:
        input_data = pd.DataFrame({
            'temperature': [temperature],
            'humidity': [humidity]
        })
        
        prediction = model.predict(input_data)
        probabilities = model.predict_proba(input_data)
        confidence = float(max(probabilities[0]) * 100)
        
        return PredictionResponse(
            predicted_crop=prediction[0],
            confidence=confidence
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction error: {str(e)}")

@app.post("/predict", response_model=PredictionResponse)
async def predict_crop(request: PredictionRequest):
    """Endpoint for making predictions with manually entered data"""
    return make_prediction(request.temperature, request.humidity)

@app.get("/sensor-data", response_model=SensorDataResponse)
async def get_sensor_data():
    """Endpoint to fetch latest sensor data and make prediction"""
    sensor_data = fetch_thingspeak_data()
    prediction = make_prediction(sensor_data.temperature, sensor_data.humidity)
    
    return SensorDataResponse(
        latest_reading=sensor_data,
        predictions=prediction
    )

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)