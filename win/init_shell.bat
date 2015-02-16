@echo off

doskey /MACROFILE=aliases.txt
set PATH=%APPDATA%\npm\node_modules\grunt-cli\bin;%PATH%
prompt $P$S$C$T$F$_$$
cd C:\repo

@echo on