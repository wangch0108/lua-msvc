# Lua-MSVC

在 Windows 平台上使用 **Microsoft Visual Studio 2022** 构建 Lua 解释器和静态库的项目。

> 从游戏开发的角度理解：Lua 是游戏行业中最流行的嵌入式脚本语言之一。《魔兽世界》、《愤怒的小鸟》等众多游戏都使用 Lua 来编写游戏逻辑、UI 系统、配置文件等。这个项目为你提供了一个在 Windows 上构建和调试 Lua 的完整环境。

## 目录结构

```
lua-msvc/
├── src/                    # Lua 源代码（通过子模块管理）
├── tools/
│   ├── init.bat           # 子模块管理入口
│   ├── submodule/         # 子模块管理工具
│   │   ├── submodules.bat         # 主入口脚本
│   │   ├── submodules.lua         # Lua 实现
│   │   └── submodule_cfg.lua      # 子模块配置
│   ├── premake5.lua       # Premake 构建配置
│   └── bin/
│       └── premake/
│           └── premake5.exe
├── build.bat              # 生成 VS 解决方案
├── LuaSrc.sln            # Visual Studio 解决方案
├── lualib.vcxproj        # 静态库项目
└── lua.vcxproj           # lua.exe 项目
```

## 快速开始

### 环境要求

- **Visual Studio 2022** - 微软的集成开发环境
- **Git** - 版本控制工具，用于子模块管理
- **Lua 或 Python 3.6+** - 子模块管理工具的运行环境（可选，会自动检测）

### 初始化项目

首次克隆项目或 `src/` 目录为空时，需要初始化子模块：

```batch
tools\init.bat init
```

这会自动：
1. 检测并使用 Lua 或 Python 环境
2. 从配置的 Git 仓库获取子模块
3. 将 Lua 源代码下载到 `src/` 目录

### 生成 Visual Studio 解决方案

```batch
build.bat
```

这会运行 Premake5 生成 `LuaSrc.sln` 解决方案文件。

### 编译项目

1. 使用 Visual Studio 2022 打开 `LuaSrc.sln`
2. 选择配置（Debug/Release）
3. 按 `F7` 或选择 **Build > Build Solution**

### 构建输出

编译后的二进制文件输出到：

```
bin/{配置}-{系统}-{架构}/{项目名}/

示例：
bin/Debug-Windows-x64/lualib/    # 静态库
bin/Debug-Windows-x64/lua/        # lua.exe 可执行文件
```

## 子模块管理

本项目使用自定义的子模块管理系统来跟踪 Lua 及其他依赖的特定版本。

### 可用命令

所有命令通过 `tools\init.bat` 执行：

| 命令 | 功能说明 |
|------|---------|
| `tools\init.bat` 或 `tools\init.bat status` | 显示子模块状态 |
| `tools\init.bat init` | 初始化所有子模块 |
| `tools\init.bat update` | 更新所有子模块到配置版本 |
| `tools\init.bat checkout <名称> <版本>` | 切换指定子模块到特定版本 |
| `tools\init.bat help` | 显示帮助信息 |

### 子模块配置

编辑 `tools\submodule\submodule_cfg.lua` 来更改使用的子模块版本：

```lua
return {
    submodules = {
        {
            name = "src",                    -- 子模块名称
            path = "src",                    -- 本地路径
            url = "https://github.com/lua/lua",
            branch = "v5.4",                 -- 跟踪的分支
            sha = "",                        -- 具体 SHA（可选）
            sparse_path = ""                 -- 稀疏检出路径（可选）
        },
        {
            name = "claude",
            path = ".claude",
            url = "https://github.com/anthropics/skills",
            branch = "main",
            sha = "",
            sparse_path = "skills"           -- 只检出 skills 目录
        }
    }
}
```

**配置说明：**
- `name` - 子模块的唯一标识符
- `path` - 相对于项目根目录的路径
- `url` - Git 仓库 URL
- `branch` - 要跟踪的分支（如 v5.4.7, main 等）
- `sha` - 具体的提交 SHA（如果指定，优先于 branch）
- `sparse_path` - 只检出仓库中的特定目录（可选）

