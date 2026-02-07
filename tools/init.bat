@echo off
chcp 65001 >nul 2>&1

:: ========================================
:: 子模块管理入口
:: ========================================
:: 转发到 submodules.bat 执行

call "%~dp0submodule\submodules.bat" %*
