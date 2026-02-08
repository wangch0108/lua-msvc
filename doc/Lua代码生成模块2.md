# Lua 代码生成解析 - 模块模式与函数定义

本文档详细分析 Lua 编译器如何将模块模式的代码（包含局部变量、函数定义、可变参数等）编译成字节码的完整数据流。

## 概述

示例代码展示了一个典型的 Lua 模块模式：
1. `local _M = {}` - 创建模块表
2. `function _M.main(...) ... end` - 定义模块方法（带可变参数）
3. 函数内的局部变量声明
4. `return _M` - 返回模块表

这个过程涉及：
- **词法分析**（llex.c）：将源代码转换为 token 流
- **语法分析**（lparser.c）：构建抽象语法树并生成字节码
- **代码生成**（lcode.c）：生成虚拟机指令

---

## 数据流

### 入口&示例代码

**入口**: `luaY_parser()` // src/lparser.c:1942

**示例代码**:
```lua
local _M = {}
function _M.main(...)
	local a = nil
	local b = false
	local c = 42
	local d = "hello"
	local v = ...
end
return _M
```

**前置数据说明**:
- `lua_State* L`：Lua 状态机
- `ZIO* z`：输入流（读取 test.lua 文件内容）
- `Mbuffer* buff`：词法分析缓冲区
- `Dyndata* dyd`：动态数据结构（局部变量、标签、goto 列表）
- `name`：源文件名称 "test.lua"

---

### 调用链

#### 编译器初始化阶段

1. **[前置数据]** 创建 Lua 状态机，准备加载 test.lua 文件

2. **[进入 luaY_parser()]** (lua_State* L, ZIO* z, Mbuffer* buff, Dyndata* dyd, const char* name("test.lua"), int firstchar)

3. **[luaY_parser()]** 创建 LexState 和 FuncState 结构
   - `lexstate`：词法分析器状态
   - `funcstate`：main 函数编译状态

4. **[luaY_parser()]** 调用 `luaF_newLclosure(L, 1)` 创建闭包
   - 参数 1 表示有 1 个上值（_ENV）

5. **[luaY_parser()]** 调用 `luaH_new(L)` 创建哈希表用于词法分析器
   - 避免字符串重复收集

6. **[luaY_parser()]** 调用 `luaF_newproto(L)` 创建函数原型
   - `funcstate.f = cl->p = luaF_newproto(L)`
   - 设置源文件名：`funcstate.f->source = luaS_new(L, "test.lua")`

7. **[luaY_parser()]** 初始化动态数据：`dyd->actvar.n = dyd->gt.n = dyd->label.n = 0`

8. **[luaY_parser()]** 调用 `luaX_setinput(L, &lexstate, z, funcstate.f->source, firstchar)`
   - 设置词法分析器输入
   - 开始读取第一个 token

9. **[luaY_parser()]** 调用 `mainfunc(&lexstate, &funcstate)` 开始解析 main 函数

10. **[进入 mainfunc()]** (LexState* ls, FuncState* fs)

11. **[mainfunc()]** 调用 `open_func(ls, fs, &bl)` 打开函数状态

12. **[进入 open_func()]** (LexState* ls, FuncState* fs, BlockCnt* bl)
    - 设置 `fs->prev = ls->fs`（建立函数链）
    - 设置 `ls->fs = fs`（当前函数）
    - 初始化 `fs->pc = 0, fs->freereg = 0, fs->nk = 0, fs->np = 0, fs->nups = 0`

13. **[回到 mainfunc()]** 调用 `setvararg(fs, 0)` 设置 main 函数为可变参数

14. **[进入 setvararg()]** (FuncState* fs, int nparams(0))
    - 设置 `fs->f->is_vararg = 1`
    - 调用 `luaK_codeABC(fs, OP_VARARGPREP, 0, 0, 0)` 生成 VARARGPREP 指令

15. **[回到 mainfunc()]** 调用 `allocupvalue(fs)` 分配上值

16. **[进入 allocupvalue()]** (FuncState* fs)
    - 在 `fs->f->upvalues` 中分配新的上值槽位
    - `fs->nups = 1`

17. **[回到 mainfunc()]** 设置环境上值
    - `env->instack = 1`
    - `env->idx = 0`
    - `env->kind = VDKREG`
    - `env->name = ls->envn`（"_ENV"）

18. **[mainfunc()]** 调用 `luaX_next(ls)` 读取第一个 token
    - 当前 token 变为 `{ local : TK_LOCAL }`

19. **[mainfunc()]** 调用 `statlist(ls)` 解析语句列表

20. **[进入 statlist()]** (LexState* ls(token:TK_LOCAL))

---

#### 第一条语句：local _M = {}

21. **[statlist()]** 调用 `statement(ls)`

22. **[进入 statement()]** (LexState* ls(token:TK_LOCAL), FuncState* fs)

23. **[statement()]** 进入 ***TK_LOCAL*** 分支，调用 `localstat(ls)`

24. **[进入 localstat()]** (LexState* ls(token:TK_LOCAL))

25. **[localstat()]** 初始化 `nvars = 0, toclose = -1`

26. **[localstat()]** 进入 do-while 循环（处理变量列表）

27. **[localstat()]** 调用 `str_checkname(ls)` 获取变量名 "_M"
    - token 前移，当前 token 变为 `{ = : '=' }`

28. **[localstat()]** 调用 `new_localvar(ls, "_M")`
    - 在 dyd->actvar 中创建新的局部变量条目
    - 返回 vidx = 0（第一个局部变量的索引）

29. **[进入 new_localvar()]** (LexState* ls, TString* name("_M"))
    - 检查变量数量限制
    - 扩展 actvar 数组
    - 设置 `var->vd.kind = VDKREG`（普通变量）
    - 设置 `var->vd.name = "_M"`

30. **[回到 localstat()]** vidx = 0

31. **[localstat()]** 调用 `getlocalattribute(ls)` 获取变量属性

32. **[进入 getlocalattribute()]** (LexState* ls)
    - 当前 token 是 '='，不是 '<'
    - 返回 VDKREG（普通变量）

33. **[回到 localstat()]** kind = VDKREG

34. **[localstat()]** 设置 `getlocalvardesc(fs, vidx)->vd.kind = VDKREG`

35. **[localstat()]** 调用 `testnext(ls, ',')`，下一个 token 是 '='，不是 ','
    - 退出 do-while 循环

36. **[localstat()]** nvars = 1

37. **[localstat()]** 调用 `testnext(ls, '=')`，当前 token 是 '='
    - 消耗 '='，token 前移到 `{`

38. **[localstat()]** 进入 ***有初始化表达式*** 分支

39. **[localstat()]** 调用 `nexps = explist(ls, &e)` 分析右侧表达式

40. **[进入 explist()]** (LexState* ls(token:'{'), expdesc* e)

41. **[explist()]** 调用 `expr(ls, e)` 分析表达式

42. **[进入 expr()]** (LexState* ls(token:'{'), expdesc* e)

43. **[expr()]** 调用 `subexpr(ls, e, 0)`

44. **[进入 subexpr()]** (LexState* ls(token:'{'), expdesc* e, int priority(0))

45. **[subexpr()]** 调用 `simpleexp(ls, e)` 分析简单表达式

46. **[进入 simpleexp()]** (LexState* ls(token:'{'), expdesc* e)

47. **[simpleexp()]** 进入 ***'{'*** 分支，调用 `constructor(ls, e)`

48. **[进入 constructor()]** (LexState* ls(token:'{'), expdesc* t)

49. **[constructor()]** 调用 `luaK_codeABC(fs, OP_NEWTABLE, 0, 0, 0)` 生成创建表指令
    - pc = 0（第一条指令的位置）

50. **[进入 luaK_codeABC()]** (FuncState* fs, OpCode o(OP_NEWTABLE), int a(0), int b(0), int c(0))
    - 编码指令为整数
    - 写入 `fs->f->code[fs->pc]`
    - fs->pc++

51. **[回到 constructor()]** 调用 `luaK_code(fs, 0)` 预留 EXTRAARG 空间

52. **[constructor()]** 初始化 ConsControl
    - `cc.na = cc.nh = cc.tostore = 0`
    - `cc.t = t`

53. **[constructor()]** 调用 `init_exp(t, VNONRELOC, fs->freereg)`
    - t->k = VNONRELOC
    - t->u.info = 0（表将在 R[0]）

54. **[constructor()]** 调用 `luaK_reserveregs(fs, 1)`
    - fs->freereg = 1

55. **[constructor()]** 调用 `checknext(ls, '{')`，消耗 '{'
    - token 前移到 `}`

56. **[constructor()]** 进入 do-while 循环

57. **[constructor()]** ls->t.token == '}'，break（空表）

58. **[constructor()]** 调用 `check_match(ls, '}', '{', line)`

59. **[constructor()]** 调用 `lastlistfield(fs, &cc)`

60. **[constructor()]** 调用 `luaK_settablesize(fs, pc, t->u.info, cc.na, cc.nh)`

61. **[回到 simpleexp()]** e->k = VNONRELOC, e->u.info = 0

62. **[回到 subexpr()]** 返回

63. **[回到 expr()]** 返回

