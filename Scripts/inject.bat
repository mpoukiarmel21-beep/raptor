@echo off
set INPUT=%~1
if "%INPUT%"=="" set INPUT=Input.ipa
set DYLIB=Tweak\.theos\obj\raptor.dylib
set WORKDIR=%TEMP%\raptor_%RANDOM%
mkdir "%WORKDIR%"
powershell -Command "Expand-Archive -Path '%INPUT%' -DestinationPath '%WORKDIR%' -Force"
for /d %%A in ("%WORKDIR%\Payload\*.app") do set APP=%%A
copy /Y "%DYLIB%" "%APP%\Frameworks\raptor.dylib"
optool install -c load -p @executable_path/Frameworks/raptor.dylib -t "%APP%\Instagram" 2>nul || echo optool not found
ldid -S "%APP%\Instagram" 2>nul
powershell -Command "Compress-Archive -Path '%WORKDIR%\Payload' -DestinationPath 'raptor.ipa' -Force"
echo -> raptor.ipa

