# Lua 代码生成解析 - t = {}; t.a = 1

本文档详细分析 Lua 编译器如何将 `t = {}; t.a = 1` 编译成字节码的完整数据流。

## 概述

示例代码由两条语句组成：
1. `t = {}` - 创建空表并赋值给全局变量 t
2. `t.a = 1` - 设置表 t 的字段 a 为整数 1

这个过程涉及：
- **语法分析**（lparser.c）：将 Lua 源代码解析为抽象语法树
- **代码生成**（lcode.c）：从抽象语法树生成 Lua 虚拟机字节码

---

## 数据流

### 入口&示例代码

**入口**: `statement()` // lparser.c:1845

**示例代码**:
```lua
t = {}
t.a = 1
```

**前置数据说明**:
- `LexState* ls`：词法分析器状态，包含 token 流
- `FuncState* fs`：当前函数编译状态（main 函数）
- 第一个 token 为 `{ t : TK_NAME, seminfo : {ts:"t"} }`

---

### 调用链

#### 第一条语句：t = {}

1. **[前置数据]** LexState 第一个 token 为 `{ t : TK_NAME, seminfo : {ts:"t"} }`

2. **[进入 statement()]** (LexState* ls(token:TK_NAME), FuncState* fs(main函数域))

3. **[statement()]** 进入 ***default*** 分支（非关键字开头），调用 `exprstat()`

4. **[进入 exprstat()]** (LexState* ls(token:TK_NAME), FuncState* fs, v(LHS_assign,未初始化))

5. **[exprstat()]** 调用 `suffixedexp(ls, &v.v)` 分析左值表达式

6. **[进入 suffixedexp()]** (LexState* ls(token:TK_NAME), expdesc* v(未初始化))

7. **[suffixedexp()]** 调用 `primaryexp(ls, v)` 分析主表达式

8. **[进入 primaryexp()]** (LexState* ls(token:TK_NAME), expdesc* v(未初始化))

9. **[primaryexp()]** 进入 ***TK_NAME*** 分支，调用 `singlevar(ls, v)`

10. **[进入 singlevar()]** (LexState* ls(token:TK_NAME), expdesc* var(未初始化))

11. **[singlevar()]** 调用 `str_checkname(ls)`，取出变量名 "t"，token 前移到下一个 `{ t : '=' }`

12. **[singlevar()]** 调用 `singlevaraux(fs, "t", var, 1)` 查找变量

13. **[进入 singlevaraux()]** (FuncState* fs(main函数域), TString* n("t"), expdesc* var(未初始化), int base(1))

14. **[singlevaraux()]** 调用 `searchvar(fs, "t", var)` 在当前函数域查找局部变量

15. **[searchvar()]** 此时 `fs->nactvar = 0`，当前函数域没有活跃的局部变量，return -1

16. **[回到 singlevaraux()]** v = -1（未找到局部变量）

17. **[singlevaraux()]** 进入 ***else*** 分支（v < 0），调用 `searchupvalue(fs, "t")` 查找上值

18. **[进入 searchupvalue()]** (FuncState* fs(main函数域), TString* n("t"))

19. **[searchupvalue()]** 此时 `fs->nups = 1`（只有 _ENV），但没有找到名为 "t" 的 upval，return -1

20. **[回到 singlevaraux()]** idx = -1（未找到上值）

21. **[singlevaraux()]** 进入 ***idx < 0*** 分支，递归调用 `singlevaraux(NULL, "t", var, 0)`

22. **[进入 singlevaraux()]** (FuncState* fs(NULL), ...) - fs == NULL，表示已经到达最外层

23. **[singlevaraux()]** 进入 ***fs == NULL*** 分支，执行 `init_exp(var, VVOID, 0)`

24. **[回到 singlevaraux()]** var->k = VVOID，表示这是一个全局变量

25. **[回到 singlevar()]** var->k == VVOID，确认是全局变量

26. **[singlevar()]** 调用 `singlevaraux(fs, ls->envn, var, 1)` 获取 _ENV 变量

27. **[进入 singlevaraux()]** (FuncState* fs(main), TString* n("_ENV"), expdesc* var, int base(1))

28. **[singlevaraux()]** 调用 `searchvar(fs, "_ENV", var)`

29. **[searchvar()]** 找到 _ENV 作为上值（索引 0），return 对应的上值索引

30. **[回到 singlevaraux()]** v >= 0，进入 ***v >= 0*** 分支

31. **[singlevaraux()]** v 不是 VLOCAL，设置 `init_exp(var, VUPVAL, 0)`

32. **[回到 singlevar()]** var->k = VUPVAL, var->u.info = 0（_ENV 的上值索引）

33. **[singlevar()]** 调用 `luaK_exp2anyregup(fs, var)`，确保 var 在寄存器中

34. **[进入 luaK_exp2anyregup()]** (FuncState* fs, expdesc* e(VUPVAL, info:0))

35. **[luaK_exp2anyregup()]** e->k == VUPVAL，返回 0（不需要额外操作）

36. **[回到 singlevar()]** 调用 `codestring(&key, "t")`，创建字符串常量 key

37. **[进入 codestring()]** (expdesc* e, TString* s("t"))

38. **[codestring()]** 调用 `luaK_stringK(fs, s)` 将字符串加入常量表

39. **[回到 singlevar()]** key->k = VKSTR, key->u.strval = "t"

40. **[singlevar()]** 调用 `luaK_indexed(fs, var, &key)` 将表达式转换为索引形式

41. **[进入 luaK_indexed()]** (FuncState* fs, expdesc* t(VUPVAL, info:0), expdesc* k(VKSTR, "t"))

42. **[luaK_indexed()]** k->k == VKSTR，调用 `str2K(fs, k)`

43. **[进入 str2K()]** (FuncState* fs, expdesc* e(VKSTR, "t"))

44. **[str2K()]** 调用 `stringK(fs, e->u.strval)` 将字符串加入常量表

45. **[进入 stringK()]** (FuncState* fs, TString* s("t"))

46. **[stringK()]** 调用 `addk(fs, &key, &value)` 添加常量到 K 表

47. **[进入 addk()]** (FuncState* fs, TValue* key("t"), TValue* value("t"))

48. **[addk()]** 从 fs->ls->h 中查找是否已有缓存，当前 K 表为空

49. **[addk()]** K 表中没有对应常量，创建新的 entry 写入 f->k，`fs->nk = 1`，return 0

50. **[回到 str2K()]** e->u.info = 0（K 表索引），e->k = VK

51. **[回到 luaK_indexed()]** t->k == VUPVAL，k 现在是 VK

52. **[luaK_indexed()]** 进入 ***t->k == VUPVAL*** 分支

53. **[luaK_indexed()]** 设置 `t->u.ind.t = 0`（_ENV 的上值索引）

54. **[luaK_indexed()]** 设置 `t->u.ind.idx = 0`（"t" 的 K 表索引）

55. **[luaK_indexed()]** 设置 `t->k = VINDEXUP`

56. **[回到 suffixedexp()]** v->k = VINDEXUP，表示 _ENV["t"]

57. **[suffixedexp()]** 下一个 token 是 '='，不是 '.'/'['/':'/'('，进入 ***default*** 分支返回

58. **[回到 exprstat()]** v.v->k = VINDEXUP，ls->t.token == '='

59. **[exprstat()]** 进入 ***token == '=' || token == ','*** 分支，这是赋值语句

60. **[exprstat()]** 设置 `v.prev = NULL`（单一左值）

61. **[exprstat()]** 调用 `restassign(ls, &v, 1)` 处理剩余的赋值逻辑

62. **[进入 restassign()]** (LexState* ls(token:'='), struct LHS_assign* lh, int nvars(1))

63. **[restassign()]** 调用 `check_readonly(ls, &lh->v)` 检查是否为只读变量

64. **[restassign()]** 调用 `testnext(ls, ',')`，下一个 token 是 '='，不是 ','

65. **[restassign()]** 进入 ***else*** 分支（restassign -> '=' explist）

66. **[restassign()]** 调用 `checknext(ls, '=')`，确认并消耗 '='，token 前移到 `{`

67. **[restassign()]** 调用 `nexps = explist(ls, &e)` 分析右侧表达式列表

68. **[进入 explist()]** (LexState* ls(token:'{'), expdesc* v)

69. **[explist()]** 调用 `expr(ls, v)` 分析表达式

70. **[进入 expr()]** (LexState* ls(token:'{'), expdesc* v)

71. **[expr()]** 调用 `subexpr(ls, v, 0)` 分析子表达式

72. **[进入 subexpr()]** (LexState* ls(token:'{'), expdesc* v, int priority(0))

73. **[subexpr()]** 调用 `simpleexp(ls, v)` 分析简单表达式

74. **[进入 simpleexp()]** (LexState* ls(token:'{'), expdesc* v)

75. **[simpleexp()]** 进入 ***'{'*** 分支（表构造器）

76. **[simpleexp()]** 调用 `constructor(ls, v)` 构造表

77. **[进入 constructor()]** (LexState* ls(token:'{'), expdesc* t)

