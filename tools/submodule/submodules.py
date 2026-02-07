# -*- coding: utf-8 -*-
"""
Lua-MSVC 子模块管理工具
===================================

自动管理 Git 子模块的初始化、更新和版本控制。

配置文件: tools/submodules.config (JSON 格式)
使用方式: 通过 tools/submodules.bat 调用

作者: lua-msvc 项目组
"""

from __future__ import print_function
import os
import sys
import json
import subprocess
import shutil

# Python 2/3 兼容性
try:
    from pathlib import Path
    HAS_PATHLIB = True
except ImportError:
    HAS_PATHLIB = False

try:
    basestring
except NameError:
    basestring = str

# ========================================
# 配置与常量
# ========================================

if HAS_PATHLIB:
    SCRIPT_DIR = Path(__file__).parent.resolve()
    PROJECT_ROOT = SCRIPT_DIR.parent
    CONFIG_FILE = SCRIPT_DIR / "submodules.config"
else:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
    CONFIG_FILE = os.path.join(SCRIPT_DIR, "submodules.config")

# 颜色输出 (Windows 控制台兼容)
class Colors(object):
    """终端颜色代码"""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

    @staticmethod
    def enable():
        """启用 ANSI 颜色 (Windows 10+ 需要)"""
        if sys.platform == "win32":
            try:
                import ctypes
                kernel32 = ctypes.windll.kernel32
                kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
            except:
                pass

    @staticmethod
    def disable():
        """禁用颜色输出"""
        for attr in dir(Colors):
            if not attr.startswith('_') and attr.isupper():
                setattr(Colors, attr, '')


# ========================================
# 工具函数
# ========================================

def print_header(text):
    """打印标题"""
    print("\n" + Colors.HEADER + Colors.BOLD + "=" * 50 + Colors.ENDC)
    print(Colors.HEADER + Colors.BOLD + text.center(50) + Colors.ENDC)
    print(Colors.HEADER + Colors.BOLD + "=" * 50 + Colors.ENDC + "\n")


def print_success(text):
    """打印成功信息"""
    print(Colors.OKGREEN + "[OK] " + text + Colors.ENDC)


def print_error(text):
    """打印错误信息"""
    print(Colors.FAIL + "[ERR] " + text + Colors.ENDC, file=sys.stderr)


def print_warning(text):
    """打印警告信息"""
    print(Colors.WARNING + "[WARN] " + text + Colors.ENDC)


def print_info(text):
    """打印信息"""
    print(Colors.OKCYAN + "[INFO] " + text + Colors.ENDC)


