@echo off

doskey /MACROFILE=%HOMEDRIVE%\repo\devenv\win\aliases.txt
set PATH=%APPDATA%\npm\node_modules\grunt-cli\bin;%PATH%
prompt $P$S$C$T$F$_$$
cd %HOMEDRIVE%\repo

@echo on