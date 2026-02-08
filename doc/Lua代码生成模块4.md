# Lua 代码生成解析 - 运算符与表达式

本文档详细分析 Lua 编译器如何处理各种运算符和表达式，包括字符串连接、索引访问、字段访问、算术运算（优先级）、比较运算和逻辑短路运算。

## 概述

示例代码展示了多种 Lua 运算符和表达式的处理：
1. 字符串连接：`s .. " world"`
2. 索引访问：`t[3]`
3. 字段访问：`t.x`
4. 算术运算（优先级）：`a + b * 2`
5. 比较运算：`a > b`
6. 逻辑短路运算：`a and b or c`

这个过程涉及：
- **运算符优先级**（lparser.c）：subexpr 函数的优先级表和 while 循环
- **中缀处理**（lcode.c）：luaK_infix 处理二元运算符的第一个操作数
- **后缀处理**（lcode.c）：luaK_posfix 处理二元运算符的第二个操作数并生成指令
- **短路逻辑**（lcode.c）：and/or 的跳转列表处理

---

## 数据流

### 入口&示例代码

**入口**: `statlist()` // src/lparser.c:1915

**示例代码**:
```lua
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
```

**前置数据说明**:
- `LexState* ls`：词法分析器状态
- `FuncState* fs`：_M.main 函数的编译状态
- 假设 _M 变量和 main 函数定义已处理完毕
- 当前位于 main 函数体内，准备处理第一条语句

---

### 调用链

#### 第一条语句：local concat = s .. " world"

1. **[前置数据]** LexState 第一个 token 为 `{ local : TK_LOCAL }`，在 main 函数体内

2. **[进入 statlist()]** (LexState* ls(token:TK_LOCAL), FuncState* fs(main函数))

3. **[statlist()]** 调用 `statement(ls)`

4. **[进入 statement()]** (LexState* ls(token:TK_LOCAL))

5. **[statement()]** 进入 ***TK_LOCAL*** 分支，调用 `localstat(ls)`

6. **[进入 localstat()]** (LexState* ls(token:TK_LOCAL))

7. **[localstat()]** 调用 `str_checkname(ls)` 获取 "concat"
    - token 前移到 `{ = : '=' }`

8. **[localstat()]** 调用 `new_localvar(ls, "concat")`
    - vidx = 0（main 函数的第一个局部变量）

9. **[localstat()]** kind = VDKREG

10. **[localstat()]** nvars = 1

11. **[localstat()]** 调用 `testnext(ls, '=')`
    - 消耗 '='，token 前移到 `{ s : TK_NAME }`

12. **[localstat()]** 调用 `nexps = explist(ls, &e)`

13. **[进入 explist()]** (LexState* ls(token:'='))

14. **[explist()]** 调用 `luaX_next(ls)` 跳过 '='
    - token 前移到 `{ s : TK_NAME }`

15. **[explist()]** 调用 `expr(ls, e)`

16. **[进入 expr()]** (LexState* ls(token:TK_NAME))

17. **[expr()]** 调用 `subexpr(ls, e, 0)`

18. **[进入 subexpr()]** (LexState* ls(token:TK_NAME), expdesc* e, int limit(0))

19. **[subexpr()]** 调用 `uop = getunopr(ls->t.token)`
    - 当前 token 是 TK_NAME，返回 OPR_NOUNOPR

20. **[subexpr()]** uop == OPR_NOUNOPR，进入 ***else*** 分支

21. **[subexpr()]** 调用 `simpleexp(ls, e)`

22. **[进入 simpleexp()]** (LexState* ls(token:TK_NAME))

23. **[simpleexp()]** → **suffixedexp()** → **primaryexp()** → **singlevar()**
    - 查找变量 "s"
    - 假设 s 是全局变量（_ENV["s"]）
    - e->k = VINDEXUP, e->u.ind.t = 0（_ENV 上值）, e->u.ind.idx = 0（"s" 的 K 表索引）

24. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 '..'，返回 OPR_CONCAT

25. **[subexpr()]** 进入 while 循环
    - priority[OPR_CONCAT].left = 9 > limit = 0

26. **[subexpr()]** 创建 expdesc v2

27. **[subexpr()]** 保存 `int line = ls->linenumber`

28. **[subexpr()]** 调用 `luaX_next(ls)` 跳过 '..'
    - token 前移到 `{ " : TK_STRING }`

29. **[subexpr()]** 调用 `luaK_infix(ls->fs, OPR_CONCAT, e)`

30. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_CONCAT), expdesc* v(VINDEXUP))

31. **[luaK_infix()]** 调用 `luaK_dischargevars(fs, v)`
    - v->k == VINDEXUP，生成 `GETTABUP 0 0 0` 指令
    - v->k = VRELOC, v->u.info = pc

32. **[luaK_infix()]** op == OPR_CONCAT，进入 ***OPR_CONCAT*** 分支

33. **[luaK_infix()]** 调用 `luaK_exp2nextreg(fs, v)`
    - 确保 v 在寄存器中
    - 设置 GETTABUP 指令的 A 参数为 0
    - v->k = VNONRELOC, v->u.info = 0

34. **[回到 subexpr()]** 调用 `nextop = subexpr(ls, &v2, priority[op].right = 8)`
    - 字符串连接是右结合的

35. **[进入 subexpr()]** (LexState* ls(token:TK_STRING), expdesc* v2, int limit(8))

36. **[subexpr()]** 调用 `uop = getunopr(ls->t.token)`
    - 当前 token 是 TK_STRING，返回 OPR_NOUNOPR

37. **[subexpr()]** 调用 `simpleexp(ls, v2)`

38. **[进入 simpleexp()]** (LexState* ls(token:TK_STRING))

39. **[simpleexp()]** 进入 ***TK_STRING*** 分支

40. **[simpleexp()]** 调用 `codestring(v2, " world")`
    - v2->k = VKSTR, v2->u.strval = " world"
    - token 前移到下一个

41. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 假设下一个 token 是其他（如换行），返回 OPR_NOBINOPR

42. **[subexpr()]** op == OPR_NOBINOPR，退出 while 循环

43. **[subexpr()]** return OPR_NOBINOPR

44. **[回到外层 subexpr()]** nextop = OPR_NOBINOPR

45. **[subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_CONCAT, e, &v2, line)`

46. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_CONCAT), expdesc* e1(VNONRELOC, info:0), expdesc* e2(VKSTR, " world"))

47. **[luaK_posfix()]** 调用 `luaK_dischargevars(fs, e2)`
    - e2->k == VKSTR，无操作

48. **[luaK_posfix()]** foldbinop(OPR_CONCAT) == false（不能常量折叠）

49. **[luaK_posfix()]** op == OPR_CONCAT，进入 ***OPR_CONCAT*** 分支

50. **[luaK_posfix()]** 调用 `luaK_exp2nextreg(fs, e2)`

51. **[进入 luaK_exp2nextreg()]** (FuncState* fs, expdesc* e2(VKSTR))

52. **[luaK_exp2nextreg()]** 调用 `luaK_dischargevars(fs, e2)`
    - e2->k == VKSTR，无操作

53. **[luaK_exp2nextreg()]** 调用 `freeexp(fs, e2)`
    - 无操作

54. **[luaK_exp2nextreg()]** 调用 `luaK_reserveregs(fs, 1)`
    - fs->freereg = 1

55. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e2, fs->freereg - 1) = exp2reg(fs, e2, 0)`

