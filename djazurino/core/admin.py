from django.contrib import admin
from .models import TestFileModel


class TestFileModelAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "file1", "file2")


# Register the model with the admin site so it appears at /admin/
admin.site.register(TestFileModel, TestFileModelAdmin)
