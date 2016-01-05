@echo off

doskey /MACROFILE=%HOMEDRIVE%\repo\environment\win\aliases.txt
set PATH=%APPDATA%\npm\node_modules\grunt-cli\bin;%PATH%
prompt $P$S$C$T$F$_$$
cd %HOMEDRIVE%\repo

@echo on