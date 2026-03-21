from django.http import (
    HttpResponseBadRequest,
    HttpResponseForbidden,
    HttpResponseNotFound,
    HttpResponseServerError,
    JsonResponse,
)


def health_check(request):
    return JsonResponse({"status": "ok", "service": "notechondria-backend"})


def _api_error_response(request, message, status_code):
    if request.path.startswith("/api/"):
        return JsonResponse(
            {
                "detail": message,
                "status_code": status_code,
                "path": request.path,
            },
            status=status_code,
        )
    return None


def api_bad_request(request, exception):
    response = _api_error_response(request, "Bad request.", 400)
    if response is not None:
        return response
    return HttpResponseBadRequest("Bad request.")


def api_permission_denied(request, exception):
    response = _api_error_response(request, "Permission denied.", 403)
    if response is not None:
        return response
    return HttpResponseForbidden("Permission denied.")


def api_page_not_found(request, exception):
    response = _api_error_response(request, "API route not found.", 404)
    if response is not None:
        return response
    return HttpResponseNotFound("Page not found.")


def api_server_error(request):
    response = _api_error_response(request, "Internal server error.", 500)
    if response is not None:
        return response
    return HttpResponseServerError("Internal server error.")
