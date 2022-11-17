@ECHO OFF
SET "_filename=%TEMP%\%~n0"
SET "_sapsystem=%~1"
REG QUERY HKLM\Software\SAP /s /v SAPEXE | FINDSTR /C:SAPEXE >"%_filename%.tmp"
FOR /F "tokens=3,6 delims=\\ " %%G IN (%_filename%.tmp) DO (
	CALL :func_checkBatchConfig %%G %%H
)
DEL /Q "%_filename%.tmp"
GOTO :eof

:func_checkBatchConfig
SET "_batchconfig=%1\usr\sap\%2\J%_sapsystem%\j2ee\configtool\batchconfig.bat"
IF EXIST "%_batchconfig%" (
		CALL "%_batchconfig%" -task get.versions.of.deployed.units
)
EXIT /B
