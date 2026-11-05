"""Typed application errors and their HTTP shape: {"error": {"code", "message"}}."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

# Codes whose HTTP status is fixed by the contract in SPEC §6.
STATUS_BY_CODE: dict[str, int] = {
    "unauthorized": 401,
    "forbidden": 403,
    "caregiver_scope_denied": 403,
    "relationship_inactive": 403,
    "consent_required": 403,
    "not_found": 404,
    "invitation_invalid": 410,
    "consent_version_conflict": 409,
    "conflict": 409,
    "daily_cap_reached": 409,
    "outside_greeting_window": 409,
    "quiet_hours": 409,
    "not_designated_device": 409,
    "session_stopped": 409,
    "validation_error": 422,
    "provider_unavailable": 503,
}


class AppError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status: Optional[int] = None,
        **extra: Any,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status or STATUS_BY_CODE.get(code, 400)
        self.extra = extra

    def to_body(self) -> dict[str, Any]:
        body: dict[str, Any] = {"error": {"code": self.code, "message": self.message}}
        if self.extra:
            body["error"].update(self.extra)
        return body


def unauthorized(message: str = "Missing or invalid credentials", **extra: Any) -> AppError:
    return AppError("unauthorized", message, **extra)


def forbidden(message: str = "Not allowed", **extra: Any) -> AppError:
    return AppError("forbidden", message, **extra)


def not_found(message: str = "Not found", **extra: Any) -> AppError:
    return AppError("not_found", message, **extra)


def validation_error(message: str, **extra: Any) -> AppError:
    return AppError("validation_error", message, **extra)


def consent_required(message: str = "Consent is required for this action", **extra: Any) -> AppError:
    return AppError("consent_required", message, **extra)


def provider_unavailable(
    message: str = "Provider unavailable",
    *,
    recovery: Optional[list[str]] = None,
    provider: Optional[str] = None,
    **extra: Any,
) -> AppError:
    payload: dict[str, Any] = dict(extra)
    if provider is not None:
        payload["provider"] = provider
    payload["recovery"] = recovery or ["retry", "type_instead"]
    return AppError("provider_unavailable", message, **payload)


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(status_code=exc.status, content=exc.to_body())

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = exc.errors()
        message = errors[0].get("msg", "Invalid request") if errors else "Invalid request"
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_error", "message": message}},
        )

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={"error": {"code": "internal_error", "message": "Unexpected server error"}},
        )
