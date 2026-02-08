# Lua 字节码完整解析 - 从 Token 到指令的详细流程

本文档详细分析 Lua 编译器所有 47 个字节码指令的生成逻辑，包括操作码、指令格式、参数用途、示例代码以及从 Token 到指令的完整调用链。

---

## 字节码格式说明

Lua 虚拟机指令是 32 位无符号整数，前 7 位为操作码。根据操作码不同，指令有以下格式：

| 格式 | 结构 | 说明 |
|------|------|------|
| **iABC** | `C(8) \| B(8) \| k(1) \| A(8) \| Op(7)` | 最常用格式，3 个参数 |
| **iABx** | `Bx(17) \| A(8) \| Op(7)` | 大参数格式 |
| **iAsBx** | `sBx(有符号17位) \| A(8) \| Op(7)` | 有符号大参数，用于跳转和立即数 |
| **iAx** | `Ax(25) \| Op(7)` | 超大参数格式 |
| **isJ** | `sJ(有符号25位) \| Op(7)` | 跳转指令格式 |

**参数说明**：
- `A`: 目标寄存器或第一个参数
- `B`: 第二个参数（寄存器或常量索引）
- `C`: 第三个参数（寄存器或常量索引）
- `Bx`: 扩展参数（无符号，范围 0-131071）
- `sBx`: 扩展参数（有符号，范围 -65536-65535）
- `Ax`: 超大参数（范围 0-33554431）
- `sJ`: 跳转偏移量（有符号）
- `k`: 常量标志位（1 表示常量，0 表示寄存器）

**关键数据结构**：
```c
/* expkind - 表达式类型枚举 */
typedef enum {
  VVOID,      /* 空表达式 */
  VNIL,       /* nil 常量 */
  VTRUE,      /* true 常量 */
  VFALSE,     /* false 常量 */
  VK,         /* K 表中的常量 */
  VKFLT,      /* 浮点常量 */
  VKINT,      /* 整数常量 */
  VKSTR,      /* 字符串常量 */
  VNONRELOC,  /* 固定寄存器中的值 */
  VLOCAL,     /* 局部变量 */
  VUPVAL,     /* 上值 */
  VCONST,     /* 编译期常量 */
  VINDEXED,   /* 索引变量（表+键寄存器） */
  VINDEXUP,   /* 索引上值（上值+K表键） */
  VINDEXI,    /* 整数索引变量（表+整数键） */
  VINDEXSTR,  /* 字符串索引变量（表+K表字符串键） */
  VJMP,       /* 测试/比较表达式 */
  VRELOC,     /* 可重定位表达式 */
  VCALL,      /* 函数调用 */
  VVARARG     /* 可变参数 */
} expkind;

/* expdesc - 表达式描述符 */
typedef struct expdesc {
  expkind k;               /* 表达式类型 */
  union {
    lua_Integer ival;      /* VKINT: 整数值 */
    lua_Number nval;       /* VKFLT: 浮点值 */
    TString *strval;       /* VKSTR: 字符串 */
    int info;              /* 通用信息 */
    struct {               /* 索引变量 */
      short idx;           /* 键索引 */
      lu_byte t;           /* 表索引 */
    } ind;
    struct {               /* 局部变量 */
      lu_byte ridx;        /* 寄存器索引 */
      unsigned short vidx; /* actvar 索引 */
    } var;
  } u;
  int t;                   /* true 时跳转列表 */
  int f;                   /* false 时跳转列表 */
} expdesc;
```

---

## 操作码列表（共 47 个）

### 加载/移动指令（8 个）
1. OP_MOVE
2. OP_LOADI
3. OP_LOADF
4. OP_LOADK
5. OP_LOADKX
6. OP_LOADFALSE
7. OP_LFALSESKIP
8. OP_LOADTRUE
9. OP_LOADNIL

### 上值操作指令（2 个）
10. OP_GETUPVAL
11. OP_SETUPVAL

### 表访问指令（8 个）
12. OP_GETTABUP
13. OP_GETTABLE
14. OP_GETI
15. OP_GETFIELD
16. OP_SETTABUP
17. OP_SETTABLE
18. OP_SETI
19. OP_SETFIELD

### 表创建指令（1 个）
20. OP_NEWTABLE

### 函数调用指令（3 个）
21. OP_SELF
22. OP_CALL
23. OP_TAILCALL

### 算术运算指令（17 个）
24. OP_ADDI
25. OP_ADDK
26. OP_SUBK
27. OP_MULK
28. OP_MODK
29. OP_POWK
30. OP_DIVK
31. OP_IDIVK
32. OP_BANDK
33. OP_BORK
34. OP_BXORK
35. OP_SHRI
36. OP_SHLI
37. OP_ADD
38. OP_SUB
39. OP_MUL
40. OP_MOD
41. OP_POW
42. OP_DIV
43. OP_IDIV

### 位运算指令（5 个）
44. OP_BAND
45. OP_BOR
46. OP_BXOR
47. OP_SHL
48. OP_SHR

### 元方法指令（3 个）
49. OP_MMBIN
50. OP_MMBINI
51. OP_MMBINK

### 一元运算指令（4 个）
52. OP_UNM
53. OP_BNOT
54. OP_NOT
55. OP_LEN

### 其他指令（16 个）
56. OP_CONCAT
57. OP_CLOSE
58. OP_TBC
59. OP_JMP
60. OP_EQ
61. OP_LT
62. OP_LE
63. OP_EQK
64. OP_EQI
65. OP_LTI
66. OP_LEI
67. OP_GTI
68. OP_GEI
69. OP_TEST
70. OP_TESTSET
71. OP_RETURN
72. OP_RETURN0
73. OP_RETURN1
74. OP_FORLOOP
75. OP_FORPREP
76. OP_TFORPREP
77. OP_TFORCALL
78. OP_TFORLOOP
79. OP_SETLIST
80. OP_CLOSURE
81. OP_VARARG
82. OP_VARARGPREP
83. OP_EXTRAARG

---

## 1. 移动和加载指令

### OP_MOVE

**格式**: iABC
**描述**: `R[A] := R[B]` - 将寄存器 B 的值复制到寄存器 A
**参数**:
- `A`: 目标寄存器
- `B`: 源寄存器
- `C`: 未使用（0）

**示例代码**: `local a = b`（假设 b 是已存在的局部变量）

**Token 到指令的完整流程**:

```
前置条件：假设 b 是第 2 个局部变量（vidx=1），寄存器 ridx=1

1. **[词法分析]** "local" → TK_NAME，"a" → TK_NAME，"=" → '='，"b" → TK_NAME
   当前 token: { local : TK_NAME }

2. **[进入 statlist()]** → **statement()** → **localstat()**

3. **[localstat()]** 调用 `str_checkname(ls)` 获取变量名 "a"
   - 调用 luaX_next()，token 前移到 { = : '=' }

4. **[localstat()]** 调用 `new_localvar(ls, "a")`
   - 在 dyd->actvar.arr 中创建新条目
   - vidx = 0（a 是第一个局部变量）
   - var->vd.name = "a"
   - var->vd.kind = VDKREG

5. **[localstat()]** kind = VDKREG（普通变量）

6. **[localstat()]** nvars = 1

7. **[localstat()]** 调用 `testnext(ls, '=')`
   - 当前 token 是 '='，返回 1
   - 调用 luaX_next()，token 前移到 { b : TK_NAME }

8. **[localstat()]** 进入有初始化表达式分支

9. **[localstat()]** 调用 `nexps = explist(ls, &e)` 分析右侧表达式

10. **[进入 explist()]** (LexState* ls(token:TK_NAME))

11. **[explist()]** 调用 `expr(ls, &e)`

12. **[进入 expr()]** (expdesc* e)

13. **[expr()]** 调用 `subexpr(ls, &e, 0)`

14. **[进入 subexpr()]** (int priority(0))

15. **[subexpr()]** 调用 `getunopr(ls->t.token)`
    - 当前 token 是 TK_NAME
    - 返回 OPR_NOUNOPR

16. **[subexpr()]** uop == OPR_NOUNOPR，进入 else 分支

17. **[subexpr()]** 调用 `simpleexp(ls, &e)`

18. **[进入 simpleexp()]** (token: TK_NAME)

19. **[simpleexp()]** 进入 ***TK_NAME*** 分支

20. **[simpleexp()]** 调用 `singlevar(ls, &e)`

21. **[进入 singlevar()]** (expdesc* e)

22. **[singlevar()]** 调用 `singlevaraux(fs, ls->t.seminfo.ts, &e, 1)`

23. **[进入 singlevaraux()]** (TString* varname("b"), expdesc* var, int base(1))

24. **[singlevaraux()]** 调用 `searchvar(fs, varname, &aux)` 在局部变量中查找

25. **[进入 searchvar()]** (FuncState* fs, TString* varname("b"))

26. **[searchvar()]** 遍历 fs->f->locvars 查找 "b"
    - 在索引 1 处找到（b 是第二个局部变量）
    - 返回 vidx = 1

27. **[回到 singlevaraux()]** 找到局部变量

28. **[singlevaraux()]** 调用 `init_exp(var, VLOCAL, vidx)`
    - var->k = VLOCAL
    - var->u.info = 1（局部变量索引）

29. **[回到 singlevar()]** 返回

30. **[回到 simpleexp()]** 调用 luaX_next(ls)
    - token 前移到 { end : TK_END }

31. **[回到 subexpr()]** 返回

32. **[回到 expr()]** 返回
    - e->k = VLOCAL
    - e->u.var.vidx = 1

33. **[回到 explist()]** n = 1

34. **[回到 localstat()]** nexps = 1, nvars = 1

35. **[localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

36. **[进入 adjust_assign()]** (int nvars(1), int nexps(1), expdesc* e)

37. **[adjust_assign()]** 调用 `luaK_setoneret(fs, e)`

38. **[进入 luaK_setoneret()]** (expdesc* e)

39. **[luaK_setoneret()]** 调用 `luaK_exp2anyreg(fs, e)`

40. **[进入 luaK_exp2anyreg()]** (expdesc* e, e->k=VLOCAL)

41. **[luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

42. **[进入 luaK_exp2nextreg()]** (expdesc* e, e->k=VLOCAL)

43. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg)`

44. **[进入 exp2reg()]** (expdesc* e, int reg)

45. **[exp2reg()]** 调用 `luaK_dischargevars(fs, e)`

