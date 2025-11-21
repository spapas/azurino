from django.db import models


class TestFileModel(models.Model):
    name = models.CharField(max_length=255)
    file1 = models.FileField(upload_to='test_files/')
    file2 = models.FileField(upload_to='test_files/test_subfolder/')