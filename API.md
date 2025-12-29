# Azurino API Documentation

RESTful API for Azure Blob Storage operations with bucket-scoped authentication.

## Base URL

```
http://localhost:4000/api
```

Production: `https://your-domain.com/api`

## Authentication

All API endpoints (except health checks) require Bearer token authentication.

### Headers

```http
Authorization: Bearer <token>
```

### Token Configuration

Tokens are scoped per bucket in `config/local.exs`:

```elixir
config :azurino, :bucket_tokens, %{
  "default" => ["token-abc123"],
  "reports" => ["token-xyz789"],
  "public" => [:all]  # Allow any token
}
```

### Error Responses

**401 Unauthorized** - Missing or invalid token:
```json
{"error": "Unauthorized"}
```

**403 Forbidden** - Token not allowed for bucket:
```json
{"error": "Token not allowed for bucket"}
```

## Endpoints

### Health Check

#### GET /api/health

Check API status (no authentication required).

**Response 200**:
```json
{
  "status": "ok",
  "message": "API is running"
}
```

**Example**:
```bash
curl http://localhost:4000/api/health
```

---

#### GET /api/health/:id

Check specific service health (no authentication required).

**Parameters**:
- `id` (path) - Service identifier

**Response 200**:
```json
{
  "id": "myservice",
  "status": "healthy"
}
```

**Example**:
```bash
curl http://localhost:4000/api/health/storage
```

---

### File Operations

All file operation endpoints require authentication and use the bucket from the URL path.

#### GET /api/azure/:bucket/exists

Check if a file exists in storage.

**Parameters**:
- `bucket` (path, required) - Bucket name
- `filename` (query, required) - File path (can include folders)

**Response 200**:
```json
{
  "exists": true,
  "filename": "reports/2024/summary.pdf"
}
```

**Example**:
```bash
curl -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/exists?filename=data.csv"
```

---

#### GET /api/azure/:bucket/info

Get file metadata (size, content type, last modified, etag).

**Parameters**:
- `bucket` (path, required) - Bucket name
- `filename` (query, required) - File path

**Response 200**:
```json
{
  "filename": "document.pdf",
  "size": 2048576,
  "content_type": "application/pdf",
  "last_modified": "Tue, 02 Jan 2024 12:00:00 GMT",
  "etag": "abc123xyz"
}
```

**Response 404** - File not found:
```json
{
  "status": "error",
  "message": "File not found"
}
```

**Example**:
```bash
curl -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/info?filename=report.pdf"
```

---

#### DELETE /api/azure/:bucket/delete

Delete a file from storage.

**Parameters**:
- `bucket` (path, required) - Bucket name
- `filename` (query, required) - File path to delete

**Response 200**:
```json
{
  "status": "success",
  "filename": "oldfile.txt",
  "message": "File deleted"
}
```

**Response 404** - File not found:
```json
{
  "status": "error",
  "message": "File not found"
}
```

**Example**:
```bash
curl -X DELETE \
  -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/delete?filename=temp.txt"
```

---

#### GET /api/azure/:bucket/download

Generate a signed URL for downloading a file.

**Parameters**:
- `bucket` (path, required) - Bucket name
- `filename` (query, required) - File path to download

**Response 200**:
```json
{
  "status": "success",
  "filename": "data.csv",
  "signed_url": {
    "path": "data.csv",
    "signature": "hmac-sha256-signature",
    "expires": 1704196800
  }
}
```

**Usage**: Use the signed URL parameters to download the file via `/api/azure/:bucket/download-signed`.

**Example**:
```bash
curl -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/download?filename=data.csv"
```

---

#### GET /api/azure/:bucket/download-signed

Download a file using signed URL parameters (no Bearer token required).

**Parameters**:
- `bucket` (path, required) - Bucket name
- `path` (query, required) - File path
- `signature` (query, required) - HMAC signature
- `expires` (query, required) - Expiration timestamp

**Response 200**: Binary file content with headers:
- `Content-Type`: File MIME type
- `Content-Disposition`: `attachment; filename="..."`
- `ETag`: File version identifier
- `Last-Modified`: Last modification date
- `Cache-Control`: `private, max-age=3600`

**Response 304** - Not Modified (if client sent `If-None-Match` or `If-Modified-Since`)

**Response 401** - Expired or invalid signature:
```json
{
  "status": "error",
  "message": "Signed URL has expired"
}
```

**Example**:
```bash
curl "http://localhost:4000/api/azure/default/download-signed?path=data.csv&signature=abc123&expires=1704196800" \
  -o data.csv
```

---

#### GET /api/azure/:bucket/list

List files and folders in a directory.

**Parameters**:
- `bucket` (path, required) - Bucket name
- `folder` (query, optional) - Folder path to list (empty string = root)

**Response 200**:
```json
{
  "status": "success",
  "files": [
    {
      "name": "report.pdf",
      "size": 1024,
      "modified": "2024-01-01"
    },
    {
      "name": "data.csv",
      "size": 2048,
      "modified": "2024-01-02"
    }
  ],
  "folders": [
    {
      "name": "archives"
    },
    {
      "name": "2024"
    }
  ]
}
```

**Example - List root**:
```bash
curl -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/list"
```

**Example - List specific folder**:
```bash
curl -H "Authorization: Bearer token-abc123" \
  "http://localhost:4000/api/azure/default/list?folder=reports/2024"
```

---

#### POST /api/azure/:bucket/upload

Upload a file to storage.

**Parameters**:
- `bucket` (path, required) - Bucket name
- `folder` (form, optional) - Destination folder (empty string = root)
- `file` (form, required) - File to upload (multipart/form-data)

**Request Headers**:
```http
Authorization: Bearer token-abc123
Content-Type: multipart/form-data
```

