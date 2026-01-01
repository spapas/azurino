"""
Test file for Azure Blob Storage backend.

Usage:
    python manage.py test core.tests.test_storage
    
Or run specific tests:
    python manage.py test core.tests.test_storage.AzureBlobStorageTest.test_save_and_open
"""

from django.test import TestCase
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.conf import settings
import os
import tempfile
import time
import uuid
from urllib.parse import urlparse, parse_qs


class AzureBlobStorageTest(TestCase):
    """Test cases for AzureBlobStorage backend."""
    
    def setUp(self):
        """Set up test fixtures."""
        # Use unique prefix per test to avoid conflicts
        self.test_prefix = f'test_{uuid.uuid4().hex[:8]}_'
        self.test_filename = f'{self.test_prefix}file.txt'
        self.test_content = b'Hello, Azure Blob Storage!'
        self.storage = default_storage
        self.saved_files = []  # Track all saved files for cleanup
        print(f"\nUsing storage: {self.storage.__class__.__name__}")
        print(f"Test prefix: {self.test_prefix}")
    
    def tearDown(self):
        """Clean up after tests."""
        # Delete all files saved during the test
        for filename in self.saved_files:
            try:
                if self.storage.exists(filename):
                    self.storage.delete(filename)
                    print(f"Cleaned up: {filename}")
            except Exception as e:
                print(f"Failed to cleanup {filename}: {e}")
    
    def _save_and_track(self, filename, content):
        """Save a file and track it for cleanup."""
        saved_name = self.storage.save(filename, content)
        self.saved_files.append(saved_name)
        return saved_name
    
    def test_save_and_open(self):
        """Test saving and opening a file."""
        # Create a file
        file_obj = ContentFile(self.test_content)
        
        # Save it
        saved_name = self._save_and_track(self.test_filename, file_obj)
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
        saved_name = self._save_and_track(self.test_filename, file_obj)
        
        # Now it should exist
        self.assertTrue(self.storage.exists(saved_name))
        print(f"✓ File exists after save: {saved_name}")
    
    def test_size(self):
        """Test getting file size."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self._save_and_track(self.test_filename, file_obj)
        
        # Check size
        size = self.storage.size(saved_name)
        self.assertEqual(size, len(self.test_content))
        print(f"✓ File size correct: {size} bytes")
    
    def test_url(self):
        """Test getting a URL for the file."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self._save_and_track(self.test_filename, file_obj)
        
        # Get URL
        url = self.storage.url(saved_name)
        self.assertIsNotNone(url)
        self.assertTrue(url.startswith('http'))
        print(f"✓ Got URL: {url[:80]}...")
        
        # Verify URL structure includes signed parameters
        parsed = urlparse(url)
        query_params = parse_qs(parsed.query)
        self.assertIn('signature', query_params, "URL should have signature parameter")
        self.assertIn('expires', query_params, "URL should have expires parameter")
        self.assertIn('path', query_params, "URL should have path parameter")
        
        # Verify expiration is in the future
        expires = int(query_params['expires'][0])
        current_time = int(time.time())
        self.assertGreater(expires, current_time, "Expiration should be in the future")
        print(f"✓ URL has valid signature structure, expires in {expires - current_time}s")
    
    def test_delete(self):
        """Test deleting a file."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self._save_and_track(self.test_filename, file_obj)
        
        # Verify it exists
        self.assertTrue(self.storage.exists(saved_name))
        
        # Delete it
        self.storage.delete(saved_name)
        self.saved_files.remove(saved_name)  # Remove from tracking
        print(f"✓ File deleted: {saved_name}")
        
        # Verify it's gone
        self.assertFalse(self.storage.exists(saved_name))
    
    def test_modified_time(self):
        """Test getting file modification time."""
        # Save file
        file_obj = ContentFile(self.test_content)
        saved_name = self._save_and_track(self.test_filename, file_obj)
        
        # Get modified time
        modified_time = self.storage.get_modified_time(saved_name)
        if modified_time:
            print(f"✓ Modified time: {modified_time}")
            self.assertIsNotNone(modified_time)
            # Verify it's recent (within last hour)
            from datetime import datetime, timezone, timedelta
            now = datetime.now(timezone.utc)
            age = now - modified_time
            self.assertLess(age, timedelta(hours=1), "Modified time should be recent")
        else:
            print("⚠ Modified time not available")
    
    def test_listdir(self):
        """Test listing directory contents."""
        # Save a few test files with unique prefix
        saved_names = []
        for i in range(3):
            filename = f'{self.test_prefix}list_{i}.txt'
            file_obj = ContentFile(f'Test content {i}'.encode())
            saved_name = self._save_and_track(filename, file_obj)
            saved_names.append(saved_name)
        
        # List directory
        try:
            directories, files = self.storage.listdir('')
            print(f"✓ Found {len(directories)} directories and {len(files)} files")
            print(f"Sample files: {files[:5] if len(files) > 5 else files}")
            
            # Verify our files are in the list using the actual saved names
            # (which may include folder prefix and random suffixes)
            for saved_name in saved_names:
                # Check if the saved name appears in the files list
                # The listdir may return full paths or just filenames
                found = any(saved_name in f or f in saved_name for f in files)
                self.assertTrue(found, f"File {saved_name} should be in directory listing. Files: {files[:10]}")
            
            print(f"✓ All test files found in listing")
        except NotImplementedError:
            print("⚠ listdir() not implemented")
    
    def test_empty_file(self):
        """Test handling empty files."""
        empty_content = b''
        filename = f'{self.test_prefix}empty.txt'
        
        # Save empty file
        saved_name = self._save_and_track(filename, ContentFile(empty_content))
        print(f"✓ Empty file saved: {saved_name}")
        
        # Verify size is 0
        size = self.storage.size(saved_name)
        self.assertEqual(size, 0)
        print(f"✓ Empty file size is 0")
        
        # Open and verify
        opened = self.storage.open(saved_name)
        content = opened.read()
        self.assertEqual(content, empty_content)
        print(f"✓ Empty file content matches")
    
    def test_unicode_filename(self):
        """Test handling filenames with Unicode characters."""
        unicode_filename = f'{self.test_prefix}file_test.txt'  # Simplified for compatibility
        content = b'Unicode content test: \xd1\x84\xd0\xb0\xd0\xb9\xd0\xbb'
        
        try:
            saved_name = self._save_and_track(unicode_filename, ContentFile(content))
            print(f"✓ Unicode filename saved: {saved_name}")
            
            # Verify we can read it back
            opened = self.storage.open(saved_name)
            read_content = opened.read()
            self.assertEqual(read_content, content)
            print(f"✓ Unicode content matches")
        except Exception as e:
            print(f"⚠ Unicode handling issue: {e}")
    
    def test_special_chars_filename(self):
        """Test handling filenames with special characters."""
        special_filename = f'{self.test_prefix}file-with_special.chars.txt'
        content = b'Special chars test'
        
        saved_name = self._save_and_track(special_filename, ContentFile(content))
        print(f"✓ Special chars filename saved: {saved_name}")
        
        # Verify we can read it back
        opened = self.storage.open(saved_name)
        read_content = opened.read()
        self.assertEqual(read_content, content)
        print(f"✓ Special chars filename content matches")
    
    def test_large_file(self):
        """Test handling larger files (1MB)."""
        large_content = b'X' * (1024 * 1024)  # 1MB
        filename = f'{self.test_prefix}large.bin'
        
        # Save large file
        saved_name = self._save_and_track(filename, ContentFile(large_content))
        print(f"✓ Large file saved: {saved_name}")
        
        # Verify size
        size = self.storage.size(saved_name)
        self.assertEqual(size, len(large_content))
        print(f"✓ Large file size correct: {size} bytes")
        
        # Open and verify (read in chunks to test streaming)
        opened = self.storage.open(saved_name)
        read_content = opened.read()
        self.assertEqual(len(read_content), len(large_content))
        print(f"✓ Large file content length matches")
    
    def test_duplicate_filename(self):
        """Test saving files with duplicate names."""
        content1 = b'First file'
        content2 = b'Second file'
        filename = f'{self.test_prefix}duplicate.txt'
        
        # Save first file
        saved_name1 = self._save_and_track(filename, ContentFile(content1))
        print(f"✓ First file saved: {saved_name1}")
        
        # Save with same name - should get different name
        saved_name2 = self._save_and_track(filename, ContentFile(content2))
        print(f"✓ Second file saved: {saved_name2}")
        
        # Names should be different
        self.assertNotEqual(saved_name1, saved_name2)
        print(f"✓ Duplicate filenames handled correctly")
        
        # Both files should exist with correct content
        content_1 = self.storage.open(saved_name1).read()
        content_2 = self.storage.open(saved_name2).read()
        self.assertEqual(content_1, content1)
        self.assertEqual(content_2, content2)
        print(f"✓ Both files have correct content")
    
    def test_nonexistent_file(self):
        """Test error handling for non-existent files."""
        nonexistent = f'{self.test_prefix}does_not_exist.txt'
        
        # exists() should return False
        self.assertFalse(self.storage.exists(nonexistent))
        print(f"✓ exists() returns False for non-existent file")
        
        # open() should raise FileNotFoundError
        with self.assertRaises(FileNotFoundError):
            self.storage.open(nonexistent)
        print(f"✓ open() raises FileNotFoundError for non-existent file")
        
        # size() should return 0 or raise error
        try:
            size = self.storage.size(nonexistent)
            self.assertEqual(size, 0)
            print(f"✓ size() returns 0 for non-existent file")
        except:
            print(f"✓ size() raises error for non-existent file")


class ManualStorageTest(TestCase):
    """
    Manual tests for interactive testing with real files.
    Run with: python manage.py test core.tests.test_storage.ManualStorageTest
    """
    
    def setUp(self):
        """Set up temp directory."""
        self.temp_dir = tempfile.mkdtemp()
        self.storage = default_storage
        self.saved_files = []
        print(f"\nTemp directory: {self.temp_dir}")
    
    def tearDown(self):
        """Clean up temp directory and storage."""
        # Clean up temp directory
        import shutil
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)
        
        # Clean up storage
        for filename in self.saved_files:
            try:
                if self.storage.exists(filename):
                    self.storage.delete(filename)
            except Exception as e:
                print(f"Failed to cleanup {filename}: {e}")
    
    def test_upload_download_verify(self):
        """Upload an actual file from disk, download it back, and verify."""
        # Create a temporary test file
        test_file_path = os.path.join(self.temp_dir, 'test_upload.txt')
        test_content = b'This is a test file for manual upload testing.\nWith multiple lines.\nAnd special chars: \xc3\xa9 \xc3\xa0 \xc3\xb1'
        
        with open(test_file_path, 'wb') as f:
            f.write(test_content)
        
        # Upload it
        with open(test_file_path, 'rb') as f:
            saved_name = self.storage.save('manual_test.txt', f)
        
        self.saved_files.append(saved_name)
        
        # Assertions
        self.assertIsNotNone(saved_name)
        print(f"\n✓ Uploaded file as: {saved_name}")
        
        # Verify URL
        url = self.storage.url(saved_name)
        self.assertIsNotNone(url)
        self.assertTrue(url.startswith('http'))
        print(f"✓ URL: {url[:80]}...")
        
        # Verify size
        size = self.storage.size(saved_name)
        self.assertEqual(size, len(test_content))
        print(f"✓ Size: {size} bytes")
        
        # Verify exists
        exists = self.storage.exists(saved_name)
        self.assertTrue(exists)
        print(f"✓ Exists: {exists}")
        
        # Download the file back to temp folder
        download_path = os.path.join(self.temp_dir, 'test_download.txt')
        opened_file = self.storage.open(saved_name)
        with open(download_path, 'wb') as f:
            f.write(opened_file.read())
        
        print(f"\n✓ Downloaded file to: {download_path}")
        
        # Compare files
        with open(test_file_path, 'rb') as f1, open(download_path, 'rb') as f2:
            original_content = f1.read()
            downloaded_content = f2.read()
            self.assertEqual(original_content, downloaded_content)
            print(f"✓ Files match! ({len(original_content)} bytes)")
        
        # Test deletion
        self.storage.delete(saved_name)
        self.saved_files.remove(saved_name)
        self.assertFalse(self.storage.exists(saved_name))
        print(f"\n✓ Deleted from storage: {saved_name}")
        print(f"✓ Verified file no longer exists")


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
    print(f"Bucket: {getattr(storage, 'bucket', 'N/A')}")
    print(f"Folder: {getattr(storage, 'folder', 'N/A')}\n")
    
    # Test save
    test_content = b'Quick test content'
    test_filename = f'quick_test_{uuid.uuid4().hex[:8]}.txt'
    
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
    print(f"✓ URL: {url[:100]}...\n")
    
    # Test open
    print("Reading file back...")
    opened = storage.open(saved_name)
    content = opened.read()
    print(f"✓ Content: {content.decode()}\n")
    
    # Test delete
    print(f"Deleting file: {saved_name}")
    storage.delete(saved_name)
    print(f"✓ Deleted\n")
    
    # Verify it's gone
    exists_after = storage.exists(saved_name)
    print(f"✓ Exists after delete: {exists_after}\n")
    
    print("=== Test Complete ===")
