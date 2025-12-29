@echo off
REM Check if a file exists in Azure blob storage
REM Usage: exists.bat [filename] [bucket] [token]
REM Example: exists.bat test.txt test01 123

set FILENAME=%~1
set BUCKET=%~2
set TOKEN=%~3

if "%FILENAME%"=="" set FILENAME=pomo%%2Fvenv%%2Fpyvenv.cfg
if "%BUCKET%"=="" set BUCKET=test01
if "%TOKEN%"=="" set TOKEN=123

curl -H "Authorization: Bearer %TOKEN%" "http://localhost:4000/api/azure/%BUCKET%/exists?filename=%FILENAME%"