**Response 200**:
```json
{
  "status": "success",
  "filename": "report.pdf",
  "blob_path": "uploads/report.pdf",
  "signed_url": {
    "path": "uploads/report.pdf",
    "signature": "abc123",
    "expires": 1704196800
  },
  "message": "File uploaded successfully"
}
```

**Response 500** - Upload failed:
```json
{
  "status": "error",
  "message": "Upload error details"
}
```

**Example**:
```bash
curl -X POST \
  -H "Authorization: Bearer token-abc123" \
  -F "file=@/path/to/file.pdf" \
  -F "folder=reports" \
  "http://localhost:4000/api/azure/default/upload"
```

---

## File Path Conventions

### Supported Characters

File paths support:
- Letters (a-z, A-Z)
- Numbers (0-9)
- Special characters: `-`, `_`, `.`, `/`
- Spaces (will be handled by URL encoding)

### Folder Structure

Use forward slashes (`/`) to create folder hierarchy:

```
reports/2024/summary.pdf
data/exports/january/customers.csv
```

### Root vs Folders

- **Root**: Empty folder parameter or `folder=`
- **Subfolder**: `folder=myfolder` or `folder=path/to/folder`

### URL Encoding

Query parameters are automatically URL-encoded by clients. No manual encoding needed:

```bash
# This works automatically
curl "...?filename=my folder/my file.pdf"
```

---

## Rate Limiting

Currently no rate limiting is enforced. Consider implementing rate limiting in production.

---

## Error Handling

### Standard Error Format

```json
{
  "status": "error",
  "message": "Error description"
}
```

### HTTP Status Codes

- `200 OK` - Request succeeded
- `304 Not Modified` - Resource not changed (caching)
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Missing or invalid authentication
- `403 Forbidden` - Token not allowed for bucket
- `404 Not Found` - Resource doesn't exist
- `500 Internal Server Error` - Server error

---

## Client Examples

### cURL

```bash
# Set token as variable
TOKEN="token-abc123"
BUCKET="default"

# Check if file exists
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:4000/api/azure/$BUCKET/exists?filename=data.csv"

# Get file info
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:4000/api/azure/$BUCKET/info?filename=data.csv"

# Upload file
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@data.csv" \
  -F "folder=uploads" \
  "http://localhost:4000/api/azure/$BUCKET/upload"

# Delete file
curl -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:4000/api/azure/$BUCKET/delete?filename=uploads/data.csv"
```

### Python (requests)

```python
import requests

BASE_URL = "http://localhost:4000/api"
TOKEN = "token-abc123"
BUCKET = "default"

headers = {"Authorization": f"Bearer {TOKEN}"}

# Check if file exists
response = requests.get(
    f"{BASE_URL}/azure/{BUCKET}/exists",
    headers=headers,
    params={"filename": "data.csv"}
)
print(response.json())

# Upload file
with open("data.csv", "rb") as f:
    files = {"file": f}
    data = {"folder": "uploads"}
    response = requests.post(
        f"{BASE_URL}/azure/{BUCKET}/upload",
        headers=headers,
        files=files,
        data=data
    )
print(response.json())

# Get signed download URL
response = requests.get(
    f"{BASE_URL}/azure/{BUCKET}/download",
    headers=headers,
    params={"filename": "uploads/data.csv"}
)
signed_url = response.json()["signed_url"]

# Download using signed URL
download_url = f"{BASE_URL}/azure/{BUCKET}/download-signed"
response = requests.get(download_url, params=signed_url)
with open("downloaded.csv", "wb") as f:
    f.write(response.content)
```

### JavaScript (fetch)

```javascript
const BASE_URL = 'http://localhost:4000/api';
const TOKEN = 'token-abc123';
const BUCKET = 'default';

const headers = {
  'Authorization': `Bearer ${TOKEN}`
};

// Check if file exists
const response = await fetch(
  `${BASE_URL}/azure/${BUCKET}/exists?filename=data.csv`,
  { headers }
);
const data = await response.json();
console.log(data);

// Upload file
const formData = new FormData();
formData.append('file', fileInput.files[0]);
formData.append('folder', 'uploads');

const uploadResponse = await fetch(
  `${BASE_URL}/azure/${BUCKET}/upload`,
  {
    method: 'POST',
    headers: headers,
    body: formData
  }
);
const uploadData = await uploadResponse.json();
console.log(uploadData);
```

---

## Security Best Practices

1. **HTTPS in Production**: Always use HTTPS to protect tokens in transit
2. **Token Rotation**: Regularly rotate API tokens
3. **Principle of Least Privilege**: Give each token access to only required buckets
4. **Monitor Access**: Log and monitor API access patterns
5. **Signed URL Expiration**: Keep signed URL expiration times short (default: 1 hour)

---

## Troubleshooting

### Authentication Failures

**Problem**: Getting 401 Unauthorized

**Solutions**:
- Verify token is in `config/local.exs` for the bucket
- Check `Authorization` header format: `Bearer <token>`
- Ensure no extra whitespace in token

### File Not Found (404)

**Problem**: File exists but API returns 404

**Solutions**:
- Check filename spelling and case
- Verify folder path (use `/` separators)
- Ensure file was uploaded to correct bucket

### Upload Failures

**Problem**: Upload returns 500 error

**Solutions**:
- Verify file size within limits
- Check Azure SAS URL is valid and not expired
- Ensure SAS URL has write permissions (`sp=racwdl`)

---

## Support & Development

- **Repository**: Check your Git repository
- **Tests**: Run `mix test` to verify API functionality
- **Test Scripts**: Use `.bat` files in `api-tests/` directory

For development assistance, see the [Phoenix Framework documentation](https://hexdocs.pm/phoenix/).
