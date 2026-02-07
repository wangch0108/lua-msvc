-- ========================================
-- Lua-MSVC 子模块管理工具
-- ========================================
--
-- 功能:
--   自动管理 Git 子模块的初始化、更新和版本控制
--
-- 配置文件: tools/submodule/submodule_cfg.lua (Lua 表格格式)
-- 使用方式: lua tools/submodule/submodules.lua [init|update|status|checkout] [选项]
--
-- ========================================

-- ========================================
-- 全局配置
-- ========================================

-- 是否启用调试输出（打印所有执行的命令）
local DEBUG_MODE = true

-- ========================================
-- 工具函数
-- ========================================

local function get_script_dir()
    local source = debug.getinfo(1).source
    -- 移除开头的 @
    source = source:gsub("^@", "")

    -- 转换路径分隔符
    source = source:gsub("\\", "/")

    -- 获取目录路径
    local dir = source:match("^(.*)/[^/]*$")

    -- 如果是相对路径，转换为绝对路径
    if dir and not dir:match("^[A-Za-z]:") and not dir:match("^/") then
        -- 相对路径，从当前工作目录解析
        local cwd = io.popen("cd"):read("*a"):gsub("\n", ""):gsub("\r", "")
        -- 转换 cwd 为正斜杠格式
        cwd = cwd:gsub("\\", "/")
        dir = cwd .. "/" .. dir
    end

    -- 确保以 / 结尾
    if dir and dir:sub(-1) ~= "/" then
        dir = dir .. "/"
    end

    return dir or "./"
end

local SCRIPT_DIR = get_script_dir()
local PROJECT_ROOT = SCRIPT_DIR:gsub("tools/submodule/$", "")
local CONFIG_FILE = SCRIPT_DIR .. "submodule_cfg.lua"

