@echo off
REM Upload a file to Azure blob storage
REM Usage: upload.bat [filename] [folder] [bucket] [token]
REM Example: upload.bat test.txt myfolder test01 123

set FILENAME=%~1
set FOLDER=%~2
set BUCKET=%~3
set TOKEN=%~4

if "%FILENAME%"=="" set FILENAME=test.txt
if "%FOLDER%"=="" set FOLDER=
if "%BUCKET%"=="" set BUCKET=test01
if "%TOKEN%"=="" set TOKEN=123

REM Create a test file if it doesn't exist
if not exist "%FILENAME%" (
    echo Creating test file: %FILENAME%
    echo This is a test file created at %date% %time% > "%FILENAME%"
)

curl -X POST -H "Authorization: Bearer %TOKEN%" -F "file=@%FILENAME%" -F "folder=%FOLDER%" http://localhost:4000/api/azure/%BUCKET%/upload
