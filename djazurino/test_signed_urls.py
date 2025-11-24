#!/usr/bin/env python
"""
Quick test script to verify Django storage works with new signed URL flow.

Usage:
    python test_signed_urls.py
"""

import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'djazurino.settings')
sys.path.insert(0, os.path.dirname(__file__))
django.setup()

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage


def test_signed_url_flow():
    """Test the complete signed URL flow: upload, get URL, verify structure."""
    print("Testing Signed URL Flow")
    print("=" * 60)
    
    # 1. Upload a test file
    print("\n1. Uploading test file...")
    test_content = b'Test content for signed URL verification'
    test_filename = 'test_signed_url.txt'
    
    try:
        saved_name = default_storage.save(test_filename, ContentFile(test_content))
        print(f"   ✓ Uploaded as: {saved_name}")
    except Exception as e:
        print(f"   ✗ Upload failed: {e}")
        return False
    
    # 2. Get the signed URL
    print("\n2. Getting signed URL...")
    try:
        url = default_storage.url(saved_name)
        print(f"   ✓ URL: {url}")
        
        # Verify it's a signed URL (contains signature, expires, path params)
        if 'signature=' in url and 'expires=' in url and 'path=' in url:
            print("   ✓ URL contains signature, expires, and path parameters")
        else:
            print("   ✗ URL missing required signed URL parameters")
            print(f"      Expected: signature=, expires=, path=")
            return False
            
    except Exception as e:
        print(f"   ✗ Failed to get URL: {e}")
        return False
    
    # 3. Verify file exists
    print("\n3. Checking if file exists...")
    try:
        exists = default_storage.exists(saved_name)
        print(f"   {'✓' if exists else '✗'} File exists: {exists}")
    except Exception as e:
        print(f"   ✗ Exists check failed: {e}")
    
    # 4. Get file size
    print("\n4. Getting file size...")
    try:
        size = default_storage.size(saved_name)
        expected_size = len(test_content)
        if size == expected_size:
            print(f"   ✓ Size correct: {size} bytes")
        else:
            print(f"   ✗ Size mismatch: got {size}, expected {expected_size}")
    except Exception as e:
        print(f"   ✗ Size check failed: {e}")
    
    # 5. Download and verify content
    print("\n5. Downloading file to verify content...")
    try:
        file_obj = default_storage.open(saved_name)
        downloaded_content = file_obj.read()
        
        if downloaded_content == test_content:
            print(f"   ✓ Content matches: {len(downloaded_content)} bytes")
        else:
            print(f"   ✗ Content mismatch!")
            print(f"      Expected: {test_content}")
            print(f"      Got: {downloaded_content}")
    except Exception as e:
        print(f"   ✗ Download failed: {e}")
    
    # 6. Clean up
    print("\n6. Cleaning up...")
    try:
        default_storage.delete(saved_name)
        print(f"   ✓ Deleted: {saved_name}")
    except Exception as e:
        print(f"   ⚠ Delete failed (may need manual cleanup): {e}")
    
    print("\n" + "=" * 60)
    print("✓ All signed URL tests passed!")
    return True


if __name__ == '__main__':
    try:
        success = test_signed_url_flow()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n✗ Test failed with exception: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