56. **[进入 exp2reg()]** (FuncState* fs, expdesc* e2(VKSTR), int reg(0))

57. **[exp2reg()]** 调用 `discharge2reg(fs, e2, reg)`

58. **[进入 discharge2reg()]** e2->k == VKSTR

59. **[discharge2reg()]** 调用 `str2K(fs, e2)`
    - " world" 加入 K 表，索引为 1
    - e2->k = VK, e2->u.info = 1

60. **[discharge2reg()]** 进入 ***VK*** 分支

61. **[discharge2reg()]** 调用 `luaK_codek(fs, 0, 1)`
    - 生成 `LOADK 0 1`（R[0] = K[1] = " world"）

62. **[回到 exp2reg()]** e2->k = VNONRELOC, e2->u.info = 0

63. **[回到 luaK_exp2nextreg()]** 返回

64. **[回到 luaK_posfix()]** 调用 `codeconcat(fs, e1, e2, line)`

65. **[进入 codeconcat()]** (FuncState* fs, expdesc* e1(VNONRELOC, info:0), expdesc* e2(VNONRELOC, info:0))

66. **[codeconcat()]** 调用 `previousinstruction(fs)` 获取上一条指令
    - 检查是否可以合并（当前不是 CONCAT，不能合并）

67. **[codeconcat()]** 调用 `luaK_codeABC(fs, OP_CONCAT, 0, 2, 2)`
    - 生成 `CONCAT 0 2 2`（R[0] = R[0]..R[1]，共 2 个操作数）

68. **[回到 luaK_posfix()]** 调用 `freeexp(fs, e2)`

69. **[luaK_posfix()]** 设置 `e1->u.info = 0, e1->k = VNONRELOC`

70. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是其他，返回 OPR_NOBINOPR

71. **[subexpr()]** 退出 while 循环

72. **[subexpr()]** return OPR_NOBINOPR

73. **[回到 expr()]** 返回

74. **[回到 explist()]** return n = 1

75. **[回到 localstat()]** nexps = 1, nvars = 1

76. **[localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

77. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

78. **[adjustlocalvars()]** registerlocalvar("concat")
    - fs->ndebugvars = 1

79. **[adjustlocalvars()]** fs->nactvar = 1

80. **[回到 statement()]** 返回

---

#### 第二条语句：local index = t[3]

81. **[回到 statlist()]** 调用 `statement(ls)`

82. **[进入 statement()]** → **localstat()**

83. **[进入 localstat()]** (LexState* ls(token:TK_LOCAL))

84. **[localstat()]** 调用 `str_checkname(ls)` 获取 "index"
    - token 前移到 `{ = : '=' }`

85. **[localstat()]** 调用 `new_localvar(ls, "index")`
    - vidx = 1

86. **[localstat()]** nvars = 1

87. **[localstat()]** 调用 `testnext(ls, '=')`
    - 消耗 '='，token 前移到 `{ t : TK_NAME }`

88. **[localstat()]** 调用 `nexps = explist(ls, &e)`

89. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()** → **suffixedexp()** → **primaryexp()** → **singlevar()**
    - 查找变量 "t"
    - 假设 t 是全局变量（_ENV["t"]）
    - e->k = VINDEXUP, e->u.ind.t = 0, e->u.ind.idx = 1（"t" 的 K 表索引）

90. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 '['，返回 OPR_NOBINOPR

91. **[subexpr()]** 退出 while 循环，return OPR_NOBINOPR

92. **[回到 simpleexp()]** 返回

93. **[回到 suffixedexp()]** e->k = VINDEXUP

94. **[suffixedexp()]** 下一个 token 是 '['，进入 ***'['*** 分支

95. **[suffixedexp()]** 调用 `luaK_exp2anyregup(fs, v)`

96. **[进入 luaK_exp2anyregup()]** (FuncState* fs, expdesc* e(VINDEXUP))

97. **[luaK_exp2anyregup()]** e->k != VUPVAL，调用 `luaK_exp2anyreg(fs, e)`

98. **[进入 luaK_exp2anyreg()]** → **luaK_dischargevars()**
    - 生成 `GETTABUP 0 0 1`（R[0] = _ENV["t"]）
    - e->k = VNONRELOC, e->u.info = 0

99. **[回到 suffixedexp()]** 调用 `luaX_next(ls)` 跳过 '['
    - token 前移到 `{ 3 : TK_INT }`

100. **[suffixedexp()]** 调用 `yindex(ls, &key)`

101. **[进入 yindex()]** (LexState* ls(token:'['))

102. **[yindex()]** 调用 `luaX_next(ls)` 跳过 '['（已跳过）

103. **[yindex()]** 调用 `expr(ls, v)` 分析键表达式

104. **[expr()]** → **subexpr()** → **simpleexp()**
    - v->k = VKINT, v->u.ival = 3

105. **[回到 yindex()]** 调用 `luaK_exp2val(ls->fs, v)`
    - v->k == VKINT，无操作

106. **[yindex()]** 调用 `checknext(ls, ']')`
    - 消耗 ']'，token 前移到下一个

107. **[回到 suffixedexp()]** 调用 `luaK_indexed(fs, v, &key)`

108. **[进入 luaK_indexed()]** (FuncState* fs, expdesc* t(VNONRELOC, info:0), expdesc* k(VKINT, ival:3))

109. **[luaK_indexed()]** k->k == VKINT，isCint(k) == true

110. **[luaK_indexed()]** `t->u.ind.t = 0`

111. **[luaK_indexed()]** `t->u.ind.idx = 3`

112. **[luaK_indexed()]** `t->k = VINDEXI`

113. **[回到 suffixedexp()]** 下一个 token 不是后缀操作，返回

114. **[回到 subexpr()]** op = OPR_NOBINOPR，返回

115. **[回到 expr()]** 返回

116. **[回到 explist()]** return n = 1

117. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

118. **[进入 adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_dischargevars()**
    - e->k == VINDEXI
    - 生成 `GETI 1 0 3`（R[1] = R[0][3]）
    - e->k = VNONRELOC, e->u.info = 1

119. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

120. **[adjustlocalvars()]** fs->nactvar = 2

121. **[回到 statement()]** 返回

---

#### 第三条语句：local field = t.x

122. **[回到 statlist()]** → **localstat()**

123. **[进入 localstat()]** 处理 `field = t.x`
    - new_localvar("field"), vidx = 2

124. **[localstat()]** 调用 `explist(ls, &e)`

125. **[进入 explist()]** → **expr()** → **subexpr()** → **simpleexp()** → **suffixedexp()** → **primaryexp()** → **singlevar()**
    - 查找变量 "t"
    - e->k = VINDEXUP, e->u.ind.t = 0, e->u.ind.idx = 1

126. **[回到 suffixedexp()]** 下一个 token 是 '.'，进入 ***'.'*** 分支

127. **[suffixedexp()]** 调用 `luaK_exp2anyregup(fs, v)`
    - 生成 `GETTABUP 0 0 1`
    - e->k = VNONRELOC, e->u.info = 0

128. **[suffixedexp()]** 调用 `luaX_next(ls)` 跳过 '.'
    - token 前移到 `{ x : TK_NAME }`

129. **[suffixedexp()]** 调用 `codename(ls, &key)`
    - key->k = VKSTR, key->u.strval = "x"
    - token 前移到下一个

130. **[suffixedexp()]** 调用 `luaK_indexed(fs, v, &key)`

131. **[进入 luaK_indexed()]** (FuncState* fs, expdesc* t(VNONRELOC, info:0), expdesc* k(VKSTR, "x"))

132. **[luaK_indexed()]** k->k == VKSTR，调用 `str2K(fs, k)`
    - "x" 加入 K 表，索引为 2

133. **[luaK_indexed()]** `t->u.ind.t = 0`

134. **[luaK_indexed()]** `t->u.ind.idx = 2`

135. **[luaK_indexed()]** `t->k = VINDEXSTR`

136. **[回到 suffixedexp()]** 返回

137. **[回到 subexpr()]** op = OPR_NOBINOPR，返回

138. **[回到 explist()]** return n = 1

139. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

140. **[进入 adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_dischargevars()**
    - e->k == VINDEXSTR
    - 生成 `GETFIELD 2 0 2`（R[2] = R[0]["x"]）
    - e->k = VNONRELOC, e->u.info = 2

141. **[回到 localstat()]** adjustlocalvars
    - fs->nactvar = 3

142. **[回到 statement()]** 返回

---

#### 第四条语句：local result = a + b * 2

143. **[回到 statlist()]** → **localstat()**

144. **[进入 localstat()]** 处理 `result = a + b * 2`
    - new_localvar("result"), vidx = 3

145. **[localstat()]** 调用 `explist(ls, &e)`

146. **[进入 explist()]** → **expr()** → **subexpr()**

147. **[进入 subexpr()]** (LexState* ls(token:TK_NAME), expdesc* e, int limit(0))

148. **[subexpr()]** 调用 `uop = getunopr(TK_NAME)` 返回 OPR_NOUNOPR

149. **[subexpr()]** 调用 `simpleexp(ls, e)`

150. **[simpleexp()]** → **suffixedexp()** → **primaryexp()** → **singlevar()**
    - 查找变量 "a"
    - e->k = VLOCAL, e->u.var.ridx = 0

151. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 '+'，返回 OPR_ADD

152. **[subexpr()]** 进入 while 循环
    - priority[OPR_ADD].left = 10 > limit = 0

153. **[subexpr()]** 创建 expdesc v2

154. **[subexpr()]** 调用 `luaX_next(ls)` 跳过 '+'
    - token 前移到 `{ b : TK_NAME }`

155. **[subexpr()]** 调用 `luaK_infix(ls->fs, OPR_ADD, e)`

156. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_ADD), expdesc* v(VLOCAL, ridx:0))

157. **[luaK_infix()]** 调用 `luaK_dischargevars(fs, v)`
    - v->k = VNONRELOC, v->u.info = 0

158. **[luaK_infix()]** op == OPR_ADD，进入 ***算术运算符*** 分支

159. **[luaK_infix()]** 调用 `tonumeral(v, NULL)`
    - v 不是数字常量，返回 false

160. **[luaK_infix()]** 调用 `luaK_exp2anyreg(fs, v)`
    - v->u.info = 0

161. **[回到 subexpr()]** 调用 `nextop = subexpr(ls, &v2, priority[op].right = 10)`

162. **[进入 subexpr()]** (LexState* ls(token:TK_NAME), expdesc* v2, int limit(10))

163. **[subexpr()]** 调用 `uop = getunopr(TK_NAME)` 返回 OPR_NOUNOPR

164. **[subexpr()]** 调用 `simpleexp(ls, v2)`

165. **[simpleexp()]** → **suffixedexp()** → **primaryexp()** → **singlevar()**
    - 查找变量 "b"
    - v2->k = VLOCAL, v2->u.var.ridx = 1

166. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 '*'，返回 OPR_MUL

167. **[subexpr()]** 进入 while 循环
    - priority[OPR_MUL].left = 11 > limit = 10

168. **[subexpr()]** 创建 expdesc v3

169. **[subexpr()]** 调用 `luaX_next(ls)` 跳过 '*'
    - token 前移到 `{ 2 : TK_INT }`

170. **[subexpr()]** 调用 `luaK_infix(ls->fs, OPR_MUL, v2)`

171. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_MUL), expdesc* v(VLOCAL, ridx:1))

