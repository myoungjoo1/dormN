from fastapi import FastAPI
from app.database import test_connection

app = FastAPI()

@app.get("/hello")
def hello():
    return {"message": "DormN"}

@app.get("/db-test")
def db_test():
    result = test_connection()

    return {
        "message": "Database connected",
        "result": result[0]
    }