46. **[进入 luaK_dischargevars()]** (expdesc* e, e->k=VLOCAL)

47. **[luaK_dischargevars()]** 进入 ***VLOCAL*** 分支

48. **[luaK_dischargevars()]** 调用 `getlocvar(fs, e->u.var.vidx)` 获取寄存器索引
    - vidx = 1
    - 返回 ridx = 1（b 在寄存器 1）

49. **[luaK_dischargevars()]** 调用 `init_exp(e, VNONRELOC, ridx)`
    - e->k = VNONRELOC
    - e->u.info = 1

50. **[回到 exp2reg()]** e->k = VNONRELOC, e->u.info = 1

51. **[exp2reg()]** reg == e->u.info，不需要移动
    - 返回 e->u.info = 1

52. **[回到 luaK_exp2nextreg()]** 返回 1

53. **[回到 luaK_exp2anyreg()]** 返回 1

54. **[回到 luaK_setoneret()]** 返回

55. **[回到 adjust_assign()]** 返回

56. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`

57. **[进入 adjustlocalvars()]** (int nvars(1))

58. **[adjustlocalvars()]** 进入 for 循环，i 从 0 到 nvars-1

59. **[第1次循环]** 调用 `registerlocalvar(fs, ls, i)`

60. **[进入 registerlocalvar()]** (int i(0))

61. **[registerlocalvar()]** 获取 actvar[i]
    - vid = actvar[0].vd
    - vid.name = "a"
    - vid.kind = VDKREG

62. **[registerlocalvar()]** 调用 `luaF_getlocalbyname(fs->f, vid.name)` 检查是否已存在
    - 返回 -1（不存在）

63. **[registerlocalvar()]** 分配寄存器 ridx = fs->freereg = 0

64. **[registerlocalvar()]** 调用 `setobjname2s(fs->ls->L, &fs->f->k[fs->nk], &vid.k, vid.name)`

65. **[registerlocalvar()]** 设置 f->locvars[fs->ndebugvars]
    - locvar->name = "a"
    - locvar->startpc = fs->pc
    - locvar->endpc = -1

66. **[registerlocalvar()]** fs->ndebugvars++

67. **[registerlocalvar()]** fs->freereg++

68. **[回到 adjustlocalvars()]** i++, i = 1，退出循环

69. **[adjustlocalvars()]** 调用 `fs->nactvar += nvars`
    - fs->nactvar = 1

70. **[回到 localstat()]** 返回

71. **[回到 statement()]** 返回

72. **[回到 statlist()]** 返回

最终状态：
- 生成的指令：无（b 和 a 都在寄存器中，优化掉 MOVE）
- a 在寄存器 0，b 在寄存器 1
- e->k = VNONRELOC, e->u.info = 1

注意：如果 a 和 b 不在同一寄存器，会生成 OP_MOVE 指令：
```
[discharge2reg()] e->k == VNONRELOC, e->u.info = 1, reg = 0
[discharge2reg()] e->u.info != reg，调用 luaK_codeABC(fs, OP_MOVE, reg, e->u.info, 0)
```
生成的指令：MOVE R[0], R[1]
```

---

### OP_LOADI

**格式**: iAsBx
**描述**: `R[A] := sBx` - 加载整数立即数到寄存器
**参数**:
- `A`: 目标寄存器
- `sBx`: 有符号整数立即数（范围 -65536 到 65535）

**示例代码**: `local a = 42`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "42" → TK_INT，seminfo.ival = 42

2. **[进入 simpleexp()]** (token: TK_INT)

3. **[simpleexp()]** 进入 ***TK_INT*** 分支

4. **[simpleexp()]** 调用 `init_exp(v, VKINT, 0)`
    - v->k = VKINT
    - v->u.ival = ls->t.seminfo.ival = 42

5. **[simpleexp()]** 调用 luaX_next(ls)
    - token 前移

6. **[回到 subexpr()]** v->k = VKINT, v->u.ival = 42

7. **[回到 expr()]** v->k = VKINT, v->u.ival = 42

8. **[回到 explist()]** n = 1

9. **[回到 localstat()]** nexps = 1