local function print_header(text)
    print("\n" .. string.rep("=", 50))
    local padding = math.floor((50 - #text) / 2)
    print(string.rep(" ", padding) .. text)
    print(string.rep("=", 50) .. "\n")
end

local function print_success(text)
    print("[OK] " .. text)
end

local function print_error(text)
    error("[ERR] " .. text .. "\n")
end

local function print_warning(text)
    print("[WARN] " .. text)
end

local function print_info(text)
    print("[INFO] " .. text)
end

local function print_debug(text)
    if DEBUG_MODE then
        print("[DEBUG] " .. text)
    end
end

-- 执行命令并返回输出
-- 返回: output, exit_code
--   output: 命令输出（stdout + stderr）
--   exit_code: 退出代码（0 表示成功）
local function os_exec(cmd)
    print_debug("执行: " .. cmd)

    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        print_debug("错误: 无法执行命令")
        return nil, 1
    end

    local output = handle:read("*a")
    local success, _, exit_code = handle:close()

    exit_code = exit_code or (success and 0 or 1)

    if exit_code ~= 0 then
        print_debug("退出代码: " .. exit_code)
        if output and output:match("%S") then
            print_debug("输出: " .. output:gsub("\n", " "):gsub("%s+", " "):sub(1, 200))
        end
    else
        -- 成功时也打印输出（如果有）
        if output and output:match("%S") then
            local trimmed = output:gsub("\n", " "):gsub("%s+", " "):sub(1, 200)
            if #trimmed > 0 then
                print_debug("输出: " .. trimmed)
            end
        end
    end

    return output, exit_code
end

-- 检查 Git 是否可用
local function check_git()
    local cmd = "git --version"
    local output = os_exec(cmd)
    return output and output:match("git version") ~= nil
end

-- ========================================
-- 配置管理
-- ========================================

local function load_config()
    local file = io.open(CONFIG_FILE, "r")
    if not file then
        print_error("配置文件不存在: " .. CONFIG_FILE)
        return nil
    end

    -- 读取文件内容
    local content = file:read("*a")
    file:close()

    -- 执行配置文件
    local config_func, err = load(content, CONFIG_FILE, "t", {})
    if not config_func then
        print_error("配置文件语法错误: " .. tostring(err))
        return nil
    end

    local success, result = pcall(config_func)
    if not success or not result or not result.submodules then
        print_error("配置文件格式错误")
        return nil
    end

    print_success("已加载 " .. #result.submodules .. " 个子模块配置")
    return result
end

-- 检查目录是否为 Git 仓库
local function is_git_repo(path)
    local git_dir = path .. "/.git"
    local cmd = "if exist \"" .. git_dir .. "\" (echo YES) else (echo NO)"
    local f = io.popen(cmd)
    local result = f:read("*a")
    f:close()
    return result:match("YES") ~= nil
end

-- ========================================
-- 子模块操作
-- ========================================

local function init_submodule(sm)
    print("\n初始化子模块: " .. sm.name)
    print("  路径: " .. sm.path)
    print("  URL: " .. sm.url)

    local sm_path = PROJECT_ROOT .. sm.path
    local sparse_path = sm.sparse_path or ""

    if sparse_path ~= "" then
        print("  稀疏检出: " .. sparse_path)
    end

    -- 检查是否已初始化（Git 仓库）
    if is_git_repo(sm_path) then
        print_warning("Git 仓库已存在，跳过初始化")
        return true
    end

    -- 创建父目录
    local parent_dir = sm.path:match("^(.*)[/\\][^/\\]+$")
    if parent_dir then
        cmd = "if not exist \"" .. PROJECT_ROOT .. parent_dir .. "\" mkdir \"" .. PROJECT_ROOT .. parent_dir .. "\""
        os_exec(cmd)
    end

    -- 克隆仓库
    print_info("正在从 " .. sm.url .. " 克隆...")

    if sparse_path ~= "" then
        -- 使用 sparse checkout 只检出指定目录
        print_info("使用稀疏检出模式")

        -- 1. 确保目录存在
        local cmd = "if not exist \"" .. sm_path .. "\" mkdir \"" .. sm_path .. "\""
        os_exec(cmd)

        cmd = "cd /d \"" .. sm_path .. "\" && git init"
        local output, exit_code = os_exec(cmd)

        if exit_code ~= 0 then
            print_error("初始化 Git 仓库失败")
            if output and output:match("%S") then
                print("  错误信息: " .. output:gsub("\n", "\n    "))
            end
            return false
        end

        -- 2. 启用 sparse checkout
        cmd = "cd /d \"" .. sm_path .. "\" && git config core.sparseCheckout true"
        os_exec(cmd)

        -- 3. 设置要检出的路径
        cmd = "cd /d \"" .. sm_path .. "\" && echo " .. sparse_path .. " > .git/info/sparse-checkout"
        os_exec(cmd)

        -- 4. 添加远程仓库并拉取
        cmd = "cd /d \"" .. sm_path .. "\" && git remote add origin " .. sm.url
        os_exec(cmd)

        cmd = "cd /d \"" .. sm_path .. "\" && git fetch origin"
        output, exit_code = os_exec(cmd)

        if exit_code ~= 0 then
            print_error("拉取远程仓库失败")
            if output and output:match("%S") then
                print("  错误信息: " .. output:gsub("\n", "\n    "))
            end
            return false
        end

        -- 5. 检出指定分支
        local branch = sm.branch or "main"
        cmd = "cd /d \"" .. sm_path .. "\" && git checkout " .. branch
        output, exit_code = os_exec(cmd)

        if exit_code ~= 0 then
            print_error("检出分支失败")
            if output and output:match("%S") then
                print("  错误信息: " .. output:gsub("\n", "\n    "))
            end
            return false
        end
    else
        -- 普通 clone
        cmd = "git clone " .. sm.url .. " \"" .. sm_path .. "\""
        local output, exit_code = os_exec(cmd)

        if exit_code ~= 0 then
            print_error("克隆失败")
            if output and output:match("%S") then
                print("  错误信息: " .. output:gsub("\n", "\n    "))
            end
            return false
        end
    end

    print_success(sm.name .. " 初始化完成")
    return true
end

local function cmd_init(config)
    local not_initialized = {}

    for _, sm in ipairs(config.submodules) do
        local sm_path = PROJECT_ROOT .. sm.path
        -- 直接检查是否是 Git 仓库（无论目录是否存在）
        if not is_git_repo(sm_path) then
            table.insert(not_initialized, sm)
        end
    end

    if #not_initialized == 0 then
        print_success("所有子模块都已初始化")
        return true
    end

    print_header("初始化 " .. #not_initialized .. " 个子模块")

    local success_count = 0
    for _, sm in ipairs(not_initialized) do
        if init_submodule(sm) then
            success_count = success_count + 1
        end
    end

    print("\n成功: " .. success_count .. "/" .. #not_initialized)
    return success_count == #not_initialized
end

local function update_submodule(sm)
    print("\n更新子模块: " .. sm.name)
    print("  分支: " .. (sm.branch or "未指定"))
    print("  SHA: " .. (sm.sha or "未指定"))

    local sm_path = PROJECT_ROOT .. sm.path

    -- 检查是否是 Git 仓库
    if not is_git_repo(sm_path) then
        print_warning("不是 Git 仓库或目录不存在，跳过: " .. sm.path)
        return false
    end

    -- 获取当前状态
    local cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse HEAD"
    local current_sha = os_exec(cmd)
    if current_sha then current_sha = current_sha:gsub("\n", ""):gsub("\r", ""):sub(1, 8) end

    cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse --abbrev-ref HEAD"
    local current_branch = os_exec(cmd)
    if current_branch then current_branch = current_branch:gsub("\n", ""):gsub("\r", "") end

    print("  当前分支: " .. (current_branch or "未知"))
    print("  当前 SHA: " .. (current_sha or "未知"))

    -- 获取远程更新
    print_info("正在获取远程更新...")
    cmd = "cd /d \"" .. sm_path .. "\" && git fetch origin"
    os_exec(cmd)

    -- 确定 checkout 目标
    local target = sm.sha or sm.branch
    if not target or target == "" then
        print_warning("未指定分支或 SHA，保持当前版本")
        return true
    end

    -- Checkout 目标
    print_info("切换到 " .. target .. "...")
    cmd = "cd /d \"" .. sm_path .. "\" && git checkout " .. target
    local output, exit_code = os_exec(cmd)

    if exit_code ~= 0 then
        print_error("切换失败")
        if output and output:match("%S") then
            print("  错误信息: " .. output:gsub("\n", "\n    "))
        end
        return false
    end

    -- 获取更新后的 SHA
    cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse HEAD"
    local new_sha = os_exec(cmd)
    if new_sha then new_sha = new_sha:gsub("\n", ""):gsub("\r", ""):sub(1, 8) end

    print_success(sm.name .. " 已更新")
    print("  新 SHA: " .. (new_sha or "未知"))

    return true
end

local function cmd_update(config)
    local initialized = {}

    for _, sm in ipairs(config.submodules) do
        local sm_path = PROJECT_ROOT .. sm.path
        if is_git_repo(sm_path) then
            table.insert(initialized, sm)
        end
    end

    if #initialized == 0 then
        print_warning("没有已初始化的子模块")
        print_info("请先运行: submodules.bat init")
        return false
    end

    print_header("更新 " .. #initialized .. " 个子模块")

    local success_count = 0
    for _, sm in ipairs(initialized) do
        if update_submodule(sm) then
            success_count = success_count + 1
        end
    end

    print("\n成功: " .. success_count .. "/" .. #initialized)
    return success_count == #initialized
end

local function cmd_status(config)
    print_header("子模块状态")

    local initialized = {}
    local not_initialized = {}

    for _, sm in ipairs(config.submodules) do
        local sm_path = PROJECT_ROOT .. sm.path
        if is_git_repo(sm_path) then
            table.insert(initialized, sm)
        else
            table.insert(not_initialized, sm)
        end
    end

    if #initialized > 0 then
        print("已初始化:")
        for _, sm in ipairs(initialized) do
            local sm_path = PROJECT_ROOT .. sm.path

            local cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse --abbrev-ref HEAD"
            local current_branch = os_exec(cmd)
            if current_branch then current_branch = current_branch:gsub("\n", ""):gsub("\r", "") end

            cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse HEAD"
            local current_sha = os_exec(cmd)
            if current_sha then current_sha = current_sha:gsub("\n", ""):gsub("\r", ""):sub(1, 8) end

            cmd = "cd /d \"" .. sm_path .. "\" && git status --porcelain"
            local status_output = os_exec(cmd)
            local has_changes = status_output and status_output:match("%S")

            print("\n  " .. sm.name)
            print("    路径: " .. sm.path)
            print("    URL: " .. sm.url)
            print("    配置分支: " .. (sm.branch or "-"))
            print("    配置 SHA: " .. (sm.sha or "-"))
            if sm.sparse_path and sm.sparse_path ~= "" then
                print("    稀疏检出: " .. sm.sparse_path)
            end
            print("    当前分支: " .. (current_branch or "未知"))
            print("    当前 SHA: " .. (current_sha or "未知"))
            print("    状态: " .. (has_changes and "有未提交更改" or "干净"))
        end
    end

    if #not_initialized > 0 then
        print("\n未初始化:")
        for _, sm in ipairs(not_initialized) do
            print("\n  " .. sm.name)
            print("    路径: " .. sm.path)
            print("    URL: " .. sm.url)
        end
    end

    print()
    return true
end

local function cmd_checkout(config, name, target)
    if not name or not target then
        print_error("checkout 命令需要指定子模块名称和目标版本")
        print_info("用法: submodules.bat checkout <名称> <版本>")
        return false
    end

    local sm = nil
    for _, s in ipairs(config.submodules) do
        if s.name == name then
            sm = s
            break
        end
    end

    if not sm then
        print_error("未找到子模块: " .. name)
        return false
    end

    local sm_path = PROJECT_ROOT .. sm.path

    -- 检查是否是 Git 仓库
    if not is_git_repo(sm_path) then
        print_error("子模块目录不是 Git 仓库或不存在: " .. sm.path)
        print_info("请先运行: submodules.bat init")
        return false
    end

    print("\n切换子模块: " .. sm.name)
    print("  目标: " .. target)

    -- 获取远程更新
    print_info("正在获取远程更新...")
    local cmd = "cd /d \"" .. sm_path .. "\" && git fetch origin"
    os_exec(cmd)

    -- 尝试切换
    cmd = "cd /d \"" .. sm_path .. "\" && git checkout " .. target
    local output, exit_code = os_exec(cmd)

    if exit_code ~= 0 then
        print_error("切换失败")
        if output and output:match("%S") then
            print("  错误信息: " .. output:gsub("\n", "\n    "))
        end
        return false
    end

    -- 获取新的 SHA
    cmd = "cd /d \"" .. sm_path .. "\" && git rev-parse HEAD"
    local new_sha = os_exec(cmd)
    if new_sha then new_sha = new_sha:gsub("\n", ""):gsub("\r", ""):sub(1, 8) end

    print_success("已切换 " .. sm.name .. " 到 " .. target .. " (" .. (new_sha or "?") .. ")")

    return true
end

-- ========================================
-- 主程序
-- ========================================

local function main()
    local args = arg or {}

    local command = #args > 0 and args[1] or "status"
    local name = #args > 1 and args[2] or nil
    local target = #args > 2 and args[3] or nil

    -- 检查 Git
    if not check_git() then
        print_error("Git 未安装或不在 PATH 中")
        print_info("请从 https://git-scm.com/ 下载安装 Git")
        return 1
    end

    -- 加载配置
    local config = load_config()
    if not config then
        return 1
    end

    -- 执行命令
    if command == "init" then
        return cmd_init(config) and 0 or 1
    elseif command == "update" then
        return cmd_update(config) and 0 or 1
    elseif command == "status" then
        return cmd_status(config) and 0 or 1
    elseif command == "checkout" then
        return cmd_checkout(config, name, target) and 0 or 1
    elseif command == "help" or command == "--help" or command == "-h" then
        print("\n" .. string.rep("=", 50))
        local title = "Lua-MSVC 子模块管理工具"
        print(string.rep(" ", math.floor((50 - #title) / 2)) .. title)
        print(string.rep("=", 50) .. "\n")
        print("用法: submodules.bat <命令> [选项]\n")
        print("命令:")
        print("  init              初始化所有子模块")
        print("  update            更新所有子模块到配置版本")
        print("  status            显示子模块状态 (默认)")
        print("  checkout          切换子模块到指定版本")
        print("  help              显示此帮助信息\n")
        print("示例:")
        print("  submodules.bat")
        print("  submodules.bat init")
        print("  submodules.bat update")
        print("  submodules.bat status")
        print("  submodules.bat checkout src v5.4.6\n")
        return 0
    else
        print_error("未知命令: " .. command)
        print_info("运行 'submodules.bat help' 查看帮助")
        return 1
    end
end

main()