78. **[constructor()]** 调用 `luaK_codeABC(fs, OP_NEWTABLE, 0, 0, 0)` 生成创建表指令

79. **[进入 luaK_codeABC()]** (FuncState* fs, OpCode o(OP_NEWTABLE), int a(0), int b(0), int c(0))

80. **[luaK_codeABC()]** 计算指令编码，写入 fs->f->code[fs->pc]

81. **[回到 constructor()]** pc = 0（NEWTABLE 指令的位置）

82. **[constructor()]** 调用 `luaK_code(fs, 0)` 预留 EXTRAARG 空间

83. **[constructor()]** 初始化 ConsControl：`cc.na = cc.nh = cc.tostore = 0`

84. **[constructor()]** 调用 `init_exp(t, VNONRELOC, fs->freereg)`，t->u.info = 0（表将在 R[0]）

85. **[constructor()]** 调用 `luaK_reserveregs(fs, 1)`，`fs->freereg = 1`

86. **[constructor()]** 调用 `init_exp(&cc.v, VVOID, 0)`

87. **[constructor()]** 调用 `checknext(ls, '{')`，消耗 '{'，token 前移到 `}`

88. **[constructor()]** 进入 do-while 循环

89. **[constructor()]** ls->t.token == '}'，break（空表）

90. **[constructor()]** 调用 `check_match(ls, '}', '{', line)`

91. **[constructor()]** 调用 `lastlistfield(fs, &cc)`

92. **[constructor()]** 调用 `luaK_settablesize(fs, pc, t->u.info, cc.na, cc.nh)` 设置表大小

93. **[回到 simpleexp()]** v->k = VNONRELOC, v->u.info = 0（表在 R[0]）

94. **[回到 subexpr()]** 返回

95. **[回到 expr()]** 返回

96. **[回到 explist()]** 下一个 token 不是 ','，return n = 1

97. **[回到 restassign()]** nexps = 1, nvars = 1

98. **[restassign()]** nexps == nvars，进入 ***else*** 分支

99. **[restassign()]** 调用 `luaK_setoneret(ls->fs, &e)` 关闭表达式

100. **[restassign()]** 调用 `luaK_storevar(ls->fs, &lh->v, &e)` 存储变量

101. **[进入 luaK_storevar()]** (FuncState* fs, expdesc* var(VINDEXUP), expdesc* ex(VNONRELOC, info:0))

102. **[luaK_storevar()]** var->k == VINDEXUP，进入 ***VINDEXUP*** 分支

103. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETTABUP, var->u.ind.t, var->u.ind.idx, ex)`

104. **[codeABRK()]** 生成指令 `SETTABUP 0 0 0`（_ENV["t"] = R[0]）

105. **[回到 restassign()]** return

106. **[回到 exprstat()]** return

107. **[回到 statement()]** 恢复寄存器状态

---

#### 第二条语句：t.a = 1

108. **[回到 statement()]** 下一次循环，读取下一个语句

109. **[前置数据]** LexState 当前 token 为 `{ t : TK_NAME, seminfo : {ts:"t"} }`

110. **[进入 statement()]** (LexState* ls(token:TK_NAME))

111. **[statement()]** 进入 ***default*** 分支，调用 `exprstat(ls)`

112. **[进入 exprstat()]** (LexState* ls(token:TK_NAME))

113. **[exprstat()]** 调用 `suffixedexp(ls, &v.v)`

114. **[进入 suffixedexp()]** (LexState* ls(token:TK_NAME))

115. **[suffixedexp()]** 调用 `primaryexp(ls, v)`

116. **[进入 primaryexp()]** (LexState* ls(token:TK_NAME))

117. **[primaryexp()]** 进入 ***TK_NAME*** 分支，调用 `singlevar(ls, v)`

118. **[进入 singlevar()]** (LexState* ls(token:TK_NAME))

119. **[singlevar()]** 和之前一样，将 "t" 解析为 `_ENV["t"]`（VINDEXUP）

120. **[回到 suffixedexp()]** v->k = VINDEXUP

121. **[suffixedexp()]** 下一个 token 是 '.'，进入 ***'.'*** 分支

122. **[suffixedexp()]** 调用 `fieldsel(ls, v)` 处理字段选择

123. **[进入 fieldsel()]** (LexState* ls(token:'.'), expdesc* v(VINDEXUP))

124. **[fieldsel()]** 调用 `luaK_exp2anyregup(fs, v)` 确保 v 在寄存器中

125. **[进入 luaK_exp2anyregup()]** (FuncState* fs, expdesc* e(VINDEXUP, ind.t:0, ind.idx:0))

126. **[luaK_exp2anyregup()]** e->k == VINDEXUP（不是 VUPVAL），进入 ***else*** 分支

127. **[luaK_exp2anyregup()]** 调用 `luaK_exp2anyreg(fs, e)`

128. **[进入 luaK_exp2anyreg()]** (FuncState* fs, expdesc* e(VINDEXUP))

129. **[luaK_exp2anyreg()]** 调用 `luaK_dischargevars(fs, e)` 释放变量

130. **[进入 luaK_dischargevars()]** (FuncState* fs, expdesc* e(VINDEXUP))

131. **[luaK_dischargevars()]** e->k == VINDEXUP，进入 ***VINDEXUP*** 分支

132. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETTABUP, 0, e->u.ind.t, e->u.ind.idx)` 生成指令

133. **[进入 luaK_codeABC()]** (FuncState* fs, OpCode o(OP_GETTABUP), int a(0), int b(0), int c(0))

134. **[luaK_codeABC()]** 编码指令为整数，写入 fs->f->code[fs->pc]，fs->pc++

135. **[回到 luaK_dischargevars()]** e->u.info = pc（GETTABUP 指令位置），e->k = VRELOC

136. **[回到 luaK_exp2anyreg()]** e->k == VRELOC（不是 VNONRELOC）

137. **[luaK_exp2anyreg()]** e->k != VNONRELOC，进入 ***else*** 分支

