# 代码分析语言参考

本文档提供不同编程语言的代码分析要点，帮助准确识别和分析各种语言的代码结构。

---

## C/C++ 分析要点

### 数据结构识别

**结构体定义**：
```c
struct StructName {
    type field1;
    type field2;
};
```

**联合体定义**：
```c
union UnionName {
    type field1;
    type field2;
};
```

**枚举定义**：
```c
enum EnumName {
    VALUE1,
    VALUE2,
    VALUE3
};
```

### 函数识别

**函数定义模式**：
```c
[返回类型] [函数名]([参数列表]) {
    // 函数体
}
```

**搜索模式**：
- 函数定义：`Grep: "^\s*[a-zA-Z_][a-zA-Z0-9_*\s]+\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\("`
- 结构体定义：`Grep: "struct\s+[a-zA-Z_][a-zA-Z0-9_]*"`
- 枚举定义：`Grep: "enum\s+[a-zA-Z_][a-zA-Z0-9_]*"`

### 指针与内存

**指针声明**：
```c
type* ptr;           // 指针
type** ptrptr;       // 指针的指针
const type* ptr;     // 常量指针
type* const ptr;     // 指针常量
```

**内存操作**：
- `malloc/calloc` - 动态内存分配
- `free` - 释放内存
- `memcpy/memmove` - 内存复制
- `memset` - 内存填充

---

## Python 分析要点

### 数据结构识别

**类定义**：
```python
class ClassName:
    def __init__(self, params):
        self.field1 = value1
        self.field2 = value2
```

**命名元组**：
```python
from collections import namedtuple
TypeName = namedtuple('TypeName', ['field1', 'field2'])
```

**数据类**：
```python
from dataclasses import dataclass

@dataclass
class ClassName:
    field1: type
    field2: type = default_value
```

### 函数识别

**函数定义**：
```python
def function_name(param1: type, param2: type) -> return_type:
    # 函数体
```

**搜索模式**：
- 函数定义：`Grep: "^def\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\("`
- 类定义：`Grep: "^class\s+[a-zA-Z_][a-zA-Z0-9_]*"`
- 装饰器：`Grep: "^@\w+"`

### Python 特性

**列表推导**：
```python
result = [expression for item in iterable if condition]
```

**生成器**：
```python
def generator():
    yield value
```

**上下文管理器**：
```python
with context_manager as variable:
    # 代码块
```

---

## Lua 分析要点

### 数据结构识别

**表（Table）**：
```lua
local tableName = {
    field1 = value1,
    field2 = value2,
    ["key_with_space"] = value3
}
```

**数组形式**：
```lua
local array = {value1, value2, value3}
```

**模块定义**：
```lua
local module = {}
function module.function_name()
    -- 实现
end
return module
```

### 函数识别

**函数定义**：
```lua
local function function_name(param1, param2)
    -- 函数体
end
```

**方法定义**：
```lua
function table:method_name(param)
    -- 方法体，self 为隐式参数
end
```

**搜索模式**：
- 函数定义：`Grep: "function\s+[a-zA-Z_][a-zA-Z0-9_:\.]*\s*\("`
- 局部函数：`Grep: "local\s+function\s+[a-zA-Z_][a-zA-Z0-9_]*"`

### Lua 特性

**元表（Metatable）**：
```lua
setmetatable(table, {
    __index = other_table,
    __add = function(a, b) end,
    __tostring = function(t) end
})
```

**闭包**：
```lua
function outer()
    local upvalue = 0
    return function()
        upvalue = upvalue + 1
        return upvalue
    end
end
```

**协程**：
```lua
local co = coroutine.create(function()
    -- 协程体
end)
coroutine.resume(co)
```

---

## C# 分析要点

### 数据结构识别

**类定义**：
```csharp
public class ClassName
{
    public type Field1 { get; set; }
    private type _field2;
}
```

**结构体**：
```csharp
public struct StructName
{
    public type Field1;
    public type Field2;
}
```

**枚举**：
```csharp
public enum EnumName
{
    Value1,
    Value2,
    Value3
}
```

**记录（Record）**：
```csharp
public record RecordName(type Field1, type Field2);
```

### 函数识别

**方法定义**：
```csharp
[访问修饰符] [返回类型] [方法名]([参数列表])
{
    // 方法体
}
```

**异步方法**：
```csharp
public async Task<ReturnType> MethodNameAsync()
{
    await SomeAsyncOperation();
    return result;
}
```

**搜索模式**：
- 方法定义：`Grep: "^\s*\[?\w+\s+\]?\s*\w+\s+\w+\s*\("`
- 类定义：`Grep: "class\s+\w+"`

### C# 特性

**LINQ 查询**：
```csharp
var result = from item in collection
             where condition
             select item;
```

**Lambda 表达式**：
```csharp
Func<type, type> lambda = (param) => expression;
```

**事件处理**：
```csharp
public event EventHandler<EventArgs> EventName;
```

---

## 通用分析建议

### 1. 入口点识别

| 项目类型 | 入口点 |
|---------|--------|
| C 可执行程序 | `main()` 函数 |
| C++ 可执行程序 | `main()` 或 `WinMain()` 函数 |
| Python 脚本 | `if __name__ == "__main__":` 块 |
| Python 模块 | 导出的函数/类 |
| Lua 脚本 | 脚本顶层代码或 `require()` 返回值 |
| C# 应用程序 | `Program.Main()` 方法 |
| C# 库 | 公共类和方法 |

### 2. 调用关系分析

1. 从入口点开始，读取函数源码
2. 识别函数调用语句
3. 对每个被调用函数，递归分析
4. 记录调用链和参数传递

### 3. 数据流追踪

1. 识别函数参数（输入）
2. 追踪局部变量的变化
3. 识别返回值（输出）
4. 注意副作用（全局变量、I/O操作）

### 4. 搜索技巧

**查找定义**：
- `Grep: "struct\s+[结构名]"` - C/C++ 结构体
- `Grep: "class\s+[类名]"` - Python/C# 类
- `Grep: "def\s+[函数名]"` - Python 函数

**查找使用**：
- `Grep: "[变量名]"` - 变量使用位置
- `Grep: "[函数名]\s*\("` - 函数调用

**查找赋值**：
- `Grep: "[变量名]\s*="` - 赋值语句
