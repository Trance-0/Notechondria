from urllib.parse import urlparse

from django.conf import settings
from django.http import HttpResponse


class ApiCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        is_api_request = request.path.startswith("/api/")
        origin = request.headers.get("Origin", "")

        if is_api_request and request.method == "OPTIONS":
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)

        if not is_api_request or not origin:
            return response

        if self._is_allowed_origin(origin):
            response["Access-Control-Allow-Origin"] = origin
            response["Access-Control-Allow-Credentials"] = "true"
            response["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, Origin, X-Requested-With"
            response["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
            response["Vary"] = "Origin"

        return response

    @staticmethod
    def _is_allowed_origin(origin: str) -> bool:
        parsed = urlparse(origin)
        host = parsed.hostname or ""
        if host in {"localhost", "127.0.0.1"}:
            return True
        if host in settings.ALLOWED_HOSTS:
            return True
        # Check CSRF_TRUSTED_ORIGINS for cross-origin frontend deployments
        # (e.g. GitHub Pages frontend talking to Render backend)
        for trusted in getattr(settings, "CSRF_TRUSTED_ORIGINS", []):
            trusted_parsed = urlparse(trusted)
            if trusted_parsed.hostname == host:
                return True
        return False
