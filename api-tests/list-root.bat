@echo off
REM List files in the root folder
REM Usage: list-root.bat [bucket] [token]
REM Example: list-root.bat test01 123

set BUCKET=%~1
set TOKEN=%~2

if "%BUCKET%"=="" set BUCKET=test01
if "%TOKEN%"=="" set TOKEN=123

curl -H "Authorization: Bearer %TOKEN%" "http://localhost:4000/api/azure/%BUCKET%/list"