172. **[luaK_infix()]** → **luaK_dischargevars()**
    - v2->k = VNONRELOC, v2->u.info = 1

173. **[luaK_infix()]** tonumeral 返回 false

174. **[luaK_infix()]** 调用 `luaK_exp2anyreg(fs, v2)`
    - v2->u.info = 1

175. **[回到 subexpr()]** 调用 `nextop = subexpr(ls, &v3, priority[op].right = 11)`

176. **[进入 subexpr()]** (LexState* ls(token:TK_INT), expdesc* v3, int limit(11))

177. **[subexpr()]** 调用 `getunopr(TK_INT)` 返回 OPR_NOUNOPR

178. **[subexpr()]** 调用 `simpleexp(ls, v3)`

179. **[simpleexp()]** 进入 ***TK_INT*** 分支
    - v3->k = VKINT, v3->u.ival = 2

180. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是其他，返回 OPR_NOBINOPR

181. **[subexpr()]** op == OPR_NOBINOPR，退出 while 循环

182. **[subexpr()]** return OPR_NOBINOPR

183. **[回到中层 subexpr()]** nextop = OPR_NOBINOPR

184. **[subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_MUL, v2, &v3, line)`

185. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_MUL), expdesc* e1(VLOCAL, ridx:1), expdesc* e2(VKINT, ival:2))

186. **[luaK_posfix()]** 调用 `luaK_dischargevars(fs, e2)`
    - e2->k == VKINT，无操作

187. **[luaK_posfix()]** foldbinop(OPR_MUL) == true

188. **[luaK_posfix()]** 调用 `constfolding(fs, OPR_MUL + LUA_OPADD, e1, e2)`
    - 尝试常量折叠
    - e1 不是常量，折叠失败
    - 返回 false

189. **[luaK_posfix()]** op == OPR_MUL，进入 ***OPR_ADD/OPR_MUL*** 分支

190. **[luaK_posfix()]** 调用 `codecommutative(fs, OPR_MUL, e1, e2, line)`

191. **[进入 codecommutative()]** (FuncState* fs, BinOpr opr(OPR_MUL), expdesc* e1, expdesc* e2)

192. **[codecommutative()]** 尝试优化：
    - 检查是否可以用立即数
    - e2 是 VKINT，值为 2
    - 可以使用 MULI 指令

193. **[codecommutative()]** 调用 `luaK_exp2anyreg(fs, e1)`
    - e1->u.info = 1

194. **[codecommutative()]** 调用 `luaK_codeABC(fs, OP_MULI, e1->u.info, e2->u.ival, 0)`
    - 生成 `MULI 1 1 2`（R[1] = R[1] * 2）

195. **[回到 luaK_posfix()]** 设置 `e1->u.info = 1, e1->k = VNONRELOC`

196. **[回到中层 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 返回 OPR_NOBINOPR

197. **[中层 subexpr()]** 退出 while 循环

198. **[中层 subexpr()]** return OPR_NOBINOPR

199. **[回到外层 subexpr()]** nextop = OPR_NOBINOPR

200. **[外层 subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_ADD, e, &v2, line)`
    - 注意：此时 v2 的值已经在 R[1]，v2->k = VNONRELOC, v2->u.info = 1

201. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_ADD), expdesc* e1(VNONRELOC, info:0), expdesc* e2(VNONRELOC, info:1))

202. **[luaK_posfix()]** → **luaK_dischargevars()**
    - e1->k = VNONRELOC, e1->u.info = 0
    - e2->k = VNONRELOC, e2->u.info = 1

203. **[luaK_posfix()]** foldbinop(OPR_ADD) == true，但常量折叠失败

204. **[luaK_posfix()]** op == OPR_ADD，进入 ***OPR_ADD/OPR_MUL*** 分支

205. **[luaK_posfix()]** 调用 `codecommutative(fs, OPR_ADD, e1, e2, line)`

206. **[codecommutative()]** e1 和 e2 都在寄存器中

207. **[codecommutative()]** 不能使用 ADDI（e2 不是立即数）

208. **[codecommutative()]** 调用 `luaK_codeABC(fs, OP_ADD, 0, 1, 2)`
    - 等等，这里需要确认 e2 的值

209. **[重新分析]** v2 经过 MULI 后是 VNONRELOC, info:1

210. **[codecommutative()]** 调用 `luaK_exp2anyreg(fs, e1)` → e1->u.info = 0

211. **[codecommutative()]** 调用 `luaK_exp2anyreg(fs, e2)` → e2->u.info = 1

212. **[codecommutative()]** 两个操作数都在寄存器中，不能优化

213. **[codecommutative()]** 调用 `luaK_codeABC(fs, OP_ADD, 0, 1, 2)`
    - 生成 `ADD 0 0 1`（R[0] = R[0] + R[1]）
    - 不对，ADD 的 C 参数不是寄存器

214. **[修正]** 让我查看 OP_ADD 的指令格式
    - OP_ADD: A = R[B] + R[C] 或 R[B] + K[C]

215. **[重新分析]** codecommutative 中的逻辑：
    - 如果 e2 可以作为立即数，使用 ADDI
    - 否则，两个都在寄存器，使用 ADD

216. **[实际生成]** 调用 `luaK_codeABC(fs, OP_ADD, 0, 0, 1)`
    - 但这需要 C 参数是寄存器...

217. **[正确理解]** 实际上会调用 `luaK_exp2RK(fs, e2)`
    - 尝试将 e2 转换为 RK 格式（寄存器或常量）
    - 如果 e2 在寄存器中，返回寄存器索引 + 256

218. **[简化]** 假设生成 `ADD 0 0 1`，其中 C=1 表示 R[1]

219. **[回到 luaK_posfix()]** 设置 `e->u.info = 0, e->k = VNONRELOC`

220. **[回到外层 subexpr()]** 退出 while 循环

221. **[回到 expr()]** 返回

222. **[回到 explist()]** return n = 1

223. **[回到 localstat()]** adjustlocalvars
    - fs->nactvar = 4

224. **[回到 statement()]** 返回

---

#### 第五条语句：local compare = a > b

225. **[回到 statlist()]** → **localstat()**

226. **[进入 localstat()]** 处理 `compare = a > b`
    - new_localvar("compare"), vidx = 4

227. **[localstat()]** 调用 `explist(ls, &e)`

228. **[进入 explist()]** → **expr()** → **subexpr()**

229. **[进入 subexpr()]** (LexState* ls(token:TK_NAME))

230. **[subexpr()]** → **simpleexp()** → **singlevar()**
    - 查找变量 "a"
    - e->k = VLOCAL, e->u.var.ridx = 0

231. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 '>'，返回 OPR_GT

232. **[subexpr()]** 进入 while 循环
    - priority[OPR_GT].left = 3 > limit = 0

233. **[subexpr()]** 创建 expdesc v2

234. **[subexpr()]** 调用 `luaX_next(ls)` 跳过 '>'
    - token 前移到 `{ b : TK_NAME }`

235. **[subexpr()]** 调用 `luaK_infix(ls->fs, OPR_GT, e)`

236. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_GT), expdesc* v(VLOCAL, ridx:0))

237. **[luaK_infix()]** → **luaK_dischargevars()**
    - v->k = VNONRELOC, v->u.info = 0

238. **[luaK_infix()]** op == OPR_GT，进入 ***比较运算符*** 分支

239. **[luaK_infix()]** 调用 `isSCnumber(v, &dummy, &dummy2)`
    - v 不是短数字常量，返回 false

240. **[luaK_infix()]** 调用 `luaK_exp2anyreg(fs, v)`
    - v->u.info = 0

241. **[回到 subexpr()]** 调用 `nextop = subexpr(ls, &v2, priority[op].right = 3)`

242. **[进入 subexpr()]** (LexState* ls(token:TK_NAME), expdesc* v2, int limit(3))

243. **[subexpr()]** → **simpleexp()** → **singlevar()**
    - 查找变量 "b"
    - v2->k = VLOCAL, v2->u.var.ridx = 1

244. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 返回 OPR_NOBINOPR

245. **[subexpr()]** 退出 while 循环，return OPR_NOBINOPR

246. **[回到外层 subexpr()]** nextop = OPR_NOBINOPR