138. **[luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

139. **[进入 luaK_exp2nextreg()]** (FuncState* fs, expdesc* e(VRELOC))

140. **[luaK_exp2nextreg()]** 调用 `luaK_dischargevars(fs, e)` 再次检查

141. **[进入 luaK_dischargevars()]** e->k == VRELOC，进入 ***default*** 分支，不做操作

142. **[回到 luaK_exp2nextreg()]** 调用 `freeexp(fs, e)`

143. **[进入 freeexp()]** e->k == VRELOC，没有需要释放的寄存器，直接返回

144. **[回到 luaK_exp2nextreg()]** 调用 `luaK_reserveregs(fs, 1)`，fs->freereg = 1

145. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg - 1)` 即 `exp2reg(fs, e, 0)`

146. **[进入 exp2reg()]** (FuncState* fs, expdesc* e(VRELOC), int reg(0))

147. **[exp2reg()]** 调用 `discharge2reg(fs, e, reg)`

148. **[进入 discharge2reg()]** (FuncState* fs, expdesc* e(VRELOC), int reg(0))

149. **[discharge2reg()]** 调用 `luaK_dischargevars(fs, e)`

150. **[进入 luaK_dischargevars()]** e->k == VRELOC，进入 ***default*** 分支

151. **[回到 discharge2reg()]** e->k == VRELOC，进入 ***VRELOC*** 分支

152. **[discharge2reg()]** 调用 `getinstruction(fs, e)` 获取之前生成的指令

153. **[进入 getinstruction()]** 返回 &fs->f->code[e->u.info]（GETTABUP 指令的地址）

154. **[回到 discharge2reg()]** 调用 `SETARG_A(*pc, reg)` 将指令的 A 参数设置为 0

155. **[discharge2reg()]** GETTABUP 指令变为 `GETTABUP 0 0 0`（R[0] = _ENV["t"]）

156. **[回到 exp2reg()]** e->k != VJMP，hasjumps(e) == false，跳过跳转列表处理

157. **[exp2reg()]** 执行 `e->f = e->t = NO_JUMP`

158. **[exp2reg()]** 执行 `e->u.info = reg = 0`

159. **[exp2reg()]** 执行 `e->k = VNONRELOC`

160. **[回到 luaK_exp2nextreg()]** e->k = VNONRELOC, e->u.info = 0

161. **[回到 luaK_exp2anyreg()]** return e->u.info = 0

162. **[回到 luaK_exp2anyregup()]** return

163. **[回到 fieldsel()]** 调用 `luaX_next(ls)`，跳过 '.'，token 前移到 `{ a : TK_NAME }`

134. **[fieldsel()]** 调用 `codename(ls, &key)`，获取字段名 "a"

135. **[进入 codename()]** 调用 `str_checkname(ls)`，取出 "a"

136. **[codename()]** 调用 `luaK_stringK(fs, s)`，将 "a" 加入常量表

137. **[回到 fieldsel()]** key->k = VKSTR, key->u.info = 1（"a" 在 K 表的索引）

138. **[fieldsel()]** 调用 `luaK_indexed(fs, v, &key)` 将表达式转换为索引形式

139. **[进入 luaK_indexed()]** (FuncState* fs, expdesc* t(VNONRELOC, info:0), expdesc* k(VKSTR, info:1))

140. **[luaK_indexed()]** t->k == VNONRELOC（不是 VUPVAL）

141. **[luaK_indexed()]** 进入 ***else*** 分支

142. **[luaK_indexed()]** 设置 `t->u.ind.t = 0`（表在 R[0]）

143. **[luaK_indexed()]** k 是 VKSTR，设置 `t->u.ind.idx = 1`（"a" 的 K 表索引）

144. **[luaK_indexed()]** 设置 `t->k = VINDEXSTR`

145. **[回到 fieldsel()]** v->k = VINDEXSTR，表示 t["a"]

146. **[回到 suffixedexp()]** v->k = VINDEXSTR

147. **[suffixedexp()]** 下一个 token 是 '='，进入 ***default*** 分支返回

148. **[回到 exprstat()]** v.v->k = VINDEXSTR，ls->t.token == '='

149. **[exprstat()]** 进入赋值分支

150. **[exprstat()]** 调用 `restassign(ls, &v, 1)`

151. **[进入 restassign()]** (LexState* ls(token:'='))

152. **[restassign()]** 调用 `checknext(ls, '=')`，消耗 '='，token 前移到 `{ 1 : TK_INT }`

153. **[restassign()]** 调用 `nexps = explist(ls, &e)`

154. **[进入 explist()]** (LexState* ls(token:TK_INT))

155. **[explist()]** 调用 `expr(ls, v)`

156. **[进入 expr()]** (LexState* ls(token:TK_INT))

157. **[expr()]** 调用 `subexpr(ls, v, 0)`

158. **[进入 subexpr()]** (LexState* ls(token:TK_INT))

159. **[subexpr()]** 调用 `simpleexp(ls, v)`

160. **[进入 simpleexp()]** (LexState* ls(token:TK_INT))

161. **[simpleexp()]** 进入 ***TK_INT*** 分支

162. **[simpleexp()]** 执行 `init_exp(v, VKINT, 0)`

163. **[simpleexp()]** 设置 `v->u.ival = ls->t.seminfo.i = 1`

164. **[回到 subexpr()]** v->k = VKINT, v->u.ival = 1

165. **[回到 expr()]** return

166. **[回到 explist()]** 下一个 token 不是 ','，return n = 1

167. **[回到 restassign()]** nexps = 1, nvars = 1

168. **[restassign()]** nexps == nvars，进入 ***else*** 分支

169. **[restassign()]** 调用 `luaK_setoneret(ls->fs, &e)`

170. **[进入 luaK_setoneret()]** (FuncState* fs, expdesc* e(VKINT, ival:1))

171. **[luaK_setoneret()]** 调用 `luaK_exp2anyreg(fs, e)` 将常量加载到寄存器

172. **[进入 luaK_exp2anyreg()]** (FuncState* fs, expdesc* e(VKINT))

173. **[luaK_exp2anyreg()]** 调用 `luaK_exp2reg(fs, e)`

174. **[进入 luaK_exp2reg()]** 生成 LOADI 指令

175. **[luaK_exp2reg()]** `LOADI 1 1`（R[1] = 1）

176. **[回到 luaK_exp2anyreg()]** e->k = VNONRELOC, e->u.info = 1

177. **[回到 luaK_setoneret()]** return

178. **[回到 restassign()]** 调用 `luaK_storevar(ls->fs, &lh->v, &e)`

179. **[进入 luaK_storevar()]** (FuncState* fs, expdesc* var(VINDEXSTR), expdesc* ex(VNONRELOC, info:1))

180. **[luaK_storevar()]** var->k == VINDEXSTR，进入 ***VINDEXSTR*** 分支

181. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETFIELD, var->u.ind.t, var->u.ind.idx, ex)`

182. **[codeABRK()]** 生成指令 `SETFIELD 0 1 1`（R[0]["a"] = R[1]）

183. **[回到 restassign()]** return

184. **[回到 exprstat()]** return

185. **[回到 statement()]** 恢复寄存器状态

---

### 调用链树状图

```
statement()                                          [语句入口]
├── 第一条语句: t = {}
│   ├── exprstat()                                  [表达式语句]
│   │   ├── suffixedexp()                           [后缀表达式: t]
│   │   │   ├── primaryexp()                        [主表达式]
│   │   │   │   └── singlevar()                     [变量: t]
│   │   │   │       ├── str_checkname()             [获取变量名 "t"]
│   │   │   │       ├── singlevaraux()              [查找局部变量: 未找到]
│   │   │   │       ├── singlevaraux()              [查找上值: 未找到]
│   │   │   │       ├── singlevaraux(fs=NULL)      [递归终止: VVOID]
│   │   │   │       ├── singlevaraux()              [获取 _ENV: VUPVAL]
│   │   │   │       ├── luaK_exp2anyregup()         [确保在寄存器]
│   │   │   │       ├── codename()                  [创建字符串 "t"]
│   │   │   │       └── luaK_indexed()              [转换为 VINDEXUP]
│   │   │   └── [返回: VINDEXUP]                    [_ENV["t"]]
│   │   └── restassign()                            [赋值处理]
│   │       └── explist()                           [右侧表达式: {}]
│   │           └── expr() → simpleexp()
│   │               └── constructor()               [表构造器]
│   │                   ├── luaK_codeABC()          [NEWTABLE 指令]
│   │                   ├── luaK_code()             [EXTRAARG 预留]
│   │                   ├── [空表，无字段]
│   │                   └── luaK_settablesize()     [设置表大小]
│   │           └── [返回: VNONRELOC]               [R[0] = {}]
│   └── luaK_storevar()                             [生成 SETTABUP]
│       └── codeABRK()                              [SETTABUP 0 0 0]
│
├── 第二条语句: t.a = 1
│   ├── exprstat()                                  [表达式语句]
│   │   ├── suffixedexp()                           [后缀表达式: t.a]
│   │   │   ├── primaryexp() → singlevar()          [变量: t]
│   │   │   │   └── [同样流程，返回: VINDEXUP]      [_ENV["t"]]
│   │   │   └── fieldsel()                          [字段选择: .a]
│   │   │       ├── luaK_exp2anyregup()             [确保在寄存器]
│   │   │       │   └── luaK_exp2anyreg()
│   │   │       │       ├── luaK_dischargevars()    [VINDEXUP → VRELOC]
│   │   │       │       │   └── luaK_codeABC()      [GETTABUP 指令]
│   │   │       │       └── luaK_exp2nextreg()
│   │   │       │           └── exp2reg()
│   │   │       │               └── discharge2reg() [VRELOC: 设置A参数=0]
│   │   │       │           └── [返回: VNONRELOC]   [R[0] = _ENV["t"]]
│   │   │       ├── luaX_next()                     [跳过 '.']
│   │   │       ├── codename()                      [获取字段名 "a"]
│   │   │       └── luaK_indexed()                  [转换为 VINDEXSTR]
│   │   │           └── str2K()                     ["a" 加入 K 表]
│   │   │       └── [返回: VINDEXSTR]               [R[0]["a"]]
│   │   └── restassign()                            [赋值处理]
│   │       └── explist()                           [右侧表达式: 1]
│   │           └── expr() → simpleexp()
│   │               └── init_exp()                  [VKINT, 值=1]
│   │           └── [返回: VKINT]
│   │       └── luaK_setoneret()
│   │           └── luaK_exp2anyreg()
│   │               └── luaK_exp2reg()
│   │                   └── luaK_int()             [LOADI 指令]
│   │           └── [返回: VNONRELOC]               [R[1] = 1]
│   └── luaK_storevar()                             [生成 SETFIELD]
│       └── codeABRK()                              [SETFIELD 0 1 1]
│
└── [返回]
```

**树状图说明**：
- 每个缩进层级（├── / └──）表示一次函数调用
- `→` 表示函数内部继续调用
- `[返回: XXX]` 表示函数返回时的 expdesc 类型
- `[说明]` 表示关键操作或数据状态

---

### 最终生成的字节码

```
; t = {}
NEWTABLE 0 0 0 0        ; R[0] = {}
EXTRAARG 0              ; 额外参数（表大小）
SETTABUP 0 0 0          ; _ENV["t"] = R[0]

; t.a = 1
GETTABUP 0 0 0          ; R[0] = _ENV["t"] (获取 t)
LOADI 1 1               ; R[1] = 1
SETFIELD 0 1 1          ; R[0]["a"] = R[1]
```

---

## 数据结构详解

### expdesc

