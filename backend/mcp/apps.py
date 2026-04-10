from django.apps import AppConfig


class McpConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "mcp"
    verbose_name = "MCP Server"

    def ready(self):
        # Import tools module to trigger register_tool() calls.
        from . import tools  # noqa: F401
