@echo off
echo Kopieer onderstaande naar het "License File" veld in Microsoft Azure - Custom Deployment
echo.
powershell "$inputFilePath = ('%1') ; [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($inputFilePath))"
pause