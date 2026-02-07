@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion

:: ========================================
:: Lua-MSVC 子模块管理工具 - 用户入口
:: ========================================
::
:: 功能:
::   - 自动检测并安装 Python/Lua 环境
::   - 执行子模块管理命令
::
:: 使用方式:
::   submodules.bat [init^|update^|status] [选项]
::
:: ========================================

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%..\.."
set "LUA_SCRIPT=%SCRIPT_DIR%submodules.lua"
set "LUA_CONFIG=%SCRIPT_DIR%submodule_cfg.lua"
set "PYTHON_SCRIPT=%SCRIPT_DIR%submodules.py"
set "PYTHON_CONFIG=%SCRIPT_DIR%submodules.config"

:: 转换为绝对路径
for %%i in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fi"
for %%i in ("%LUA_SCRIPT%") do set "LUA_SCRIPT=%%~fi"
for %%i in ("%PYTHON_SCRIPT%") do set "PYTHON_SCRIPT=%%~fi"

cd /d "%PROJECT_ROOT%"

:: 解析命令
set "COMMAND=%~1"
if "%COMMAND%"=="" set "COMMAND=status"

:: ========================================
:: 步骤 1: 查找 Lua (优先使用)
:: ========================================

set "LUA_CMD="

:: 1. 检查项目构建输出中的 Lua
for %%c in (Debug Release) do (
    for %%a in (Windows-x64 windows-x86_64) do (
        for %%p in (bin\%%c-%%a\lua\lua.exe bin\%%c-%%a\lua.exe) do (
            if exist "%PROJECT_ROOT%\%%p" (
                set "LUA_CMD=%PROJECT_ROOT%\%%p"
                goto :lua_found
            )
        )
    )
)

:: 2. 检查 PATH 中的 lua
lua --version >nul 2>&1
if not errorlevel 1 (
    set "LUA_CMD=lua"
    goto :lua_found
)

:: 3. 检查常见 Lua 安装位置
for %%p in (
    "C:\Program Files\Lua\lua.exe"
    "C:\Lua\lua.exe"
    "C:\lua5.4\lua.exe"
    "C:\lua5.3\lua.exe"
) do (
    if exist %%p (
        set "LUA_CMD=%%p"
        goto :lua_found
    )
)

:: ========================================
:: 步骤 2: Lua 未找到，查找 Python
:: ========================================

:find_python
set "PYTHON_CMD="

:: 1. 尝试 py launcher
py --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
    goto :python_found
)

:: 2. 尝试 python3
python3 --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON_CMD=python3"
    goto :python_found
)

:: 3. 尝试 python (排除 Python 2)
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set "PY_VERSION=%%v"
echo %PY_VERSION% | findstr /C:"3." >nul
if not errorlevel 1 (
    set "PYTHON_CMD=python"
    goto :python_found
)

:: 4. 检查常见安装位置
for %%p in (
    "%LOCALAPPDATA%\Programs\Python\python.exe"
    "C:\Python39\python.exe"
    "C:\Python310\python.exe"
    "C:\Python311\python.exe"
    "C:\Python312\python.exe"
) do (
    if exist %%p (
        set "PYTHON_CMD=%%~dpnf"
        goto :python_found
    )
)

:: 都没找到，显示安装帮助
goto :show_install_help

:: ========================================
:: 步骤 3: 找到 Lua，执行脚本
:: ========================================

:lua_found
%LUA_CMD% "%LUA_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not %EXIT_CODE%==0 (
    echo.
    echo ========================================
    echo 执行失败，退出代码: %EXIT_CODE%
    echo ========================================
    pause
)
exit /b %EXIT_CODE%

:: ========================================
:: 步骤 4: 找到 Python，执行脚本
:: ========================================

:python_found
%PYTHON_CMD% "%PYTHON_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not %EXIT_CODE%==0 (
    echo.
    echo ========================================
    echo 执行失败，退出代码: %EXIT_CODE%
    echo ========================================
    pause
)
exit /b %EXIT_CODE%

:: ========================================
:: 安装帮助
:: ========================================

:show_install_help
echo ========================================
echo 未找到必需的运行环境
echo ========================================
echo.
echo 本工具需要以下环境之一:
echo.
echo [选项 A] 使用 Lua (推荐)
echo     如果已编译本项目，Lua 应该位于:
echo     bin\{Debug^|Release}-Windows-x64\lua\lua.exe
echo.
echo     如果需要单独安装 Lua:
echo     https://lua.org/download.html
echo.
echo [选项 B] 使用 Python
echo     本工具需要 Python 3.6 或更高版本。
echo.
echo     安装方式:
echo     1. Microsoft Store - 搜索 "Python 3.x" 并安装
echo     2. winget install Python.Python.3.12
echo     3. https://www.python.org/downloads/
echo        (勾选 "Add Python to PATH")
echo.
echo ========================================
pause
exit /b 1
