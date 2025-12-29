# API Test Scripts

Quick test scripts for the Azurino Azure Blob Storage API.

## Available Scripts

### health.bat
Check API health status (no authentication required).
```
health.bat
```

### upload.bat
Upload a file to Azure blob storage.
```
upload.bat [filename] [folder] [bucket] [token]

Examples:
  upload.bat                              # Defaults: test.txt, root folder, test01, token 123
  upload.bat myfile.pdf reports test01 123
  upload.bat data.csv "" test02 123      # Upload to root folder
```

### download.bat
Get a signed download URL for a file.
```
download.bat [filename] [bucket] [token]

Examples:
  download.bat                     # Defaults: test.txt, test01, token 123
  download.bat myfile.pdf test01 123
```

### delete.bat
Delete a file from Azure blob storage.
```
delete.bat [filename] [bucket] [token]

Examples:
  delete.bat                     # Defaults: test.txt, test01, token 123
  delete.bat myfile.pdf test01 123
```

### exists.bat
Check if a file exists in Azure blob storage.
```
exists.bat [filename] [bucket] [token]

Examples:
  exists.bat                     # Defaults: test.txt, test01, token 123
  exists.bat myfile.pdf test01 123
```

### info.bat
Get file metadata (size, content type, last modified, etag).
```
info.bat [filename] [bucket] [token]

Examples:
  info.bat                     # Defaults: test.txt, test01, token 123
  info.bat myfile.pdf test01 123
```

### list.bat
List files and folders in a specific folder.
```
list.bat                                    # Lists pomo/venv/ folder in test01
curl -H "Authorization: Bearer 123" "http://localhost:4000/api/azure/test01/list?folder=myfolder/"
```

### list-root.bat
List files and folders in the root folder.
```
list-root.bat [bucket] [token]

Examples:
  list-root.bat                  # Defaults: test01, token 123
  list-root.bat test02 123
```

## Authentication

All scripts (except health.bat) require authentication via Bearer token. Configure tokens in `config/local.exs`:

```elixir
config :azurino, :bucket_tokens, %{
  "test01" => ["123", "writer-test01"],
  "test02" => ["123"]
}
```

## Typical Workflow

1. Check API is running: `health.bat`
2. Upload a file: `upload.bat myfile.txt reports test01 123`
3. Check if it exists: `exists.bat reports/myfile.txt test01 123`
4. Get file info: `info.bat reports/myfile.txt test01 123`
5. List folder: Update list.bat with your folder path
6. Download: `download.bat reports/myfile.txt test01 123`
7. Delete: `delete.bat reports/myfile.txt test01 123`
