@echo off
REM Delete a file from Azure blob storage
REM Usage: delete.bat [filename] [bucket] [token]
REM Example: delete.bat test.txt test01 123

set FILENAME=%~1
set BUCKET=%~2
set TOKEN=%~3

if "%FILENAME%"=="" set FILENAME=test.txt
if "%BUCKET%"=="" set BUCKET=test01
if "%TOKEN%"=="" set TOKEN=123

curl -X DELETE -H "Authorization: Bearer %TOKEN%" "http://localhost:4000/api/azure/%BUCKET%/delete?filename=%FILENAME%"