64. **[回到 explist()]** 下一个 token 不是 ','，return n = 1

65. **[回到 localstat()]** nexps = 1, nvars = 1

66. **[localstat()]** nexps == nvars，进入 ***精确赋值*** 分支

67. **[localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

68. **[进入 adjust_assign()]** (LexState* ls, int nvars(1), int nexps(1), expdesc* e(VNONRELOC, info:0))

69. **[adjust_assign()]** 调用 `luaK_setoneret(ls->fs, e)`

70. **[进入 luaK_setoneret()]** (FuncState* fs, expdesc* e(VNONRELOC))
    - e->k == VNONRELOC，不需要操作

71. **[回到 adjust_assign()]** 返回

72. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

73. **[进入 adjustlocalvars()]** (LexState* ls, int nvars(1))

74. **[adjustlocalvars()]** 循环 nvars 次

75. **[进入第1次循环]** 调用 `registerlocalvar(ls, fs, getlocalvardesc(fs, 0)->vd.name)`

76. **[进入 registerlocalvar()]** (LexState* ls, FuncState* fs, TString* varname("_M"))
    - 扩展 f->locvars 数组
    - 设置 `f->locvars[fs->ndebugvars].varname = "_M"`
    - 设置 `f->locvars[fs->ndebugvars].startpc = fs->pc = 1`
    - fs->ndebugvars = 1
    - 返回 0

77. **[回到 adjustlocalvars()]** 设置 `getlocalvardesc(fs, 0)->vd.pidx = 0`

78. **[adjustlocalvars()]** fs->nactvar = 1（激活的局部变量数量）

79. **[adjustlocalvars()]** 设置 `getlocalvardesc(fs, 0)->vd.ridx = 0`（寄存器索引）

80. **[回到 localstat()]** 调用 `checktoclose(fs, toclose)`

81. **[localstat()]** 返回

82. **[回到 statement()]** 返回，恢复寄存器状态

---

#### 第二条语句：function _M.main(...) ... end

83. **[回到 statlist()]** 调用 `statement(ls)`

84. **[进入 statement()]** (LexState* ls(token:TK_FUNCTION))

85. **[statement()]** 进入 ***TK_FUNCTION*** 分支，调用 `funcstat(ls, line)`

86. **[进入 funcstat()]** (LexState* ls(token:TK_FUNCTION))

87. **[funcstat()]** 调用 `luaX_next(ls)`，跳过 FUNCTION
    - token 前移到 `{ _M : TK_NAME }`

88. **[funcstat()]** 调用 `ismethod = funcname(ls, &v)` 分析函数名

89. **[进入 funcname()]** (LexState* ls(token:TK_NAME), expdesc* v)

90. **[funcname()]** 调用 `singlevar(ls, v)` 分析基础变量名

91. **[进入 singlevar()]** (LexState* ls(token:TK_NAME))

92. **[singlevar()]** 调用 `str_checkname(ls)`，取出 "_M"
    - token 前移到 `{ . : '.' }`

93. **[singlevar()]** 调用 `singlevaraux(fs, "_M", var, 1)` 查找变量

94. **[进入 singlevaraux()]** (FuncState* fs(main), TString* n("_M"), expdesc* var, int base(1))

95. **[singlevaraux()]** 调用 `searchvar(fs, "_M", var)` 在当前函数域查找局部变量

96. **[进入 searchvar()]** (FuncState* fs(main), TString* n("_M"))
    - 遍历 actvar.arr，从 fs->nactvar-1 = 0 开始向下查找
    - 找到 "_M" 在 actvar.arr[0]
    - return 0（局部变量索引）

97. **[回到 singlevaraux()]** v = 0 >= 0

98. **[singlevaraux()]** 进入 ***v >= 0*** 分支

99. **[singlevaraux()]** v == VLOCAL（局部变量类型）

100. **[singlevaraux()]** base == 1，不需要标记上值

101. **[singlevaraux()]** 调用 `init_exp(var, VLOCAL, v)`

102. **[进入 init_exp()]** (expdesc* var, expkind k(VLOCAL), int i(0))
    - var->k = VLOCAL
    - var->u.var.vidx = 0
    - var->u.var.ridx = 0（从 getlocalvardesc 获取）

103. **[回到 singlevar()]** var->k = VLOCAL，局部变量 _M

104. **[回到 funcname()]** var->k = VLOCAL

105. **[funcname()]** 下一个 token 是 '.'，进入 while 循环

106. **[funcname()]** 调用 `fieldsel(ls, v)` 处理字段选择

107. **[进入 fieldsel()]** (LexState* ls(token:'.'), expdesc* v(VLOCAL))

108. **[fieldsel()]** 调用 `luaK_exp2anyregup(fs, v)`

109. **[进入 luaK_exp2anyregup()]** (FuncState* fs, expdesc* e(VLOCAL))
    - e->k == VLOCAL，不等于 VUPVAL
    - 调用 `luaK_exp2anyreg(fs, e)`

110. **[进入 luaK_exp2anyreg()]** (FuncState* fs, expdesc* e(VLOCAL))

111. **[luaK_exp2anyreg()]** 调用 `luaK_dischargevars(fs, e)`

112. **[进入 luaK_dischargevars()]** (FuncState* fs, expdesc* e(VLOCAL))

113. **[luaK_dischargevars()]** 进入 ***VLOCAL*** 分支

114. **[luaK_dischargevars()]** `e->u.info = e->u.var.ridx = 0`

115. **[luaK_dischargevars()]** `e->k = VNONRELOC`

116. **[回到 luaK_exp2anyreg()]** e->k == VNONRELOC

117. **[luaK_exp2anyreg()]** `!hasjumps(e)` 为 true

118. **[luaK_exp2anyreg()]** return e->u.info = 0

119. **[回到 luaK_exp2anyregup()]** 返回

120. **[回到 fieldsel()]** 调用 `luaX_next(ls)`，跳过 '.'
    - token 前移到 `{ main : TK_NAME }`

121. **[fieldsel()]** 调用 `codename(ls, &key)` 获取字段名

122. **[进入 codename()]** (LexState* ls, expdesc* e)
    - 调用 `str_checkname(ls)` 获取 "main"
    - 调用 `codestring(e, "main")`

123. **[回到 fieldsel()]** key->k = VKSTR

124. **[fieldsel()]** 调用 `luaK_indexed(fs, v, &key)` 转换为索引形式

125. **[进入 luaK_indexed()]** (FuncState* fs, expdesc* t(VNONRELOC, info:0), expdesc* k(VKSTR, "main"))

126. **[luaK_indexed()]** k->k == VKSTR，调用 `str2K(fs, k)`

127. **[str2K()]** 将 "main" 加入常量表

128. **[回到 luaK_indexed()]** t->k == VNONRELOC，进入 ***else*** 分支

129. **[luaK_indexed()]** `t->u.ind.t = 0`（表在 R[0]）

130. **[luaK_indexed()]** `t->u.ind.idx = k->u.info = 0`（"main" 的 K 表索引）

131. **[luaK_indexed()]** `t->k = VINDEXSTR`

132. **[回到 fieldsel()]** v->k = VINDEXSTR（_M["main"]）

133. **[回到 funcname()]** 下一个 token 是 '('，不是 ':' 或 '.'

134. **[funcname()]** return ismethod = 0

135. **[回到 funcstat()]** ismethod = 0

136. **[funcstat()]** 调用 `body(ls, &b, ismethod, line)` 分析函数体

137. **[进入 body()]** (LexState* ls(token:'('), expdesc* e, int ismethod(0), int line)

138. **[body()]** 调用 `new_fs.f = addprototype(ls)` 添加函数原型

139. **[进入 addprototype()]** (LexState* ls)
    - 在 fs->f->p 数组中添加新的 Proto*
    - fs->np = 1
    - return &new_fs.f

140. **[回到 body()]** 设置 `new_fs.f->linedefined = line`

141. **[body()]** 调用 `open_func(ls, &new_fs, &bl)` 打开新函数状态

142. **[进入 open_func()]** (LexState* ls, FuncState* &new_fs, BlockCnt* bl)
    - 设置 `new_fs.prev = ls->fs`（指向 main 函数）
    - 设置 `ls->fs = &new_fs`（当前函数变为 main 函数）
    - 初始化 `new_fs.pc = 0, new_fs.freereg = 0, new_fs.nk = 0, new_fs.np = 0`

143. **[回到 body()]** 调用 `checknext(ls, '(')`

144. **[body()]** ismethod == 0，跳过 self 参数创建

145. **[body()]** 调用 `parlist(ls)` 分析参数列表

146. **[进入 parlist()]** (LexState* ls(token:TK_DOTS))

147. **[parlist()]** ls->t.token == TK_DOTS，进入 ***TK_DOTS*** 分支

148. **[parlist()]** 调用 `luaX_next(ls)`，跳过 '...'
    - token 前移到 `{ ) : ')' }`

149. **[parlist()]** 设置 `isvararg = 1`

150. **[parlist()]** `!isvararg` 为 false，退出 do-while 循环

151. **[parlist()]** nparams = 0

152. **[parlist()]** 调用 `adjustlocalvars(ls, 0)`（没有命名参数）

153. **[parlist()]** 设置 `f->numparams = 0`

154. **[parlist()]** isvararg == 1，调用 `setvararg(fs, 0)`

155. **[进入 setvararg()]** (FuncState* fs(main函数), int nparams(0))
    - 设置 `fs->f->is_vararg = 1`
    - 调用 `luaK_codeABC(fs, OP_VARARGPREP, 0, 0, 0)`
    - 生成 VARARGPREP 指令

156. **[回到 parlist()]** 调用 `luaK_reserveregs(fs, 0)`

157. **[parlist()]** 返回

158. **[回到 body()]** 调用 `checknext(ls, ')')`

159. **[body()]** 调用 `statlist(ls)` 解析函数体语句列表

160. **[进入 statlist()]** (LexState* ls(token:TK_LOCAL))

---

#### 函数内第一条语句：local a = nil

161. **[statlist()]** 调用 `statement(ls)`

162. **[进入 statement()]** (LexState* ls(token:TK_LOCAL), FuncState* fs(main函数))

163. **[statement()]** 进入 ***TK_LOCAL*** 分支，调用 `localstat(ls)`

164. **[进入 localstat()]** (LexState* ls(token:TK_LOCAL))

165. **[localstat()]** 调用 `str_checkname(ls)` 获取 "a"
    - token 前移到 `{ = : '=' }`

166. **[localstat()]** 调用 `new_localvar(ls, "a")`
    - 在 main 函数的 actvar 中创建新的局部变量
    - vidx = 0（main 函数的第一个局部变量）

167. **[localstat()]** 调用 `getlocalattribute(ls)`，返回 VDKREG

168. **[localstat()]** nvars = 1

169. **[localstat()]** 调用 `testnext(ls, '=')`，当前 token 是 '='

170. **[localstat()]** 调用 `nexps = explist(ls, &e)`

171. **[进入 explist()]** (LexState* ls(token:'='))

172. **[explist()]** 调用 `luaX_next(ls)`，跳过 '='
    - token 前移到 `{ nil : TK_NIL }`

173. **[explist()]** 调用 `expr(ls, e)`

174. **[进入 expr()]** (LexState* ls(token:TK_NIL))

175. **[expr()]** 调用 `subexpr(ls, e, 0)`

176. **[进入 subexpr()]** (LexState* ls(token:TK_NIL))

177. **[subexpr()]** 调用 `simpleexp(ls, e)`

178. **[进入 simpleexp()]** (LexState* ls(token:TK_NIL))

179. **[simpleexp()]** 进入 ***TK_NIL*** 分支

180. **[simpleexp()]** 调用 `init_exp(v, VNIL, 0)`
    - v->k = VNIL
    - v->u.info = 0

181. **[回到 subexpr()]** 返回

182. **[回到 expr()]** 返回

183. **[回到 explist()]** 下一个 token 不是 ','，return n = 1

184. **[回到 localstat()]** nexps = 1, nvars = 1

185. **[localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

186. **[进入 adjust_assign()]** 调用 `luaK_setoneret(ls->fs, &e)`

187. **[进入 luaK_setoneret()]** (FuncState* fs, expdesc* e(VNIL))
    - 调用 `luaK_exp2anyreg(fs, e)`

188. **[进入 luaK_exp2anyreg()]** (FuncState* fs, expdesc* e(VNIL))

189. **[luaK_exp2anyreg()]** 调用 `luaK_dischargevars(fs, e)`

190. **[进入 luaK_dischargevars()]** e->k == VNIL，进入 ***default*** 分支

191. **[回到 luaK_exp2anyreg()]** e->k != VNONRELOC

192. **[luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

193. **[进入 luaK_exp2nextreg()]** (FuncState* fs, expdesc* e(VNIL))

194. **[luaK_exp2nextreg()]** 调用 `luaK_dischargevars(fs, e)`（无操作）

195. **[luaK_exp2nextreg()]** 调用 `freeexp(fs, e)`（无操作）

196. **[luaK_exp2nextreg()]** 调用 `luaK_reserveregs(fs, 1)`
    - fs->freereg = 1

197. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg - 1) = exp2reg(fs, e, 0)`

198. **[进入 exp2reg()]** (FuncState* fs, expdesc* e(VNIL), int reg(0))

199. **[exp2reg()]** 调用 `discharge2reg(fs, e, reg)`

200. **[进入 discharge2reg()]** (FuncState* fs, expdesc* e(VNIL), int reg(0))

201. **[discharge2reg()]** 调用 `luaK_dischargevars(fs, e)`（无操作）

202. **[discharge2reg()]** e->k == VNIL，进入 ***VNIL*** 分支

203. **[discharge2reg()]** 调用 `luaK_nil(fs, reg, 1)`
    - 生成 LOADNIL 指令

204. **[回到 exp2reg()]** hasjumps(e) == false，跳过跳转列表处理

205. **[exp2reg()]** `e->f = e->t = NO_JUMP`

206. **[exp2reg()]** `e->u.info = reg = 0`

207. **[exp2reg()]** `e->k = VNONRELOC`

208. **[回到 luaK_exp2nextreg()]** e->k = VNONRELOC, e->u.info = 0

209. **[回到 luaK_exp2anyreg()]** return e->u.info = 0

210. **[回到 luaK_setoneret()]** 返回

211. **[回到 adjust_assign()]** 返回

212. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

213. **[进入 adjustlocalvars()]** (LexState* ls, int nvars(1))

214. **[adjustlocalvars()]** 循环 1 次

215. **[进入第1次循环]** 调用 `registerlocalvar(ls, fs, "a")`
    - 设置 `f->locvars[0].varname = "a"`
    - 设置 `f->locvars[0].startpc = 1`
    - fs->ndebugvars = 1

216. **[回到 adjustlocalvars()]** 设置 `getlocalvardesc(fs, 0)->vd.pidx = 0`

217. **[adjustlocalvars()]** 设置 `getlocalvardesc(fs, 0)->vd.ridx = 0`

218. **[adjustlocalvars()]** fs->nactvar = 1

219. **[回到 localstat()]** 返回

220. **[回到 statement()]** 返回，恢复寄存器状态

---

#### 函数内第二条语句：local b = false

221. **[回到 statlist()]** 调用 `statement(ls)`

222. **[进入 statement()]** (LexState* ls(token:TK_LOCAL))

223. **[statement()]** 调用 `localstat(ls)`

224. **[进入 localstat()]** 类似处理 "b"

225. **[localstat()]** 调用 `new_localvar(ls, "b")`
    - vidx = 1

226. **[localstat()]** 调用 `explist(ls, &e)`，分析 false

227. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()**

228. **[simpleexp()]** 进入 ***TK_FALSE*** 分支

229. **[simpleexp()]** 调用 `init_exp(v, VFALSE, 0)`
    - v->k = VFALSE

230. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

231. **[adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

232. **[discharge2reg()]** e->k == VFALSE，进入 ***VFALSE*** 分支

233. **[discharge2reg()]** 调用 `luaK_codeABC(fs, OP_LOADFALSE, 1, 0, 0)`
    - 生成 LOADFALSE 指令到 R[1]

234. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

235. **[adjustlocalvars()]** registerlocalvar("b")
    - fs->ndebugvars = 2

236. **[adjustlocalvars()]** fs->nactvar = 2

237. **[回到 statement()]** 返回

---

#### 函数内第三条语句：local c = 42

238. **[回到 statlist()]** 调用 `statement(ls)`

239. **[进入 statement()]** 调用 `localstat(ls)`

240. **[进入 localstat()]** 处理 "c = 42"

241. **[localstat()]** 调用 `new_localvar(ls, "c")`
    - vidx = 2

242. **[localstat()]** 调用 `explist(ls, &e)`，分析 42

243. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()**

244. **[simpleexp()]** 进入 ***TK_INT*** 分支

245. **[simpleexp()]** 调用 `init_exp(v, VKINT, 0)`

246. **[simpleexp()]** 设置 `v->u.ival = 42`

247. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

248. **[adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

249. **[discharge2reg()]** e->k == VKINT，进入 ***VKINT*** 分支

250. **[discharge2reg()]** 调用 `luaK_int(fs, 2, 42)`
    - 生成 LOADI 指令：`LOADI 2 42`

251. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

252. **[adjustlocalvars()]** registerlocalvar("c")
    - fs->ndebugvars = 3

253. **[adjustlocalvars()]** fs->nactvar = 3

254. **[回到 statement()]** 返回

---

#### 函数内第四条语句：local d = "hello"

255. **[回到 statlist()]** 调用 `statement(ls)`

256. **[进入 statement()]** 调用 `localstat(ls)`

257. **[进入 localstat()]** 处理 "d = "hello""

258. **[localstat()]** 调用 `new_localvar(ls, "d")`
    - vidx = 3

259. **[localstat()]** 调用 `explist(ls, &e)`，分析 "hello"

260. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()**

261. **[simpleexp()]** 进入 ***TK_STRING*** 分支

262. **[simpleexp()]** 调用 `codestring(v, "hello")`
    - v->k = VKSTR
    - v->u.strval = "hello"

263. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

264. **[adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

265. **[discharge2reg()]** e->k == VKSTR，进入 ***VKSTR*** 分支

266. **[discharge2reg()]** 调用 `str2K(fs, e)` 将 "hello" 加入常量表
    - 返回 K 表索引 0

267. **[discharge2reg()]** 进入 ***VK*** 分支（str2K 后 e->k = VK）

268. **[discharge2reg()]** 调用 `luaK_codek(fs, 3, 0)`
    - 生成 LOADK 指令：`LOADK 3 0`

269. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

270. **[adjustlocalvars()]** registerlocalvar("d")
    - fs->ndebugvars = 4

271. **[adjustlocalvars()]** fs->nactvar = 4

272. **[回到 statement()]** 返回

---

#### 函数内第五条语句：local v = ...

273. **[回到 statlist()]** 调用 `statement(ls)`

274. **[进入 statement()]** 调用 `localstat(ls)`

275. **[进入 localstat()]** 处理 "v = ..."

276. **[localstat()]** 调用 `new_localvar(ls, "v")`
    - vidx = 4

277. **[localstat()]** 调用 `explist(ls, &e)`，分析 ...

278. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()**

279. **[simpleexp()]** 进入 ***TK_DOTS*** 分支

280. **[simpleexp()]** 调用 `init_exp(v, VVARARG, 0)`
    - v->k = VVARARG

281. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

282. **[adjust_assign()]** 调用 `luaK_setoneret(ls->fs, &e)`

283. **[进入 luaK_setoneret()]** (FuncState* fs, expdesc* e(VVARARG))

284. **[luaK_setoneret()]** 调用 `luaK_setreturns(fs, e, 1)`

285. **[进入 luaK_setreturns()]** (FuncState* fs, expdesc* e(VVARARG), int nresults(1))

286. **[luaK_setreturns()]** e->k == VVARARG，进入 ***VVARARG*** 分支

287. **[luaK_setreturns()]** 调用 `luaK_codeABC(fs, OP_VARARG, 4, 1, 0)`
    - 生成 VARARG 指令：`VARARG 4 1`（将可变参数加载到 R[4]，返回 1 个值）

288. **[luaK_setreturns()]** 设置 `e->u.info = pc`（VARARG 指令位置）

289. **[luaK_setreturns()]** 设置 `e->k = VCALL`

290. **[回到 luaK_setoneret()]** 返回

291. **[回到 adjust_assign()]** 返回

292. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

293. **[adjustlocalvars()]** registerlocalvar("v")
    - fs->ndebugvars = 5

294. **[adjustlocalvars()]** fs->nactvar = 5

295. **[回到 statement()]** 返回

---

#### 函数结束：end

296. **[回到 statlist()]** 调用 `statement(ls)`

297. **[进入 statement()]** (LexState* ls(token:TK_END))

298. **[statement()]** token == TK_END，返回

299. **[回到 statlist()]** token == TK_END，return

300. **[回到 body()]** 调用 `new_fs.f->lastlinedefined = ls->linenumber`

301. **[body()]** 调用 `check_match(ls, TK_END, TK_FUNCTION, line)`

302. **[body()]** 调用 `codeclosure(ls, e)`

303. **[进入 codeclosure()]** (LexState* ls, expdesc* v)

304. **[codeclosure()]** 设置 `fs = ls->fs->prev`（回到 main 函数）

305. **[codeclosure()]** 调用 `init_exp(v, VRELOC, luaK_codeABx(fs, OP_CLOSURE, 0, fs->np - 1))`
    - fs->np = 1
    - 生成 CLOSURE 指令：`CLOSURE 0 0`

306. **[codeclosure()]** 调用 `luaK_exp2nextreg(fs, v)`
    - 将闭包放入寄存器

307. **[codeclosure()]** 返回，v->k = VNONRELOC, v->u.info = 1

308. **[回到 body()]** 调用 `close_func(ls)`

309. **[进入 close_func()]** 关闭函数状态
    - ls->fs = ls->fs->prev（回到 main 函数）

310. **[回到 body()]** 返回

311. **[回到 funcstat()]** 调用 `check_readonly(ls, &v)`（v 是 VINDEXSTR，不是只读）

312. **[funcstat()]** 调用 `luaK_storevar(ls->fs, &v, &b)`

313. **[进入 luaK_storevar()]** (FuncState* fs(main), expdesc* var(VINDEXSTR), expdesc* ex(VNONRELOC, info:1))

314. **[luaK_storevar()]** var->k == VINDEXSTR，进入 ***VINDEXSTR*** 分支

315. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETFIELD, var->u.ind.t, var->u.ind.idx, ex)`
    - var->u.ind.t = 0（_M 在 R[0]）
    - var->u.ind.idx = 0（"main" 的 K 表索引）
    - ex 在 R[1]
    - 生成 SETFIELD 指令：`SETFIELD 0 0 1`

316. **[回到 funcstat()]** 调用 `luaK_fixline(ls->fs, line)`

317. **[回到 statement()]** 返回

---

#### 第三条语句：return _M

318. **[回到 statlist()]** 调用 `statement(ls)`

319. **[进入 statement()]** (LexState* ls(token:TK_RETURN))

320. **[statement()]** 进入 ***TK_RETURN*** 分支，调用 `retstat(ls)`

321. **[进入 retstat()]** (LexState* ls(token:TK_RETURN))

322. **[retstat()]** 调用 `first = luaY_nvarstack(fs)`
    - fs->nactvar = 1
    - 返回 first = 1

323. **[retstat()]** 下一个 token 是 '_M'，不是 ';' 或 block_follow

324. **[retstat()]** 调用 `nret = explist(ls, &e)` 分析返回值

325. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()**

326. **[simpleexp()]** → **primaryexp()** → **singlevar()**

327. **[singlevar()]** 查找 "_M"，返回 VLOCAL, vidx = 0

328. **[回到 retstat()]** nret = 1

329. **[retstat()]** hasmultret(VLOCAL) == false

330. **[retstat()]** nret == 1，进入 ***单一返回值*** 分支

331. **[retstat()]** 调用 `first = luaK_exp2anyreg(fs, &e)`

332. **[进入 luaK_exp2anyreg()]** (FuncState* fs, expdesc* e(VLOCAL))

333. **[luaK_exp2anyreg()]** → **luaK_dischargevars()**

334. **[luaK_dischargevars()]** e->k == VLOCAL，进入 ***VLOCAL*** 分支

335. **[luaK_dischargevars()]** `e->u.info = 0, e->k = VNONRELOC`

336. **[回到 luaK_exp2anyreg()]** return e->u.info = 0

337. **[回到 retstat()]** first = 0

338. **[retstat()]** 调用 `luaK_ret(fs, 0, 1)`
    - 生成 RETURN 指令：`RETURN 0 1`

339. **[retstat()]** 调用 `testnext(ls, ';')`，跳过可选的分号

340. **[回到 statement()]** 返回

341. **[回到 statlist()]** 下一个 token 是 TK_EOS，return

342. **[回到 mainfunc()]** 调用 `check(ls, TK_EOS)`

343. **[mainfunc()]** 调用 `close_func(ls)`

344. **[进入 close_func()]** 关闭 main 函数
    - ls->fs = NULL

345. **[回到 mainfunc()]** 返回

346. **[回到 luaY_parser()]** 断言检查

347. **[luaY_parser()]** 移除扫描器表，返回闭包 cl

---

### 调用链树状图

```
luaY_parser()                                  [编译器入口]
├── 创建 LClosure 和 Proto
├── 初始化 LexState 和 FuncState
├── luaX_setinput()                            [设置输入流]
└── mainfunc()                                 [解析 main 函数]
    ├── open_func()                            [打开函数状态]
    ├── setvararg()                            [设置可变参数]
    │   └── luaK_codeABC()                     [OP_VARARGPREP 指令]
    ├── allocupvalue()                         [分配 _ENV 上值]
    └── statlist()                             [解析语句列表]
        │
        ├── 第一条语句: local _M = {}
        │   └── statement() → localstat()
        │       ├── new_localvar("_M")         [创建局部变量]
        │       └── explist()
        │           └── expr() → simpleexp()
        │               └── constructor()      [表构造器]
        │                   ├── luaK_codeABC()  [NEWTABLE 指令]
        │                   └── [空表，无字段]
        │       └── adjustlocalvars()           [激活局部变量]
        │
        ├── 第二条语句: function _M.main(...)
        │   └── statement() → funcstat()
        │       ├── funcname()                  [解析函数名]
        │       │   ├── singlevar("_M")        [查找 _M]
        │       │   └── fieldsel()             [解析 .main]
        │       └── body()                      [解析函数体]
        │           ├── addprototype()          [添加函数原型]
        │           ├── open_func()             [打开新函数状态]
        │           ├── parlist()               [解析参数列表]
        │           │   └── TK_DOTS 分支        [可变参数]
        │           │       └── setvararg()     [设置可变参数]
        │           │           └── luaK_codeABC() [OP_VARARGPREP]
        │           └── statlist()             [解析函数体]
        │               │
        │               ├── local a = nil
        │               │   └── localstat()
        │               │       └── explist()
        │               │           └── simpleexp() → init_exp(VNIL)
        │               │       └── luaK_exp2nextreg() → exp2reg()
        │               │           └── discharge2reg()
        │               │               └── luaK_nil()      [LOADNIL]
        │               │       └── adjustlocalvars()
        │               │
        │               ├── local b = false
        │               │   └── localstat()
        │               │       └── explist() → simpleexp() → init_exp(VFALSE)
        │               │       └── luaK_exp2nextreg() → exp2reg() → discharge2reg()
        │               │           └── luaK_codeABC()     [LOADFALSE]
        │               │       └── adjustlocalvars()
        │               │
        │               ├── local c = 42
        │               │   └── localstat()
        │               │       └── explist() → simpleexp() → init_exp(VKINT, 42)
        │               │       └── luaK_exp2nextreg() → exp2reg() → discharge2reg()
        │               │           └── luaK_int()         [LOADI]
        │               │       └── adjustlocalvars()
        │               │
        │               ├── local d = "hello"
        │               │   └── localstat()
        │               │       └── explist() → simpleexp() → codestring("hello")
        │               │       └── luaK_exp2nextreg() → exp2reg() → discharge2reg()
        │               │           └── str2K() → luaK_codek()  [LOADK]
        │               │       └── adjustlocalvars()
        │               │
        │               ├── local v = ...
        │               │   └── localstat()
        │               │       └── explist() → simpleexp() → init_exp(VVARARG)
        │               │       └── luaK_setoneret() → luaK_setreturns()
        │               │           └── luaK_codeABC()         [VARARG]
        │               │       └── adjustlocalvars()
        │               │
        │               └── statlist() 返回 (遇到 TK_END)
        │           ├── codeclosure()                 [生成闭包]
        │           │   └── luaK_codeABx()             [CLOSURE 指令]
        │           └── close_func()                   [关闭函数状态]
        │       └── luaK_storevar()
        │           └── codeABRK()                     [SETFIELD 指令]
        │
        ├── 第三条语句: return _M
        │   └── statement() → retstat()
        │       ├── luaY_nvarstack()                  [获取返回起始位置]
        │       ├── explist()
        │       │   └── expr() → singlevar("_M")      [查找 _M]
        │       ├── luaK_exp2anyreg()                 [确保在寄存器]
        │       └── luaK_ret()                        [生成 RETURN 指令]
        │
        └── statlist() 返回 (遇到 TK_EOS)
    └── close_func()                             [关闭 main 函数]
```

**树状图说明**：
- 每个缩进层级（├── / └──）表示一次函数调用
- `→` 表示函数内部继续调用
- `[说明]` 表示关键操作或数据状态
- 同级语句按执行顺序从上到下排列

---

### 最终生成的字节码

#### main 函数字节码

```
; main 函数初始化
VARARGPREP 0 0 0        ; 准备可变参数

; local _M = {}
NEWTABLE 0 0 0 0       ; R[0] = {}
EXTRAARG 0              ; 额外参数
; (局部变量 _M 绑定到 R[0])

; function _M.main(...)
; (函数定义，不生成 main 函数的指令)
CLOSURE 1 0            ; R[1] = closure(proto[0])
SETFIELD 0 0 1         ; R[0]["main"] = R[1]

; return _M
RETURN 0 1 1           ; return R[0] (1 个值)
```

#### _M.main 函数字节码

```
; 函数初始化
VARARGPREP 0 0 0       ; 准备可变参数

; local a = nil
LOADNIL 0 1            ; R[0] = nil
; (局部变量 a 绑定到 R[0])

; local b = false
LOADFALSE 1 0 0        ; R[1] = false
; (局部变量 b 绑定到 R[1])

; local c = 42
LOADI 2 42             ; R[2] = 42
; (局部变量 c 绑定到 R[2])

; local d = "hello"
LOADK 3 0              ; R[3] = K[0] ("hello")
; (局部变量 d 绑定到 R[3])

; local v = ...
VARARG 4 1 0           ; R[4] = ... (取 1 个参数)
; (局部变量 v 绑定到 R[4])

; 函数结束 (隐式返回 0 个值)
RETURN 0 0 0           ; return (无返回值)
```

---

## 数据结构详解

### LexState

**定义**：
```c
// src/llex.h
typedef struct LexState {
  int current;              /* 当前字符 */
  int linenumber;           /* 输入行计数器 */
  int lastline;             /* 最后消耗的 token 所在行 */
  Token t;                  /* 当前 token */
  Token lookahead;          /* 前瞻 token */
  struct FuncState *fs;     /* 当前函数（解析器） */
  struct lua_State *L;      /* Lua 状态机 */
  ZIO *z;                   /* 输入流 */
  Mbuffer *buff;            /* token 缓冲区 */
  Table *h;                 /* 避免字符串被收集/重用 */
  struct Dyndata *dyd;      /* 解析器使用的动态结构 */
  TString *source;          /* 当前源名称 */
  TString *envn;            /* 环境变量名（"_ENV"） */
} LexState;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| current | int | 当前正在处理的字符 | 词法分析器 |
| linenumber | int | 当前行号 | 错误报告和调试信息 |
| t | Token | 当前 token（包含类型和语义值） | 所有解析函数 |
| lookahead | Token | 前瞻 token（用于 LL(2) 解析） | 特殊语法结构 |
| fs | FuncState* | 当前函数编译状态 | 代码生成 |
| z | ZIO* | 输入流（读取源代码） | 词法分析器 |
| buff | Mbuffer* | token 字符串缓冲区 | 字符串 token 构建 |
| h | Table* | 字符串哈希表（避免重复） | 字符串 intern |
| dyd | Dyndata* | 动态数据（局部变量、标签、goto） | 变量管理 |
| source | TString* | 源文件名 | 调试信息 |
| envn | TString* | 环境变量名（"_ENV"） | 全局变量访问 |

---

### FuncState

**定义**：
```c
// src/lparser.h
typedef struct FuncState {
  Proto *f;                  /* 当前函数原型 */
  struct FuncState *prev;     /* 外层函数 */
  struct LexState *ls;        /* 词法状态 */
  struct BlockCnt *bl;        /* 当前块链 */
  int pc;                     /* 下一个代码位置 */
  int lasttarget;             /* 上一个跳转标签位置 */
  int previousline;           /* 上一次保存的行号 */
  int nk;                     /* K 表元素数量 */
  int np;                     /* 原型表元素数量 */
  int nabslineinfo;           /* 绝对行信息数量 */
  int firstlocal;             /* 第一个局部变量索引 */
  int firstlabel;             /* 第一个标签索引 */
  short ndebugvars;           /* 调试变量数量 */
  lu_byte nactvar;            /* 活跃局部变量数量 */
  lu_byte nups;               /* 上值数量 */
  lu_byte freereg;            /* 下一个空闲寄存器 */
  lu_byte iwthabs;            /* 自上次绝对行信息以来的指令数 */
  lu_byte needclose;          /* 返回时是否需要关闭 upvalue */
} FuncState;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 | 赋值位置 |
|--------|----------|----------|----------|----------|
| f | Proto* | 当前函数原型 | 所有代码生成函数 | open_func |
| prev | FuncState* | 外层函数状态（链表） | 函数嵌套调用 | open_func |
| ls | LexState* | 词法分析器状态 | 所有解析函数 | open_func |
| bl | BlockCnt* | 块控制链 | 块级作用域管理 | open_func, block_* |
| pc | int | 程序计数器（下一条指令位置） | luaK_code*, 所有代码生成 | open_func(=0), luaK_code(++) |
| nk | int | 常量表 K 的元素数量 | stringK, addk | open_func(=0), addk(++) |
| np | int | 原型表元素数量 | addprototype | open_func(=0), addprototype(++) |
| nups | lu_byte | 上值数量 | singlevaraux, newupvalue | open_func(=0), allocupvalue(++) |
| freereg | lu_byte | 下一个空闲寄存器索引 | 寄存器分配 | open_func(=0), luaK_reserveregs |
| nactvar | lu_byte | 当前活跃的局部变量数量 | 局部变量管理 | open_func(=0), adjustlocalvars |

---

### Vardesc

**定义**：
```c
// src/lparser.h
typedef union Vardesc {
  struct {
    TValuefields;  /* 常量值（如果是编译期常量） */
    lu_byte kind;  /* 变量类型：VDKREG/RDKCONST/RDKTOCLOSE/RDKCTC */
    lu_byte ridx;  /* 保存变量的寄存器 */
    short pidx;    /* Proto 的 locvars 数组中的索引 */
    TString *name; /* 变量名 */
  } vd;
  TValue k;        /* 常量值（如果有） */
} Vardesc;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 | 赋值位置 |
|--------|----------|----------|----------|----------|
| vd.kind | lu_byte | 变量类型（普通/常量/to-close/编译期常量） | 变量访问 | new_localvar(VDKREG), getlocalattribute |
| vd.ridx | lu_byte | 保存变量的寄存器索引 | 变量访问 | adjustlocalvars |
| vd.pidx | short | locvars 数组中的索引（调试信息） | 调试信息 | registerlocalvar |
| vd.name | TString* | 变量名 | 调试信息 | new_localvar |

**kind 枚举值说明**：

| 枚举值 | 含义 | 使用场景 |
|--------|------|----------|
| VDKREG (0) | 普通局部变量 | 默认局部变量 |
| RDKCONST (1) | 只读变量 | <const> 声明的变量 |
| RDKTOCLOSE (2) | to-be-closed 变量 | <close> 声明的变量 |
| RDKCTC (3) | 编译期常量 | 编译期能确定值的常量 |

---

### Dyndata

**定义**：
```c
// src/lparser.h
typedef struct Dyndata {
  struct {  /* 所有活跃局部变量的列表 */
    Vardesc *arr;
    int n;
    int size;
  } actvar;
  Labellist gt;      /* 待处理的 goto 列表 */
  Labellist label;   /* 活跃标签列表 */
} Dyndata;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| actvar.arr | Vardesc* | 局部变量数组 | 所有局部变量操作 |
| actvar.n | int | 当前局部变量数量 | 局部变量管理 |
| actvar.size | int | 数组容量 | 扩容检查 |
| gt | Labellist | goto 语句列表 | goto 处理 |
| label | Labellist | 标签列表 | label 处理 |

---

### BlockCnt

**定义**：
```c
// src/lparser.c
typedef struct BlockCnt {
  struct BlockCnt *previous;  /* 链表 */
  int firstlabel;             /* 块中第一个标签索引 */
  int firstgoto;              /* 块中第一个待处理 goto 索引 */
  lu_byte nactvar;            /* 块外的活跃局部变量数 */
  lu_byte upval;              /* 块中是否有上值 */
  lu_byte isloop;             /* 块是否是循环 */
  lu_byte insidetbc;          /* 是否在 to-be-closed 变量作用域内 */
} BlockCnt;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| previous | BlockCnt* | 前一个块（链表） | 块嵌套 |
| nactvar | lu_byte | 块开始时的活跃变量数 | 退出块时恢复 |
| isloop | lu_byte | 是否是循环块（break 语义） | 循环处理 |
| insidetbc | lu_byte | 是否在 to-be-closed 作用域内 | 变量关闭 |

---

### expdesc

（已在参考文档中详细说明，此处略）

---

### ConsControl

**定义**：
```c
// src/lparser.c
typedef struct ConsControl {
  expdesc v;      /* 最后读取的列表项 */
  expdesc *t;     /* 表描述符 */
  int nh;         /* record 类型元素总数 */
  int na;         /* 已存储的数组元素数 */
  int tostore;    /* 待存储的数组元素数 */
} ConsControl;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| v | expdesc | 当前正在处理的字段值 | constructor, field, listfield, recfield |
| t | expdesc* | 指向表表达式的指针 | constructor, listfield, recfield |
| nh | int | 哈希类型字段数量 | constructor, recfield |
| na | int | 数组类型元素数量 | constructor, listfield |
| tostore | int | 待存储到表的元素数量 | constructor, listfield, closelistfield |

---

## 函数详解

### luaY_parser()

**源码位置**：src/lparser.c:1942

**源代码**：
```c
LClosure *luaY_parser (lua_State *L, ZIO *z, Mbuffer *buff,
                      Dyndata *dyd, const char *name, int firstchar) {
  LexState lexstate;
  FuncState funcstate;
  LClosure *cl = luaF_newLclosure(L, 1);  /* 创建 main 闭包 */
  setclLvalue2s(L, L->top.p, cl);  /* 锚定它（避免被回收） */
  luaD_inctop(L);
  lexstate.h = luaH_new(L);  /* 为扫描器创建表 */
  sethvalue2s(L, L->top.p, lexstate.h);  /* 锚定它 */
  luaD_inctop(L);
  funcstate.f = cl->p = luaF_newproto(L);
  luaC_objbarrier(L, cl, cl->p);
  funcstate.f->source = luaS_new(L, name);  /* 创建并锚定 TString */
  luaC_objbarrier(L, funcstate.f, funcstate.f->source);
  lexstate.buff = buff;
  lexstate.dyd = dyd;
  dyd->actvar.n = dyd->gt.n = dyd->label.n = 0;
  luaX_setinput(L, &lexstate, z, funcstate.f->source, firstchar);
  mainfunc(&lexstate, &funcstate);
  lua_assert(!funcstate.prev && funcstate.nups == 1 && !lexstate.fs);
  /* 所有作用域应该正确结束 */
  lua_assert(dyd->actvar.n == 0 && dyd->gt.n == 0 && dyd->label.n == 0);
  L->top.p--;  /* 移除扫描器的表 */
  return cl;  /* 闭包也在栈上 */
}
```

**功能说明**：

#### 逻辑段 1：创建闭包和原型
- **操作内容**：创建 main 函数的闭包和原型
- **数据影响**：cl = 新闭包，cl->p = 新原型
- **输入**：lua_State* L
- **输出**：LClosure* cl

#### 逻辑段 2：初始化词法分析器
- **操作内容**：创建哈希表用于字符串 intern，设置源文件名
- **数据影响**：lexstate.h = 新哈希表，funcstate.f->source = 源文件名
- **输入**：L, z, name
- **输出**：初始化后的 lexstate

#### 逻辑段 3：初始化动态数据
- **操作内容**：清空局部变量、goto、标签列表
- **数据影响**：dyd->actvar.n = dyd->gt.n = dyd->label.n = 0
- **输入**：dyd
- **输出**：清空后的 dyd

#### 逻辑段 4：设置输入并开始解析
- **操作内容**：设置词法分析器输入，调用 mainfunc 解析
- **数据影响**：开始读取 token，解析源代码
- **输入**：lexstate, funcstate
- **输出**：填充完整的 Proto

#### 逻辑段 5：清理并返回
- **操作内容**：断言检查，移除临时表，返回闭包
- **数据影响**：栈恢复，闭包留在栈上
- **输入**：L, cl
- **输出**：LClosure* cl

#### 函数总结
- **输入**：lua_State* L, ZIO* z, Mbuffer* buff, Dyndata* dyd, const char* name, int firstchar
- **输出**：LClosure* cl（编译后的闭包）
- **调用函数**：luaF_newLclosure, luaH_new, luaF_newproto, luaS_new, luaX_setinput, mainfunc

---

### mainfunc()

**源码位置**：src/lparser.c:1924

**源代码**：
```c
static void mainfunc (LexState *ls, FuncState *fs) {
  BlockCnt bl;
  Upvaldesc *env;
  open_func(ls, fs, &bl);
  setvararg(fs, 0);  /* main 函数总是声明为可变参数 */
  env = allocupvalue(fs);  /* ...设置环境上值 */
  env->instack = 1;
  env->idx = 0;
  env->kind = VDKREG;
  env->name = ls->envn;
  luaC_objbarrier(ls->L, fs->f, env->name);
  luaX_next(ls);  /* 读取第一个 token */
  statlist(ls);  /* 解析 main 函数体 */
  check(ls, TK_EOS);
  close_func(ls);
}
```

**功能说明**：

#### 逻辑段 1：打开函数状态
- **操作内容**：调用 open_func 初始化函数状态
- **数据影响**：fs->prev = NULL, ls->fs = fs, fs->pc = 0
- **输入**：ls, fs
- **输出**：初始化后的 fs

#### 逻辑段 2：设置可变参数
- **操作内容**：调用 setvararg 设置 main 函数为可变参数
- **数据影响**：fs->f->is_vararg = 1, 生成 OP_VARARGPREP 指令
- **输入**：fs
- **输出**：无

#### 逻辑段 3：创建 _ENV 上值
- **操作内容**：分配并设置环境上值
- **数据影响**：fs->nups = 1, env->name = "_ENV"
- **输入**：fs
- **输出**：无

#### 逻辑段 4：解析函数体
- **操作内容**：读取第一个 token，调用 statlist 解析语句列表
- **数据影响**：生成字节码
- **输入**：ls
- **输出**：无

#### 逻辑段 5：关闭函数
- **操作内容**：检查 EOS，调用 close_func
- **数据影响**：ls->fs = NULL
- **输入**：ls
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, FuncState* fs
- **输出**：无
- **调用函数**：open_func, setvararg, allocupvalue, luaX_next, statlist, close_func

---

### open_func()

**源码位置**：src/lparser.c:729

**源代码**：
```c
static void open_func (LexState *ls, FuncState *fs, BlockCnt *bl) {
  Proto *f = fs->f;
  fs->prev = ls->fs;  /* 函数状态链表 */
  fs->ls = ls;
  ls->fs = fs;
  fs->pc = 0;
  fs->previousline = f->linedefined;
  fs->iwthabs = 0;
  fs->lasttarget = 0;
  fs->freereg = 0;
  fs->nk = 0;
  fs->nabslineinfo = 0;
  fs->np = 0;
  fs->nups = 0;
  fs->bl = NULL;
  f->source = ls->source;
  f->maxstacksize = 0;  /* 临时值；将在 'precheck' 中修正 */
  ls->dyd->actvar.n = 0;
  ls->dyd->gt.n = 0;
  ls->dyd->label.n = 0;
  if (ls->fs != NULL) {  /* 不是 main 函数？ */
    fs->firstlocal = ls->fs->firstlocal;
    fs->firstlabel = ls->fs->firstlabel;
  }
  else {
    fs->firstlocal = 0;
    fs->firstlabel = 0;
  }
  bl->previous = NULL;
  bl->nactvar = 0;
  bl->firstlabel = 0;
  bl->firstgoto = 0;
  bl->upval = 0;
  bl->isloop = 0;
  bl->insidetbc = 0;
}
```

**功能说明**：

#### 逻辑段 1：建立函数链
- **操作内容**：将新函数链接到外层函数
- **数据影响**：fs->prev = ls->fs, ls->fs = fs
- **输入**：ls, fs
- **输出**：无

#### 逻辑段 2：初始化函数状态
- **操作内容**：初始化所有计数器和指针
- **数据影响**：pc = 0, freereg = 0, nk = 0, np = 0, nups = 0
- **输入**：fs
- **输出**：无

#### 逻辑段 3：初始化动态数据
- **操作内容**：清空局部变量、goto、标签列表
- **数据影响**：dyd->actvar.n = dyd->gt.n = dyd->label.n = 0
- **输入**：ls->dyd
- **输出**：无

#### 逻辑段 4：继承或初始化索引
- **操作内容**：如果有外层函数，继承 firstlocal 和 firstlabel
- **数据影响**：fs->firstlocal, fs->firstlabel
- **输入**：ls->fs
- **输出**：无

#### 逻辑段 5：初始化块控制
- **操作内容**：初始化 BlockCnt 结构
- **数据影响**：bl 的所有字段清零
- **输入**：bl
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, FuncState* fs, BlockCnt* bl
- **输出**：无
- **调用函数**：无

---

### setvararg()

**源码位置**：src/lparser.c:953

**源代码**：
```c
static void setvararg (FuncState *fs, int nparams) {
  fs->f->is_vararg = 1;
  luaK_codeABC(fs, OP_VARARGPREP, nparams, 0, 0);
}
```

**功能说明**：

#### 逻辑段 1：设置可变参数标志
- **操作内容**：标记函数为可变参数函数
- **数据影响**：fs->f->is_vararg = 1
- **输入**：fs
- **输出**：无

#### 逻辑段 2：生成 VARARGPREP 指令
- **操作内容**：生成准备可变参数的指令
- **数据影响**：生成 OP_VARARGPREP 指令
- **输入**：fs, nparams
- **输出**：无

#### 函数总结
- **输入**：FuncState* fs, int nparams（参数数量）
- **输出**：无
- **调用函数**：luaK_codeABC

---

### localstat()

**源码位置**：src/lparser.c:1726

**源代码**：
```c
static void localstat (LexState *ls) {
  /* stat -> LOCAL NAME ATTRIB { ',' NAME ATTRIB } ['=' explist] */
  FuncState *fs = ls->fs;
  int toclose = -1;  /* to-be-closed 变量索引（如果有） */
  Vardesc *var;  /* 最后一个变量 */
  int vidx, kind;  /* 最后一个变量的索引和类型 */
  int nvars = 0;
  int nexps;
  expdesc e;
  do {
    vidx = new_localvar(ls, str_checkname(ls));
    kind = getlocalattribute(ls);
    getlocalvardesc(fs, vidx)->vd.kind = kind;
    if (kind == RDKTOCLOSE) {  /* to-be-closed？ */
      if (toclose != -1)  /* 已经有一个？ */
        luaK_semerror(ls, "multiple to-be-closed variables in local list");
      toclose = fs->nactvar + nvars;
    }
    nvars++;
  } while (testnext(ls, ','));
  if (testnext(ls, '='))
    nexps = explist(ls, &e);
  else {
    e.k = VVOID;
    nexps = 0;
  }
  var = getlocalvardesc(fs, vidx);  /* 获取最后一个变量 */
  if (nvars == nexps &&  /* 没有调整？ */
      var->vd.kind == RDKCONST &&  /* 最后一个变量是常量？ */
      luaK_exp2const(fs, &e, &var->k)) {  /* 编译期常量？ */
    var->vd.kind = RDKCTC;  /* 变量是编译期常量 */
    adjustlocalvars(ls, nvars - 1);  /* 排除最后一个变量 */
    fs->nactvar++;  /* 但计算它 */
  }
  else {
    adjust_assign(ls, nvars, nexps, &e);
    adjustlocalvars(ls, nvars);
  }
  checktoclose(fs, toclose);
}
```

**功能说明**：

#### 逻辑段 1：创建局部变量列表
- **操作内容**：循环创建局部变量，获取属性
- **数据影响**：nvars 个变量加入 actvar 数组
- **输入**：ls
- **输出**：nvars, vidx, kind

#### 逻辑段 2：分析初始化表达式
- **操作内容**：如果有 '='，分析右侧表达式列表
- **数据影响**：nexps = 表达式数量，e = 最后一个表达式
- **输入**：ls
- **输出**：nexps, e

#### 逻辑段 3：检查编译期常量
- **操作内容**：如果变量是 const 且值是编译期常量，优化为 RDKCTC
- **数据影响**：var->vd.kind = RDKCTC
- **输入**：nvars, nexps, var, e
- **输出**：无

#### 逻辑段 4：调整赋值和激活变量
- **操作内容**：调用 adjust_assign 和 adjustlocalvars
- **数据影响**：生成赋值指令，激活 nvars 个局部变量
- **输入**：nvars, nexps, e
- **输出**：无

#### 逻辑段 5：处理 to-be-closed 变量
- **操作内容**：如果有 to-be-closed 变量，生成 TBC 指令
- **数据影响**：生成 OP_TBC 指令
- **输入**：toclose
- **输出**：无

#### 函数总结
- **输入**：LexState* ls
- **输出**：无
- **调用函数**：new_localvar, getlocalattribute, explist, adjust_assign, adjustlocalvars, checktoclose

---

### funcstat()

**源码位置**：src/lparser.c:1782

**源代码**：
```c
static void funcstat (LexState *ls, int line) {
  /* funcstat -> FUNCTION funcname body */
  int ismethod;
  expdesc v, b;
  luaX_next(ls);  /* 跳过 FUNCTION */
  ismethod = funcname(ls, &v);
  body(ls, &b, ismethod, line);
  check_readonly(ls, &v);
  luaK_storevar(ls->fs, &v, &b);
  luaK_fixline(ls->fs, line);  /* 定义"发生在"第一行 */
}
```

**功能说明**：

#### 逻辑段 1：分析函数名
- **操作内容**：跳过 FUNCTION，调用 funcname 分析函数名
- **数据影响**：v = 函数名表达式，ismethod = 是否方法
- **输入**：ls
- **输出**：ismethod, v

#### 逻辑段 2：分析函数体
- **操作内容**：调用 body 分析函数体并生成闭包
- **数据影响**：b = 闭包表达式，生成 CLOSURE 指令
- **输入**：ls, ismethod, line
- **输出**：b

#### 逻辑段 3：检查只读并存储
- **操作内容**：检查目标是否只读，生成存储指令
- **数据影响**：生成 SETFIELD/SETTABUP/SETTABLE 等指令
- **输入**：v, b
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, int line
- **输出**：无
- **调用函数**：luaX_next, funcname, body, check_readonly, luaK_storevar, luaK_fixline

---

### funcname()

**源码位置**：src/lparser.c:1768

**源代码**：
```c
static int funcname (LexState *ls, expdesc *v) {
  /* funcname -> NAME {fieldsel} [':' NAME] */
  int ismethod = 0;
  singlevar(ls, v);
  while (ls->t.token == '.')
    fieldsel(ls, v);
  if (ls->t.token == ':') {
    ismethod = 1;
    fieldsel(ls, v);
  }
  return ismethod;
}
```

**功能说明**：

#### 逻辑段 1：分析基础变量名
- **操作内容**：调用 singlevar 分析第一个名称
- **数据影响**：v = 变量表达式（VLOCAL/VUPVAL/VINDEXUP）
- **输入**：ls, v
- **输出**：v

#### 逻辑段 2：处理字段选择
- **操作内容**：循环处理 '.' 连接的字段
- **数据影响**：v 变为索引类型（VINDEXSTR/VINDEXUP）
- **输入**：ls, v
- **输出**：v

#### 逻辑段 3：处理方法语法
- **操作内容**：如果有 ':'，标记为方法并处理字段
- **数据影响**：ismethod = 1
- **输入**：ls
- **输出**：ismethod

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：int ismethod（是否是方法定义）
- **调用函数**：singlevar, fieldsel

---

### body()

**源码位置**：src/lparser.c:990

**源代码**：
```c
static void body (LexState *ls, expdesc *e, int ismethod, int line) {
  /* body ->  '(' parlist ')' block END */
  FuncState new_fs;
  BlockCnt bl;
  new_fs.f = addprototype(ls);
  new_fs.f->linedefined = line;
  open_func(ls, &new_fs, &bl);
  checknext(ls, '(');
  if (ismethod) {
    new_localvarliteral(ls, "self");  /* 创建 'self' 参数 */
    adjustlocalvars(ls, 1);
  }
  parlist(ls);
  checknext(ls, ')');
  statlist(ls);
  new_fs.f->lastlinedefined = ls->linenumber;
  check_match(ls, TK_END, TK_FUNCTION, line);
  codeclosure(ls, e);
  close_func(ls);
}
```

**功能说明**：

#### 逻辑段 1：添加函数原型
- **操作内容**：在父函数的原型表中添加新原型
- **数据影响**：new_fs.f = 新原型，fs->np++
- **输入**：ls
- **输出**：new_fs.f

#### 逻辑段 2：打开新函数状态
- **操作内容**：初始化新函数的编译状态
- **数据影响**：new_fs 初始化，ls->fs 指向 new_fs
- **输入**：ls, &new_fs
- **输出**：无

#### 逻辑段 3：处理 self 参数
- **操作内容**：如果是方法，创建 self 参数
- **数据影响**：添加 "self" 局部变量
- **输入**：ls
- **输出**：无

#### 逻辑段 4：分析参数列表和函数体
- **操作内容**：分析参数列表，分析语句列表
- **数据影响**：生成函数内的字节码
- **输入**：ls
- **输出**：无

#### 逻辑段 5：生成闭包并关闭函数
- **操作内容**：生成 CLOSURE 指令，关闭函数状态
- **数据影响**：e = 闭包表达式，ls->fs 恢复到父函数
- **输入**：ls, e
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, expdesc* e, int ismethod, int line
- **输出**：无（e 被填充为闭包表达式）
- **调用函数**：addprototype, open_func, new_localvarliteral, adjustlocalvars, parlist, statlist, check_match, codeclosure, close_func

---

### parlist()

**源码位置**：src/lparser.c:959

**源代码**：
```c
static void parlist (LexState *ls) {
  /* parlist -> [ {NAME ','} (NAME | '...') ] */
  FuncState *fs = ls->fs;
  Proto *f = fs->f;
  int nparams = 0;
  int isvararg = 0;
  if (ls->t.token != ')') {  /* parlist 非空？ */
    do {
      switch (ls->t.token) {
        case TK_NAME: {
          new_localvar(ls, str_checkname(ls));
          nparams++;
          break;
        }
        case TK_DOTS: {
          luaX_next(ls);
          isvararg = 1;
          break;
        }
        default: luaX_syntaxerror(ls, "<name> or '...' expected");
      }
    } while (!isvararg && testnext(ls, ','));
  }
  adjustlocalvars(ls, nparams);
  f->numparams = cast_byte(fs->nactvar);
  if (isvararg)
    setvararg(fs, f->numparams);  /* 声明可变参数 */
  luaK_reserveregs(fs, fs->nactvar);  /* 为参数预留寄存器 */
}
```

**功能说明**：

#### 逻辑段 1：分析参数列表
- **操作内容**：循环分析 NAME 或 '...'
- **数据影响**：nparams 个局部变量，isvararg 标志
- **输入**：ls
- **输出**：nparams, isvararg

#### 逻辑段 2：激活参数变量
- **操作内容**：调用 adjustlocalvars 激活参数
- **数据影响**：fs->nactvar = nparams
- **输入**：ls, nparams
- **输出**：无

#### 逻辑段 3：设置参数数量和可变参数
- **操作内容**：设置 numparams，如果是可变参数调用 setvararg
- **数据影响**：f->numparams = nparams, 可能设置 is_vararg
- **输入**：fs, isvararg
- **输出**：无

#### 函数总结
- **输入**：LexState* ls
- **输出**：无
- **调用函数**：new_localvar, adjustlocalvars, setvararg, luaK_reserveregs

---

### retstat()

**源码位置**：src/lparser.c:1813

**源代码**：
```c
static void retstat (LexState *ls) {
  /* stat -> RETURN [explist] [';'] */
  FuncState *fs = ls->fs;
  expdesc e;
  int nret;  /* 返回的值数量 */
  int first = luaY_nvarstack(fs);  /* 第一个要返回的槽 */
  if (block_follow(ls, 1) || ls->t.token == ';')
    nret = 0;  /* 不返回值 */
  else {
    nret = explist(ls, &e);  /* 可选的返回值 */
    if (hasmultret(e.k)) {
      luaK_setmultret(fs, &e);
      if (e.k == VCALL && nret == 1 && !fs->bl->insidetbc) {  /* 尾调用？ */
        SET_OPCODE(getinstruction(fs,&e), OP_TAILCALL);
        lua_assert(GETARG_A(getinstruction(fs,&e)) == luaY_nvarstack(fs));
      }
      nret = LUA_MULTRET;  /* 返回所有值 */
    }
    else {
      if (nret == 1)  /* 只有一个单一值？ */
        first = luaK_exp2anyreg(fs, &e);  /* 可以使用原始槽 */
      else {  /* 值必须去到栈顶 */
        luaK_exp2nextreg(fs, &e);
        lua_assert(nret == fs->freereg - first);
      }
    }
  }
  luaK_ret(fs, first, nret);
  testnext(ls, ';');  /* 跳过可选的分号 */
}
```

**功能说明**：

#### 逻辑段 1：获取返回起始位置
- **操作内容**：计算第一个返回值的位置
- **数据影响**：first = luaY_nvarstack(fs)
- **输入**：fs
- **输出**：first

#### 逻辑段 2：分析返回值
- **操作内容**：如果有返回值，分析表达式列表
- **数据影响**：nret = 返回值数量，e = 最后一个表达式
- **输入**：ls
- **输出**：nret, e

#### 逻辑段 3：处理多重返回
- **操作内容**：如果是 VCALL 或 VVARARG，调用 luaK_setmultret
- **数据影响**：可能转换为 OP_TAILCALL
- **输入**：fs, e
- **输出**：nret = LUA_MULTRET

#### 逻辑段 4：处理单一返回
- **操作内容**：确保返回值在正确的寄存器
- **数据影响**：生成必要的指令
- **输入**：fs, e, nret
- **输出**：first

#### 逻辑段 5：生成 RETURN 指令
- **操作内容**：调用 luaK_ret 生成返回指令
- **数据影响**：生成 OP_RETURN 指令
- **输入**：fs, first, nret
- **输出**：无

#### 函数总结
- **输入**：LexState* ls
- **输出**：无
- **调用函数**：luaY_nvarstack, explist, luaK_setmultret, luaK_exp2anyreg, luaK_exp2nextreg, luaK_ret

---

### codeclosure()

**源码位置**：src/lparser.c:722

**源代码**：
```c
static void codeclosure (LexState *ls, expdesc *v) {
  FuncState *fs = ls->fs->prev;
  init_exp(v, VRELOC, luaK_codeABx(fs, OP_CLOSURE, 0, fs->np - 1));
  luaK_exp2nextreg(fs, v);  /* 将它固定在最后一个寄存器 */
}
```

**功能说明**：

#### 逻辑段 1：切换到父函数
- **操作内容**：获取父函数的 FuncState
- **数据影响**：fs = ls->fs->prev
- **输入**：ls
- **输出**：fs（父函数）

#### 逻辑段 2：生成 CLOSURE 指令
- **操作内容**：生成 OP_CLOSURE 指令
- **数据影响**：v->k = VRELOC, v->u.info = 指令位置
- **输入**：fs, v
- **输出**：v

#### 逻辑段 3：固定到寄存器
- **操作内容**：将闭包表达式放入下一个寄存器
- **数据影响**：v->k = VNONRELOC
- **输入**：fs, v
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：无（v 被填充为闭包表达式）
- **调用函数**：luaK_codeABx, luaK_exp2nextreg

---

## 总结

这个示例展示了 Lua 编译器如何处理典型的模块模式代码：

1. **编译器入口**：从 `luaY_parser` 开始，初始化词法分析器和语法分析器状态

2. **main 函数**：作为顶层函数，被设置为可变参数函数，创建 _ENV 上值

3. **局部变量声明**：`local _M = {}` 展示了局部变量的创建和初始化流程，包括表构造器的处理

4. **函数定义**：`function _M.main(...)` 展示了：
   - 函数名的解析（`_M.main` 索引表达式）
   - 函数原型的创建和嵌套函数状态的管理
   - 可变参数的声明和处理（OP_VARARGPREP）
   - 闭包的生成（OP_CLOSURE）

5. **函数内的局部变量**：展示了不同类型的常量初始化：
   - `nil` → LOADNIL
   - `false` → LOADFALSE
   - 整数 → LOADI
   - 字符串 → LOADK
   - 可变参数 `...` → VARARG

6. **返回语句**：`return _M` 展示了返回语句的编译，生成 RETURN 指令

整个过程中，`expdesc` 结构作为核心数据结构，通过不同的 `expkind` 类型表示表达式所处的不同阶段和状态。`FuncState` 维护了函数编译的完整状态，包括寄存器分配、常量表、上值表等。`LexState` 维护了词法分析状态和 token 流。

从游戏开发的角度看，这个过程展示了 Lua 如何高效地将脚本代码编译为字节码，使得游戏引擎可以快速加载和执行 Lua 脚本。模块模式（`local _M = {}` 后 `return _M`）是 Lua 中常用的代码组织方式，通过闭包实现私有变量和公共 API 的封装。