**定义**：
```c
// src/lparser.h
typedef struct expdesc {
  expkind k;
  union {
    lua_Integer ival;    /* for VKINT */
    lua_Number nval;  /* for VKFLT */
    TString *strval;  /* for VKSTR */
    int info;  /* for generic use */
    struct {  /* for indexed variables */
      short idx;  /* index (R or "long" K) */
      lu_byte t;  /* table (register or upvalue) */
    } ind;
    struct {  /* for local variables */
      lu_byte ridx;  /* register holding the variable */
      unsigned short vidx;  /* compiler index (in 'actvar.arr')  */
    } var;
  } u;
  int t;  /* patch list of 'exit when true' */
  int f;  /* patch list of 'exit when false' */
} expdesc;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 | 赋值位置 |
|--------|----------|----------|----------|----------|
| k | expkind | 表达式类型（变量/常量/索引等） | 所有表达式操作 | init_exp, luaK_indexed, luaK_storevar |
| u.ival | lua_Integer | 整数常量值 | VKINT 类型表达式 | simpleexp (TK_INT) |
| u.nval | lua_Number | 浮点常量值 | VKFLT 类型表达式 | simpleexp (TK_FLT) |
| u.strval | TString* | 字符串常量值 | VKSTR 类型表达式 | codestring |
| u.info | int | 通用信息（寄存器索引/常量索引等） | VNONRELOC/VK/VUPVAL 等 | luaK_exp2anyreg, luaK_indexed |
| u.ind.idx | short | 索引变量的键索引 | VINDEXED/VINDEXSTR/VINDEXI/VINDEXUP | luaK_indexed |
| u.ind.t | lu_byte | 索引变量的表位置 | VINDEXED/VINDEXSTR/VINDEXI/VINDEXUP | luaK_indexed |
| u.var.ridx | lu_byte | 局部变量的寄存器索引 | VLOCAL 类型 | singlevaraux |
| u.var.vidx | unsigned short | 局部变量的编译器索引 | VLOCAL 类型 | singlevaraux |
| t | int | 为真时跳转的补丁列表 | 条件表达式 | 各种条件跳转 |
| f | int | 为假时跳转的补丁列表 | 条件表达式 | 各种条件跳转 |

---

### expkind

**定义**：
```c
// src/lparser.h
typedef enum {
  VVOID,     /* 空表达式 */
  VNIL,      /* 常量 nil */
  VTRUE,     /* 常量 true */
  VFALSE,    /* 常量 false */
  VK,        /* K 表中的常量 */
  VKFLT,     /* 浮点常量 */
  VKINT,     /* 整数常量 */
  VKSTR,     /* 字符串常量 */
  VNONRELOC, /* 固定寄存器中的值 */
  VLOCAL,    /* 局部变量 */
  VUPVAL,    /* 上值 */
  VCONST,    /* 编译时常量 */
  VINDEXED,  /* 索引变量 t[k]，k 在寄存器 */
  VINDEXUP,  /* 上值索引 upval[k]，k 在 K 表 */
  VINDEXI,   /* 整数索引 t[i] */
  VINDEXSTR, /* 字符串索引 t["s"] */
  VJMP,      /* 跳转指令 */
  VRELOC,    /* 可重定位表达式 */
  VCALL,     /* 函数调用 */
  VVARARG    /* 可变参数 */
} expkind;
```

**expkind 枚举说明**：

| 枚举值 | 含义 | 使用场景 |
|--------|------|----------|
| VVOID | 空值/全局变量标记 | 标记需要从 _ENV 获取的全局变量 |
| VNIL | nil 常量 | nil 关键字 |
| VTRUE | true 常量 | true 关键字 |
| VFALSE | false 常量 | false 关键字 |
| VK | K 表中的常量 | 已加载到常量表的通用常量 |
| VKFLT | 浮点常量 | 浮点数字面量 |
| VKINT | 整数常量 | 整数数字面量 |
| VKSTR | 字符串常量 | 字符串字面量 |
| VNONRELOC | 固定寄存器值 | 值在已知寄存器中，不需要重定位 |
| VLOCAL | 局部变量 | 函数内的局部变量 |
| VUPVAL | 上值 | 外部函数的变量（闭包） |
| VCONST | 编译期常量 | 使用 <const> 声明的变量 |
| VINDEXED | 寄存器索引 | 表[key]，key 在寄存器中 |
| VINDEXUP | 上值字符串索引 | _ENV[key]，key 在 K 表中 |
| VINDEXI | 整数索引 | 表[整数常量] |
| VINDEXSTR | 字符串索引 | 表["字符串"]，key 在 K 表中 |
| VJMP | 条件跳转 | 比较和逻辑运算 |
| VRELOC | 可重定位 | 结果可放在任意寄存器 |
| VCALL | 函数调用 | 函数调用表达式 |
| VVARARG | 可变参数 | ... 表达式 |

---

### LHS_assign

**定义**：
```c
// src/lparser.c
struct LHS_assign {
  struct expdesc v;         /* 左值表达式描述符 */
  struct LHS_assign *prev;  /* 前一个左值（用于多重赋值） */
};
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| v | expdesc | 左值表达式（被赋值的变量） | exprstat, restassign |
| prev | LHS_assign* | 指向前一个左值（链表） | restassign（多重赋值 a, b = ...） |

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

### FuncState