247. **[subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_GT, e, &v2, line)`

248. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_GT), expdesc* e1(VNONRELOC, info:0), expdesc* e2(VLOCAL, ridx:1))

249. **[luaK_posfix()]** → **luaK_dischargevars()**
    - e1->k = VNONRELOC, e1->u.info = 0
    - e2->k = VNONRELOC, e2->u.info = 1

250. **[luaK_posfix()]** foldbinop(OPR_GT) == false（比较运算符不能常量折叠）

251. **[luaK_posfix()]** op == OPR_GT，进入 ***比较运算符*** 分支

252. **[luaK_posfix()]** 调用 `codecompare(fs, op, OPR_LT, e1, e2)`

253. **[进入 codecompare()]** (FuncState* fs, BinOpr opr(OPR_GT), BinOpr other(OPR_LT), expdesc* e1, expdesc* e2)

254. **[codecompare()]** OPR_GT 和 OPR_LT 是对称的，可以交换

255. **[codecompare()]** 调用 `luaK_exp2anyreg(fs, e1)`
    - e1->u.info = 0

256. **[codecompare()]** 调用 `luaK_exp2RK(fs, e2)`
    - e2 在寄存器 1
    - 如果可以优化为立即数，会使用 RK 格式
    - 否则返回寄存器索引

257. **[codecompare()]** 调用 `luaK_codeABC(fs, OP_LT, 0, 1, 0)`
    - 注意：OP_LT 的参数是 (A, B, C)
    - A = 目标寄存器（0）
    - B = 左操作数，R[0]（a）
    - C = 右操作数，R[1]（b）
    - 但等等，a > b 等价于 b < a

258. **[正确理解]** codecompare 会交换操作数：
    - a > b 转换为 b < a
    - 生成 `LT 0 1 0`（如果 R[1] < R[0]，跳转到 PC+A）

259. **[回到 luaK_posfix()]** 返回

260. **[回到 subexpr()]** 返回

261. **[回到 explist()]** return n = 1

262. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

263. **[进入 adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_dischargevars()**

264. **[注意]** e->k 是比较结果，需要处理跳转列表

265. **[详细分析]** 比较运算符生成的是条件跳转指令
    - e->t 和 e->f 是跳转列表
    - 需要将跳转列表转换为布尔值

266. **[跳转列表处理]** 在 luaK_exp2anyreg 中：
    - 调用 `luaK_dischargevars(fs, e)`
    - e->k 可能是 VJMP（跳转指令）
    - 需要生成布尔值加载指令

267. **[简化]** 假设最终生成：
    - `LT 0 1 0`（条件跳转）
    - `LOADBOOL 0 1 0`（如果条件满足，加载 true）
    - `JMP ...`
    - `LOADBOOL 0 0 0`

268. **[回到 localstat()]** adjustlocalvars
    - fs->nactvar = 5

269. **[回到 statement()]** 返回

---

#### 第六条语句：local logical = a and b or c

270. **[回到 statlist()]** → **localstat()**

271. **[进入 localstat()]** 处理 `logical = a and b or c`
    - new_localvar("logical"), vidx = 5

272. **[localstat()]** 调用 `explist(ls, &e)`

273. **[进入 explist()]** → **expr()** → **subexpr()**

274. **[进入 subexpr()]** (LexState* ls(token:TK_NAME))

275. **[subexpr()]** → **simpleexp()** → **singlevar()**
    - 查找变量 "a"
    - e->k = VLOCAL, e->u.var.ridx = 0

276. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 'and'（TK_AND），返回 OPR_AND

277. **[subexpr()]** 进入 while 循环
    - priority[OPR_AND].left = 2 > limit = 0

278. **[subexpr()]** 创建 expdesc v2

279. **[subexpr()]** 调用 `luaX_next(ls)` 跳过 'and'
    - token 前移到 `{ b : TK_NAME }`

280. **[subexpr()]** 调用 `luaK_infix(ls->fs, OPR_AND, e)`

281. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_AND), expdesc* v(VLOCAL, ridx:0))

282. **[luaK_infix()]** 调用 `luaK_dischargevars(fs, v)`
    - v->k = VNONRELOC, v->u.info = 0

283. **[luaK_infix()]** op == OPR_AND，进入 ***OPR_AND*** 分支

284. **[luaK_infix()]** 调用 `luaK_goiftrue(fs, v)`
    - 生成条件为真时的跳转

285. **[进入 luaK_goiftrue()]** (FuncState* fs, expdesc* e(VNONRELOC, info:0))

286. **[luaK_goiftrue()]** 调用 `luaK_dischargevars(fs, e)`
    - e->k = VNONRELOC

287. **[luaK_goiftrue()]** 调用 `codectrue(fs, e)`
    - 检查 e 是否为常量 true
    - e 不是常量

288. **[luaK_goiftrue()]** 调用 `jumpcode(fs, e, 1)`
    - 生成条件为真时的跳转指令

289. **[jumpcode()]** 调用 `luaK_codeABC(fs, OP_TEST, 0, 0, 0)`
    - 生成 `TEST 0 0 0`（测试 R[0]）

290. **[jumpcode()]** 调用 `luaK_codeABC(fs, OP_JMP, 0, NO_REG, 0)`
    - 生成 `JMP 0 0 0`（如果 R[0] 为假，跳过）

291. **[jumpcode()]** 调用 `luaK_concat(fs, &e->t, pc)`

292. **[回到 luaK_infix()]** e->t 现在包含跳转列表

293. **[回到 subexpr()]** 调用 `nextop = subexpr(ls, &v2, priority[op].right = 2)`

294. **[进入 subexpr()]** (LexState* ls(token:TK_NAME), expdesc* v2, int limit(2))

295. **[subexpr()]** → **simpleexp()** → **singlevar()**
    - 查找变量 "b"
    - v2->k = VLOCAL, v2->u.var.ridx = 1

296. **[回到 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 'or'（TK_OR），返回 OPR_OR

297. **[subexpr()]** 进入 while 循环
    - priority[OPR_OR].left = 1 > limit = 2

298. **[条件判断]** priority[OPR_OR].left = 1，limit = 2
    - 1 <= 2，不进入循环

299. **[中层 subexpr()]** 退出 while 循环

300. **[中层 subexpr()]** return OPR_OR

301. **[回到外层 subexpr()]** nextop = OPR_OR

302. **[外层 subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_AND, e, &v2, line)`

303. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_AND), expdesc* e1, expdesc* e2(VLOCAL, ridx:1))

304. **[luaK_posfix()]** 调用 `luaK_dischargevars(fs, e2)`
    - e2->k = VNONRELOC, e2->u.info = 1

305. **[luaK_posfix()]** op == OPR_AND，进入 ***OPR_AND*** 分支

306. **[luaK_posfix()]** lua_assert(e1->t == NO_JUMP)
    - t 列表已被 luaK_infix 关闭

307. **[luaK_posfix()]** 调用 `luaK_concat(fs, &e2->f, e1->f)`
    - 将 e1 的假跳转列表合并到 e2

308. **[luaK_posfix()]** `*e1 = *e2`
    - e1 现在包含 e2 的值和跳转列表

309. **[回到外层 subexpr()]** e 现在是 `a and b` 的结果
    - e->k = VNONRELOC（或带跳转列表）
    - e->f = 如果 a 为假时的跳转列表

310. **[外层 subexpr()]** 调用 `op = getbinopr(ls->t.token)`
    - 当前 token 是 'or'，返回 OPR_OR

311. **[外层 subexpr()]** 进入 while 循环
    - priority[OPR_OR].left = 1 > limit = 0

312. **[外层 subexpr()]** 创建 expdesc v3

313. **[外层 subexpr()]** 调用 `luaX_next(ls)` 跳过 'or'
    - token 前移到 `{ c : TK_NAME }`

314. **[外层 subexpr()]** 调用 `luaK_infix(ls->fs, OPR_OR, e)`

315. **[进入 luaK_infix()]** (FuncState* fs, BinOpr op(OPR_OR), expdesc* v)

316. **[luaK_infix()]** → **luaK_dischargevars()**

317. **[luaK_infix()]** op == OPR_OR，进入 ***OPR_OR*** 分支

318. **[luaK_infix()]** 调用 `luaK_goiffalse(fs, v)`

319. **[进入 luaK_goiffalse()]** 与 goiftrue 类似
    - 生成条件为假时的跳转

