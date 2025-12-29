@echo off
REM Get file metadata (size, content type, etc.)
REM Usage: info.bat [filename] [bucket] [token]
REM Example: info.bat test.txt test01 123

set FILENAME=%~1
set BUCKET=%~2
set TOKEN=%~3

if "%FILENAME%"=="" set FILENAME=test.txt
if "%BUCKET%"=="" set BUCKET=test01
if "%TOKEN%"=="" set TOKEN=123

curl -H "Authorization: Bearer %TOKEN%" "http://localhost:4000/api/azure/%BUCKET%/info?filename=%FILENAME%"
