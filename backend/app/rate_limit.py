import math
import threading
import time
from collections import deque
from collections.abc import Callable

from fastapi import HTTPException, Request, status


class RateLimiter:
    # In-memory sliding window. Correct only with a single backend process, which is how the
    # app is deployed (one uvicorn worker, one replica).
    def __init__(self, limit: int, window_seconds: float) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str) -> None:
        with self._lock:
            hits = self._prune(key, time.monotonic())
            if len(hits) >= self.limit:
                retry_after = math.ceil(hits[0] + self.window_seconds - time.monotonic())
                raise HTTPException(
                    status.HTTP_429_TOO_MANY_REQUESTS,
                    "Too many attempts. Wait a minute and try again.",
                    headers={"Retry-After": str(max(retry_after, 1))},
                )

    def record(self, key: str) -> None:
        with self._lock:
            self._hits.setdefault(key, deque()).append(time.monotonic())

    def hit(self, key: str) -> None:
        self.check(key)
        self.record(key)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()

    def _prune(self, key: str, now: float) -> deque[float]:
        hits = self._hits.get(key)
        if hits is None:
            return deque()
        while hits and hits[0] <= now - self.window_seconds:
            hits.popleft()
        if not hits:
            del self._hits[key]
        return hits


def client_ip(request: Request) -> str:
    # With --proxy-headers this is the X-Forwarded-For address, but only when the request came
    # from an address in FORWARDED_ALLOW_IPS; otherwise it's the TCP peer.
    return request.client.host if request.client else "unknown"


def limit_by_ip(limiter: RateLimiter) -> Callable[[Request], None]:
    def dependency(request: Request) -> None:
        limiter.hit(client_ip(request))

    return dependency


login_ip_limiter = RateLimiter(limit=10, window_seconds=60)
login_failure_limiter = RateLimiter(limit=5, window_seconds=15 * 60)
refresh_ip_limiter = RateLimiter(limit=30, window_seconds=60)
invite_ip_limiter = RateLimiter(limit=10, window_seconds=60)

ALL_LIMITERS = (login_ip_limiter, login_failure_limiter, refresh_ip_limiter, invite_ip_limiter)