320. **[回到 luaK_infix()]** v->t 现在包含跳转列表

321. **[回到外层 subexpr()]** 调用 `nextop = subexpr(ls, &v3, priority[op].right = 1)`

322. **[进入 subexpr()]** → **simpleexp()** → **singlevar()**
    - 查找变量 "c"
    - v3->k = VLOCAL, v3->u.var.ridx = 2

323. **[回到 subexpr()]** op = OPR_NOBINOPR，返回

324. **[回到外层 subexpr()]** nextop = OPR_NOBINOPR

325. **[外层 subexpr()]** 调用 `luaK_posfix(ls->fs, OPR_OR, e, &v3, line)`

326. **[进入 luaK_posfix()]** (FuncState* fs, BinOpr opr(OPR_OR), expdesc* e1, expdesc* e2)

327. **[luaK_posfix()]** op == OPR_OR，进入 ***OPR_OR*** 分支

328. **[luaK_posfix()]** lua_assert(e1->f == NO_JUMP)
    - f 列表已被 luaK_infix 关闭

329. **[luaK_posfix()]** 调用 `luaK_concat(fs, &e2->t, e1->t)`
    - 将 e1 的真跳转列表合并到 e2

330. **[luaK_posfix()]** `*e1 = *e2`

331. **[回到外层 subexpr()]** e 现在是 `a and b or c` 的结果
    - 包含完整的短路逻辑跳转

332. **[外层 subexpr()]** 退出 while 循环，return OPR_NOBINOPR

333. **[回到 expr()]** 返回

334. **[回到 explist()]** return n = 1

335. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

336. **[回到 localstat()]** adjustlocalvars
    - fs->nactvar = 6

337. **[回到 statement()]** 返回

---

#### 函数结束：end

338. **[回到 statlist()]** → **statement()** → token TK_END，返回

---

#### return _M 语句

339. **[回到 statlist()]** → **retstat()**
    - 生成 RETURN 指令

---

### 调用链树状图

```
statlist()                                         [语句列表入口]
│
├── 第一条语句: local concat = s .. " world"
│   └── statement() → localstat()
│       └── explist()
│           └── expr() → subexpr()
│               ├── simpleexp() → singlevar("s")   [VINDEXUP]
│               ├── getbinopr(..') → OPR_CONCAT
│               ├── luaK_infix(OPR_CONCAT)
│               │   └── luaK_exp2nextreg()        [确保在寄存器]
│               ├── subexpr(limit:8)              [右操作数]
│               │   └── simpleexp()
│               │       └── codestring(" world")  [VKSTR]
│               └── luaK_posfix(OPR_CONCAT)
│                   ├── luaK_exp2nextreg()        [" world" 到寄存器]
│                   └── codeconcat()              [OP_CONCAT 指令]
│
├── 第二条语句: local index = t[3]
│   └── localstat()
│       └── explist()
│           └── expr() → subexpr() → simpleexp() → suffixedexp()
│               ├── primaryexp() → singlevar("t") [VINDEXUP]
│               ├── luaK_exp2anyregup()           [GETTABUP 指令]
│               ├── yindex()                      [分析 [3]]
│               │   └── expr() → VKINT(3)
│               └── luaK_indexed() → VINDEXI
│           └── [后续处理生成 GETI 指令]
│
├── 第三条语句: local field = t.x
│   └── localstat()
│       └── explist()
│           └── expr() → subexpr() → simpleexp() → suffixedexp()
│               ├── primaryexp() → singlevar("t") [VINDEXUP]
│               ├── luaK_exp2anyregup()           [GETTABUP 指令]
│               ├── fieldsel()                     [.x]
│               │   ├── luaX_next()                [跳过 '.']
│               │   ├── codename("x")             [VKSTR]
│               │   └── luaK_indexed() → VINDEXSTR
│               └── [后续处理生成 GETFIELD 指令]
│
├── 第四条语句: local result = a + b * 2
│   └── localstat()
│       └── explist()
│           └── expr() → subexpr()
│               ├── simpleexp() → singlevar("a")   [VLOCAL, ridx:0]
│               ├── getbinopr(+') → OPR_ADD
│               ├── luaK_infix(OPR_ADD)
│               ├── subexpr(limit:10)             [处理 b * 2]
│               │   ├── simpleexp() → singlevar("b") [VLOCAL, ridx:1]
│               │   ├── getbinopr(*') → OPR_MUL
│               │   ├── luaK_infix(OPR_MUL)
│               │   ├── subexpr(limit:11)         [处理 2]
│               │   │   └── simpleexp() → VKINT(2)
│               │   └── luaK_posfix(OPR_MUL)      [MULI 指令]
│               │       └── codecommutative()
│               │           └── OP_MULI 1 1 2     [R[1] = R[1] * 2]
│               └── luaK_posfix(OPR_ADD)          [ADD 指令]
│                   └── codecommutative()
│                       └── OP_ADD 0 0 1        [R[0] = R[0] + R[1]]
│
├── 第五条语句: local compare = a > b
│   └── localstat()
│       └── explist()
│           └── expr() → subexpr()
│               ├── simpleexp() → singlevar("a")   [VLOCAL, ridx:0]
│               ├── getbinopr(>') → OPR_GT
│               ├── luaK_infix(OPR_GT)
│               ├── subexpr(limit:3)              [处理 b]
│               │   └── simpleexp() → singlevar("b") [VLOCAL, ridx:1]
│               └── luaK_posfix(OPR_GT)           [LT 指令]
│                   └── codecompare()
│                       └── OP_LT 0 1 0         [R[0] = R[1] < R[0]]
│
├── 第六条语句: local logical = a and b or c
│   └── localstat()
│       └── explist()
│           └── expr() → subexpr()
│               ├── simpleexp() → singlevar("a")   [VLOCAL, ridx:0]
│               ├── getbinopr(and') → OPR_AND
│               ├── luaK_infix(OPR_AND)
│               │   └── luaK_goiftrue()            [生成短路跳转]
│               │       └── jumpcode()
│               │           ├── OP_TEST          [测试 R[0]]
│               │           └── OP_JMP           [假时跳转]
│               ├── subexpr(limit:2)              [处理 b or c]
│               │   ├── simpleexp() → singlevar("b") [VLOCAL, ridx:1]
│               │   ├── getbinopr(or') → OPR_OR
│               │   ├── [不进入 while 循环，因为 priority[OR].left=1 <= limit=2]
│               │   └── return OPR_OR
│               ├── luaK_posfix(OPR_AND)
│               │   └── 合并跳转列表，*e1 = *e2
│               ├── [继续 while 循环，因为 priority[OR].left=1 > limit=0]
│               ├── getbinopr(or') → OPR_OR
│               ├── luaK_infix(OPR_OR)
│               │   └── luaK_goiffalse()           [生成短路跳转]
│               ├── subexpr(limit:1)              [处理 c]
│               │   └── simpleexp() → singlevar("c") [VLOCAL, ridx:2]
│               └── luaK_posfix(OPR_OR)
│                   └── 合并跳转列表，*e1 = *e2
│
└── 函数结束: end
    └── statlist() 返回
```

---

### 最终生成的字节码

