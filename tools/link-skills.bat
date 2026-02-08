@echo off
chcp 65001 >nul 2>&1

setlocal EnableDelayedExpansion

:: ========================================
:: Claude Skills 软链接管理脚本
:: ========================================
:: 将 tools\claude_skills 下的所有目录
:: 软链接到 .claude\skills 下

set "SOURCE_DIR=%~dp0claude_skills"
set "TARGET_DIR=%~dp0..\.claude\skills"

:: 转换为绝对路径
call :resolve_path "!SOURCE_DIR!" SOURCE_DIR
call :resolve_path "!TARGET_DIR!" TARGET_DIR

echo.
echo ========================================
echo Claude Skills 软链接管理
echo ========================================
echo.
echo 源目录: !SOURCE_DIR!
echo 目标目录: !TARGET_DIR!
echo.

:: 检查源目录是否存在
if not exist "!SOURCE_DIR!" (
    echo [错误] 源目录不存在: !SOURCE_DIR!
    pause
    exit /b 1
)

:: 创建目标目录（如果不存在）
if not exist "!TARGET_DIR!" (
    echo [创建] 目标目录: !TARGET_DIR!
    mkdir "!TARGET_DIR!"
)


:: 遍历源目录下的所有子目录并创建软链接
set COUNT=0
for /D %%d in ("!SOURCE_DIR!\*") do (
    set "DIR_NAME=%%~nxd"
    set "LINK_PATH=!TARGET_DIR!\%%~nxd"
    set "TARGET_PATH=%%d"

    echo.
    echo [处理] %%~nxd

    :: 检查链接是否已存在
    if exist "!LINK_PATH!" (
        :: 检查是否是符号链接
        dir /AL "!LINK_PATH!" >nul 2>&1
        if !errorlevel! equ 0 (
            echo [跳过] 符号链接已存在: %%~nxd
        ) else (
            echo [警告] 目标存在但不是符号链接: %%~nxd
        )
    ) else (
        :: 创建目录联接（无需管理员权限）
        mklink /J "!LINK_PATH!" "!TARGET_PATH!" >nul 2>&1
        if !errorlevel! equ 0 (
            echo [成功] 已创建符号链接: %%~nxd
            set /a COUNT+=1
        ) else (
            echo [失败] 无法创建符号链接: %%~nxd
        )
    )
)

echo.
echo ========================================
echo 完成！共创建 !COUNT! 个符号链接
echo ========================================
pause
exit /b 0

:: ========================================
:: 解析路径为绝对路径
:: ========================================
:resolve_path
set "%~2=%~f1"
exit /b 0
