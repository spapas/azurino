from django.core.files.storage import Storage
from django.core.files.base import File, ContentFile
from django.utils.deconstruct import deconstructible
from django.conf import settings
import requests
from io import BytesIO
from urllib.parse import quote, urlparse, urlunparse
import mimetypes
import logging
import time

logger = logging.getLogger(__name__)


@deconstructible
class AzureBlobStorage(Storage):
    """
    Custom Django storage backend for Azure Blob Storage via Elixir API.
    
    Usage in settings.py:
        DEFAULT_FILE_STORAGE = 'path.to.AzureBlobStorage'
        AZURE_API_BASE_URL = 'http://127.0.0.1:4000/api/azure'
        AZURE_STORAGE_FOLDER = 'uploads'  # Optional, default folder
    """
    
    def __init__(self, base_url=None, folder=None, api_token=None):
        self.base_url = base_url or getattr(settings, 'AZURE_API_BASE_URL', 'http://127.0.0.1:4000/api/azure')
        self.folder = folder or getattr(settings, 'AZURE_STORAGE_FOLDER', 'uploads')
        self.api_token = api_token or getattr(settings, 'AZURE_API_TOKEN', '123')

        # Normalize localhost to 127.0.0.1 in development to avoid IPv6/DNS
        # or environment proxy resolution delays on some systems.
        try:
            self.base_url = self._normalize_base_url(self.base_url)
        except Exception:
            pass

        # Reuse a session for performance (avoid repeated TCP handshakes).
        self._session = requests.Session()
        try:
            self._session.trust_env = False
        except Exception:
            # Some requests versions/environments may not allow modifying this
            # attribute; ignore if unavailable.
            pass
    
    def _get_headers(self):
        """Get headers including authentication token."""
        headers = {}
        if self.api_token:
            headers['Authorization'] = f'Bearer {self.api_token}'
        return headers

    def _normalize_base_url(self, url):
        """If host is 'localhost', normalize to '127.0.0.1' to avoid
        potential IPv6/DNS/proxy resolution delays in local dev environments.
        """
        try:
            parsed = urlparse(url)
            hostname = parsed.hostname
            if hostname and hostname.lower() == 'localhost':
                host = '127.0.0.1'
                # preserve port if present
                netloc = host
                if parsed.port:
                    netloc = f"{host}:{parsed.port}"
                new = parsed._replace(netloc=netloc)
                return urlunparse(new)
        except Exception:
            pass
        return url
    
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
        
        # Prepare multipart upload. Prefer passing a file-like object so
        # requests can stream it. Fall back to bytes if needed.
        content.seek(0)
        # Guess content type from filename if not provided on the file object
        guessed_type, _ = mimetypes.guess_type(name)
        content_type = getattr(content, 'content_type', None) or guessed_type or 'application/octet-stream'

        # If content is a file-like object, pass it directly; otherwise wrap bytes
        if hasattr(content, 'read'):
            fileobj = content
            # Ensure pointer is at start
            try:
                fileobj.seek(0)
            except Exception:
                pass
        else:
            file_bytes = content.read() if hasattr(content, 'read') else content
            fileobj = BytesIO(file_bytes)

        files = {'file': (name, fileobj, content_type)}
        data = {'folder': self.folder}
        
        start = time.monotonic()
        try:
            response = self._session.post(url, files=files, data=data, headers=self._get_headers(), timeout=30)
            elapsed = time.monotonic() - start
            # requests provides elapsed on the response as well (a timedelta)
            resp_elapsed_td = getattr(response, 'elapsed', None)
            resp_elapsed = resp_elapsed_td.total_seconds() if resp_elapsed_td is not None else None
            logger.info("Upload request: url=%s status=%s elapsed=%.3fs resp_elapsed=%s", url, response.status_code, elapsed, resp_elapsed)

            response.raise_for_status()

            result = response.json()
            if result.get('status') == 'success':
                # Return the blob_path which includes folder/filename
                return result.get('blob_path', name)
            else:
                raise Exception(f"Upload failed: {result.get('message', 'Unknown error')}")
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Upload request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
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
        
        start = time.monotonic()
        try:
            response = self._session.get(url, headers=self._get_headers(), timeout=30)
            elapsed = time.monotonic() - start
            logger.info("Download request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)

            if response.status_code == 404:
                raise FileNotFoundError(f"File not found: {name}")

            response.raise_for_status()

            # Return a File object with the binary content
            return ContentFile(response.content, name=name)
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Download request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            raise Exception(f"Download failed: {str(e)}")
    
    def delete(self, name):
        """
        Delete file from Azure Blob Storage.
        Note: Delete is not yet implemented in the Elixir API.
        """
        url = f"{self.base_url}/delete/{quote(name, safe='')}"
        
        start = time.monotonic()
        try:
            response = self._session.delete(url, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("Delete request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)
            
            if response.status_code == 404:
                # File doesn't exist, consider it deleted
                return
            
            # Try to parse response JSON for status; otherwise treat 2xx as success
            try:
                result = response.json()
                if result.get('status') == 'error':
                    # API returned an error payload; ignore for now but user may want to log it
                    pass
            except ValueError:
                # Not JSON — ignore and treat as success for delete
                pass
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Delete request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            # Silently fail if delete endpoint doesn't exist
            pass
    
    def exists(self, name):
        """Check if file exists in Azure Blob Storage."""
        url = f"{self.base_url}/exists/{quote(name, safe='')}"
        
        start = time.monotonic()
        try:
            response = self._session.get(url, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("Exists request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)

            if response.status_code == 200:
                data = response.json()
                return data.get('exists', False)
            return False
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Exists request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            return False
    
    def url(self, name):  # type: ignore[override]
        """
        Get signed URL for file access.
        Returns the Azure Blob URL with SAS token.
        """
        url = f"{self.base_url}/download/{quote(name, safe='')}"
        
        start = time.monotonic()
        try:
            response = self._session.get(url, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("Signed URL request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)

            if response.status_code == 200:
                data = response.json()
                return data.get('url')
            return None
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Signed URL request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            return None
    
    def size(self, name):
        """Get file size from blob metadata."""
        url = f"{self.base_url}/info/{quote(name, safe='')}"
        
        start = time.monotonic()
        try:
            response = self._session.get(url, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("Size request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)

            if response.status_code == 200:
                data = response.json()
                return data.get('size', 0)
            return 0
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("Size request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            return 0
    
    def get_accessed_time(self, name):  # type: ignore[override]
        """Azure Blob Storage doesn't provide accessed time."""
        return None
    
    def get_created_time(self, name):  # type: ignore[override]
        """Get created/modified time from blob metadata."""
        url = f"{self.base_url}/info/{quote(name, safe='')}"
        
        start = time.monotonic()
        try:
            response = self._session.get(url, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("Info request: url=%s status=%s elapsed=%.3fs", url, response.status_code, elapsed)

            if response.status_code == 200:
                data = response.json()
                # last_modified is in HTTP date format
                last_modified = data.get('last_modified')
                if last_modified:
                    from email.utils import parsedate_to_datetime
                    return parsedate_to_datetime(last_modified)
            return None
        except (requests.exceptions.RequestException, ValueError) as e:
            elapsed = time.monotonic() - start
            logger.exception("Info request failed: url=%s elapsed=%.3fs error=%s", url, elapsed, e)
            return None
    
    def get_modified_time(self, name):  # type: ignore[override]
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
        
        start = time.monotonic()
        try:
            response = self._session.get(url, params=params, headers=self._get_headers(), timeout=10)
            elapsed = time.monotonic() - start
            logger.info("List request: url=%s params=%s status=%s elapsed=%.3fs", url, params, response.status_code, elapsed)

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
        except requests.exceptions.RequestException as e:
            elapsed = time.monotonic() - start
            logger.exception("List request failed: url=%s params=%s elapsed=%.3fs error=%s", url, params, elapsed, e)
            return ([], [])