**定义**：
```c
// src/lparser.h
typedef struct FuncState {
  Proto *f;                  /* 当前函数原型 */
  struct FuncState *prev;    /* 外层函数 */
  struct LexState *ls;       /* 词法状态 */
  struct BlockCnt *bl;       /* 当前块链 */
  int pc;                    /* 下一个代码位置 */
  int lasttarget;            /* 上一个跳转标签位置 */
  int previousline;          /* 上一次保存的行号 */
  int nk;                    /* K 表元素数量 */
  int np;                    /* 原型表元素数量 */
  int nabslineinfo;          /* 绝对行信息数量 */
  int firstlocal;            /* 第一个局部变量索引 */
  int firstlabel;            /* 第一个标签索引 */
  short ndebugvars;          /* 调试变量数量 */
  lu_byte nactvar;           /* 活跃局部变量数量 */
  lu_byte nups;              /* 上值数量 */
  lu_byte freereg;           /* 下一个空闲寄存器 */
  lu_byte iwthabs;           /* 自上次绝对行信息以来的指令数 */
  lu_byte needclose;         /* 返回时是否需要关闭 upvalue */
} FuncState;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| f | Proto* | 当前函数原型 | 所有代码生成函数 |
| prev | FuncState* | 外层函数状态 | 函数嵌套调用 |
| ls | LexState* | 词法分析器状态 | 所有解析函数 |
| bl | BlockCnt* | 块控制链 | 块级作用域管理 |
| pc | int | 程序计数器（下一条指令位置） | luaK_code*, 所有代码生成 |
| nk | int | 常量表 K 的元素数量 | stringK, addk |
| nups | lu_byte | 上值数量 | singlevaraux, newupvalue |
| freereg | lu_byte | 下一个空闲寄存器索引 | 寄存器分配 |
| nactvar | lu_byte | 当前活跃的局部变量数量 | 局部变量管理 |

---

### LexState

**定义**：
```c
// src/llex.h
typedef struct LexState {
  int current;          /* 当前字符 */
  int linenumber;       /* 当前行号 */
  Token t;              /* 当前 token */
  struct FuncState *fs; /* 当前函数状态 */
  TString *envn;        /* 环境变量名（"_ENV"） */
  // ... 其他字段
} LexState;
```

**字段说明**：

| 字段名 | 数据类型 | 数据含义 | 使用位置 |
|--------|----------|----------|----------|
| t | Token | 当前 token（包含类型和语义值） | 所有解析函数 |
| linenumber | int | 当前行号 | 错误报告和调试信息 |
| fs | FuncState* | 当前函数状态 | 代码生成 |
| envn | TString* | 环境变量名（"_ENV"） | singlevar（获取全局变量） |

---

## 函数详解

### statement()

**源码位置**：src/lparser.c:1845

**源代码**：
```c
static void statement (LexState *ls) {
  int line = ls->linenumber;
  enterlevel(ls);
  switch (ls->t.token) {
    case ';': {
      luaX_next(ls);
      break;
    }
    case TK_IF: {
      ifstat(ls, line);
      break;
    }
    // ... 其他 case 分支
    default: {
      exprstat(ls);
      break;
    }
  }
  lua_assert(ls->fs->f->maxstacksize >= ls->fs->freereg &&
             ls->fs->freereg >= luaY_nvarstack(ls->fs));
  ls->fs->freereg = luaY_nvarstack(ls->fs);
  leavelevel(ls);
}
```

**功能说明**：

#### 逻辑段 1：初始化
- **操作内容**：保存当前行号，进入新的语法层次
- **数据影响**：line = ls->linenumber，增加递归深度
- **输入**：LexState*
- **输出**：无

#### 逻辑段 2：根据 token 类型分发
- **操作内容**：检查当前 token 类型，跳转到对应处理函数
- **数据影响**：调用对应的语句处理函数
- **输入**：ls->t.token
- **输出**：无

#### 逻辑段 3：清理寄存器状态
- **操作内容**：恢复寄存器状态，退出语法层次
- **数据影响**：fs->freereg = nvarstack(fs)
- **输入**：FuncState*
- **输出**：无

#### 函数总结
- **输入**：LexState* ls
- **输出**：无
- **调用函数**：enterlevel, luaX_next, ifstat, exprstat, leavelevel 等

---

### exprstat()

**源码位置**：src/lparser.c:1795

**源代码**：
```c
static void exprstat (LexState *ls) {
  FuncState *fs = ls->fs;
  struct LHS_assign v;
  suffixedexp(ls, &v.v);
  if (ls->t.token == '=' || ls->t.token == ',') {
    v.prev = NULL;
    restassign(ls, &v, 1);
  }
  else {
    Instruction *inst;
    check_condition(ls, v.v.k == VCALL, "syntax error");
    inst = &getinstruction(fs, &v.v);
    SETARG_C(*inst, 1);
  }
}
```

**功能说明**：

#### 逻辑段 1：分析左值表达式
- **操作内容**：调用 suffixedexp 分析左值（赋值目标）
- **数据影响**：v.v 被填充为左值的 expdesc
- **输入**：v.v（未初始化）
- **输出**：v.v（左值描述符）

#### 逻辑段 2：判断是赋值还是函数调用
- **操作内容**：检查下一个 token
- **数据影响**：决定是赋值语句还是函数调用语句
- **输入**：ls->t.token
- **输出**：控制流分支

#### 逻辑段 3a：赋值分支
- **操作内容**：初始化赋值链，调用 restassign
- **数据影响**：生成赋值字节码
- **输入**：v, nvars=1
- **输出**：无

#### 逻辑段 3b：函数调用分支
- **操作内容**：修改调用指令，丢弃返回值
- **数据影响**：设置 C 参数为 1（无返回值）
- **输入**：v.v（VCALL 类型）
- **输出**：修改后的指令

#### 函数总结
- **输入**：LexState* ls
- **输出**：无
- **调用函数**：suffixedexp, restassign, getinstruction

---

### suffixedexp()

**源码位置**：src/lparser.c:1103

**源代码**：
```c
static void suffixedexp (LexState *ls, expdesc *v) {
  FuncState *fs = ls->fs;
  primaryexp(ls, v);
  for (;;) {
    switch (ls->t.token) {
      case '.': {
        fieldsel(ls, v);
        break;
      }
      case '[': {
        expdesc key;
        luaK_exp2anyregup(fs, v);
        yindex(ls, &key);
        luaK_indexed(fs, v, &key);
        break;
      }
      case ':': {
        expdesc key;
        luaX_next(ls);
        codename(ls, &key);
        luaK_self(fs, v, &key);
        funcargs(ls, v);
        break;
      }
      case '(': case TK_STRING: case '{': {
        luaK_exp2nextreg(fs, v);
        funcargs(ls, v);
        break;
      }
      default: return;
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：分析主表达式
- **操作内容**：调用 primaryexp 获取基础表达式
- **数据影响**：v 被初始化为基础表达式描述符
- **输入**：v（未初始化）
- **输出**：v（主表达式）

#### 逻辑段 2：循环处理后缀操作
- **操作内容**：根据后缀 token 类型（. / [ / : / ( / { / string）分发处理
- **数据影响**：v 被修改为带后缀的表达式描述符
- **输入**：v, ls->t.token
- **输出**：v（最终表达式）

#### 逻辑段 3a：字段选择（.）
- **操作内容**：调用 fieldsel 处理 t.field 形式
- **数据影响**：v 变为 VINDEXSTR/VINDEXED 类型
- **输入**：v（表表达式）
- **输出**：v（索引表达式）

#### 逻辑段 3b：索引选择（[）
- **操作内容**：处理 t[key] 形式
- **数据影响**：v 变为 VINDEXED/VINDEXI 类型
- **输入**：v（表表达式）
- **输出**：v（索引表达式）

#### 逻辑段 3c：方法调用（:）
- **操作内容**：处理 t:method() 形式
- **数据影响**：生成 SELF 指令
- **输入**：v（表表达式）
- **输出**：v（方法调用）

#### 逻辑段 3d：函数调用
- **操作内容**：处理 f() 形式
- **数据影响**：生成 CALL 指令
- **输入**：v（函数表达式）
- **输出**：v（函数调用）

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：无（v 被修改）
- **调用函数**：primaryexp, fieldsel, yindex, luaK_indexed, funcargs

---

### primaryexp()

**源码位置**：src/lparser.c:1081

**源代码**：
```c
static void primaryexp (LexState *ls, expdesc *v) {
  switch (ls->t.token) {
    case '(': {
      int line = ls->linenumber;
      luaX_next(ls);
      expr(ls, v);
      check_match(ls, ')', '(', line);
      luaK_dischargevars(ls->fs, v);
      return;
    }
    case TK_NAME: {
      singlevar(ls, v);
      return;
    }
    default: {
      luaX_syntaxerror(ls, "unexpected symbol");
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：括号表达式分支
- **操作内容**：处理 (expr) 形式
- **数据影响**：v 被填充为括号内表达式的结果
- **输入**：v（未初始化）
- **输出**：v（表达式结果）

#### 逻辑段 2：变量名分支
- **操作内容**：调用 singlevar 查找变量
- **数据影响**：v 被填充为变量描述符（VLOCAL/VUPVAL/VINDEXUP 等）
- **输入**：v（未初始化）
- **输出**：v（变量描述符）

#### 逻辑段 3：错误分支
- **操作内容**：报告语法错误
- **数据影响**：抛出异常
- **输入**：无
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：无（v 被修改）
- **调用函数**：luaX_next, expr, check_match, singlevar

---

### singlevar()

**源码位置**：src/lparser.c:463

**源代码**：
```c
static void singlevar (LexState *ls, expdesc *var) {
  TString *varname = str_checkname(ls);
  FuncState *fs = ls->fs;
  singlevaraux(fs, varname, var, 1);
  if (var->k == VVOID) {
    expdesc key;
    singlevaraux(fs, ls->envn, var, 1);
    lua_assert(var->k != VVOID);
    luaK_exp2anyregup(fs, var);
    codestring(&key, varname);
    luaK_indexed(fs, var, &key);
  }
}
```

**功能说明**：

#### 逻辑段 1：获取变量名
- **操作内容**：从 token 流中提取变量名
- **数据影响**：varname = "t"（或其他变量名），token 前移
- **输入**：ls->t（TK_NAME）
- **输出**：TString* varname

#### 逻辑段 2：查找变量
- **操作内容**：调用 singlevaraux 查找变量
- **数据影响**：var 被填充为变量类型（VLOCAL/VUPVAL/VVOID）
- **输入**：fs, varname, var
- **输出**：var（变量描述符）

#### 逻辑段 3：处理全局变量
- **操作内容**：如果是 VVOID，表示全局变量，需要从 _ENV 获取
- **数据影响**：var 变为 VINDEXUP 类型（_ENV[varname]）
- **输入**：var（VVOID）
- **输出**：var（VINDEXUP）

#### 函数总结
- **输入**：LexState* ls, expdesc* var
- **输出**：无（var 被修改）
- **调用函数**：str_checkname, singlevaraux, luaK_exp2anyregup, codestring, luaK_indexed

---

### singlevaraux()

**源码位置**：src/lparser.c:435

**源代码**：
```c
static void singlevaraux (FuncState *fs, TString *n, expdesc *var, int base) {
  if (fs == NULL)
    init_exp(var, VVOID, 0);
  else {
    int v = searchvar(fs, n, var);
    if (v >= 0) {
      if (v == VLOCAL && !base)
        markupval(fs, var->u.var.vidx);
    }
    else {
      int idx = searchupvalue(fs, n);
      if (idx < 0) {
        singlevaraux(fs->prev, n, var, 0);
        if (var->k == VLOCAL || var->k == VUPVAL)
          idx = newupvalue(fs, n, var);
        else
          return;
      }
      init_exp(var, VUPVAL, idx);
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：递归终止条件
- **操作内容**：如果 fs == NULL，表示已到最外层
- **数据影响**：var->k = VVOID（标记为全局变量）
- **输入**：fs（NULL）
- **输出**：var（VVOID）

#### 逻辑段 2：查找局部变量
- **操作内容**：在当前函数域搜索变量
- **数据影响**：找到则 var 变为 VLOCAL
- **输入**：fs, n
- **输出**：var 或 v（搜索结果）

#### 逻辑段 3：查找上值
- **操作内容**：在上值表中搜索变量
- **数据影响**：找到则 var 变为 VUPVAL
- **输入**：fs, n
- **输出**：var（VUPVAL）

#### 逻辑段 4：递归向上层函数查找
- **操作内容**：在外层函数中继续查找
- **数据影响**：递归调用，可能创建新的上值
- **输入**：fs->prev, n
- **输出**：var（VLOCAL/VUPVAL/VVOID）

#### 函数总结
- **输入**：FuncState* fs, TString* n, expdesc* var, int base
- **输出**：无（var 被修改）
- **调用函数**：searchvar, searchupvalue, newupvalue, init_exp

---

### fieldsel()

**源码位置**：src/lparser.c:811

**源代码**：
```c
static void fieldsel (LexState *ls, expdesc *v) {
  FuncState *fs = ls->fs;
  expdesc key;
  luaK_exp2anyregup(fs, v);
  luaX_next(ls);
  codename(ls, &key);
  luaK_indexed(fs, v, &key);
}
```

**功能说明**：

#### 逻辑段 1：确保表在寄存器中
- **操作内容**：调用 luaK_exp2anyregup 确保表对象在寄存器中
- **数据影响**：v 可能从 VUPVAL 变为 VNONRELOC
- **输入**：v（可能是 VUPVAL/VLOCAL/VNONRELOC）
- **输出**：v（VNONRELOC）

#### 逻辑段 2：跳过点号
- **操作内容**：消耗 '.' token
- **数据影响**：token 前移到字段名
- **输入**：ls->t（.）
- **输出**：ls->t（字段名）

#### 逻辑段 3：获取字段名
- **操作内容**：调用 codename 处理字段名
- **数据影响**：key 变为 VKSTR 类型
- **输入**：key（未初始化）
- **输出**：key（VKSTR）

#### 逻辑段 4：转换为索引表达式
- **操作内容**：调用 luaK_indexed 将表达式转换为索引形式
- **数据影响**：v 变为 VINDEXSTR 类型
- **输入**：v（表表达式）, key（字段名）
- **输出**：v（索引表达式）

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：无（v 被修改）
- **调用函数**：luaK_exp2anyregup, luaX_next, codename, luaK_indexed

---

### luaK_indexed()

**源码位置**：src/lcode.c:1279

**源代码**：
```c
void luaK_indexed (FuncState *fs, expdesc *t, expdesc *k) {
  if (k->k == VKSTR)
    str2K(fs, k);
  lua_assert(!hasjumps(t) &&
             (t->k == VLOCAL || t->k == VNONRELOC || t->k == VUPVAL));
  if (t->k == VUPVAL && !isKstr(fs, k))
    luaK_exp2anyreg(fs, t);
  if (t->k == VUPVAL) {
    int temp = t->u.info;
    lua_assert(isKstr(fs, k));
    t->u.ind.t = temp;
    t->u.ind.idx = k->u.info;
    t->k = VINDEXUP;
  }
  else {
    t->u.ind.t = (t->k == VLOCAL) ? t->u.var.ridx: t->u.info;
    if (isKstr(fs, k)) {
      t->u.ind.idx = k->u.info;
      t->k = VINDEXSTR;
    }
    else if (isCint(k)) {
      t->u.ind.idx = cast_int(k->u.ival);
      t->k = VINDEXI;
    }
    else {
      t->u.ind.idx = luaK_exp2anyreg(fs, k);
      t->k = VINDEXED;
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：处理字符串键
- **操作内容**：如果键是字符串，将其加入 K 表
- **数据影响**：k 从 VKSTR 变为 VK
- **输入**：k（VKSTR）
- **输出**：k（VK）

#### 逻辑段 2a：处理上值索引（VUPVAL）
- **操作内容**：表是上值，键必须是字符串常量
- **数据影响**：t 变为 VINDEXUP
- **输入**：t（VUPVAL）, k（VK）
- **输出**：t（VINDEXUP）

#### 逻辑段 2b：处理寄存器索引
- **操作内容**：表在寄存器中，根据键类型选择索引方式
- **数据影响**：t 变为 VINDEXSTR/VINDEXI/VINDEXED
- **输入**：t（VLOCAL/VNONRELOC）, k
- **输出**：t（对应的索引类型）

#### 函数总结
- **输入**：FuncState* fs, expdesc* t（表）, expdesc* k（键）
- **输出**：无（t 被修改为索引类型）
- **调用函数**：str2K, luaK_exp2anyreg

---

### restassign()

**源码位置**：src/lparser.c:1375

**源代码**：
```c
static void restassign (LexState *ls, struct LHS_assign *lh, int nvars) {
  expdesc e;
  check_condition(ls, vkisvar(lh->v.k), "syntax error");
  check_readonly(ls, &lh->v);
  if (testnext(ls, ',')) {
    struct LHS_assign nv;
    nv.prev = lh;
    suffixedexp(ls, &nv.v);
    if (!vkisindexed(nv.v.k))
      check_conflict(ls, lh, &nv.v);
    enterlevel(ls);
    restassign(ls, &nv, nvars+1);
    leavelevel(ls);
  }
  else {
    int nexps;
    checknext(ls, '=');
    nexps = explist(ls, &e);
    if (nexps != nvars)
      adjust_assign(ls, nvars, nexps, &e);
    else {
      luaK_setoneret(ls->fs, &e);
      luaK_storevar(ls->fs, &lh->v, &e);
      return;
    }
  }
  init_exp(&e, VNONRELOC, ls->fs->freereg-1);
  luaK_storevar(ls->fs, &lh->v, &e);
}
```

**功能说明**：

#### 逻辑段 1：检查左值有效性
- **操作内容**：验证左值是有效的变量类型，检查是否只读
- **数据影响**：可能抛出语法错误
- **输入**：lh->v
- **输出**：无

#### 逻辑段 2a：多重赋值分支（,）
- **操作内容**：处理 a, b, c = ... 形式
- **数据影响**：递归构建左值链表
- **输入**：ls, lh, nvars
- **输出**：无

#### 逻辑段 2b：单一赋值分支（=）
- **操作内容**：处理 a = ... 形式
- **数据影响**：分析右侧表达式，生成赋值指令
- **输入**：ls, lh, nvars
- **输出**：无

#### 函数总结
- **输入**：LexState* ls, struct LHS_assign* lh, int nvars
- **输出**：无
- **调用函数**：suffixedexp, explist, adjust_assign, luaK_setoneret, luaK_storevar

---

### explist()

**源码位置**：src/lparser.c:1012

**源代码**：
```c
static int explist (LexState *ls, expdesc *v) {
  int n = 1;
  expr(ls, v);
  while (testnext(ls, ',')) {
    luaK_exp2nextreg(ls->fs, v);
    expr(ls, v);
    n++;
  }
  return n;
}
```

**功能说明**：

#### 逻辑段 1：分析第一个表达式
- **操作内容**：调用 expr 分析第一个表达式
- **数据影响**：v 被填充为第一个表达式的结果
- **输入**：v（未初始化）
- **输出**：v（表达式结果）

#### 逻辑段 2：循环分析后续表达式
- **操作内容**：如果遇到逗号，继续分析下一个表达式
- **数据影响**：n 增加，v 被覆盖为新的表达式
- **输入**：ls->t（,）
- **输出**：n（表达式数量）

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：int n（表达式数量）
- **调用函数**：expr, luaK_exp2nextreg

---

### luaK_storevar()

**源码位置**：src/lcode.c:1049

**源代码**：
```c
void luaK_storevar (FuncState *fs, expdesc *var, expdesc *ex) {
  switch (var->k) {
    case VLOCAL: {
      freeexp(fs, ex);
      exp2reg(fs, ex, var->u.var.ridx);
      return;
    }
    case VUPVAL: {
      int e = luaK_exp2anyreg(fs, ex);
      luaK_codeABC(fs, OP_SETUPVAL, e, var->u.info, 0);
      break;
    }
    case VINDEXUP: {
      codeABRK(fs, OP_SETTABUP, var->u.ind.t, var->u.ind.idx, ex);
      break;
    }
    case VINDEXI: {
      codeABRK(fs, OP_SETI, var->u.ind.t, var->u.ind.idx, ex);
      break;
    }
    case VINDEXSTR: {
      codeABRK(fs, OP_SETFIELD, var->u.ind.t, var->u.ind.idx, ex);
      break;
    }
    case VINDEXED: {
      codeABRK(fs, OP_SETTABLE, var->u.ind.t, var->u.ind.idx, ex);
      break;
    }
    default: lua_assert(0);
  }
  freeexp(fs, ex);
}
```

**功能说明**：

#### 逻辑段 1：VLOCAL 分支
- **操作内容**：将表达式计算到指定寄存器
- **数据影响**：生成 MOVE 指令或直接计算
- **输入**：var（VLOCAL）, ex
- **输出**：无

#### 逻辑段 2：VUPVAL 分支
- **操作内容**：生成 SETUPVAL 指令
- **数据影响**：写入上值
- **输入**：var（VUPVAL）, ex
- **输出**：SETUPVAL 指令

#### 逻辑段 3：VINDEXUP 分支
- **操作内容**：生成 SETTABUP 指令（_ENV[key] = value）
- **数据影响**：设置上值表的字段
- **输入**：var（VINDEXUP）, ex
- **输出**：SETTABUP 指令

#### 逻辑段 4：VINDEXSTR 分支
- **操作内容**：生成 SETFIELD 指令（table["str"] = value）
- **数据影响**：设置表的字符串字段
- **输入**：var（VINDEXSTR）, ex
- **输出**：SETFIELD 指令

#### 逻辑段 5：其他索引类型
- **操作内容**：处理 VINDEXED 和 VINDEXI
- **数据影响**：生成对应的 SETTABLE/SETI 指令
- **输入**：var, ex
- **输出**：对应指令

#### 函数总结
- **输入**：FuncState* fs, expdesc* var（左值）, expdesc* ex（右值表达式）
- **输出**：无（生成存储指令）
- **调用函数**：freeexp, exp2reg, luaK_exp2anyreg, codeABRK

---

### constructor()

**源码位置**：src/lparser.c:925

**源代码**：
```c
static void constructor (LexState *ls, expdesc *t) {
  FuncState *fs = ls->fs;
  int line = ls->linenumber;
  int pc = luaK_codeABC(fs, OP_NEWTABLE, 0, 0, 0);
  ConsControl cc;
  luaK_code(fs, 0);
  cc.na = cc.nh = cc.tostore = 0;
  cc.t = t;
  init_exp(t, VNONRELOC, fs->freereg);
  luaK_reserveregs(fs, 1);
  init_exp(&cc.v, VVOID, 0);
  checknext(ls, '{');
  do {
    lua_assert(cc.v.k == VVOID || cc.tostore > );
    if (ls->t.token == '}') break;
    closelistfield(fs, &cc);
    field(ls, &cc);
  } while (testnext(ls, ',') || testnext(ls, ';'));
  check_match(ls, '}', '{', line);
  lastlistfield(fs, &cc);
  luaK_settablesize(fs, pc, t->u.info, cc.na, cc.nh);
}
```

**功能说明**：

#### 逻辑段 1：生成 NEWTABLE 指令
- **操作内容**：生成创建表的字节码指令
- **数据影响**：pc = 指令位置，预留 EXTRAARG 空间
- **输入**：fs
- **输出**：int pc（NEWTABLE 指令位置）

#### 逻辑段 2：初始化控制结构
- **操作内容**：初始化 ConsControl 结构
- **数据影响**：cc.na = cc.nh = cc.tostore = 0, t->k = VNONRELOC
- **输入**：t, fs
- **输出**：cc, t（表描述符）

#### 逻辑段 3：解析表字段
- **操作内容**：循环解析表内的字段
- **数据影响**：cc.na, cc.nh 增加
- **输入**：ls->t（字段内容）
- **输出**：cc（字段计数）

#### 逻辑段 4：设置表大小
- **操作内容**：修改 NEWTABLE 指令的参数，设置表的大小
- **数据影响**：NEWTABLE 指令的参数被修改
- **输入**：pc, t->u.info, cc.na, cc.nh
- **输出**：修改后的指令

#### 函数总结
- **输入**：LexState* ls, expdesc* t
- **输出**：无（t 被修改为表描述符）
- **调用函数**：luaK_codeABC, luaK_reserveregs, closelistfield, field, lastlistfield, luaK_settablesize

---

### simpleexp()

**源码位置**：src/lparser.c:1140

**源代码**：
```c
static void simpleexp (LexState *ls, expdesc *v) {
  switch (ls->t.token) {
    case TK_FLT: {
      init_exp(v, VKFLT, 0);
      v->u.nval = ls->t.seminfo.r;
      break;
    }
    case TK_INT: {
      init_exp(v, VKINT, 0);
      v->u.ival = ls->t.seminfo.i;
      break;
    }
    case TK_STRING: {
      codestring(v, ls->t.seminfo.ts);
      break;
    }
    case TK_NIL: {
      init_exp(v, VNIL, 0);
      break;
    }
    case TK_TRUE: {
      init_exp(v, VTRUE, 0);
      break;
    }
    case TK_FALSE: {
      init_exp(v, VFALSE, 0);
      break;
    }
    case '{': {
      constructor(ls, v);
      break;
    }
    // ... 其他 case
    default: {
      suffixedexp(ls, v);
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：浮点常量
- **操作内容**：处理浮点数字面量
- **数据影响**：v->k = VKFLT, v->u.nval = 数值
- **输入**：ls->t（TK_FLT）
- **输出**：v（VKFLT）

#### 逻辑段 2：整数常量
- **操作内容**：处理整数数字面量
- **数据影响**：v->k = VKINT, v->u.ival = 数值
- **输入**：ls->t（TK_INT）
- **输出**：v（VKINT）

#### 逻辑段 3：字符串常量
- **操作内容**：处理字符串字面量
- **数据影响**：v->k = VKSTR, 字符串加入 K 表
- **输入**：ls->t（TK_STRING）
- **输出**：v（VKSTR）

#### 逻辑段 4：nil, true, false
- **操作内容**：处理 nil/true/false 关键字
- **数据影响**：v->k = VNIL/VTRUE/VFALSE
- **输入**：ls->t（对应关键字）
- **输出**：v（对应类型）

#### 逻辑段 5：表构造器
- **操作内容**：处理 {} 表达式
- **数据影响**：v->k = VNONRELOC（表对象）
- **输入**：ls->t（{）
- **输出**：v（表描述符）

#### 逻辑段 6：其他情况
- **操作内容**：调用 suffixedexp 处理复杂表达式
- **数据影响**：v 被填充为相应的表达式
- **输入**：v（未初始化）
- **输出**：v（表达式）

#### 函数总结
- **输入**：LexState* ls, expdesc* v
- **输出**：无（v 被修改）
- **调用函数**：init_exp, codestring, constructor, suffixedexp

---

### luaK_dischargevars()

**源码位置**：src/lcode.c:772

**源代码**：
```c
void luaK_dischargevars (FuncState *fs, expdesc *e) {
  switch (e->k) {
    case VCONST: {
      const2exp(const2val(fs, e), e);
      break;
    }
    case VLOCAL: {
      int temp = e->u.var.ridx;
      e->u.info = temp;
      e->k = VNONRELOC;
      break;
    }
    case VUPVAL: {
      e->u.info = luaK_codeABC(fs, OP_GETUPVAL, 0, e->u.info, 0);
      e->k = VRELOC;
      break;
    }
    case VINDEXUP: {
      e->u.info = luaK_codeABC(fs, OP_GETTABUP, 0, e->u.ind.t, e->u.ind.idx);
      e->k = VRELOC;
      break;
    }
    case VINDEXI: {
      freereg(fs, e->u.ind.t);
      e->u.info = luaK_codeABC(fs, OP_GETI, 0, e->u.ind.t, e->u.ind.idx);
      e->k = VRELOC;
      break;
    }
    case VINDEXSTR: {
      freereg(fs, e->u.ind.t);
      e->u.info = luaK_codeABC(fs, OP_GETFIELD, 0, e->u.ind.t, e->u.ind.idx);
      e->k = VRELOC;
      break;
    }
    case VINDEXED: {
      freeregs(fs, e->u.ind.t, e->u.ind.idx);
      e->u.info = luaK_codeABC(fs, OP_GETTABLE, 0, e->u.ind.t, e->u.ind.idx);
      e->k = VRELOC;
      break;
    }
    case VVARARG: case VCALL: {
      luaK_setoneret(fs, e);
      break;
    }
    default: break;
  }
}
```

**功能说明**：

#### 逻辑段 1：VLOCAL 分支
- **操作内容**：局部变量已在寄存器中，转换为 VNONRELOC
- **数据影响**：e->k = VNONRELOC, e->u.info = ridx
- **输入**：e（VLOCAL）
- **输出**：e（VNONRELOC）

#### 逻辑段 2：VUPVAL 分支
- **操作内容**：生成 GETUPVAL 指令
- **数据影响**：e->k = VRELOC, e->u.info = 指令位置
- **输入**：e（VUPVAL）
- **输出**：e（VRELOC）

#### 逻辑段 3：VINDEXUP 分支
- **操作内容**：生成 GETTABUP 指令（_ENV[key]）
- **数据影响**：e->k = VRELOC, e->u.info = 指令位置
- **输入**：e（VINDEXUP）
- **输出**：e（VRELOC）

#### 逻辑段 4：VINDEXSTR 分支
- **操作内容**：生成 GETFIELD 指令（table["key"]）
- **数据影响**：释放表寄存器，e->k = VRELOC
- **输入**：e（VINDEXSTR）
- **输出**：e（VRELOC）

#### 函数总结
- **输入**：FuncState* fs, expdesc* e
- **输出**：无（e 被修改为 VNONRELOC 或 VRELOC）
- **调用函数**：luaK_codeABC, freereg, freeregs

---

### luaK_exp2anyreg()

**源码位置**：src/lcode.c:955

**源代码**：
```c
int luaK_exp2anyreg (FuncState *fs, expdesc *e) {
  luaK_dischargevars(fs, e);
  if (e->k == VNONRELOC) {
    if (!hasjumps(e))
      return e->u.info;
    if (e->u.info >= luaY_nvarstack(fs)) {
      exp2reg(fs, e, e->u.info);
      return e->u.info;
    }
  }
  luaK_exp2nextreg(fs, e);
  return e->u.info;
}
```

**功能说明**：

#### 逻辑段 1：调用 dischargevars
- **操作内容**：首先释放变量，生成必要的加载指令
- **数据影响**：e 可能从 VINDEXUP 等类型变为 VRELOC
- **输入**：e
- **输出**：e（可能是 VNONRELOC 或 VRELOC）

#### 逻辑段 2：检查是否已在寄存器
- **操作内容**：如果 e->k == VNONRELOC 且无跳转，直接返回寄存器索引
- **数据影响**：无需额外操作
- **输入**：e（VNONRELOC）
- **输出**：寄存器索引

#### 逻辑段 3：使用下一个寄存器
- **操作内容**：调用 luaK_exp2nextreg 将值放入下一个可用寄存器
- **数据影响**：分配新寄存器，e 变为 VNONRELOC
- **输入**：e
- **输出**：寄存器索引

#### 函数总结
- **输入**：FuncState* fs, expdesc* e
- **输出**：int（寄存器索引）
- **调用函数**：luaK_dischargevars, luaK_exp2nextreg, exp2reg

---

### luaK_exp2anyregup()

**源码位置**：src/lcode.c:977

**源代码**：
```c
void luaK_exp2anyregup (FuncState *fs, expdesc *e) {
  if (e->k != VUPVAL || hasjumps(e))
    luaK_exp2anyreg(fs, e);
}
```

**功能说明**：

#### 逻辑段 1：检查是否为 VUPVAL
- **操作内容**：如果 e 不是 VUPVAL 或有跳转，需要放入寄存器
- **数据影响**：调用 luaK_exp2anyreg
- **输入**：e
- **输出**：e（VNONRELOC）

#### 逻辑段 2：VUPVAL 直接返回
- **操作内容**：e 是 VUPVAL 且无跳转，不需要操作
- **数据影响**：无
- **输入**：e（VUPVAL）
- **输出**：无

#### 函数总结
- **输入**：FuncState* fs, expdesc* e
- **输出**：无（e 可能被修改）
- **调用函数**：luaK_exp2anyreg

---

### luaK_exp2nextreg()

**源码位置**：src/lcode.c:943

**源代码**：
```c
void luaK_exp2nextreg (FuncState *fs, expdesc *e) {
  luaK_dischargevars(fs, e);
  freeexp(fs, e);
  luaK_reserveregs(fs, 1);
  exp2reg(fs, e, fs->freereg - 1);
}
```

**功能说明**：

#### 逻辑段 1：释放变量和表达式
- **操作内容**：调用 luaK_dischargevars 和 freeexp
- **数据影响**：可能生成加载指令，释放旧寄存器
- **输入**：e
- **输出**：e（已释放）

#### 逻辑段 2：预留寄存器
- **操作内容**：调用 luaK_reserveregs(fs, 1)
- **数据影响**：fs->freereg 增加
- **输入**：fs
- **输出**：无

#### 逻辑段 3：将表达式放入寄存器
- **操作内容**：调用 exp2reg(fs, e, fs->freereg - 1)
- **数据影响**：e->k = VNONRELOC, e->u.info = 寄存器索引
- **输入**：e, reg
- **输出**：无

#### 函数总结
- **输入**：FuncState* fs, expdesc* e
- **输出**：无（e 被修改为 VNONRELOC）
- **调用函数**：luaK_dischargevars, freeexp, luaK_reserveregs, exp2reg

---

### exp2reg()

**源码位置**：src/lcode.c:915

**源代码**：
```c
static void exp2reg (FuncState *fs, expdesc *e, int reg) {
  discharge2reg(fs, e, reg);
  if (e->k == VJMP)
    luaK_concat(fs, &e->t, e->u.info);
  if (hasjumps(e)) {
    int final;
    int p_f = NO_JUMP;
    int p_t = NO_JUMP;
    if (need_value(fs, e->t) || need_value(fs, e->f)) {
      int fj = (e->k == VJMP) ? NO_JUMP : luaK_jump(fs);
      p_f = code_loadbool(fs, reg, OP_LFALSESKIP);
      p_t = code_loadbool(fs, reg, OP_LOADTRUE);
      luaK_patchtohere(fs, fj);
    }
    final = luaK_getlabel(fs);
    patchlistaux(fs, e->f, final, reg, p_f);
    patchlistaux(fs, e->t, final, reg, p_t);
  }
  e->f = e->t = NO_JUMP;
  e->u.info = reg;
  e->k = VNONRELOC;
}
```

**功能说明**：

#### 逻辑段 1：调用 discharge2reg
- **操作内容**：将表达式的值放入指定寄存器
- **数据影响**：生成必要的加载指令，设置指令参数
- **输入**：e, reg
- **输出**：e（VRELOC 或其他类型）

#### 逻辑段 2：处理跳转表达式
- **操作内容**：如果 e 是 VJMP，合并跳转列表
- **数据影响**：e->t 包含完整的跳转列表
- **输入**：e（VJMP）
- **输出**：无

#### 逻辑段 3：处理有跳转列表的表达式
- **操作内容**：生成布尔值加载和跳转补丁
- **数据影响**：生成 LOADFALSESKIP/LOADTRUE 指令
- **输入**：e, reg
- **输出**：无

#### 逻辑段 4：设置为不可重定位
- **操作内容**：清除跳转列表，设置为 VNONRELOC
- **数据影响**：e->f = e->t = NO_JUMP, e->k = VNONRELOC
- **输入**：e, reg
- **输出**：无

#### 函数总结
- **输入**：FuncState* fs, expdesc* e, int reg
- **输出**：无（e 被修改为 VNONRELOC）
- **调用函数**：discharge2reg, luaK_concat, code_loadbool, patchlistaux

---

### discharge2reg()

**源码位置**：src/lcode.c:826

**源代码**：
```c
static void discharge2reg (FuncState *fs, expdesc *e, int reg) {
  luaK_dischargevars(fs, e);
  switch (e->k) {
    case VNIL: {
      luaK_nil(fs, reg, 1);
      break;
    }
    case VFALSE: {
      luaK_codeABC(fs, OP_LOADFALSE, reg, 0, 0);
      break;
    }
    case VTRUE: {
      luaK_codeABC(fs, OP_LOADTRUE, reg, 0, 0);
      break;
    }
    case VKSTR: {
      str2K(fs, e);
    }
    case VK: {
      luaK_codek(fs, reg, e->u.info);
      break;
    }
    case VKFLT: {
      luaK_float(fs, reg, e->u.nval);
      break;
    }
    case VKINT: {
      luaK_int(fs, reg, e->u.ival);
      break;
    }
    case VRELOC: {
      Instruction *pc = &getinstruction(fs, e);
      SETARG_A(*pc, reg);
      break;
    }
    default: {
      exp2reg(fs, e, reg);
      break;
    }
  }
}
```

**功能说明**：

#### 逻辑段 1：调用 dischargevars
- **操作内容**：首先释放变量，生成必要的加载指令
- **数据影响**：e 可能变为 VRELOC
- **输入**：e
- **输出**：e

#### 逻辑段 2：处理各种常量类型
- **操作内容**：根据 e->k 类型生成对应的加载指令
- **数据影响**：生成 LOADFALSE/LOADTRUE/LOADK 等指令
- **输入**：e, reg
- **输出**：无

#### 逻辑段 3：处理 VRELOC
- **操作内容**：修改已生成指令的 A 参数为指定寄存器
- **数据影响**：SETARG_A(*pc, reg)
- **输入**：e（VRELOC）, reg
- **输出**：无

#### 函数总结
- **输入**：FuncState* fs, expdesc* e, int reg
- **输出**：无（生成加载指令或修改已有指令）
- **调用函数**：luaK_dischargevars, luaK_codeABC, luaK_codek, str2K

---

## 示例分析

### 数据流总结

| 变量/位置 | 第一条语句后 | 第二条语句后 |
|----------|-------------|-------------|
| _ENV | 不变（_ENV） | 不变（_ENV） |
| _ENV["t"] | 指向空表 {} | 指向空表 {} |
| R[0] | 被使用，释放 | 指向 t（从 _ENV["t"] 加载） |
| R[1] | 未使用 | 存储整数 1 |
| K[0] | "t" | "t" |
| K[1] | 无 | "a" |
| 字节码数量 | 3 条 | 3 条 |

### 调用链总结

**第一条语句（t = {}）**：
```
statement() → exprstat() → suffixedexp() → primaryexp() → singlevar()
  → singlevaraux()（查找失败，返回 VVOID）
  → singlevaraux()（获取 _ENV，返回 VUPVAL）
  → luaK_indexed()（转换为 VINDEXUP）
restassign() → explist() → expr() → subexpr() → simpleexp()
  → constructor()（生成 NEWTABLE 指令）
luaK_storevar()（生成 SETTABUP 指令）
```

**第二条语句（t.a = 1）**：
```
statement() → exprstat() → suffixedexp() → primaryexp() → singlevar()
  → ... （同样将 "t" 解析为 VINDEXUP）
  → luaK_exp2anyregup() → luaK_exp2anyreg()（生成 GETTABUP）
fieldsel() → luaK_indexed()（转换为 VINDEXSTR）
restassign() → explist() → expr() → subexpr() → simpleexp()
  → init_exp()（VKINT，值为 1）
  → luaK_setoneret() → luaK_exp2anyreg()（生成 LOADI）
luaK_storevar()（生成 SETFIELD 指令）
```

---

## 总结

这个示例展示了 Lua 编译器如何将简单的表创建和字段赋值语句转换为字节码：

1. **全局变量访问**：`t` 被解析为 `_ENV["t"]`（VINDEXUP）
2. **表创建**：`{}` 生成 `NEWTABLE` 指令
3. **字段选择**：`t.a` 解析为两步：先加载 `_ENV["t"]` 到寄存器，再通过 `fieldsel` 转换为 `VINDEXSTR`
4. **字段赋值**：生成 `SETFIELD` 指令

整个过程中，`expdesc` 结构扮演了核心角色，通过不同的 `expkind` 类型表示表达式所处的不同阶段和状态，最终由 `luaK_storevar` 统一生成对应的存储指令。