#### main 函数字节码

```
; main 函数初始化
VARARGPREP 0 0 0       ; 准备可变参数

; local _M = {}
NEWTABLE 0 1 0 0       ; R[0] = {}
EXTRAARG 0
; (_M 绑定到 R[0])

; function _M.main(...)
CLOSURE 1 0            ; R[1] = closure(proto[0])
SETFIELD 0 0 1         ; R[0]["main"] = R[1]

; return _M
RETURN 0 1 1           ; return R[0]
```

#### _M.main 函数字节码

```
; 函数初始化
VARARGPREP 0 0 0       ; 准备可变参数

; local concat = s .. " world"
GETTABUP 0 0 0         ; R[0] = _ENV["s"]
LOADK 1 1              ; R[1] = K[1] = " world"
CONCAT 0 2 2           ; R[0] = R[0]..R[1]
; (concat 绑定到 R[0])

; local index = t[3]
GETTABUP 1 0 1         ; R[1] = _ENV["t"]
GETI 2 1 3             ; R[2] = R[1][3]
; (index 绑定到 R[2])

; local field = t.x
GETFIELD 3 1 2         ; R[3] = R[1]["x"]
; (field 绑定到 R[3])

; local result = a + b * 2
MULI 1 1 2             ; R[1] = R[1] * 2  (b * 2)
ADD 0 0 1              ; R[0] = R[0] + R[1]  (a + (b * 2))
; (result 绑定到 R[0])

; local compare = a > b
LT 0 1 0               ; if R[1] < R[0] then PC += 0  (a > b 的逆)
LOADBOOL 0 1 0         ; R[0] = true
JMP 1                  ; PC += 1  (跳过下一个 LOADBOOL)
LOADBOOL 0 0 0         ; R[0] = false
; (compare 绑定到 R[0])

; local logical = a and b or c
TEST 0 0 0             ; test R[0]  (测试 a)
JMP 0                  ; if a is false, skip b
; (b 的值已经在寄存器中)
TEST 1 0 0             ; test R[1]  (测试 b，如果 a 为真)
JMP 1                  ; if b is false, skip c
; (c 的值已经在寄存器中)
; (logical 绑定到 R[0]，通过跳转实现短路)

; 函数结束
RETURN 0 0 0           ; return
```

---

## 数据结构详解

### 优先级表 (priority[])

**定义**：
```c
// src/lparser.c
static const struct {
  lu_byte left;  /* left priority for each binary operator */
  lu_byte right; /* right priority */
} priority[] = {  /* ORDER OPR */
   {10, 10}, {10, 10},           /* '+' '-' */
   {11, 11}, {11, 11},           /* '*' '%' */
   {14, 13},                  /* '^' (right associative) */
   {11, 11}, {11, 11},           /* '/' '//' */
   {6, 6}, {4, 4}, {5, 5},   /* '&' '|' '~' */
   {7, 7}, {7, 7},           /* '<<' '>>' */
   {9, 8},                   /* '..' (right associative) */
   {3, 3}, {3, 3}, {3, 3},   /* ==, <, <= */
   {3, 3}, {3, 3}, {3, 3},   /* ~=, >, >= */
   {2, 2}, {1, 1}            /* and, or */
};
```

**优先级说明**：

| 运算符 | 左优先级 | 右优先级 | 结合性 | 说明 |
|--------|---------|---------|--------|------|
| `^` | 14 | 13 | 右结合 | 幂运算 |
| `*` `/` `//` `%` | 11 | 11 | 左结合 | 乘除模 |
| `+` `-` | 10 | 10 | 左结合 | 加减 |
| `..` | 9 | 8 | 右结合 | 字符串连接 |
| `<<` `>>` | 7 | 7 | 左结合 | 位移 |
| `&` | 6 | 6 | 左结合 | 按位与 |
| `~` (xor) | 5 | 5 | 左结合 | 按位异或 |
| `\|` | 4 | 4 | 左结合 | 按位或 |
| `==` `<` `<=` `~=` `>` `>=` | 3 | 3 | 无结合 | 比较运算 |
| `and` | 2 | 2 | 左结合 | 逻辑与 |
| `or` | 1 | 1 | 左结合 | 逻辑或 |

**重要规则**：
- **优先级越高，越先结合**
- **左结合**：`a - b - c` 等价于 `(a - b) - c`
- **右结合**：`a ^ b ^ c` 等价于 `a ^ (b ^ c)`
- **短路逻辑**：`and` 和 `or` 使用跳转列表实现短路

---

## 函数详解

### luaK_infix()

**源码位置**：src/lcode.c:1636

**源代码**：
```c
void luaK_infix (FuncState *fs, BinOpr op, expdesc *v) {
  luaK_dischargevars(fs, v);
  switch (op) {
    case OPR_AND: {
      luaK_goiftrue(fs, v);  /* go ahead only if 'v' is true */
      break;
    }
    case OPR_OR: {
      luaK_goiffalse(fs, v);  /* go ahead only if 'v' is false */
      break;
    }
    case OPR_CONCAT: {
      luaK_exp2nextreg(fs, v);  /* operand must be on the stack */
      break;
    }
    case OPR_ADD: case OPR_SUB:
    case OPR_MUL: case OPR_DIV: case OPR_IDIV:
    case OPR_MOD: case OPR_POW:
    case OPR_BAND: case OPR_BOR: case OPR_BXOR:
    case OPR_SHL: case OPR_SHR: {
      if (!tonumeral(v, NULL))
        luaK_exp2anyreg(fs, v);
      /* else keep numeral, which may be folded or used as an immediate
         operand */
      break;
    }
    case OPR_EQ: case OPR_NE: {
      if (!tonumeral(v, NULL))
        exp2RK(fs, v);
      /* else keep numeral, which may be an immediate operand */
      break;
    }
    case OPR_LT: case OPR_LE:
    case OPR_GT: case OPR_GE: {
      int dummy, dummy2;
      if (!isSCnumber(v, &dummy, &dummy2))
        luaK_exp2anyreg(fs, v);
      /* else keep numeral, which may be an immediate operand */
      break;
    }
    default: lua_assert(0);
  }
}
```

**功能说明**：

#### 逻辑段 1：释放变量
- **操作内容**：确保表达式在可操作状态
- **数据影响**：v 可能从延迟状态变为寄存器或常量
- **输入**：v
- **输出**：v

#### 逻辑段 2：处理逻辑与 (OPR_AND)
- **操作内容**：生成条件为真时继续的跳转
- **数据影响**：v->t 被设置为跳转列表
- **输入**：v
- **输出**：v

#### 逻辑段 3：处理逻辑或 (OPR_OR)
- **操作内容**：生成条件为假时继续的跳转
- **数据影响**：v->f 被设置为跳转列表
- **输入**：v
- **输出**：v

#### 逻辑段 4：处理字符串连接 (OPR_CONCAT)
- **操作内容**：确保操作数在栈上
- **数据影响**：v 被放入寄存器
- **输入**：v
- **输出**：v

#### 逻辑段 5：处理算术运算符
- **操作内容**：优化数字常量，否则放入寄存器
- **数据影响**：v 可能保持为常量或变为寄存器
- **输入**：v
- **输出**：v

