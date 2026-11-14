import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api import (
    ApiResponse,
    COMMON_ERROR_RESPONSES,
    http_exception_handler,
    unhandled_exception_handler,
    validation_exception_handler,
)
from app.database import test_connection
from app.routers.participations import router as participations_router
from app.routers.posts import router as posts_router
from app.routers.settlements import router as settlements_router
from app.routers.users import router as users_router
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


app = FastAPI(lifespan=lifespan, responses=COMMON_ERROR_RESPONSES)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)
app.include_router(posts_router)
app.include_router(participations_router)
app.include_router(settlements_router)
app.include_router(users_router)

@app.get("/hello", response_model=ApiResponse[dict[str, str]])
def hello():
    return {"data": {"message": "DormN"}}

@app.get("/db-test", response_model=ApiResponse[dict[str, str | int]])
def db_test():
    result = test_connection()

    return {
        "data": {
            "message": "Database connected",
            "result": result[0],
        }
    }