def run_command(cmd, cwd=None, capture=True):
    """
    执行命令并返回结果

    Args:
        cmd: 命令列表
        cwd: 工作目录
        capture: 是否捕获输出

    Returns:
        (返回码, 标准输出, 标准错误)
    """
    try:
        if capture:
            if sys.version_info[0] >= 3:
                result = subprocess.run(
                    cmd,
                    cwd=cwd,
                    capture_output=True,
                    text=True,
                    creationflags=subprocess.CREATE_NO_WINDOW
                )
                return result.returncode, result.stdout, result.stderr
            else:
                # Python 2 兼容
                proc = subprocess.Popen(
                    cmd,
                    cwd=cwd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                stdout, stderr = proc.communicate()
                return proc.returncode, stdout.decode('utf-8', errors='ignore'), stderr.decode('utf-8', errors='ignore')
        else:
            return subprocess.call(cmd, cwd=cwd), "", ""
    except FileNotFoundError:
        return 1, "", "Command not found: " + cmd[0]
    except Exception as e:
        return 1, "", str(e)


def check_git_available():
    """检查 Git 是否可用"""
    return shutil.which('git') is not None if hasattr(shutil, 'which') else \
           any(os.path.exists(os.path.join(p, 'git.exe')) for p in os.environ.get('PATH', '').split(os.pathsep))


# ========================================
# 配置管理
# ========================================

class SubmoduleConfig(object):
    """子模块配置管理"""

    def __init__(self, config_path):
        self.config_path = config_path
        self.submodules = []

    def load(self):
        """加载配置文件"""
        config_path_str = str(self.config_path) if HAS_PATHLIB else self.config_path

        if not os.path.exists(config_path_str):
            print_error("配置文件不存在: " + config_path_str)
            return False

        try:
            with open(config_path_str, 'r') as f:
                data = json.load(f)

            self.submodules = data.get('submodules', [])

            if not self.submodules:
                print_warning("配置文件中没有定义任何子模块")
                return True

            print_success("已加载 {} 个子模块配置".format(len(self.submodules)))
            return True

        except ValueError as e:
            print_error("配置文件 JSON 格式错误: " + str(e))
            return False
        except Exception as e:
            print_error("加载配置文件失败: " + str(e))
            return False

    def get_submodule(self, name):
        """根据名称获取子模块配置"""
        for sm in self.submodules:
            if sm['name'] == name:
                return sm
        return None

    def get_submodules_by_status(self):
        """返回已初始化和未初始化的子模块"""
        initialized = []
        not_initialized = []

        for sm in self.submodules:
            sm_path = self._get_path(sm['path'])
            git_dir = os.path.join(sm_path, '.git')

            if os.path.exists(git_dir):
                initialized.append(sm)
            else:
                not_initialized.append(sm)

        return initialized, not_initialized

    def _get_path(self, relative_path):
        """获取绝对路径"""
        if HAS_PATHLIB:
            return str(PROJECT_ROOT / relative_path)
        return os.path.join(PROJECT_ROOT, relative_path)


# ========================================
# 子模块操作
# ========================================

class SubmoduleManager(object):
    """子模块管理器"""

    def __init__(self, config):
        self.config = config

    def init_submodule(self, sm):
        """初始化单个子模块"""
        name = sm['name']
        path = sm['path']
        url = sm['url']

        print("")
        print(Colors.OKCYAN + "初始化子模块: " + name + Colors.ENDC)
        print("  路径: " + path)
        print("  URL: " + url)

        sm_path = self._get_submodule_path(path)

        # 检查目录是否已存在
        if os.path.exists(sm_path):
            git_dir = os.path.join(sm_path, '.git')
            if os.path.exists(git_dir):
                print_warning("目录已存在且为 Git 仓库，跳过初始化")
                return True
            else:
                print_error("目录已存在但不是 Git 仓库: " + sm_path)
                return False

        # 创建父目录
        parent_dir = os.path.dirname(sm_path)
        if not os.path.exists(parent_dir):
            os.makedirs(parent_dir)

        # 克隆仓库
        print_info("正在从 {} 克隆...".format(url))
        code, stdout, stderr = run_command(
            ['git', 'clone', url, sm_path],
            capture=False
        )

        if code != 0:
            print_error("克隆失败: " + stderr)
            return False

        print_success(name + " 初始化完成")
        return True

    def _get_submodule_path(self, relative_path):
        """获取子模块的绝对路径"""
        if HAS_PATHLIB:
            return str(PROJECT_ROOT / relative_path)
        return os.path.join(PROJECT_ROOT, relative_path)

    def init_all(self):
        """初始化所有子模块"""
        _, not_initialized = self.config.get_submodules_by_status()

        if not not_initialized:
            print_success("所有子模块都已初始化")
            return True

        print_header("初始化 {} 个子模块".format(len(not_initialized)))

        success_count = 0
        for sm in not_initialized:
            if self.init_submodule(sm):
                success_count += 1

        print("\n" + Colors.OKGREEN + "成功: {}/{}".format(success_count, len(not_initialized)) + Colors.ENDC)
        return success_count == len(not_initialized)

    def update_submodule(self, sm):
        """更新单个子模块到指定版本"""
        name = sm['name']
        path = sm['path']
        branch = sm.get('branch', '')
        sha = sm.get('sha', '')

        print("")
        print(Colors.OKCYAN + "更新子模块: " + name + Colors.ENDC)
        print("  分支: " + (branch or '未指定'))
        print("  SHA: " + (sha or '未指定'))

        sm_path = self._get_submodule_path(path)

        if not os.path.exists(sm_path):
            print_warning("目录不存在，跳过: " + path)
            return False

        # 保存当前目录
        original_cwd = os.getcwd()

        # 进入子模块目录
        os.chdir(sm_path)

        # 获取当前状态
        code, current_sha, _ = run_command(['git', 'rev-parse', 'HEAD'])
        current_sha = current_sha.strip()

        code, current_branch, _ = run_command(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
        current_branch = current_branch.strip()

        print("  当前分支: " + current_branch)
        print("  当前 SHA: " + current_sha[:8])

        # 获取远程更新
        print_info("正在获取远程更新...")
        run_command(['git', 'fetch', 'origin'], capture=False)

        # 确定 checkout 目标
        target = None
        if sha:
            target = sha
        elif branch:
            target = branch

        if not target:
            print_warning("未指定分支或 SHA，保持当前版本")
            os.chdir(original_cwd)
            return True

        # Checkout 目标
        print_info("切换到 {}...".format(target))
        code, _, stderr = run_command(['git', 'checkout', target])

        if code != 0:
            print_error("切换失败: " + stderr)
            os.chdir(original_cwd)
            return False

        # 获取更新后的 SHA
        code, new_sha, _ = run_command(['git', 'rev-parse', 'HEAD'])
        new_sha = new_sha.strip()

        print_success(name + " 已更新")
        print("  新 SHA: " + new_sha[:8])

        os.chdir(original_cwd)
        return True

    def update_all(self):
        """更新所有已初始化的子模块"""
        initialized, _ = self.config.get_submodules_by_status()

        if not initialized:
            print_warning("没有已初始化的子模块")
            print_info("请先运行: submodules.bat init")
            return False

        print_header("更新 {} 个子模块".format(len(initialized)))

        success_count = 0
        for sm in initialized:
            if self.update_submodule(sm):
                success_count += 1

        print("\n" + Colors.OKGREEN + "成功: {}/{}".format(success_count, len(initialized)) + Colors.ENDC)
        return success_count == len(initialized)

    def show_status(self):
        """显示所有子模块状态"""
        initialized, not_initialized = self.config.get_submodules_by_status()

        print_header("子模块状态")

        # 显示已初始化的子模块
        if initialized:
            print(Colors.OKGREEN + "已初始化:" + Colors.ENDC)
            for sm in initialized:
                path = sm['path']
                sm_path = self._get_submodule_path(path)

                original_cwd = os.getcwd()
                os.chdir(sm_path)

                # 获取当前分支和 SHA
                code, current_branch, _ = run_command(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
                current_branch = current_branch.strip()

                code, current_sha, _ = run_command(['git', 'rev-parse', 'HEAD'])
                current_sha = current_sha.strip()

                # 获取配置
                branch = sm.get('branch', '-')
                sha = sm.get('sha', '-')

                # 检查是否有未提交的更改
                code, status_output, _ = run_command(['git', 'status', '--porcelain'])
                has_changes = bool(status_output.strip())

                status_color = Colors.OKGREEN
                status_text = "干净"
                if has_changes:
                    status_color = Colors.WARNING
                    status_text = "有未提交更改"

                print("")
                print("  " + Colors.BOLD + sm['name'] + Colors.ENDC)
                print("    路径: " + path)
                print("    URL: " + sm['url'])
                print("    配置分支: " + branch)
                print("    配置 SHA: " + sha)
                print("    当前分支: " + current_branch)
                print("    当前 SHA: " + current_sha[:8])
                print("    状态: " + status_color + status_text + Colors.ENDC)

                os.chdir(original_cwd)

        # 显示未初始化的子模块
        if not_initialized:
            print("")
            print(Colors.WARNING + "未初始化:" + Colors.ENDC)
            for sm in not_initialized:
                print("")
                print("  " + Colors.BOLD + sm['name'] + Colors.ENDC)
                print("    路径: " + sm['path'])
                print("    URL: " + sm['url'])

        print()
        return True

    def checkout_submodule(self, name, target):
        """切换指定子模块到特定版本"""
        sm = self.config.get_submodule(name)
        if not sm:
            print_error("未找到子模块: " + name)
            return False

        path = sm['path']
        sm_path = self._get_submodule_path(path)

        if not os.path.exists(sm_path):
            print_error("子模块目录不存在: " + path)
            print_info("请先运行: submodules.bat init")
            return False

        print("")
        print(Colors.OKCYAN + "切换子模块: " + name + Colors.ENDC)
        print("  目标: " + target)

        original_cwd = os.getcwd()
        os.chdir(sm_path)

        # 获取远程更新
        print_info("正在获取远程更新...")
        run_command(['git', 'fetch', 'origin'], capture=False)

        # 尝试切换
        code, _, stderr = run_command(['git', 'checkout', target])

        os.chdir(original_cwd)

        if code != 0:
            print_error("切换失败: " + stderr)
            return False

        # 获取新的 SHA
        os.chdir(sm_path)
        code, new_sha, _ = run_command(['git', 'rev-parse', 'HEAD'])
        new_sha = new_sha.strip()
        os.chdir(original_cwd)

        print_success("已切换 {} 到 {} ({})".format(name, target, new_sha[:8]))

        return True


# ========================================
# 主程序
# ========================================

def main():
    """主函数"""
    # 简单的参数解析
    args = sys.argv[1:]

    command = 'status'
    if len(args) > 0:
        command = args[0]

    name = None
    target = None
    no_color = False

    # 解析参数
    i = 1
    while i < len(args):
        if args[i] == '--no-color':
            no_color = True
        elif command == 'checkout':
            if name is None:
                name = args[i]
            elif target is None:
                target = args[i]
        i += 1

    # 启用/禁用颜色
    if not no_color:
        try:
            Colors.enable()
        except:
            Colors.disable()
    else:
        Colors.disable()

    # 检查 Git
    git_exe = shutil.which('git') if hasattr(shutil, 'which') else None
    if not git_exe:
        # 手动检查
        for p in os.environ.get('PATH', '').split(os.pathsep):
            if os.path.exists(os.path.join(p, 'git.exe')):
                git_exe = os.path.join(p, 'git.exe')
                break

    if not git_exe:
        print_error("Git 未安装或不在 PATH 中")
        print_info("请从 https://git-scm.com/ 下载安装 Git")
        return 1

    # 切换到项目根目录
    os.chdir(PROJECT_ROOT)

    # 加载配置
    config = SubmoduleConfig(CONFIG_FILE)
    if not config.load():
        return 1

    # 创建管理器
    manager = SubmoduleManager(config)

    # 执行命令
    if command == 'init':
        success = manager.init_all()
        return 0 if success else 1

    elif command == 'update':
        success = manager.update_all()
        return 0 if success else 1

    elif command == 'status':
        success = manager.show_status()
        return 0 if success else 1

    elif command == 'checkout':
        if not name or not target:
            print_error("checkout 命令需要指定子模块名称和目标版本")
            print_info("用法: submodules.bat checkout <名称> <版本>")
            return 1
        success = manager.checkout_submodule(name, target)
        return 0 if success else 1

    elif command == '--help' or command == 'help' or command == '-h':
        print_help()
        return 0

    else:
        print_error("未知命令: " + command)
        print_info("运行 'submodules.bat help' 查看帮助")
        return 1

    return 0


def print_help():
    """打印帮助信息"""
    print("")
    print("=" * 50)
    print("Lua-MSVC 子模块管理工具".center(50))
    print("=" * 50)
    print("")
    print("用法: submodules.bat <命令> [选项]")
    print("")
    print("命令:")
    print("  init              初始化所有子模块")
    print("  update            更新所有子模块到配置版本")
    print("  status            显示子模块状态 (默认)")
    print("  checkout          切换子模块到指定版本")
    print("  help              显示此帮助信息")
    print("")
    print("选项:")
    print("  --no-color        禁用彩色输出")
    print("")
    print("示例:")
    print("  submodules.bat")
    print("  submodules.bat init")
    print("  submodules.bat update")
    print("  submodules.bat status")
    print("  submodules.bat checkout src v5.4.6")
    print("")


if __name__ == '__main__':
    sys.exit(main())
