local _M = {}

function _M.main(...)
    -- 字符串连接
    local concat = s .. " world"

    -- 索引访问
    local index = t[3]

    -- 字段访问
    local field = t.x

    -- 算术运算（二元）
    local result = a + b * 2

    -- 比较运算
    local compare = a > b

    -- 逻辑运算（短路）
    local logical = a and b or c
end

return _M