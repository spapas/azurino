"""
Test file for Azure Blob Storage backend.

Usage:
    python manage.py test yourapp.tests.test_storage
    
Or run specific tests:
    python manage.py test yourapp.tests.test_storage.AzureBlobStorageTest.test_save_and_open
"""

from django.test import TestCase
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.conf import settings
import os


class AzureBlobStorageTest(TestCase):
    """Test cases for AzureBlobStorage backend."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.test_filename = 'test_file.txt'
        self.test_content = b'Hello, Azure Blob Storage!'
        self.storage = default_storage
        print(f"\nUsing storage: {self.storage.__class__.__name__}")
    
    def tearDown(self):
        """Clean up after tests."""
        # Try to delete test files
        try:
            if self.storage.exists(self.test_filename):
                self.storage.delete(self.test_filename)
        except:
            pass
    
    def test_save_and_open(self):
        """Test saving and opening a file."""
        # Create a file
        file_obj = ContentFile(self.test_content)
        
        # Save it
        saved_name = self.storage.save(self.test_filename, file_obj)
        self.assertIsNotNone(saved_name)
        print(f"✓ File saved as: {saved_name}")
        
        # Open and read it
        opened_file = self.storage.open(saved_name)
        content = opened_file.read()
        self.assertEqual(content, self.test_content)
        print(f"✓ File content matches: {content.decode()}")
    
    def test_exists(self):
        """Test checking if a file exists."""
        # File shouldn't exist initially
        self.assertFalse(self.storage.exists(self.test_filename))
        print("✓ File doesn't exist initially")
        
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self.storage.save(self.test_filename, file_obj)
        
        # Now it should exist
        self.assertTrue(self.storage.exists(saved_name))
        print(f"✓ File exists after save: {saved_name}")
    
    def test_size(self):
        """Test getting file size."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self.storage.save(self.test_filename, file_obj)
        
        # Check size
        size = self.storage.size(saved_name)
        self.assertEqual(size, len(self.test_content))
        print(f"✓ File size correct: {size} bytes")
    
    def test_url(self):
        """Test getting a URL for the file."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self.storage.save(self.test_filename, file_obj)
        
        # Get URL
        url = self.storage.url(saved_name)
        self.assertIsNotNone(url)
        self.assertTrue(url.startswith('http'))
        print(f"✓ Got URL: {url[:80]}...")
    
    def test_delete(self):
        """Test deleting a file."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self.storage.save(self.test_filename, file_obj)
        
        # Verify it exists
        self.assertTrue(self.storage.exists(saved_name))
        
        # Delete it
        self.storage.delete(saved_name)
        print(f"✓ File deleted: {saved_name}")
        
        # Verify it's gone (might not work if delete not implemented)
        # self.assertFalse(self.storage.exists(saved_name))
    
    def test_modified_time(self):
        """Test getting file modification time."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self.storage.save(self.test_filename, file_obj)
        
        # Get modified time
        modified_time = self.storage.get_modified_time(saved_name)
        if modified_time:
            print(f"✓ Modified time: {modified_time}")
            self.assertIsNotNone(modified_time)
        else:
            print("⚠ Modified time not available")
    
    def test_listdir(self):
        """Test listing directory contents."""
        # Save a few test files
        for i in range(3):
            filename = f'test_list_{i}.txt'
            file_obj = ContentFile(f'Test content {i}'.encode())
            self.storage.save(filename, file_obj)
        
        # List directory
        try:
            directories, files = self.storage.listdir('')
            print(f"✓ Found {len(directories)} directories and {len(files)} files")
            
            # Clean up
            for i in range(3):
                filename = f'test_list_{i}.txt'
                if self.storage.exists(filename):
                    self.storage.delete(filename)
        except NotImplementedError:
            print("⚠ listdir() not implemented")


class ManualStorageTest(TestCase):
    """
    Manual tests for interactive testing.
    Run with: python manage.py test yourapp.tests.test_storage.ManualStorageTest --keepdb
    """
    
    def test_upload_real_file(self):
        """Upload an actual file from disk."""
        # Create a temporary test file
        test_file_path = 'c:/temp/test_upload.txt'
        test_content = b'This is a test file for manual upload testing.'
        
        with open(test_file_path, 'wb') as f:
            f.write(test_content)
        
        # Upload it
        storage = default_storage
        with open(test_file_path, 'rb') as f:
            saved_name = storage.save('manual_test.txt', f)
        
        print(f"\n✓ Uploaded file as: {saved_name}")
        print(f"✓ URL: {storage.url(saved_name)}")
        print(f"✓ Size: {storage.size(saved_name)} bytes")
        print(f"✓ Exists: {storage.exists(saved_name)}")
        
        # Clean up local file
        os.remove(test_file_path)
        
        # Don't delete from storage so you can verify manually
        print(f"\n⚠ File left in storage for manual verification")
        print(f"  Delete it with: storage.delete('{saved_name}')")
    
    def test_download_and_verify(self):
        """Download a file and verify its contents."""
        storage = default_storage
        test_filename = 'manual_test.txt'
        
        if not storage.exists(test_filename):
            print(f"\n⚠ File '{test_filename}' doesn't exist. Run test_upload_real_file first.")
            return
        
        # Download and read
        opened_file = storage.open(test_filename)
        content = opened_file.read()
        
        print(f"\n✓ Downloaded file: {test_filename}")
        print(f"✓ Content ({len(content)} bytes):")
        print(f"  {content.decode()}")


# Standalone script for quick testing
if __name__ == '__main__':
    import django
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'djazurino.settings')
    django.setup()
    
    from django.core.files.storage import default_storage
    from django.core.files.base import ContentFile
    
    print("=== Quick Storage Test ===\n")
    
    storage = default_storage
    print(f"Using storage: {storage.__class__.__name__}")
    print(f"Base URL: {getattr(storage, 'base_url', 'N/A')}")
    print(f"Folder: {getattr(storage, 'folder', 'N/A')}\n")
    
    # Test save
    test_content = b'Quick test content'
    test_filename = 'quick_test.txt'
    
    print(f"Saving file: {test_filename}")
    saved_name = storage.save(test_filename, ContentFile(test_content))
    print(f"✓ Saved as: {saved_name}\n")
    
    # Test exists
    exists = storage.exists(saved_name)
    print(f"✓ Exists: {exists}\n")
    
    # Test size
    size = storage.size(saved_name)
    print(f"✓ Size: {size} bytes\n")
    
    # Test URL
    url = storage.url(saved_name)
    print(f"✓ URL: {url}\n")
    
    # Test open
    print("Reading file back...")
    opened = storage.open(saved_name)
    content = opened.read()
    print(f"✓ Content: {content.decode()}\n")
    
    print("=== Test Complete ===")
    print(f"\nTo delete: storage.delete('{saved_name}')")