### 版本锁定

在游戏项目中，锁定 Lua 版本非常重要。不同版本的 Lua 可能存在 API 变化，直接升级会导致游戏脚本出错。通过版本管理，你可以：

1. 安全地测试新版本 Lua
2. 确保团队使用相同版本
3. 轻松回滚到稳定版本

### 切换 Lua 版本

```batch
tools\init.bat checkout src v5.3.6
```

然后在 Visual Studio 中重新构建解决方案。

## 工作区配置

Premake 配置定义了两个项目：

### lualib（静态库）

编译 `src/` 目录下的所有 Lua 源文件，排除：
- `lua.c`（独立解释器）
- `onelua.c`（GCC 构建的单文件版本）
- `ltests.h/c`（Lua 测试套件）
- `testes/` 目录（测试文件）

**配置选项：** Debug/Release，x64 架构

> 从游戏开发视角：静态库（.lib 文件）会被嵌入到游戏引擎中，提供 Lua 脚本执行能力。游戏引擎通过链接这个静态库来获得 Lua 虚拟机的功能。

### lua（控制台应用程序）

编译 `src/lua.c` 并链接 `lualib` 静态库，生成独立的 Lua 解释器可执行文件。

**配置选项：** Debug/Release，x64 架构

> 这个 lua.exe 类似于游戏引擎的"测试工具"，让你可以在不启动完整游戏的情况下测试 Lua 脚本。

## 常见开发工作流

### 测试不同 Lua 版本

```batch
# 1. 切换到指定版本
tools\init.bat checkout src v5.3.0

# 2. 重新生成解决方案（如果需要）
build.bat

# 3. 在 VS2022 中重新编译
```

### 更新子模块

当拉取包含子模块更新的代码更改后：

```batch
tools\init.bat update
```

这会将所有子模块更新到 `submodule_cfg.lua` 中指定的版本。

### 检查子模块状态

```batch
tools\init.bat status
```

显示哪些子模块已初始化以及它们的当前版本。

## 修改构建配置

要修改构建配置（添加新项目、更改编译器设置等）：

1. 编辑 `tools/premake5.lua`
2. 运行 `build.bat` 重新生成 Visual Studio 解决方案
3. 在 Visual Studio 中重新加载解决方案

> 使用 Premake 这样的构建配置工具，可以将项目结构以代码形式管理，便于团队协作和版本控制。这是大型游戏项目的标准做法。

## 故障排除

### 子模块初始化失败

确保：
1. Git 已安装并在 PATH 中
2. 网络连接正常
3. 配置的仓库 URL 正确

### 编译错误

1. 确保使用 Visual Studio 2022
2. 检查子模块是否正确初始化
3. 尝试清理解决方案后重新编译

## 给初学者的建议

作为游戏开发初学者，通过这个项目你可以学习到：

1. **C 语言与 Lua 的集成** - 理解如何将 Lua 嵌入到 C/C++ 游戏引擎中
2. **构建系统管理** - 学习 Premake 和 Visual Studio 的使用
3. **版本控制** - 掌握 Git 子模块的概念和操作
4. **项目组织** - 了解专业游戏项目的目录结构和配置方式

建议按照以下路径学习：
- 先运行项目，成功编译出 lua.exe
- 尝试修改 Lua 源代码，重新编译观察效果
- 使用不同的 Lua 版本，理解版本差异
- 阅读 Lua 官方文档，学习 Lua 脚本编写
- 思考如何将 Lua 集成到自己的游戏项目中

## 许可证

本项目遵循 Lua 源代码的 MIT 许可证。

## 相关资源

- [Lua 官方网站](https://www.lua.org/)
- [Lua GitHub 仓库](https://github.com/lua/lua)
- [Premake 文档](https://premake.github.io/)
- [Programming in Lua](https://www.lua.org/pil/) - Lua 官方教程