10. **[localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

11. **[adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()**

12. **[进入 luaK_exp2anyreg()]** (e->k = VKINT)

13. **[luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

14. **[进入 luaK_exp2nextreg()]** (e->k = VKINT, fs->freereg = 0)

15. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg)`
    - reg = 0

16. **[进入 exp2reg()]** (e->k = VKINT, reg = 0)

17. **[exp2reg()]** 调用 `discharge2reg(fs, e, reg)`

18. **[进入 discharge2reg()]** (e->k = VKINT, reg = 0)

19. **[discharge2reg()]** 进入 ***VKINT*** 分支

20. **[discharge2reg()]** 调用 `luaK_int(fs, reg, e->u.ival)`
    - reg = 0
    - ival = 42

21. **[进入 luaK_int()]** (FuncState* fs, int reg(0), lua_Integer ival(42))

22. **[luaK_int()]** 检查 |ival| <= MAXARG_sBx（65535）
    - |42| <= 65535，成立

23. **[luaK_int()]** 调用 `luaK_codeABC(fs, OP_LOADI, reg, (int)ival, 0)`
    - Op = OP_LOADI
    - A = 0
    - sBx = 42

24. **[进入 luaK_codeABC()]** (Op=OP_LOADI, A=0, B=42, C=0, k=0)

25. **[luaK_codeABC()]** 编码指令
    - code = CREATE_ABCk(OP_LOADI, 0, 42, 0, 0)

26. **[luaK_codeABC()]** 调用 `luaK_code(fs, code)`

27. **[进入 luaK_code()]** (Instruction code)

28. **[luaK_code()]** 写入 `fs->f->code[fs->pc] = code`

29. **[luaK_code()]** fs->pc++
    - fs->pc = 1

30. **[回到 luaK_codeABC()]** 返回 fs->pc - 1 = 0

31. **[回到 luaK_int()]** 返回

32. **[回到 discharge2reg()]** 返回

33. **[回到 exp2reg()]** 返回 reg = 0

34. **[回到 luaK_exp2nextreg()]** 调用 `luaK_reserveregs(fs, 1)`
    - fs->freereg = 1

35. **[回到 luaK_exp2anyreg()]** 返回 reg = 0

36. **[回到 adjust_assign()]** 返回

37. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 1)`
    - 为 a 分配寄存器 0

最终生成的指令：
```
[0] LOADI     R[0], 42
```

数据流总结：
- Token(TK_INT, ival=42) → expdesc(VKINT, ival=42) → 指令 OP_LOADI
```

---

### OP_LOADF

**格式**: iAsBx
**描述**: `R[A] := (lua_Number)sBx` - 加载浮点立即数到寄存器
**参数**:
- `A`: 目标寄存器
- `sBx`: 浮点数立即数（编码为整数）

**示例代码**: `local a = 3.14`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "3.14" → TK_FLT，seminfo.nval = 3.14

2. **[进入 simpleexp()]** (token: TK_FLT)

3. **[simpleexp()]** 进入 ***TK_FLT*** 分支

4. **[simpleexp()]** 调用 `init_exp(v, VKFLT, 0)`
    - v->k = VKFLT
    - v->u.nval = ls->t.seminfo.nval = 3.14

5. **[simpleexp()]** 调用 luaX_next(ls)

6. **[回到 subexpr()]** v->k = VKFLT, v->u.nval = 3.14

7. **[回到 localstat()]** 调用 `adjust_assign(ls, 1, 1, &e)`

8. **[adjust_assign()]** → **luaK_setoneret()** → **luaK_exp2anyreg()** → **luaK_exp2nextreg()**

9. **[进入 luaK_exp2nextreg()]** (e->k = VKFLT)

10. **[luaK_exp2nextreg()]** → **exp2reg()** → **discharge2reg()**

11. **[进入 discharge2reg()]** (e->k = VKFLT)

12. **[discharge2reg()]** 进入 ***VKFLT*** 分支

13. **[discharge2reg()]** 调用 `luaK_float(fs, reg, e->u.nval)`
    - reg = 0
    - nval = 3.14

14. **[进入 luaK_float()]** (FuncState* fs, int reg(0), lua_Number nval(3.14))

15. **[luaK_float()]** 调用 `luaK_codeABC(fs, OP_LOADF, reg, 0, 0)`
    - 将浮点数编码为整数参数
    - 对于 3.14，使用特定的整数编码

16. **[进入 luaK_codeABC()]** (Op=OP_LOADF, A=0, B=encoded_3.14, C=0)

17. **[luaK_codeABC()]** code = CREATE_ABCk(OP_LOADF, 0, encoded, 0, 0)

18. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

19. **[回到 luaK_float()]** 返回

20. **[回到 discharge2reg()]** 返回

21. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令：
```
[0] LOADF     R[0], 3.14
```

数据流总结：
- Token(TK_FLT, nval=3.14) → expdesc(VKFLT, nval=3.14) → 指令 OP_LOADF
```

---

### OP_LOADK

**格式**: iABx
**描述**: `R[A] := K[Bx]` - 从常量表加载值到寄存器
**参数**:
- `A`: 目标寄存器
- `Bx`: 常量表索引（0-131071）

**示例代码**: `local a = "hello"`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "hello" → TK_STRING，seminfo.ts = "hello"

2. **[进入 simpleexp()]** (token: TK_STRING)

3. **[simpleexp()]** 进入 ***TK_STRING*** 分支

4. **[simpleexp()]** 调用 `codestring(ls, v, "hello")`

5. **[进入 codestring()]** (expdesc* v, TString* s("hello"))

6. **[codestring()]** 调用 `init_exp(v, VKSTR, 0)`
    - v->k = VKSTR
    - v->u.strval = s

7. **[回到 simpleexp()]** v->k = VKSTR, v->u.strval = "hello"

8. **[回到 localstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

9. **[进入 luaK_exp2anyreg()]** (e->k = VKSTR)

10. **[luaK_exp2anyreg()]** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

11. **[进入 discharge2reg()]** (e->k = VKSTR)

12. **[discharge2reg()]** 进入 ***VKSTR*** 分支

13. **[discharge2reg()]** 调用 `str2K(fs, e)`

14. **[进入 str2K()]** (expdesc* e)

15. **[str2K()]** 调用 `stringK(fs, e->u.strval)`

16. **[进入 stringK()]** (FuncState* fs, TString* s("hello"))

17. **[stringK()]** 调用 `addk(fs, &key, &val)`

18. **[进入 addk()]** (TValue* key, TValue* val)

19. **[addk()]** 在 fs->f->k 中查找是否已存在
    - 遍历已有常量
    - 未找到 "hello"

20. **[addk()]** 调用 `luaH_newkey(fs->ls->L, fs->f->k, key, val)`
    - 将 "hello" 加入 K 表
    - idx = fs->nk = 0

21. **[addk()]** fs->nk++
    - fs->nk = 1

22. **[addk()]** 返回 idx = 0

23. **[回到 stringK()]** 返回 idx = 0

24. **[回到 str2K()]** 调用 `init_exp(e, VK, idx)`
    - e->k = VK
    - e->u.info = 0

25. **[回到 discharge2reg()]** e->k = VK, e->u.info = 0

26. **[discharge2reg()]** 进入 ***VK*** 分支

27. **[discharge2reg()]** 调用 `luaK_codek(fs, reg, e->u.info)`
    - reg = 0
    - idx = 0

28. **[进入 luaK_codek()]** (FuncState* fs, int reg(0), int idx(0))

29. **[luaK_codek()]** 检查 idx <= MAXARG_Bx（131071）
    - 0 <= 131071，成立

30. **[luaK_codek()]** 调用 `luaK_codeABx(fs, OP_LOADK, reg, idx)`

31. **[进入 luaK_codeABx()]** (Op=OP_LOADK, A=0, Bx=0)

32. **[luaK_codeABx()]** code = CREATE_ABx(OP_LOADK, 0, 0)

33. **[luaK_codeABx()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

34. **[回到 luaK_codek()]** 返回

35. **[回到 discharge2reg()]** 返回

36. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令：
```
[0] LOADK     R[0], K[0]    ; "hello"
```

常量表 K[0] = "hello"

数据流总结：
- Token(TK_STRING, "hello") → expdesc(VKSTR, "hello")
- → expdesc(VK, idx=0) → 指令 OP_LOADK
```

---

### OP_LOADKX

**格式**: iAx (配合 OP_EXTRAARG)
**描述**: `R[A] := K[Ax]` - 从常量表加载超大索引的值
**参数**:
- `A`: 目标寄存器（在 OP_LOADKX 中）
- `Ax`: 常量表超大索引（在 OP_EXTRAARG 中）

**示例代码**: 当常量索引超过 131071 时

**Token 到指令的完整流程**:

```
假设 K 表已有 131072 个常量，现在要加载第 131073 个常量

1. **[str2K()]** 调用 `stringK(fs, e->u.strval)`
    - 返回 idx = 131072

2. **[str2K()]** 调用 `init_exp(e, VK, 131072)`
    - e->k = VK
    - e->u.info = 131072

3. **[discharge2reg()]** e->k = VK, e->u.info = 131072

4. **[discharge2reg()]** 进入 ***VK*** 分支

5. **[discharge2reg()]** 调用 `luaK_codek(fs, reg, 131072)`
    - reg = 0
    - idx = 131072

6. **[进入 luaK_codek()]** (reg=0, idx=131072)

7. **[luaK_codek()]** 检查 idx <= MAXARG_Bx
    - 131072 > 131071，不成立

8. **[luaK_codek()]** 进入需要 LOADKX 的分支

9. **[luaK_codek()]** 调用 `luaK_codeABx(fs, OP_LOADKX, reg, 0)`
    - 生成第一条指令

10. **[进入 luaK_codeABx()]** (Op=OP_LOADKX, A=0, Bx=0)

11. **[luaK_codeABx()]** code = CREATE_ABx(OP_LOADKX, 0, 0)

12. **[luaK_codeABx()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - fs->pc = 100

13. **[回到 luaK_codek()]** 调用 `luaK_codeAx(fs, OP_EXTRAARG, idx)`

14. **[进入 luaK_codeAx()]** (Op=OP_EXTRAARG, Ax=131072)

15. **[luaK_codeAx()]** code = CREATE_Ax(OP_EXTRAARG, 131072)

16. **[luaK_codeAx()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - fs->pc = 101

17. **[回到 luaK_codek()]** 返回

18. **[回到 discharge2reg()]** 返回

最终生成的指令：
```
[100] LOADKX    R[0]
[101] EXTRAARG  131072
```

数据流总结：
- 当 idx > MAXARG_Bx 时，使用 LOADKX + EXTRAARG 组合
- 第一条指令 LOADKX 指定目标寄存器
- 第二条指令 EXTRAARG 提供完整的 25 位常量索引
```

---

### OP_LOADFALSE

**格式**: iABC
**描述**: `R[A] := false` - 加载 false 到寄存器
**参数**:
- `A`: 目标寄存器
- `B`, `C`: 未使用（0）

**示例代码**: `local a = false`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "false" → TK_FALSE

2. **[进入 simpleexp()]** (token: TK_FALSE)

3. **[simpleexp()]** 进入 ***TK_FALSE*** 分支

4. **[simpleexp()]** 调用 `init_exp(v, VFALSE, 0)`
    - v->k = VFALSE

5. **[simpleexp()]** 调用 luaX_next(ls)

6. **[回到 localstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

7. **[进入 luaK_exp2anyreg()]** (e->k = VFALSE)

8. **[luaK_exp2anyreg()]** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

9. **[进入 discharge2reg()]** (e->k = VFALSE)

10. **[discharge2reg()]** 进入 ***VFALSE*** 分支

11. **[discharge2reg()]** 调用 `luaK_codeABC(fs, OP_LOADFALSE, reg, 0, 0)`
    - reg = 0

12. **[进入 luaK_codeABC()]** (Op=OP_LOADFALSE, A=0, B=0, C=0)

13. **[luaK_codeABC()]** code = CREATE_ABCk(OP_LOADFALSE, 0, 0, 0, 0)

14. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

15. **[回到 discharge2reg()]** 返回

16. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令：
```
[0] LOADFALSE R[0]
```

数据流总结：
- Token(TK_FALSE) → expdesc(VFALSE) → 指令 OP_LOADFALSE
```

---

### OP_LFALSESKIP

**格式**: iABC
**描述**: `R[A] := false; pc++` - 加载 false 并跳过下一条指令
**参数**:
- `A`: 目标寄存器
- `B`, `C`: 未使用（0）

**示例代码**: `local a = not b`（当 b 不是常量时）

**Token 到指令的完整流程**:

```
假设 b 是一个局部变量

1. **[词法分析]** "not" → TK_NOT，"b" → TK_NAME

2. **[进入 subexpr()]** (token: TK_NOT)

3. **[subexpr()]** 调用 `getunopr(ls->t.token)`
    - token 是 TK_NOT
    - 返回 OPR_NOT

4. **[subexpr()]** uop = OPR_NOT，进入一元运算符分支

5. **[subexpr()]** 调用 luaX_next(ls)
    - token 前移到 { b : TK_NAME }

6. **[subexpr()]** 调用 `subexpr(ls, v, UNARY_PRIORITY)`
    - UNARY_PRIORITY = 12

7. **[进入 subexpr()]** (priority=12) 递归解析 b

8. **[subexpr()]** → **simpleexp()** → **singlevar()**
    - b 是局部变量，vidx = 1
    - v->k = VLOCAL
    - v->u.var.vidx = 1

9. **[回到上层 subexpr()]** 调用 `luaK_prefix(ls->fs, OPR_NOT, v, line)`

10. **[进入 luaK_prefix()]** (BinOpr op=OPR_NOT, expdesc* v)

11. **[luaK_prefix()]** op == OPR_NOT，进入 ***OPR_NOT*** 分支

12. **[luaK_prefix()]** 调用 `codenot(fs, v)`

13. **[进入 codenot()]** (expdesc* v, v->k=VLOCAL)

14. **[codenot()]** 调用 `luaK_goiffalse(fs, v)`

15. **[进入 luaK_goiffalse()]** (expdesc* v)

16. **[luaK_goiffalse()]** v->k != VJMP，调用 `jumpcode(fs, v, 0)`
    - 参数 0 表示 false

17. **[进入 jumpcode()]** (expdesc* v, int flag(0))

18. **[jumpcode()]** v->k = VLOCAL，需要生成测试指令

19. **[jumpcode()]** 调用 `luaK_dischargevars(fs, v)`
    - v->k = VNONRELOC
    - v->u.info = 1

20. **[jumpcode()]** 调用 `jumponreg(fs, v->u.info, flag)`

21. **[进入 jumponreg()]** (int reg(1), int flag(0))

22. **[jumponreg()]** flag == 0（false），调用 `luaK_codeABC(fs, OP_LFALSESKIP, reg, 0, 0)`

23. **[进入 luaK_codeABC()]** (Op=OP_LFALSESKIP, A=1, B=0, C=0)

24. **[luaK_codeABC()]** code = CREATE_ABCk(OP_LFALSESKIP, 1, 0, 0, 0)

25. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - pc = 10

26. **[回到 jumponreg()]** 调用 `luaK_codeAsJ(fs, OP_JMP, 0, 0)`

27. **[进入 luaK_codeAsJ()]** (Op=OP_JMP, sJ=0)

28. **[luaK_codeAsJ()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - pc = 11

29. **[回到 jumponreg()]** 返回 pc = 11

30. **[回到 jumpcode()]** 返回 pc = 11

31. **[回到 luaK_goiffalse()]** 返回 pc = 11

32. **[回到 codenot()]** 调用 `luaK_patchtohere(fs, v->f)`
    - v->f = 11（false 列表）

33. **[codenot()]** 交换 v->t 和 v->f
    - v->t = 11（跳转到 false，即值为 true）
    - v->f = NO_JUMP

34. **[codenot()]** 返回

35. **[回到 luaK_prefix()]** 返回

36. **[回到 subexpr()]** v->k = VJMP, v->t = 11, v->f = NO_JUMP

37. **[回到 localstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

38. **[进入 luaK_exp2anyreg()]** (v->k = VJMP)

39. **[luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, v)`

40. **[进入 luaK_exp2nextreg()]** (v->k = VJMP)

41. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, v, fs->freereg)`
    - reg = 0

42. **[进入 exp2reg()]** (v->k = VJMP)

43. **[exp2reg()]** v->k = VJMP，有跳转

44. **[exp2reg()]** 调用 `luaK_discharge2reg(fs, v, reg)`

45. **[进入 luaK_discharge2reg()]** (v->k = VJMP, reg=0)

46. **[luaK_discharge2reg()]** v->k = VJMP

47. **[luaK_discharge2reg()]** 调用 `patchlistaux(fs, v->f, NO_JUMP, reg, v->t)`
    - v->f = NO_JUMP
    - v->t = 11

48. **[luaK_discharge2reg()]** 调用 `luaK_codeABC(fs, OP_LOADTRUE, reg, 0, 0)`
    - reg = 0

49. **[进入 luaK_codeABC()]** (Op=OP_LOADTRUE, A=0, B=0, C=0)

50. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - pc = 12

51. **[luaK_discharge2reg()]** 调用 `luaK_patchtohere(fs, v->t)`
    - v->t = 11

52. **[luaK_discharge2reg()]** 调用 `init_exp(v, VNONRELOC, reg)`
    - v->k = VNONRELOC
    - v->u.info = 0

53. **[回到 exp2reg()]** 返回 reg = 0

54. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令：
```
[10] LFALSESKIP R[1]    ; 测试 R[1]，如果 false 则跳过下一条
[11] JMP               ; 跳转到 [13]
[12] LOADTRUE   R[0]    ; b 为 false 时，a = true
[13] ...              ; b 为 true 时，a = false（由 LFALSESKIP 设置）
```

数据流总结：
- Token(TK_NOT) + VLOCAL → VJMP（带跳转列表）
- → LFALSESKIP + JMP + LOADTRUE 组合
```

---

### OP_LOADTRUE

**格式**: iABC
**描述**: `R[A] := true` - 加载 true 到寄存器
**参数**:
- `A`: 目标寄存器
- `B`, `C`: 未使用（0）

**示例代码**: `local a = true`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "true" → TK_TRUE

2. **[进入 simpleexp()]** (token: TK_TRUE)

3. **[simpleexp()]** 进入 ***TK_TRUE*** 分支

4. **[simpleexp()]** 调用 `init_exp(v, VTRUE, 0)`
    - v->k = VTRUE

5. **[回到 localstat()]** → **adjust_assign()** → **luaK_exp2anyreg()**

6. **[进入 luaK_exp2anyreg()]** (e->k = VTRUE)

7. **[luaK_exp2anyreg()]** → **luaK_exp2nextreg()** → **exp2reg()** → **discharge2reg()**

8. **[进入 discharge2reg()]** (e->k = VTRUE)

9. **[discharge2reg()]** 进入 ***VTRUE*** 分支

10. **[discharge2reg()]** 调用 `luaK_codeABC(fs, OP_LOADTRUE, reg, 0, 0)`
    - reg = 0

11. **[进入 luaK_codeABC()]** (Op=OP_LOADTRUE, A=0, B=0, C=0)

12. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

13. **[回到 discharge2reg()]** 返回

14. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令：
```
[0] LOADTRUE  R[0]
```

数据流总结：
- Token(TK_TRUE) → expdesc(VTRUE) → 指令 OP_LOADTRUE
```

---

### OP_LOADNIL

**格式**: iABC
**描述**: `R[A], R[A+1], ..., R[A+B] := nil` - 将连续寄存器设为 nil
**参数**:
- `A`: 起始寄存器
- `B`: 数量（从 A 到 A+B 都设为 nil）

**示例代码**: `local a, b, c = nil`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "nil" → TK_NIL

2. **[进入 localstat()]** 处理多个变量声明

3. **[localstat()]** do-while 循环处理变量列表
    - 第1次：new_localvar(ls, "a")，vidx = 0
    - 第2次：new_localvar(ls, "b")，vidx = 1
    - 第3次：new_localvar(ls, "c")，vidx = 2

4. **[localstat()]** nvars = 3

5. **[localstat()]** 调用 `testnext(ls, '=')`
    - 当前 token 是 '='

6. **[localstat()]** 调用 `nexps = explist(ls, &e)`

7. **[进入 explist()]** (token: TK_NIL)

8. **[explist()]** → **expr()** → **subexpr()** → **simpleexp()**

9. **[进入 simpleexp()]** (token: TK_NIL)

10. **[simpleexp()]** 进入 ***TK_NIL*** 分支

11. **[simpleexp()]** 调用 `init_exp(v, VNIL, 0)`
    - v->k = VNIL

12. **[回到 explist()]** n = 1

13. **[回到 localstat()]** nexps = 1, nvars = 3

14. **[localstat()]** 调用 `adjust_assign(ls, 3, 1, &e)`

15. **[进入 adjust_assign()]** (nvars=3, nexps=1)

16. **[adjust_assign()]** nvars > nexps，需要设置多余的变量为 nil

17. **[adjust_assign()]** 调用 `luaK_setoneret(fs, e)`

18. **[adjust_assign()]** 调用 `setvararg(fs, nvars - nexps)`
    - 处理多余的变量

19. **[adjust_assign()]** 调用 `luaK_setreturns(fs, e, nvars)`

20. **[进入 luaK_setreturns()]** (e->k=VNIL, nresults=3)

21. **[luaK_setreturns()]** e->k == VNIL，不需要额外处理

22. **[回到 adjust_assign()]** 调用 `luaK_exp2nextreg(fs, e)`

23. **[进入 luaK_exp2nextreg()]** (e->k=VNIL)

24. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg)`
    - reg = 0

25. **[进入 exp2reg()]** (e->k=VNIL, reg=0)

26. **[exp2reg()]** 调用 `discharge2reg(fs, e, reg)`

27. **[进入 discharge2reg()]** (e->k=VNIL, reg=0)

28. **[discharge2reg()]** 进入 ***VNIL*** 分支

29. **[discharge2reg()]** 调用 `luaK_nil(fs, reg, nvars)`
    - reg = 0
    - n = 3

30. **[进入 luaK_nil()]** (FuncState* fs, int from(0), int n(3))

31. **[luaK_nil()]** 调用 `previousinstruction(fs)`

32. **[previousinstruction()]** 返回 &fs->f->code[fs->pc - 1]
    - 检查前一条指令是否可以合并

33. **[luaK_nil()]** 前一条指令不是 LOADNIL 或无法合并

34. **[luaK_nil()]** 调用 `luaK_codeABC(fs, OP_LOADNIL, from, n-1, 0)`
    - from = 0
    - n - 1 = 2

35. **[进入 luaK_codeABC()]** (Op=OP_LOADNIL, A=0, B=2, C=0)

36. **[luaK_codeABC()]** code = CREATE_ABCk(OP_LOADNIL, 0, 2, 0, 0)
    - A=0（起始寄存器）
    - B=2（从 R[0] 到 R[2] 共 3 个）

37. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

38. **[回到 luaK_nil()]** 返回

39. **[回到 discharge2reg()]** 返回

40. **[回到 exp2reg()]** 调用 `init_exp(e, VNONRELOC, reg)`
    - e->k = VNONRELOC
    - e->u.info = 0

41. **[回到 luaK_exp2nextreg()]** 调用 `luaK_reserveregs(fs, nvars)`
    - fs->freereg += 3
    - fs->freereg = 3

42. **[回到 localstat()]** 调用 `adjustlocalvars(ls, 3)`
    - 为 a, b, c 分配寄存器 0, 1, 2

最终生成的指令：
```
[0] LOADNIL   R[0], R[2]    ; R[0]=nil, R[1]=nil, R[2]=nil
```

数据流总结：
- Token(TK_NIL) → expdesc(VNIL) → OP_LOADNIL（带多个寄存器）
- 优化：连续的 LOADNIL 指令会合并
```

---

## 2. 上值操作指令

### OP_GETUPVAL

**格式**: iABC
**描述**: `R[A] := UpValue[B]` - 从上值表加载值到寄存器
**参数**:
- `A`: 目标寄存器
- `B`: 上值索引
- `C`: 未使用（0）

**示例代码**:
```lua
-- 外层函数
local function outer()
    local x = 10
    -- 内层函数
    return function()
        return x  -- 访问上值 x
    end
end
```

**Token 到指令的完整流程**:

```
假设在外层函数中 x 是第 2 个局部变量（vidx=1）
内层函数需要访问 x，它成为内层函数的第 1 个上值

1. **[内层函数中]** "x" → TK_NAME

2. **[simpleexp()]** → **singlevar()**

3. **[进入 singlevar()]** (varname="x")

4. **[singlevar()]** 调用 `singlevaraux(fs, "x", &var, 1)`

5. **[进入 singlevaraux()]** (FuncState* fs(内层), TString* "x")

6. **[singlevaraux()]** 调用 `searchvar(fs, "x", &aux)`
    - 在内层函数的局部变量中查找
    - 未找到

7. **[singlevaraux()]** 返回 0，未在局部变量中找到

8. **[singlevaraux()]** base == 1，继续在上层函数中查找

9. **[singlevaraux()]** fs->prev != NULL，有外层函数

10. **[singlevaraux()]** 调用 `singlevaraux(fs->prev, "x", &var, 0)`
    - 递归在外层函数中查找

11. **[进入 singlevaraux()]** (FuncState* fs(外层), base=0)

12. **[singlevaraux()]** 调用 `searchvar(fs, "x", &aux)`
    - 在外层函数的局部变量中查找
    - 在 vidx=1 处找到 x

13. **[singlevaraux()]** 找到局部变量

14. **[singlevaraux()]** base == 0，需要创建上值

15. **[singlevaraux()]** 调用 `newupvalue(fs, "x", vidx, var)`

16. **[进入 newupvalue()]** (FuncState* fs(内层), TString* "x", int vidx(1))

17. **[newupvalue()]** 检查是否已存在同名上值
    - 遍历 fs->upvalues

18. **[newupvalue()]** 未找到，创建新上值

19. **[newupvalue()]** idx = fs->nups = 0

20. **[newupvalue()]** 设置 upval[idx]
    - upval->instack = 1（在外层函数栈上）
    - upval->idx = vidx = 1（外层函数中的局部变量索引）
    - upval->kind = VLOCAL
    - upval->name = "x"

21. **[newupvalue()]** fs->nups++
    - fs->nups = 1

22. **[newupvalue()]** 返回 idx = 0

23. **[回到 singlevaraux()]** 调用 `init_exp(var, VUPVAL, idx)`
    - var->k = VUPVAL
    - var->u.info = 0（上值索引）

24. **[回到 singlevar()]** 返回

25. **[回到 simpleexp()]** var->k = VUPVAL, var->u.info = 0

26. **[回到 expr()]** var->k = VUPVAL

27. **[回到 explist()]** n = 1

28. **[回到 retstat()]** 处理 return x

29. **[retstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

30. **[进入 luaK_exp2anyreg()]** (e->k = VUPVAL)

31. **[luaK_exp2anyreg()]** 调用 `luaK_dischargevars(fs, e)`

32. **[进入 luaK_dischargevars()]** (e->k = VUPVAL)

33. **[luaK_dischargevars()]** 进入 ***VUPVAL*** 分支

34. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETUPVAL, 0, e->u.info, 0)`
    - A = 0（目标寄存器，稍后填充）
    - B = 0（上值索引）
    - C = 0

35. **[进入 luaK_codeABC()]** (Op=OP_GETUPVAL, A=0, B=0, C=0)

36. **[luaK_codeABC()]** code = CREATE_ABCk(OP_GETUPVAL, 0, 0, 0, 0)

37. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - pc = 5

38. **[luaK_dischargevars()]** 调用 `init_exp(e, VRELOC, pc)`
    - e->k = VRELOC
    - e->u.info = 5

39. **[回到 luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

40. **[进入 luaK_exp2nextreg()]** (e->k = VRELOC)

41. **[luaK_exp2nextreg()]** 调用 `exp2reg(fs, e, fs->freereg)`
    - reg = 0

42. **[进入 exp2reg()]** (e->k = VRELOC, reg=0)

43. **[exp2reg()]** e->k = VRELOC，需要重定位

44. **[exp2reg()]** 调用 `discharge2reg(fs, e, reg)`

45. **[进入 discharge2reg()]** (e->k = VRELOC, reg=0)

46. **[discharge2reg()]** e->k = VRELOC

47. **[discharge2reg()]** pc = e->u.info = 5

48. **[discharge2reg()]** 调用 `SETARG_A(fs->f->code[pc], reg)`
    - 将指令 [5] 的参数 A 设为 0

49. **[discharge2reg()]** 调用 `init_exp(e, VNONRELOC, reg)`
    - e->k = VNONRELOC
    - e->u.info = 0

50. **[回到 exp2reg()]** 返回 reg = 0

51. **[回到 luaK_exp2nextreg()]** fs->freereg++

最终生成的指令（内层函数）：
```
[5] GETUPVAL  R[0], U[0]    ; 从上值 U[0]（即外层的 x）加载到 R[0]
```

上值表 U[0] 指向外层函数的局部变量 x（vidx=1）

数据流总结：
- 在内层函数中访问外层变量 x
- 在内层函数的 upvalues 表中创建条目
- var->k = VUPVAL, var->u.info = 0
- → VRELOC（指令已生成，A 待填充）
- → VNONRELOC（A 填充为 0）
```

---

### OP_SETUPVAL

**格式**: iABC
**描述**: `UpValue[B] := R[A]` - 将寄存器的值存储到上值
**参数**:
- `A`: 源寄存器
- `B`: 上值索引
- `C`: 未使用（0）

**示例代码**:
```lua
local function outer()
    local x = 10
    return function()
        x = 20  -- 修改上值
    end
end
```

**Token 到指令的完整流程**:

```
1. **[词法分析]** "x" → TK_NAME，"=" → '='，"20" → TK_INT

2. **[进入 statlist()]** → **statement()** → **exprstat()**

3. **[进入 exprstat()]** (token: TK_NAME)

4. **[exprstat()]** → **primaryexp()** → **suffixedexp()** → **simpleexp()** → **singlevar()**

5. **[singlevar()]** → **singlevaraux()**
    - 找到上值 x
    - var->k = VUPVAL
    - var->u.info = 0

6. **[回到 suffixedexp()]** 没有 '.' 或 '['，返回

7. **[回到 exprstat()]** 调用 `check(ls, '=')`
    - 当前 token 是 '='

8. **[exprstat()]** 调用 luaX_next(ls)
    - token 前移到 { 20 : TK_INT }

9. **[exprstat()]** 调用 `expr(ls, &v2)`

10. **[expr()]** → **subexpr()** → **simpleexp()**
    - v2->k = VKINT
    - v2->u.ival = 20

11. **[回到 exprstat()]** var->k = VUPVAL, v2->k = VKINT

12. **[exprstat()]** 调用 `luaK_exp2nextreg(fs, &v2)`

13. **[luaK_exp2nextreg()]** → **exp2reg()** → **discharge2reg()**
    - v2->k = VNONRELOC
    - v2->u.info = 0（20 在 R[0]）

14. **[exprstat()]** 调用 `luaK_storevar(fs, &var, &v2)`

15. **[进入 luaK_storevar()]** (var->k=VUPVAL, expdesc* v2)

16. **[luaK_storevar()]** var->k == VUPVAL

17. **[luaK_storevar()]** 调用 `luaK_codeABC(fs, OP_SETUPVAL, v2->u.info, var->u.info, 0)`
    - A = v2->u.info = 0（源寄存器）
    - B = var->u.info = 0（上值索引）
    - C = 0

18. **[进入 luaK_codeABC()]** (Op=OP_SETUPVAL, A=0, B=0, C=0)

19. **[luaK_codeABC()]** code = CREATE_ABCk(OP_SETUPVAL, 0, 0, 0, 0)

20. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

21. **[回到 luaK_storevar()]** 返回

22. **[回到 exprstat()]** 返回

最终生成的指令：
```
[0] LOADI     R[0], 20
[1] SETUPVAL  R[0], U[0]    ; 将 R[0] 的值存储到上值 U[0]（即外层的 x）
```

数据流总结：
- 左值 var->k = VUPVAL（上值 x）
- 右值 v2->k = VKINT → VNONRELOC（值 20 在 R[0]）
- → OP_SETUPVAL 指令
```

---

## 3. 表访问指令

### OP_GETTABUP

**格式**: iABC
**描述**: `R[A] := UpValue[B][K[C]:shortstring]` - 从上值表中获取字段
**参数**:
- `A`: 目标寄存器
- `B`: 上值索引（通常是 _ENV，即 0）
- `C`: 字段名在常量表中的索引

**示例代码**: `local a = t.x`（t 是全局变量，即 _ENV.t）

**Token 到指令的完整流程**:

```
1. **[词法分析]** "t" → TK_NAME，"." → '.', "x" → TK_NAME

2. **[进入 suffixedexp()]** (token: TK_NAME)

3. **[suffixedexp()]** → **simpleexp()** → **singlevar()**

4. **[进入 singlevar()]** (varname="t")

5. **[singlevar()]** → **singlevaraux(fs, "t", &var, 1)**

6. **[进入 singlevaraux()]** (FuncState* fs, TString* "t", base=1)

7. **[singlevaraux()]** 调用 `searchvar(fs, "t", &aux)`
    - 在当前函数的局部变量中查找
    - 未找到

8. **[singlevaraux()]** base == 1，继续查找

9. **[singlevaraux()]** fs->prev == NULL（main 函数，无外层）

10. **[singlevaraux()]** 调用 `singlevaraux(fs, "_ENV", &var, 1)`
    - 查找 _ENV 上值

11. **[进入 singlevaraux()]** (varname="_ENV")

12. **[singlevaraux()]** 调用 `searchvar(fs, "_ENV", &aux)`
    - 未在局部变量中找到

13. **[singlevaraux()]** base == 1，继续

14. **[singlevaraux()]** fs->prev == NULL

15. **[singlevaraux()]** 返回 0（未找到）

16. **[回到上层 singlevaraux()]** 调用 `init_exp(var, VVOID, 0)`
    - var->k = VVOID（全局变量）

17. **[回到 singlevar()]** var->k == VVOID

18. **[singlevar()]** 调用 `singlevaraux(fs, "_ENV", &var, 1)`
    - 再次查找 _ENV

19. **[singlevaraux()]** 在上值中找到 _ENV
    - _ENV 是第 1 个上值
    - 返回 VUPVAL, u.info = 0

20. **[回到 singlevar()]** var->k = VUPVAL, var->u.info = 0

21. **[singlevar()]** 调用 `luaK_exp2anyregup(fs, var)`

22. **[进入 luaK_exp2anyregup()]** (var->k=VUPVAL)

23. **[luaK_exp2anyregup()]** 返回（上值不需要放在寄存器中）

24. **[回到 suffixedexp()]** 当前 token 是 '.'

25. **[suffixedexp()]** 调用 `fieldsel(ls, v)`

26. **[进入 fieldsel()]** (expdesc* v, v->k=VUPVAL)

27. **[fieldsel()]** 调用 luaX_next(ls)
    - token 前移到 { x : TK_NAME }

28. **[fieldsel()]** 调用 `codename(ls, &key)`

29. **[进入 codename()]** (expdesc* key)

30. **[codename()]** 调用 `singlevar(ls, key)`
    - 查找 "x" 作为变量

31. **[singlevar()]** → **singlevaraux()**
    - 未在局部变量中找到
    - 返回 VVOID

32. **[回到 codename()]** key->k = VVOID

33. **[codename()]** 调用 `luaK_exp2str(fs, key)`

34. **[进入 luaK_exp2str()]** (key->k=VVOID)

35. **[luaK_exp2str()]** 调用 `luaK_exp2const(fs, key, &kv)`

36. **[luaK_exp2const()]** 将变量名转为字符串常量
    - kv = "x"

37. **[回到 luaK_exp2str()]** 调用 `luaK_stringK(fs, "x")`

38. **[进入 luaK_stringK()]** (TString* "x")

39. **[luaK_stringK()]** → **stringK()** → **addk()**
    - 将 "x" 加入 K 表
    - idx = 1

40. **[回到 luaK_exp2str()]** 调用 `init_exp(key, VK, idx)`
    - key->k = VK
    - key->u.info = 1

41. **[回到 fieldsel()]** key->k = VK, key->u.info = 1

42. **[fieldsel()]** 调用 `luaK_indexed(fs, v, key)`

43. **[进入 luaK_indexed()]** (v->k=VUPVAL, key->k=VK)

44. **[luaK_indexed()]** v->k = VUPVAL

45. **[luaK_indexed()]** key->k = VK

46. **[luaK_indexed()]** 进入 ***VUPVAL + VK*** 分支

47. **[luaK_indexed()]** 调用 `init_exp(v, VINDEXUP, 0)`
    - v->k = VINDEXUP
    - v->u.ind.t = v->u.info = 0（_ENV 的上值索引）
    - v->u.ind.idx = key->u.info = 1（"x" 在 K 表中的索引）

48. **[回到 suffixedexp()]** v->k = VINDEXUP

49. **[回到 exprstat()]** 或回到赋值语句处理

50. **[回到 localstat()]** 假设是 `local a = t.x`

51. **[localstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

52. **[进入 luaK_exp2anyreg()]** (e->k=VINDEXUP)

53. **[luaK_exp2anyreg()]** 调用 `luaK_dischargevars(fs, e)`

54. **[进入 luaK_dischargevars()]** (e->k=VINDEXUP)

55. **[luaK_dischargevars()]** 进入 ***VINDEXUP*** 分支

56. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETTABUP, 0, e->u.ind.t, e->u.ind.idx)`
    - A = 0（目标寄存器，稍后填充）
    - B = e->u.ind.t = 0（_ENV 的上值索引）
    - C = e->u.ind.idx = 1（"x" 的 K 表索引）

57. **[进入 luaK_codeABC()]** (Op=OP_GETTABUP, A=0, B=0, C=1)

58. **[luaK_codeABC()]** code = CREATE_ABCk(OP_GETTABUP, 0, 0, 1, 0)

59. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]
    - pc = 10

60. **[luaK_dischargevars()]** 调用 `init_exp(e, VRELOC, pc)`
    - e->k = VRELOC
    - e->u.info = 10

61. **[回到 luaK_exp2anyreg()]** 调用 `luaK_exp2nextreg(fs, e)`

62. **[luaK_exp2nextreg()]** → **exp2reg()** → **discharge2reg()**

63. **[discharge2reg()]** e->k = VRELOC, pc = 10, reg = 0

64. **[discharge2reg()]** 调用 `SETARG_A(fs->f->code[10], 0)`
    - 将指令 [10] 的参数 A 设为 0

65. **[discharge2reg()]** 调用 `init_exp(e, VNONRELOC, 0)`

66. **[回到 luaK_exp2anyreg()]** 返回 0

最终生成的指令：
```
[10] GETTABUP  R[0], U[0], K[1]    ; R[0] = _ENV["x"]
```

K[1] = "x"

数据流总结：
- "t.x" → VUPVAL(_ENV) + VK("x")
- → VINDEXUP(t=0, idx=1)
- → VRELOC(pc=10)
- → VNONRELOC(reg=0)
- 指令：GETTABUP R[0], U[0], K[1]
```

---

### OP_GETTABLE

**格式**: iABC
**描述**: `R[A] := R[B][R[C]]` - 从表中获取值（键在寄存器中）
**参数**:
- `A`: 目标寄存器
- `B`: 表寄存器
- `C`: 键寄存器

**示例代码**: `local a = t[k]`（t 和 k 都是局部变量）

**Token 到指令的完整流程**:

```
假设 t 在寄存器 0，k 在寄存器 1

1. **[词法分析]** "t" → TK_NAME，"[" → '[', "k" → TK_NAME, "]" → ']'

2. **[进入 suffixedexp()]** (token: TK_NAME)

3. **[suffixedexp()]** → **simpleexp()** → **singlevar()**

4. **[singlevar()]** 找到 t 是局部变量
    - v->k = VLOCAL
    - v->u.var.vidx = 0

5. **[回到 suffixedexp()]** 当前 token 是 '['

6. **[suffixedexp()]** 调用 `yindex(ls, v)`

7. **[进入 yindex()]** (expdesc* v)

8. **[yindex()]** 调用 luaX_next(ls)
    - token 前移到 { k : TK_NAME }

9. **[yindex()]** 调用 `expr(ls, &key)`

10. **[expr()]** → **subexpr()** → **simpleexp()** → **singlevar()**

11. **[singlevar()]** 找到 k 是局部变量
    - key->k = VLOCAL
    - key->u.var.vidx = 1

12. **[回到 yindex()]** 调用 `checknext(ls, ']')`
    - 当前 token 是 ']'

13. **[yindex()]** 调用 `luaK_indexed(fs, v, &key)`

14. **[进入 luaK_indexed()]** (v->k=VLOCAL, key->k=VLOCAL)

15. **[luaK_indexed()]** 调用 `luaK_exp2anyreg(fs, v)`
    - v->k = VNONRELOC
    - v->u.info = 0

16. **[luaK_indexed()]** 调用 `luaK_exp2anyreg(fs, &key)`
    - key->k = VNONRELOC
    - key->u.info = 1

17. **[luaK_indexed()]** 进入 ***VNONRELOC + VNONRELOC*** 分支

18. **[luaK_indexed()]** 调用 `init_exp(v, VINDEXED, 0)`
    - v->k = VINDEXED
    - v->u.ind.t = 0（表的寄存器）
    - v->u.ind.idx = 1（键的寄存器）

19. **[回到 suffixedexp()]** v->k = VINDEXED

20. **[回到 localstat()]** 假设是 `local a = t[k]`

21. **[localstat()]** → **adjust_assign()** → **luaK_setoneret()** → **luaK_exp2anyreg()**

22. **[luaK_exp2anyreg()]** → **luaK_dischargevars()**

23. **[luaK_dischargevars()]** e->k = VINDEXED

24. **[luaK_dischargevars()]** 进入 ***VINDEXED*** 分支

25. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETTABLE, 0, e->u.ind.t, e->u.ind.idx)`
    - A = 0（目标寄存器）
    - B = e->u.ind.t = 0（表寄存器）
    - C = e->u.ind.idx = 1（键寄存器）

26. **[luaK_codeABC()]** code = CREATE_ABCk(OP_GETTABLE, 0, 0, 1, 0)

27. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

最终生成的指令：
```
[10] GETTABLE  R[0], R[0], R[1]    ; R[0] = R[0][R[1]]
```

数据流总结：
- "t[k]" → VLOCAL(t) + VLOCAL(k)
- → VNONRELOC(t=0) + VNONRELOC(k=1)
- → VINDEXED(t=0, idx=1)
- → OP_GETTABLE
```

---

### OP_GETI

**格式**: iABC
**描述**: `R[A] := R[B][C]` - 从表中获取值（整数键）
**参数**:
- `A`: 目标寄存器
- `B`: 表寄存器
- `C`: 整数键

**示例代码**: `local a = t[3]`

**Token 到指令的完整流程**:

```
1. **[词法分析]** "t" → TK_NAME，"[" → '[', "3" → TK_INT, "]" → ']'

2. **[suffixedexp()]** → **yindex()**

3. **[yindex()]** 调用 `expr(ls, &key)`

4. **[expr()]** → **simpleexp()**

5. **[simpleexp()]** 进入 ***TK_INT*** 分支

6. **[simpleexp()]** 调用 `init_exp(v, VKINT, 0)`
    - key->k = VKINT
    - key->u.ival = 3

7. **[回到 yindex()]** key->k = VKINT

8. **[yindex()]** 调用 `luaK_indexed(fs, v, &key)`

9. **[luaK_indexed()]** v->k = VNONRELOC, v->u.info = 0（t 在 R[0]）

10. **[luaK_indexed()]** key->k = VKINT, key->u.ival = 3

11. **[luaK_indexed()]** 检查 key->k == VKINT

12. **[luaK_indexed()]** 检查 -MAXARG_C <= key->u.ival <= MAXARG_C
    - -255 <= 3 <= 255，成立

13. **[luaK_indexed()]** 进入 ***VNONRELOC + VKINT*** 分支

14. **[luaK_indexed()]** 调用 `init_exp(v, VINDEXI, 0)`
    - v->k = VINDEXI
    - v->u.ind.t = 0（表寄存器）
    - v->u.ind.idx = 3（整数键）

15. **[回到 yindex()]** 返回

16. **[回到 localstat()]** → **luaK_dischargevars()**

17. **[luaK_dischargevars()]** e->k = VINDEXI

18. **[luaK_dischargevars()]** 进入 ***VINDEXI*** 分支

19. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETI, 0, e->u.ind.t, e->u.ind.idx)`
    - A = 0
    - B = e->u.ind.t = 0
    - C = e->u.ind.idx = 3

20. **[luaK_codeABC()]** code = CREATE_ABCk(OP_GETI, 0, 0, 3, 0)

21. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

最终生成的指令：
```
[10] GETI      R[0], R[0], 3    ; R[0] = R[0][3]
```

数据流总结：
- "t[3]" → VNONRELOC(t) + VKINT(3)
- → VINDEXI(t=0, idx=3)
- → OP_GETI
```

---

### OP_GETFIELD

**格式**: iABC
**描述**: `R[A] := R[B][K[C]:shortstring]` - 从表中获取字段
**参数**:
- `A`: 目标寄存器
- `B`: 表寄存器
- `C`: 字段名在常量表中的索引

**示例代码**: `local a = t.x`（t 是局部变量）

**Token 到指令的完整流程**:

```
1. **[词法分析]** "t" → TK_NAME，"." → '.', "x" → TK_NAME

2. **[suffixedexp()]** → **fieldsel()**

3. **[fieldsel()]** → **codename()**

4. **[codename()]** → **luaK_exp2str()**
    - 将 "x" 加入 K 表
    - key->k = VK
    - key->u.info = 2

5. **[回到 fieldsel()]** 调用 `luaK_indexed(fs, v, &key)`

6. **[luaK_indexed()]** v->k = VNONRELOC, v->u.info = 0（t 在 R[0]）

7. **[luaK_indexed()]** key->k = VK, key->u.info = 2

8. **[luaK_indexed()]** 进入 ***VNONRELOC + VK*** 分支

9. **[luaK_indexed()]** 调用 `init_exp(v, VINDEXSTR, 0)`
    - v->k = VINDEXSTR
    - v->u.ind.t = 0（表寄存器）
    - v->u.ind.idx = 2（"x" 的 K 表索引）

10. **[回到 localstat()]** → **luaK_dischargevars()**

11. **[luaK_dischargevars()]** e->k = VINDEXSTR

12. **[luaK_dischargevars()]** 进入 ***VINDEXSTR*** 分支

13. **[luaK_dischargevars()]** 调用 `luaK_codeABC(fs, OP_GETFIELD, 0, e->u.ind.t, e->u.ind.idx)`
    - A = 0
    - B = e->u.ind.t = 0
    - C = e->u.ind.idx = 2

14. **[luaK_codeABC()]** code = CREATE_ABCk(OP_GETFIELD, 0, 0, 2, 0)

15. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

最终生成的指令：
```
[10] GETFIELD  R[0], R[0], K[2]    ; R[0] = R[0]["x"]
```

数据流总结：
- "t.x" → VNONRELOC(t) + VK("x")
- → VINDEXSTR(t=0, idx=2)
- → OP_GETFIELD
```

---

### OP_SETTABUP

**格式**: iABC
**描述**: `UpValue[A][K[B]:shortstring] := RK(C)` - 设置上值表的字段
**参数**:
- `A`: 上值索引（通常是 _ENV，即 0）
- `B`: 字段名在常量表中的索引
- `C`: 值（寄存器或常量，取决于 k 位）

**示例代码**: `t = {}`（t 是全局变量，即 _ENV.t）

**Token 到指令的完整流程**:

```
1. **[词法分析]** "t" → TK_NAME，"=" → '=', "{" → '{'

2. **[exprstat()]** → **simpleexp()** → **singlevar()**

3. **[singlevar()]** t 是全局变量
    - var->k = VVOID

4. **[singlevar()]** 查找 _ENV
    - env->k = VUPVAL
    - env->u.info = 0

5. **[singlevar()]** 将 t 转为 VINDEXUP
    - var->k = VINDEXUP
    - var->u.ind.t = 0（_ENV）
    - var->u.ind.idx = "t" 的 K 索引（假设为 3）

6. **[exprstat()]** 解析右侧 `{}`

7. **[exprstat()]** → **constructor()**
    - 生成 OP_NEWTABLE
    - t->k = VNONRELOC
    - t->u.info = 0

8. **[exprstat()]** 调用 `luaK_storevar(fs, &var, &t)`

9. **[进入 luaK_storevar()]** (var->k=VINDEXUP, t->k=VNONRELOC)

10. **[luaK_storevar()]** var->k == VINDEXUP

11. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETTABUP, var->u.ind.t, var->u.ind.idx, &t)`

12. **[进入 codeABRK()]** (Op=OP_SETTABUP, A=0, B=3, expdesc* t)

13. **[codeABRK()]** 调用 `luaK_exp2anyreg(fs, t)`
    - t->k = VNONRELOC
    - t->u.info = 0

14. **[codeABRK()]** 调用 `luaK_codeABC(fs, OP_SETTABUP, A, B, t->u.info)`
    - A = 0
    - B = 3
    - C = 0

15. **[luaK_codeABC()]** code = CREATE_ABCk(OP_SETTABUP, 0, 3, 0, 0)

16. **[luaK_codeABC()]** → **luaK_code()** → 写入 fs->f->code[fs->pc]

最终生成的指令：
```
[0] NEWTABLE  R[0]
[1] SETTABUP  U[0], K[3], R[0]    ; _ENV["t"] = R[0]
```

数据流总结：
- "t = {}" → 左值 VINDEXUP，右值 VNONRELOC
- → OP_NEWTABLE + OP_SETTABUP
```

---

### OP_SETTABLE

**格式**: iABC
**描述**: `R[A][R[B]] := RK(C)` - 设置表的元素（键在寄存器中）
**参数**:
- `A`: 表寄存器
- `B`: 键寄存器
- `C`: 值（寄存器或常量）

**示例代码**: `t[k] = v`（t, k, v 都是局部变量）

**Token 到指令的完整流程**:

```
1. **[exprstat()]** → **suffixedexp()** 处理 t[k]

2. **[suffixedexp()]** → **yindex()**

3. **[yindex()]** → **luaK_indexed()**
    - t->k = VNONRELOC, t->u.info = 0
    - k->k = VNONRELOC, k->u.info = 1
    - var->k = VINDEXED
    - var->u.ind.t = 0
    - var->u.ind.idx = 1

4. **[exprstat()]** 解析右侧 v
    - v->k = VNONRELOC
    - v->u.info = 2

5. **[exprstat()]** → **luaK_storevar()**

6. **[luaK_storevar()]** var->k == VINDEXED

7. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETTABLE, var->u.ind.t, var->u.ind.idx, &v)`

8. **[codeABRK()]** 调用 `luaK_exp2anyreg(fs, &v)`
    - v->u.info = 2

9. **[codeABRK()]** 调用 `luaK_codeABC(fs, OP_SETTABLE, var->u.ind.t, var->u.ind.idx, v->u.info)`
    - A = 0
    - B = 1
    - C = 2

10. **[luaK_codeABC()]** code = CREATE_ABCk(OP_SETTABLE, 0, 1, 2, 0)

最终生成的指令：
```
[10] SETTABLE  R[0], R[1], R[2]    ; R[0][R[1]] = R[2]
```

数据流总结：
- "t[k] = v" → VINDEXED(t=0, idx=1) + VNONRELOC(v=2)
- → OP_SETTABLE
```

---

### OP_SETI

**格式**: iABC
**描述**: `R[A][B] := RK(C)` - 设置表的元素（整数键）
**参数**:
- `A`: 表寄存器
- `B`: 整数键
- `C`: 值（寄存器或常量）

**示例代码**: `t[3] = "three"`

**Token 到指令的完整流程**:

```
1. **[suffixedexp()]** → **yindex()**

2. **[yindex()]** key->k = VKINT, key->u.ival = 3

3. **[luaK_indexed()]** → VINDEXI
    - var->k = VINDEXI
    - var->u.ind.t = 0
    - var->u.ind.idx = 3

4. **[exprstat()]** 右侧 "three"
    - v->k = VK
    - v->u.info = 4（K 表索引）

5. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETI, var->u.ind.t, var->u.ind.idx, &v)`

6. **[codeABRK()]** 调用 `luaK_exp2RK(fs, &v)`
    - 检查是否可以用常量
    - v->k = VK，可以用
    - 返回 RK 编码（常量索引 + ISK 位）

7. **[codeABRK()]** 调用 `luaK_codeABC(fs, OP_SETI, 0, 3, RK值)`

8. **[luaK_codeABC()]** code = CREATE_ABCk(OP_SETI, 0, 3, RK, k)

最终生成的指令：
```
[10] SETI      R[0], 3, K[4]    ; R[0][3] = K[4]
```

数据流总结：
- "t[3] = "three"" → VINDEXI(t=0, idx=3) + VK("three")
- → OP_SETI
```

---

### OP_SETFIELD

**格式**: iABC
**描述**: `R[A][K[B]:shortstring] := RK(C)` - 设置表的字段
**参数**:
- `A`: 表寄存器
- `B`: 字段名在常量表中的索引
- `C`: 值（寄存器或常量）

**示例代码**: `t.a = 1`

**Token 到指令的完整流程**:

```
1. **[suffixedexp()]** → **fieldsel()**

2. **[fieldsel()]** → **codename()**
    - key->k = VK
    - key->u.info = 5（"a" 在 K 表中的索引）

3. **[luaK_indexed()]** → VINDEXSTR
    - var->k = VINDEXSTR
    - var->u.ind.t = 0
    - var->u.ind.idx = 5

4. **[exprstat()]** 右侧 1
    - v->k = VKINT
    - v->u.ival = 1

5. **[luaK_storevar()]** 调用 `codeABRK(fs, OP_SETFIELD, var->u.ind.t, var->u.ind.idx, &v)`

6. **[codeABRK()]** 调用 `luaK_exp2RK(fs, &v)`
    - v->k = VKINT
    - 检查 |1| <= MAXINDEXRK
    - 可以使用立即数
    - 返回编码值

7. **[codeABRK()]** 调用 `luaK_codeABC(fs, OP_SETFIELD, 0, 5, 编码值)`

最终生成的指令：
```
[10] SETFIELD  R[0], K[5], 1    ; R[0]["a"] = 1
```

数据流总结：
- "t.a = 1" → VINDEXSTR(t=0, idx=5) + VKINT(1)
- → OP_SETFIELD
```

---

（由于文档长度限制，以下是剩余操作码的简化版本，完整流程遵循相同模式）

---

## 4. 表创建指令

### OP_NEWTABLE

**格式**: iABC
**描述**: `R[A] := {}` - 创建新表
**参数**:
- `A`: 目标寄存器
- `B`: 哈希大小（log2 + 1，0 表示大小为 0）
- `C`: 数组大小
- `k`: 是否使用 EXTRAARG

**示例代码**: `local t = {}`

**关键流程**:
```
1. [constructor()] 调用 luaK_codeABC(fs, OP_NEWTABLE, 0, 0, 0)
2. [luaK_codeABC()] 写入指令
3. [constructor()] 初始化 ConsControl
4. [constructor()] 解析表字段
5. [luaK_settablesize()] 根据字段数量修改指令参数
```

**生成指令**: `NEWTABLE R[0], 0, 0`

---

## 5. 函数调用指令

### OP_SELF

**格式**: iABC
**描述**: `R[A+1] := R[B]; R[A] := R[B][RK(C):string]` - 方法调用准备
**参数**:
- `A`: self 值的目标寄存器
- `B`: 表寄存器
- `C`: 方法名（常量索引）

**示例代码**: `t:method(a)`

**关键流程**:
```
1. [suffixedexp()] 进入 ':' 分支
2. [luaK_self()] 调用 luaK_exp2anyregup(fs, v)
3. [luaK_self()] 调用 luaK_codeABC(fs, OP_SELF, 0, 表寄存器, 方法名K索引)
```

**生成指令**: `SELF R[0], R[1], K[2]`

---

### OP_CALL

**格式**: iABC
**描述**: `R[A], ..., R[A+C-2] := R[A](R[A+1], ..., R[A+B-1])` - 函数调用
**参数**:
- `A`: 函数寄存器
- `B`: 参数数量 + 1
- `C`: 返回值数量 + 1

**示例代码**: `add(a, b)`

**关键流程**:
```
1. [funcargs()] 调用 explist(ls, &args)
2. [funcargs()] 调用 luaK_exp2nextreg() 将参数放入寄存器
3. [funcargs()] 计算 nparams = fs->freereg - (base+1)
4. [funcargs()] 调用 luaK_codeABC(fs, OP_CALL, base, nparams+1, 2)
```

**生成指令**: `CALL R[0], 3, 2`

---

### OP_TAILCALL

**格式**: iABC
**描述**: `return R[A](R[A+1], ..., R[A+B-1])` - 尾调用
**参数**: 同 OP_CALL

**示例代码**: `return func(a)`

**关键流程**:
```
1. [retstat()] 检测到尾调用条件
2. [retstat()] 调用 SET_OPCODE(getinstruction(fs,&e), OP_TAILCALL)
```

**生成指令**: `TAILCALL R[0], 2, 0`

---

## 6. 算术运算指令

### OP_ADDI

**格式**: iABC
**描述**: `R[A] := R[B] + sC` - 加整数立即数
**参数**:
- `A`: 目标寄存器
- `B`: 操作数寄存器
- `sC`: 有符号整数立即数

**示例代码**: `local a = b + 2`

**关键流程**:
```
1. [subexpr()] 解析 b + 2
2. [luaK_posfix()] 调用 codecommutative()
3. [codecommutative()] 检测 e2 是整数常量
4. [codecommutative()] 调用 luaK_codeABC(fs, OP_ADDI, e1->u.info, e2->u.ival, 0)
```

**生成指令**: `ADDI R[0], R[1], 2`

---

### OP_ADDK

**格式**: iABC
**描述**: `R[A] := R[B] + K[C]:number` - 加常量
**参数**:
- `A`: 目标寄存器
- `B`: 操作数寄存器
- `C`: 常量索引

**示例代码**: `local a = b + 3.14`

**关键流程**:
```
1. [luaK_posfix()] 调用 codearith(fs, OPR_ADDK, e1, e2, 0, line)
2. [codearith()] 调用 luaK_exp2anyreg(fs, e1) 和 luaK_exp2RK(fs, e2)
3. [codearith()] 调用 luaK_codeABC(fs, OP_ADDK, ...)
```

**生成指令**: `ADDK R[0], R[1], K[2]`

---

### OP_ADD

**格式**: iABC
**描述**: `R[A] := R[B] + R[C]` - 加法
**参数**:
- `A`: 目标寄存器
- `B`: 第一个操作数寄存器
- `C`: 第二个操作数寄存器

**示例代码**: `local a = b + c`

**关键流程**:
```
1. [codecommutative()] 不能使用 ADDI 优化
2. [codecommutative()] 调用 luaK_codeABC(fs, OP_ADD, ...)
```

**生成指令**: `ADD R[0], R[1], R[2]`

---

### 其他算术指令

| 指令 | 描述 | 示例 |
|------|------|------|
| OP_SUB | `R[A] := R[B] - R[C]` | `a = b - c` |
| OP_SUBK | `R[A] := R[B] - K[C]` | `a = b - 1.5` |
| OP_MUL | `R[A] := R[B] * R[C]` | `a = b * c` |
| OP_MULK | `R[A] := R[B] * K[C]` | `a = b * 2.5` |
| OP_MOD | `R[A] := R[B] % R[C]` | `a = b % c` |
| OP_MODK | `R[A] := R[B] % K[C]` | `a = b % 5` |
| OP_POW | `R[A] := R[B] ^ R[C]` | `a = b ^ c` |
| OP_POWK | `R[A] := R[B] ^ K[C]` | `a = b ^ 2` |
| OP_DIV | `R[A] := R[B] / R[C]` | `a = b / c` |
| OP_DIVK | `R[A] := R[B] / K[C]` | `a = b / 2.0` |
| OP_IDIV | `R[A] := R[B] // R[C]` | `a = b // c` |
| OP_IDIVK | `R[A] := R[B] // K[C]` | `a = b // 5` |

---

## 7. 位运算指令

### OP_BANDK, OP_BORK, OP_BXORK

**描述**: 位运算与常量
**示例**: `a & 0xFF`, `a | 0x0F`, `a ~ 0xAA`

**生成指令**: `BANDK R[0], R[1], 255`

---

### OP_SHRI, OP_SHLI

**描述**: `R[A] := R[B] >> sC` 或 `R[A] := sC << R[B]`
**示例**: `a >> 2`, `1 << a`

**关键流程**:
```
1. [codearith()] 检测左操作数是否为常量
2. [codearith()] 如果左操作数是常量，交换操作数
3. [codearith()] 生成 SHRI 或 SHLI 指令
```

**生成指令**: `SHRI R[0], R[1], 2`

---

### OP_BAND, OP_BOR, OP_BXOR, OP_SHL, OP_SHR

**描述**: 基本位运算
**示例**: `a & b`, `a | b`, `a ~ b`, `a << b`, `a >> b`

---

## 8. 一元运算指令

### OP_UNM

**格式**: iABC
**描述**: `R[A] := -R[B]` - 取反
**示例**: `local a = -b`

**关键流程**:
```
1. [subexpr()] getunopr('-') 返回 OPR_MINUS
2. [luaK_prefix()] 调用 codeunexpval(fs, OP_UNM, v, line)
3. [codeunexpval()] 调用 luaK_codeABC(fs, OP_UNM, v->u.info, v->u.info, 0)
```

**生成指令**: `UNM R[0], R[1]`

---

### OP_BNOT

**描述**: `R[A] := ~R[B]` - 按位取反
**示例**: `local a = ~b`

**生成指令**: `BNOT R[0], R[1]`

---

### OP_NOT

**描述**: `R[A] := not R[B]` - 逻辑非
**示例**: `local a = not b`

**关键流程**:
```
1. [luaK_prefix()] 调用 codenot(fs, v)
2. [codenot()] 调用 luaK_codeABC(fs, OP_NOT, ...) 或生成 LFALSESKIP+JMP 组合
```

**生成指令**: `NOT R[0], R[1]`

---

### OP_LEN

**描述**: `R[A] := #R[B]` - 长度运算
**示例**: `local a = #b`

**生成指令**: `LEN R[0], R[1]`

---

## 9. 其他指令

### OP_CONCAT

**描述**: `R[A] := R[A].. ... ..R[A+B-1]` - 字符串连接
**示例**: `s .. " world"`

**关键流程**:
```
1. [luaK_infix()] 调用 luaK_exp2nextreg() 确保左操作数在栈上
2. [luaK_posfix()] 调用 codeconcat(fs, e1, e2, line)
3. [codeconcat()] 调用 luaK_codeABC(fs, OP_CONCAT, ...)
```

**生成指令**: `CONCAT R[0], 2`

---

### OP_CLOSE

**描述**: 关闭所有 >= R[A] 的上值
**示例**: 函数返回前关闭 upvalue

---

### OP_JMP

**格式**: isJ
**描述**: `pc += sJ` - 跳转
**示例**: 条件跳转、循环控制

**关键流程**:
```
1. [luaK_jump()] 调用 luaK_codeAsJ(fs, OP_JMP, 0, 0)
2. [fixjump()] 修改跳转目标
```

---

### OP_EQ, OP_LT, OP_LE

**描述**: 比较指令
**示例**: `a > b`, `a == c`

**关键流程**:
```
1. [luaK_posfix()] 调用 codecompare()
2. [codecompare()] 生成对应的比较指令（可能转换操作数顺序）
```

**生成指令**: `EQ R[0], R[1], R[2]`

---

### OP_TEST, OP_TESTSET

**描述**: 测试指令
**示例**: 短路逻辑 `a and b`

**关键流程**:
```
1. [jumpcode()] 调用 luaK_codeABC(fs, OP_TEST, ...)
2. [jumpcode()] 生成 JMP
```

---

### OP_RETURN, OP_RETURN0, OP_RETURN1

**描述**: 返回指令
**示例**: `return a`, `return`, `return a`

**关键流程**:
```
1. [luaK_ret()] 根据 nret 值选择指令
2. [luaK_ret()] 调用 luaK_codeABC(fs, op, first, nret+1, 0)
```

**生成指令**: `RETURN R[0], 2`

---

### OP_VARARG, OP_VARARGPREP

**描述**: 可变参数处理
**示例**: `local a = ...`

**关键流程**:
```
1. [simpleexp()] 进入 TK_DOTS 分支
2. [simpleexp()] 调用 init_exp(v, VVARARG, luaK_codeABC(fs, OP_VARARG, 0, 0, 1))
3. [setvararg()] 调用 luaK_codeABC(fs, OP_VARARGPREP, nparams, 0, 0)
```

---

### OP_CLOSURE

**格式**: iABx
**描述**: `R[A] := closure(KPROTO[Bx])` - 创建闭包
**示例**: `function f() ... end`

**关键流程**:
```
1. [body()] 调用 codeclosure()
2. [codeclosure()] 调用 luaK_codeABx(fs, OP_CLOSURE, 0, fs->np - 1)
```

---

### OP_FORLOOP, OP_FORPREP

**描述**: 数值 for 循环
**示例**: `for i=1,10 do ... end`

---

### OP_TFORPREP, OP_TFORCALL, OP_TFORLOOP

**描述**: 泛型 for 循环
**示例**: `for k,v in pairs(t) do ... end`

---

### OP_SETLIST

**描述**: 批量设置表元素
**示例**: 表构造器的数组部分

---

### OP_EXTRAARG

**格式**: iAx
**描述**: 额外参数（配合 LOADKX 等指令）

---

## 总结

### 编译流程概览

```
源代码
   ↓
词法分析 (llex.c)
   ↓
Token 流 (TK_NAME, TK_INT, TK_STRING, ...)
   ↓
语法分析 (lparser.c)
   ↓
抽象语法树 (expdesc 结构)
   ↓
代码生成 (lcode.c)
   ↓
字节码指令序列 (Proto->code[])
```

### expdesc 类型转换图

```
词法值
   ↓
VKINT, VKFLT, VKSTR, VNIL, VTRUE, VFALSE (常量)
   ↓
VLOCAL, VUPVAL (变量引用)
   ↓
VNONRELOC (固定寄存器)
   ↓
VINDEXED, VINDEXI, VINDEXSTR, VINDEXUP (索引操作)
   ↓
VRELOC (可重定位)
   ↓
VJMP (跳转)
   ↓
VNONRELOC (最终结果)
```

### 关键函数说明

| 函数 | 功能 |
|------|------|
| luaK_dischargevars | 将延迟加载的表达式转换为寄存器或常量 |
| luaK_exp2anyreg | 确保表达式在寄存器中 |
| luaK_exp2nextreg | 将表达式放入下一个可用寄存器 |
| luaK_exp2RK | 尝试将表达式编码为寄存器或常量 |
| luaK_indexed | 将表达式转换为索引类型 |
| luaK_storevar | 存储表达式的值到变量 |

整个编译过程是数据驱动的，expdesc 结构扮演了核心角色，通过不同的 expkind 类型表示表达式所处的不同阶段和状态，最终由各种 luaK_* 函数生成对应的字节码指令。
