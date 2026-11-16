@echo off
chcp 936 >nul 2>&1
title 一键合并 install.esd
cd /d "%~dp0"

echo ==========================================
echo   自动把 3 个分片合并成一个 install.esd
echo ==========================================
echo.

set "P1=install_lite_26300.10066.esd.00.part"
set "P2=install_lite_26300.10066.esd.01.part"
set "P3=install_lite_26300.10066.esd.02.part"

if not exist "%P1%" goto :MISSING
if not exist "%P2%" goto :MISSING
if not exist "%P3%" goto :MISSING

echo 正在合并，5GB 大约需要 1~3 分钟，请不要关闭窗口...
echo.

copy /b "%P1%"+"%P2%"+"%P3%" "install.esd"

if not exist "install.esd" goto :FAIL

echo.
echo 合并完成！生成文件：install.esd
dir install.esd
echo.
echo 校验（可选）：
certutil -hashfile install.esd SHA256
echo.
pause
exit /b 0

:MISSING
echo [错误] 三个分片没有全部放在这个文件夹里。
echo 请把下面三个文件和本 bat 放在同一个文件夹：
echo   %P1%
echo   %P2%
echo   %P3%
echo.
pause
exit /b 1

:FAIL
echo [错误] 合并失败。可能是磁盘空间不足（需要至少 5.5GB 空闲）。
echo.
pause
exit /b 1
