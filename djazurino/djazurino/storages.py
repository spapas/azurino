from django.core.files.storage import Storage
from django.core.files.base import File, ContentFile
from django.utils.deconstruct import deconstructible
from django.conf import settings
import requests
from io import BytesIO
from urllib.parse import quote


@deconstructible
class AzureBlobStorage(Storage):
    """
    Custom Django storage backend for Azure Blob Storage via Elixir API.
    
    Usage in settings.py:
        DEFAULT_FILE_STORAGE = 'path.to.AzureBlobStorage'
        AZURE_API_BASE_URL = 'http://localhost:4000/api/azure'
        AZURE_STORAGE_FOLDER = 'uploads'  # Optional, default folder
    """
    
    def __init__(self, base_url=None, folder=None, api_token=None):
        self.base_url = base_url or getattr(settings, 'AZURE_API_BASE_URL', 'http://localhost:4000/api')
        self.folder = folder or getattr(settings, 'AZURE_STORAGE_FOLDER', 'uploads')
        self.api_token = api_token or getattr(settings, 'AZURE_API_TOKEN', None)
    
    def _get_headers(self):
        """Get headers including authentication token."""
        headers = {}
        if self.api_token:
            headers['Authorization'] = f'Bearer {self.api_token}'
        return headers
    
    def _save(self, name, content):
        """
        Save file to Azure Blob Storage via Elixir API.
        
        Args:
            name: filename to save
            content: Django File object
            
        Returns:
            The blob_path of the saved file
        """
        url = f"{self.base_url}/upload"
        
        # Read content and prepare multipart upload
        content.seek(0)
        files = {'file': (name, content.read(), content.content_type if hasattr(content, 'content_type') else 'application/octet-stream')}
        data = {'folder': self.folder}
        
        try:
            response = requests.post(url, files=files, data=data, headers=self._get_headers(), timeout=30)
            response.raise_for_status()
            
            result = response.json()
            if result.get('status') == 'success':
                # Return the blob_path which includes folder/filename
                return result.get('blob_path', name)
            else:
                raise Exception(f"Upload failed: {result.get('message', 'Unknown error')}")
        except requests.exceptions.RequestException as e:
            raise Exception(f"Upload request failed: {str(e)}")
    
    def _open(self, name, mode='rb'):
        """
        Open file from Azure Blob Storage.
        
        Args:
            name: blob path (folder/filename)
            mode: file mode
            
        Returns:
            Django File object with content
        """
        # Use the stream endpoint to download file content
        url = f"{self.base_url}/download-stream/{quote(name, safe='')}"
        
        try:
            response = requests.get(url, headers=self._get_headers(), timeout=30)
            
            if response.status_code == 404:
                raise FileNotFoundError(f"File not found: {name}")
            
            response.raise_for_status()
            
            # Return a File object with the binary content
            return ContentFile(response.content, name=name)
        except requests.exceptions.RequestException as e:
            raise Exception(f"Download failed: {str(e)}")
    
    def delete(self, name):
        """
        Delete file from Azure Blob Storage.
        Note: Delete is not yet implemented in the Elixir API.
        """
        url = f"{self.base_url}/delete/{quote(name, safe='')}"
        
        try:
            response = requests.delete(url, timeout=10)
            
            if response.status_code == 404:
                # File doesn't exist, consider it deleted
                return
            
            result = response.json()
            if result.get('status') == 'error':
                # API might not be implemented yet
                pass
        except requests.exceptions.RequestException:
            # Silently fail if delete endpoint doesn't exist
            pass
    
    def exists(self, name):
        """Check if file exists in Azure Blob Storage."""
        url = f"{self.base_url}/exists/{quote(name, safe='')}"
        
        try:
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                return data.get('exists', False)
            return False
        except requests.exceptions.RequestException:
            return False
    
    def url(self, name):
        """
        Get signed URL for file access.
        Returns the Azure Blob URL with SAS token.
        """
        url = f"{self.base_url}/download/{quote(name, safe='')}"
        
        try:
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                return data.get('url')
            return None
        except requests.exceptions.RequestException:
            return None
    
    def size(self, name):
        """Get file size from blob metadata."""
        url = f"{self.base_url}/info/{quote(name, safe='')}"
        
        try:
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                return data.get('size', 0)
            return 0
        except requests.exceptions.RequestException:
            return 0
    
    def get_accessed_time(self, name):
        """Azure Blob Storage doesn't provide accessed time."""
        return None
    
    def get_created_time(self, name):
        """Get created/modified time from blob metadata."""
        url = f"{self.base_url}/info/{quote(name, safe='')}"
        
        try:
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                # last_modified is in HTTP date format
                last_modified = data.get('last_modified')
                if last_modified:
                    from email.utils import parsedate_to_datetime
                    return parsedate_to_datetime(last_modified)
            return None
        except (requests.exceptions.RequestException, ValueError):
            return None
    
    def get_modified_time(self, name):
        """Get modified time (same as created time for blobs)."""
        return self.get_created_time(name)
    
    def listdir(self, path):
        """
        List files and folders at the given path.
        
        Returns:
            Tuple of (directories, files)
        """
        url = f"{self.base_url}/list"
        params = {'folder': path} if path else {}
        
        try:
            response = requests.get(url, params=params, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                folders = data.get('folders', [])
                files = data.get('files', [])
                
                # Remove path prefix from results
                if path:
                    prefix = path.rstrip('/') + '/'
                    folders = [f.replace(prefix, '').rstrip('/') for f in folders]
                    files = [f.replace(prefix, '') for f in files]
                
                return (folders, files)
            return ([], [])
        except requests.exceptions.RequestException:
            return ([], [])