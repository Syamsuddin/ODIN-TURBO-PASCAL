@echo off
setlocal
cd /d "%~dp0"
if not exist BIN mkdir BIN
if not exist BUILD mkdir BUILD
for %%F in (EXAMPLES\*.PAS) do (
  fpc -Mtp -B -Cr -Co -Ci -Ct -FuUNITS -FiEXAMPLES -FUBUILD -FEBIN "%%F"
  if errorlevel 1 exit /b 1
)
for %%F in (TESTS\*.PAS) do (
  fpc -Mtp -B -Cr -Co -Ci -Ct -FuUNITS -FiEXAMPLES -FUBUILD -FEBIN "%%F"
  if errorlevel 1 exit /b 1
)
echo Build selesai. Jalankan BIN\TESTALL.EXE dan BIN\TESTADV.EXE dari folder otp-AI.