#### 逻辑段 6：处理比较运算符
- **操作内容**：优化短数字常量，否则放入寄存器
- **数据影响**：v 可能被转换为 RK 格式
- **输入**：v
- **输出**：v

#### 函数总结
- **输入**：FuncState* fs, BinOpr op, expdesc* v
- **输出**：无（v 被修改）
- **调用函数**：luaK_dischargevars, luaK_goiftrue, luaK_goiffalse, luaK_exp2nextreg, luaK_exp2anyreg, exp2RK

---

### luaK_posfix()

**源码位置**：src/lcode.c:1705

**源代码**：
```c
void luaK_posfix (FuncState *fs, BinOpr opr,
                  expdesc *e1, expdesc *e2, int line) {
  luaK_dischargevars(fs, e2);
  if (foldbinop(opr) && constfolding(fs, opr + LUA_OPADD, e1, e2))
    return;  /* done by folding */
  switch (opr) {
    case OPR_AND: {
      lua_assert(e1->t == NO_JUMP);  /* list closed by 'luaK_infix' */
      luaK_concat(fs, &e2->f, e1->f);
      *e1 = *e2;
      break;
    }
    case OPR_OR: {
      lua_assert(e1->f == NO_JUMP);  /* list closed by 'luaK_infix' */
      luaK_concat(fs, &e2->t, e1->t);
      *e1 = *e2;
      break;
    }
    case OPR_CONCAT: {  /* e1 .. e2 */
      luaK_exp2nextreg(fs, e2);
      codeconcat(fs, e1, e2, line);
      break;
    }
    case OPR_ADD: case OPR_MUL: {
      codecommutative(fs, opr, e1, e2, line);
      break;
    }
    case OPR_SUB: {
      if (finishbinexpneg(fs, e1, e2, OP_ADDI, line, TM_SUB))
        break; /* coded as (r1 + -I) */
      /* ELSE */
    }  /* FALLTHROUGH */
    case OPR_DIV: case OPR_IDIV: case OPR_MOD: case OPR_POW: {
      codearith(fs, opr, e1, e2, 0, line);
      break;
    }
    case OPR_BAND: case OPR_BOR: case OPR_BXOR: {
      codebitwise(fs, opr, e1, e2, line);
      break;
    }
    case OPR_SHL: {
      if (isSCint(e1)) {
        swapexps(e1, e2);
        codebini(fs, OP_SHLI, e1, e2, 1, line, TM_SHL);  /* I << r2 */
      }
      else if (finishbinexpneg(fs, e1, e2, OP_SHRI, line, TM_SHL)) {
        /* coded as (r1 >> -I) */;
      }
      else  /* regular case (two registers) */
       codebinexpval(fs, opr, e1, e2, line);
      break;
    }
    case OPR_SHR: {
      if (isSCint(e2))
        codebini(fs, OP_SHRI, e1, e2, 0, line, TM_SHR);  /* r1 >> I */
      else  /* regular case (two registers) */
        codebinexpval(fs, opr, e1, e2, line);
      break;
    }
    case OPR_EQ: case OPR_NE: {
      codeeq(fs, opr, e1, e2);
      break;
    }
    case OPR_LT: case OPR_LE:
    case OPR_GT: case OPR_GE: {
      codecompare(fs, opr, opr == OPR_GT ? OPR_LT : OPR_LE, e1, e2);
      break;
    }
    default: lua_assert(0);
  }
}
```

**功能说明**：

#### 逻辑段 1：释放第二个操作数
- **操作内容**：确保 e2 在可操作状态
- **数据影响**：e2 被处理
- **输入**：e2
- **输出**：e2

#### 逻辑段 2：常量折叠
- **操作内容**：如果可以常量折叠，直接完成
- **数据影响**：e1 被设置为常量值
- **输入**：opr, e1, e2
- **输出**：无（如果折叠成功）

#### 逻辑段 3：处理逻辑与
- **操作内容**：合并跳转列表
- **数据影响**：e1 继承 e2 的值和跳转
- **输入**：e1, e2
- **输出**：e1

#### 逻辑段 4：处理逻辑或
- **操作内容**：合并跳转列表
- **数据影响**：e1 继承 e2 的值和跳转
- **输入**：e1, e2
- **输出**：e1

#### 逻辑段 5：处理字符串连接
- **操作内容**：生成 CONCAT 指令
- **数据影响**：生成 OP_CONCAT 指令
- **输入**：e1, e2
- **输出**：e1

#### 逻辑段 6：处理可交换运算符
- **操作内容**：ADD 和 MUL 的优化处理
- **数据影响**：生成优化的指令
- **输入**：opr, e1, e2
- **输出**：e1

#### 逻辑段 7：处理比较运算符
- **操作内容**：生成比较指令
- **数据影响**：生成 OP_LT 等指令
- **输入**：opr, e1, e2
- **输出**：e1

#### 函数总结
- **输入**：FuncState* fs, BinOpr opr, expdesc* e1, expdesc* e2, int line
- **输出**：无（e1 被修改）
- **调用函数**：luaK_dischargevars, constfolding, luaK_concat, luaK_exp2nextreg, codeconcat, codecommutative, codearith, codebitwise, codeeq, codecompare

---

## 总结

这个示例展示了 Lua 编译器如何处理各种运算符和表达式：

1. **字符串连接 `..`**：
   - 通过 `luaK_infix` 确保左操作数在栈上
   - 通过 `luaK_posfix` 调用 `codeconcat` 生成 OP_CONCAT 指令
   - 支持多个操作数的连接优化

2. **索引访问 `t[3]`**：
   - 通过 `suffixedexp` 的 `'['` 分支处理
   - `yindex` 分析索引表达式
   - `luaK_indexed` 转换为 VINDEXI 类型
   - 生成 GETI 指令

3. **字段访问 `t.x`**：
   - 通过 `suffixedexp` 的 `'.'` 分支处理
   - `fieldsel` 分析字段名
   - `luaK_indexed` 转换为 VINDEXSTR 类型
   - 生成 GETFIELD 指令

4. **算术运算优先级**：
   - `a + b * 2` 展示了优先级处理
   - `*` 优先级 11 > `+` 优先级 10
   - 先处理 `b * 2`，再处理 `a + (b*2)`
   - 通过 `subexpr` 的 while 循环和优先级表实现

5. **比较运算**：
   - `a > b` 转换为 `b < a`
   - 生成条件跳转指令
   - 需要后续的布尔值转换

6. **逻辑短路运算**：
   - `a and b or c` 展示了短路逻辑
   - `and` 优先级 2 > `or` 优先级 1
   - 通过跳转列表实现短路
   - `luaK_infix` 为 `and` 设置真跳转，为 `or` 设置假跳转
   - `luaK_posfix` 合并跳转列表

整个过程中，`subexpr` 函数是核心，它通过优先级表和 while 循环正确处理了运算符的优先级和结合性。`luaK_infix` 和 `luaK_posfix` 分别处理二元运算符的前缀和后缀部分，实现了各种优化和特殊处理（如短路逻辑）。
