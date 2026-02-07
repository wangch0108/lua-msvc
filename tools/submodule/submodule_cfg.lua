-- ========================================
-- 子模块配置文件
-- ========================================
--
-- 格式说明:
--   name:  子模块名称（唯一标识符）
--   path:  相对于项目根目录的路径
--   url:   Git 仓库 URL
--   branch: 要跟踪的分支（如 v5.4.7, main 等）
--   sha:   具体的提交 SHA（如果指定，优先于 branch）
--   sparse_path: 只检出仓库中的特定目录（可选，如 "skills" 或 "src/lib"）
--
-- 如果 sha 为空或 nil，将使用 branch 的最新提交
-- 如果两者都为空，将保持当前版本不变
--
-- ========================================

return {
    submodules = {
        {
            name = "src",
            path = "src",
            url = "https://github.com/lua/lua",
            branch = "v5.4",
            sha = "",
            sparse_path = ""
        },
        {
            name = "claude",
            path = ".claude",
            url = "https://github.com/anthropics/skills",
            branch = "main",
            sha = "",
            sparse_path = "skills"
        }
    }
}
