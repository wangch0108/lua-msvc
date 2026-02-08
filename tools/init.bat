@echo off
chcp 65001 >nul 2>&1

:: ========================================
:: 子模块管理入口
:: ========================================

:: 检查第一个参数决定执行什么操作
if "%1"=="link-skills" (
    call "%~dp0link-skills.bat"
    exit /b %errorlevel%
)

:: 默认：转发到 submodules.bat 执行
call "%~dp0submodule\submodules.bat" %*
