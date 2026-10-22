@echo off
rem Jalankan dari direktori utama otp-AI.
if "%TPBASE%"=="" set TPBASE=C:\TP
set TPCBIN=%TPBASE%\BIN\TPC.EXE
if not exist %TPCBIN% set TPCBIN=%TPBASE%\TPC.EXE
if not exist %TPCBIN% goto missing
if not exist BIN\NUL mkdir BIN
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\BASIC.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\BAYDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\CROSSVAL.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\DATAPREP.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\FUZDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\KMEANS.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\KNNDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\LOGDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\MODELIO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\NNDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\OPTDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\PATHDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\PERDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\PLOTDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\QDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\REGDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\REGMULT.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\RULEDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\TEXTDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN EXAMPLES\TREEDEMO.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN TESTS\ORACL2.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN TESTS\ORACLE.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN TESTS\TESTADV.PAS
if errorlevel 1 goto failed
%TPCBIN% /B /$R+ /$S+ /UUNITS;%TPBASE%\UNITS;%TPBASE%\BGI /IEXAMPLES /EBIN TESTS\TESTALL.PAS
if errorlevel 1 goto failed
echo Build selesai. Jalankan BIN\TESTALL dan BIN\TESTADV dari folder otp-AI.
goto end
:missing
echo TPC.EXE tidak ditemukan. Atur SET TPBASE=C:\TP sesuai instalasi.
goto end
:failed
echo Build gagal. Baca pesan compiler di atas.
:end
