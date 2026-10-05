import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from app.database import test_connection
from app.routers.participations import router as participations_router
from app.routers.posts import router as posts_router
from app.services.recruitment import process_expired_recruitment_once

logger = logging.getLogger(__name__)
RECRUITMENT_SCHEDULER_INTERVAL_SECONDS = 30


async def recruitment_scheduler():
    while True:
        try:
            await asyncio.to_thread(process_expired_recruitment_once)
        except Exception:
            logger.exception("Recruitment scheduler failed")

        await asyncio.sleep(RECRUITMENT_SCHEDULER_INTERVAL_SECONDS)


@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler_task = asyncio.create_task(recruitment_scheduler())
    try:
        yield
    finally:
        scheduler_task.cancel()
        with suppress(asyncio.CancelledError):
            await scheduler_task


app = FastAPI(lifespan=lifespan)
app.include_router(posts_router)
app.include_router(participations_router)

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
