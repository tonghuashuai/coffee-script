# CoffeeScript 的解析器从这个语法文件, 用 [Jison](http://github.com/zaach/jison) 生成的.
# Jison 是个自底而上的解析器生成工具, 和 [Bison](http://www.gnu.org/software/bison) 的风格相似, 不过是用 JavaScript 实现的.
# 它可以辨认 [LALR(1), LR(0), SLR(1) 和 LR(1)](http://en.wikipedia.org/wiki/LR_grammar) 语法.
# 为了创建 Jison 解析器, 我们把匹配模式列在左边, 把对应动作列在右边 (通常是创建语法树的节点).
# 执行的时候, 解析器自左往右地, 从流中取出 token, 然后尝试把 token 序列[匹配](http://en.wikipedia.org/wiki/Bottom-up_parsing)
# 到下面写的语法规则中. 如果可以匹配, 会把取出的 token 缩减成 [nonterminal](http://en.wikipedia.org/wiki/Terminal_and_nonterminal_symbols)
# 的符号 (语法规则前边的名字), 然后继续.
#
# 如果你执行命令 `cake build:parser`, Jison 就会按照我们的规则建立语法解析表, 保存到 `lib/parser.js` 中.

# 唯一的依赖: **Jison.Parser**.
{Parser} = require 'jison'

# Jison DSL
# ---------

# Jison 会给我们的解析器多包装一层函数.
# 如果包装函数只是简单的返回一个值, 我们就可以通过移除包装函数, 直接返回里面的内容来做优化.
unwrap = /^function\s*\(\)\s*\{\s*return\s*([\s\S]*);\s*\}/

# 我们方便 Jison 语法生成的 DSL 要感谢 [Tim Caswell](http://github.com/creationix).
# 每条语法规则带有定义模式的字符串, 可选的动作和额外选项.
# 如果没有指定动作, 就简单的返回上一个 nonterminal 的值.
o = (patternString, action, options) ->
  patternString = patternString.replace /\s{2,}/g, ' '
  patternCount = patternString.split(' ').length
  return [patternString, '$$ = $1;', options] unless action
  action = if match = unwrap.exec action then match[1] else "(#{action}())"

  # 所有需要在 "yy" 上定义的运行时函数
  action = action.replace /\bnew /g, '$&yy.'
  action = action.replace /\b(?:Block\.wrap|extend)\b/g, 'yy.$&'

  # 构造一个函数, 往第一个参数加上位置数据, 然后返回之.
  # 如果该参数不是节点, 就不做修改的返回.
  addLocationDataFn = (first, last) ->
    if not last
      "yy.addLocationDataFn(@#{first})"
    else
      "yy.addLocationDataFn(@#{first}, @#{last})"

  action = action.replace /LOC\(([0-9]*)\)/g, addLocationDataFn('$1')
  action = action.replace /LOC\(([0-9]*),\s*([0-9]*)\)/g, addLocationDataFn('$1', '$2')

  [patternString, "$$ = #{addLocationDataFn(1, patternCount)}(#{action});", options]

# 语法规则
# -----------------

# 下面列出了候选的匹配规则. 你可以看到 nonterminal 的名字是键值.
# 每个匹配的动作中, 以 `$` 打头的变量是 Jison 提供的, 对应数字的位置的值. 在这条规则中:
#
#     "Expression UNLESS Expression"
#
# `$1` 的值就是第一个 `Expression`, `$2` 的值就是终结符(terminal) `UNLESS` 对应的 token, `$3` 就是的值就是第二个 `Expression`
grammar =

  # **Root** 是语法树最顶层的节点. 由于我们是自低而上解析的, 所有解析都会终结于此.
  Root: [
    o '',                                       -> new Block
    o 'Body'
  ]

  # 由任意语句和表达式组成, 被换行符或者分号分隔
  Body: [
    o 'Line',                                   -> Block.wrap [$1]
    o 'Body TERMINATOR Line',                   -> $1.push $3
    o 'Body TERMINATOR'
  ]

  # 块和语句, 占据 **Body** 中的一行
  Line: [
    o 'Expression'
    o 'Statement'
  ]

  # 不能当作表达式的纯语句
  Statement: [
    o 'Return'
    o 'Comment'
    o 'STATEMENT',                              -> new Literal $1
  ]

  # 我们语言中所有不同类型的表达式. CoffeeScript 的基本组成元素是 **Expression** -- 所有可以成为表达式的东西都融为一个规则.
  # 例外的是, **Block** 同时也递归作为其他很多规则的基本构件, 所以没添加到这里.
  Expression: [
    o 'Value'
    o 'Invocation'
    o 'Code'
    o 'Operation'
    o 'Assign'
    o 'If'
    o 'Try'
    o 'While'
    o 'For'
    o 'Switch'
    o 'Class'
    o 'Throw'
  ]

  # 由表达式组成, 缩进的块. 注意 [Rewriter](rewriter.html) 会通过调整 token 流的方法, 把一些后缀式的写法转换成块.
  Block: [
    o 'INDENT OUTDENT',                         -> new Block
    o 'INDENT Body OUTDENT',                    -> $2
  ]

  # 标识符字面量, 变量名或者属性.
  Identifier: [
    o 'IDENTIFIER',                             -> new Literal $1
  ]

  # Alphanumerics 独立于其他 **Literal**, 是因为它们仅用作对象字面量的的键值.
  AlphaNumeric: [
    o 'NUMBER',                                 -> new Literal $1
    o 'STRING',                                 -> new Literal $1
  ]

  # 所有直接量. 基本都可以不处理直接变成 JavaScript.
  Literal: [
    o 'AlphaNumeric'
    o 'JS',                                     -> new Literal $1
    o 'REGEX',                                  -> new Literal $1
    o 'DEBUGGER',                               -> new Literal $1
    o 'UNDEFINED',                              -> new Undefined
    o 'NULL',                                   -> new Null
    o 'BOOL',                                   -> new Bool $1
  ]

  # 变量, 属性或者下标 的赋值
  Assign: [
    o 'Assignable = Expression',                -> new Assign $1, $3
    o 'Assignable = TERMINATOR Expression',     -> new Assign $1, $4
    o 'Assignable = INDENT Expression OUTDENT', -> new Assign $1, $4
  ]

  # 在对象字面量中的赋值. 和一般 **Assign** 规则不同之处是: 这里允许数字或者字符串作为键值.
  AssignObj: [
    o 'ObjAssignable',                          -> new Value $1
    o 'ObjAssignable : Expression',             -> new Assign LOC(1)(new Value($1)), $3, 'object'
    o 'ObjAssignable :
       INDENT Expression OUTDENT',              -> new Assign LOC(1)(new Value($1)), $4, 'object'
    o 'Comment'
  ]

  ObjAssignable: [
    o 'Identifier'
    o 'AlphaNumeric'
    o 'ThisProperty'
  ]

  # 函数体中的返回语句.
  Return: [
    o 'RETURN Expression',                      -> new Return $2
    o 'RETURN',                                 -> new Return
  ]

  # 注释块
  Comment: [
    o 'HERECOMMENT',                            -> new Comment $1
  ]

  # **Code** 节点是函数字面量. 缩进的代码块 **Block** 之前带一个函数箭头, 和一个可选的参数列表.
  Code: [
    o 'PARAM_START ParamList PARAM_END FuncGlyph Block', -> new Code $2, $5, $4
    o 'FuncGlyph Block',                        -> new Code [], $2, $1
  ]

  # CoffeeScript 有两个不同的箭头符号. `->` 是给一般函数用的, 而 `=>` 函数会绑定到当前 *this* 的值.
  FuncGlyph: [
    o '->',                                     -> 'func'
    o '=>',                                     -> 'boundfunc'
  ]

  # 可选的行末逗号
  OptComma: [
    o ''
    o ','
  ]

  # 函数可以接受任意长的参数列表
  ParamList: [
    o '',                                       -> []
    o 'Param',                                  -> [$1]
    o 'ParamList , Param',                      -> $1.concat $3
    o 'ParamList OptComma TERMINATOR Param',    -> $1.concat $4
    o 'ParamList OptComma INDENT ParamList OptComma OUTDENT', -> $1.concat $4
  ]

  # 函数的一个参数可以正常的定义, 或者用 splat 把剩下的参数汇集到一起.
  Param: [
    o 'ParamVar',                               -> new Param $1
    o 'ParamVar ...',                           -> new Param $1, null, on
    o 'ParamVar = Expression',                  -> new Param $1, $3
    o '...',                                    -> new Expansion
  ]

  # 函数参数.
  ParamVar: [
    o 'Identifier'
    o 'ThisProperty'
    o 'Array'
    o 'Object'
  ]

  # 在函数参数之外的 splat.
  Splat: [
    o 'Expression ...',                         -> new Splat $1
  ]

  # 可以赋值的变量或者属性.
  SimpleAssignable: [
    o 'Identifier',                             -> new Value $1
    o 'Value Accessor',                         -> $1.add $2
    o 'Invocation Accessor',                    -> new Value $1, [].concat $2
    o 'ThisProperty'
  ]

  # 所有可以赋值到的东西.
  Assignable: [
    o 'SimpleAssignable'
    o 'Array',                                  -> new Value $1
    o 'Object',                                 -> new Value $1
  ]

  # 可以被当作值的类型 -- 可赋值到的量, 函数调用, 数组下标, "类"等等.
  Value: [
    o 'Assignable'
    o 'Literal',                                -> new Value $1
    o 'Parenthetical',                          -> new Value $1
    o 'Range',                                  -> new Value $1
    o 'This'
  ]

  # 总合了大部分访问对象内容的手段: 通过属性, 原型, 数组下标或者数组切片.
  Accessor: [
    o '.  Identifier',                          -> new Access $2
    o '?. Identifier',                          -> new Access $2, 'soak'
    o ':: Identifier',                          -> [LOC(1)(new Access new Literal('prototype')), LOC(2)(new Access $2)]
    o '?:: Identifier',                         -> [LOC(1)(new Access new Literal('prototype'), 'soak'), LOC(2)(new Access $2)]
    o '::',                                     -> new Access new Literal 'prototype'
    o 'Index'
  ]

  # 使用方括号语法访问对象或数组内部.
  Index: [
    o 'INDEX_START IndexValue INDEX_END',       -> $2
    o 'INDEX_SOAK  Index',                      -> extend $2, soak : yes
  ]

  IndexValue: [
    o 'Expression',                             -> new Index $1
    o 'Slice',                                  -> new Slice $1
  ]

  # 在 CoffeeScript 里, 一个对象字面量是简单的由属性赋值列表组成.
  Object: [
    o '{ AssignList OptComma }',                -> new Obj $2, $1.generated
  ]

  # 对象字面量中的属性赋值, 可以像 JavaScript 那样用逗号分隔, 或者直接用换行分隔.
  AssignList: [
    o '',                                                       -> []
    o 'AssignObj',                                              -> [$1]
    o 'AssignList , AssignObj',                                 -> $1.concat $3
    o 'AssignList OptComma TERMINATOR AssignObj',               -> $1.concat $4
    o 'AssignList OptComma INDENT AssignList OptComma OUTDENT', -> $1.concat $4
  ]

  # 类定义包含可选的原型属性赋值, 和可选的到超类的引用.
  Class: [
    o 'CLASS',                                           -> new Class
    o 'CLASS Block',                                     -> new Class null, null, $2
    o 'CLASS EXTENDS Expression',                        -> new Class null, $3
    o 'CLASS EXTENDS Expression Block',                  -> new Class null, $3, $4
    o 'CLASS SimpleAssignable',                          -> new Class $2
    o 'CLASS SimpleAssignable Block',                    -> new Class $2, null, $3
    o 'CLASS SimpleAssignable EXTENDS Expression',       -> new Class $2, $4
    o 'CLASS SimpleAssignable EXTENDS Expression Block', -> new Class $2, $4, $5
  ]

  # 一般函数调用, 或者链式函数调用.
  Invocation: [
    o 'Value OptFuncExist Arguments',           -> new Call $1, $3, $2
    o 'Invocation OptFuncExist Arguments',      -> new Call $1, $3, $2
    o 'SUPER',                                  -> new Call 'super', [new Splat new Literal 'arguments']
    o 'SUPER Arguments',                        -> new Call 'super', $2
  ]

  # 可选的函数存在性检查.
  OptFuncExist: [
    o '',                                       -> no
    o 'FUNC_EXIST',                             -> yes
  ]

  # 函数调用的参数列表.
  Arguments: [
    o 'CALL_START CALL_END',                    -> []
    o 'CALL_START ArgList OptComma CALL_END',   -> $2
  ]

  # 对当前对象 *this* 的引用.
  This: [
    o 'THIS',                                   -> new Value new Literal 'this'
    o '@',                                      -> new Value new Literal 'this'
  ]

  # 对 *this* 的属性的引用.
  ThisProperty: [
    o '@ Identifier',                           -> new Value LOC(1)(new Literal('this')), [LOC(2)(new Access($2))], 'this'
  ]

  # 数组字面量.
  Array: [
    o '[ ]',                                    -> new Arr []
    o '[ ArgList OptComma ]',                   -> new Arr $2
  ]

  # inclusive 和 exclusive 范围.
  RangeDots: [
    o '..',                                     -> 'inclusive'
    o '...',                                    -> 'exclusive'
  ]

  # CoffeeScript 范围字面量.
  Range: [
    o '[ Expression RangeDots Expression ]',    -> new Range $2, $4, $3
  ]

  # 数组切片字面量.
  Slice: [
    o 'Expression RangeDots Expression',        -> new Range $1, $3, $2
    o 'Expression RangeDots',                   -> new Range $1, null, $2
    o 'RangeDots Expression',                   -> new Range null, $2, $1
    o 'RangeDots',                              -> new Range null, null, $1
  ]

  # **ArgList** 既可以是传给函数调用的对象列表, 又可以作为数组字面量的内容
  # (特别是逗号分隔的表达式). 新行分隔也可以.
  ArgList: [
    o 'Arg',                                              -> [$1]
    o 'ArgList , Arg',                                    -> $1.concat $3
    o 'ArgList OptComma TERMINATOR Arg',                  -> $1.concat $4
    o 'INDENT ArgList OptComma OUTDENT',                  -> $2
    o 'ArgList OptComma INDENT ArgList OptComma OUTDENT', -> $1.concat $4
  ]

  # 块或者 Splat 都是合法的参数.
  Arg: [
    o 'Expression'
    o 'Splat'
    o '...',                                     -> new Expansion
  ]

  # 简单的, 逗号分隔的, 必须的参数 (没华丽的语法). 为了使这个规则可以在不支持多行的 **Switch** 块中使用, 我们把它和 **ArgList** 分离开来.
  SimpleArgs: [
    o 'Expression'
    o 'SimpleArgs , Expression',                -> [].concat $1, $3
  ]

  # *try/catch/finally* 异常处理块的各变种.
  Try: [
    o 'TRY Block',                              -> new Try $2
    o 'TRY Block Catch',                        -> new Try $2, $3[0], $3[1]
    o 'TRY Block FINALLY Block',                -> new Try $2, null, null, $4
    o 'TRY Block Catch FINALLY Block',          -> new Try $2, $3[0], $3[1], $5
  ]

  # catch 子句把赋给异常对象一个名字并执行代码块.
  Catch: [
    o 'CATCH Identifier Block',                 -> [$2, $3]
    o 'CATCH Object Block',                     -> [LOC(2)(new Value($2)), $3]
    o 'CATCH Block',                            -> [null, $2]
  ]

  # 抛出一个异常对象.
  Throw: [
    o 'THROW Expression',                       -> new Throw $2
  ]

  # 括号表达式. 注意 **Parenthetical** 是个 **Value** 而不是 **Expression**,
  # 所以如果你要把表达式放到一个仅接受值的地方, 总用括号包起来就可以了.
  Parenthetical: [
    o '( Body )',                               -> new Parens $2
    o '( INDENT Body OUTDENT )',                -> new Parens $3
  ]

  # while 循环的条件部分.
  WhileSource: [
    o 'WHILE Expression',                       -> new While $2
    o 'WHILE Expression WHEN Expression',       -> new While $2, guard: $4
    o 'UNTIL Expression',                       -> new While $2, invert: true
    o 'UNTIL Expression WHEN Expression',       -> new While $2, invert: true, guard: $4
  ]

  # while 循环一般带个待执行的表达式块, 也可以是后缀式地加到一个表达式后. 没有 do..while.
  While: [
    o 'WhileSource Block',                      -> $1.addBody $2
    o 'Statement  WhileSource',                 -> $2.addBody LOC(1) Block.wrap([$1])
    o 'Expression WhileSource',                 -> $2.addBody LOC(1) Block.wrap([$1])
    o 'Loop',                                   -> $1
  ]

  Loop: [
    o 'LOOP Block',                             -> new While(LOC(1) new Literal 'true').addBody $2
    o 'LOOP Expression',                        -> new While(LOC(1) new Literal 'true').addBody LOC(2) Block.wrap [$2]
  ]

  # 数组, 对象和范围 comprehension 的一般写法.
  # Comprehension 一般带个代执行的表达式块, 也可以是后缀式地加到一个表达式后.
  For: [
    o 'Statement  ForBody',                     -> new For $1, $2
    o 'Expression ForBody',                     -> new For $1, $2
    o 'ForBody    Block',                       -> new For $2, $1
  ]

  ForBody: [
    o 'FOR Range',                              -> source: LOC(2) new Value($2)
    o 'ForStart ForSource',                     -> $2.own = $1.own; $2.name = $1[0]; $2.index = $1[1]; $2
  ]

  ForStart: [
    o 'FOR ForVariables',                       -> $2
    o 'FOR OWN ForVariables',                   -> $3.own = yes; $3
  ]

  # 循环中的一个变量, 取于数组中满足条件的值. 支持模式匹配.
  ForValue: [
    o 'Identifier'
    o 'ThisProperty'
    o 'Array',                                  -> new Value $1
    o 'Object',                                 -> new Value $1
  ]

  # 一个数组或者范围 comprehension 包含对应当前元素的变量, 和 (可选的) 对当前下标的引用.
  # 在对象 comprehension 的情况下, 则是 *key, value*.
  ForVariables: [
    o 'ForValue',                               -> [$1]
    o 'ForValue , ForValue',                    -> [$1, $3]
  ]

  # comprehension 的源是个数组或者对象, 带可选的 guard 从句. 如果是数组 comprehension, 你还可以选择固定间隔的步进.
  ForSource: [
    o 'FORIN Expression',                               -> source: $2
    o 'FOROF Expression',                               -> source: $2, object: yes
    o 'FORIN Expression WHEN Expression',               -> source: $2, guard: $4
    o 'FOROF Expression WHEN Expression',               -> source: $2, guard: $4, object: yes
    o 'FORIN Expression BY Expression',                 -> source: $2, step:  $4
    o 'FORIN Expression WHEN Expression BY Expression', -> source: $2, guard: $4, step: $6
    o 'FORIN Expression BY Expression WHEN Expression', -> source: $2, step:  $4, guard: $6
  ]

  Switch: [
    o 'SWITCH Expression INDENT Whens OUTDENT',            -> new Switch $2, $4
    o 'SWITCH Expression INDENT Whens ELSE Block OUTDENT', -> new Switch $2, $4, $6
    o 'SWITCH INDENT Whens OUTDENT',                       -> new Switch null, $3
    o 'SWITCH INDENT Whens ELSE Block OUTDENT',            -> new Switch null, $3, $5
  ]

  Whens: [
    o 'When'
    o 'Whens When',                             -> $1.concat $2
  ]

  # 单独的 **When** 从句, 带动作.
  When: [
    o 'LEADING_WHEN SimpleArgs Block',            -> [[$2, $3]]
    o 'LEADING_WHEN SimpleArgs Block TERMINATOR', -> [[$2, $3]]
  ]

  # 最基本的 *if* 只含条件和动作. 下面把 if 相关的规则拆分开来, 是为了避免二义性.
  IfBlock: [
    o 'IF Expression Block',                    -> new If $2, $3, type: $1
    o 'IfBlock ELSE IF Expression Block',       -> $1.addElse LOC(3,5) new If $4, $5, type: $3
  ]

  # 其他 *if* 表达式的形式, 包含后缀式一行流的 *if* 和 *unless*.
  If: [
    o 'IfBlock'
    o 'IfBlock ELSE Block',                     -> $1.addElse $3
    o 'Statement  POST_IF Expression',          -> new If $3, LOC(1)(Block.wrap [$1]), type: $2, statement: true
    o 'Expression POST_IF Expression',          -> new If $3, LOC(1)(Block.wrap [$1]), type: $2, statement: true
  ]

  # 算术和逻辑操作符, 作用于 1 个或者多个操作数(operand).
  # 这里把它们按优先级分组. 确切的优先级规则在页低给出.
  # 如果我们可以把大部分都归结到一个泛化的 *Operand OpSymbol Operand* 形式的规则, 这个定义就可以短很多.
  # 但为了使优先级生效, 就得分别定义了.
  Operation: [
    o 'UNARY Expression',                       -> new Op $1 , $2
    o 'UNARY_MATH Expression',                  -> new Op $1 , $2
    o '-     Expression',                      (-> new Op '-', $2), prec: 'UNARY_MATH'
    o '+     Expression',                      (-> new Op '+', $2), prec: 'UNARY_MATH'

    o '-- SimpleAssignable',                    -> new Op '--', $2
    o '++ SimpleAssignable',                    -> new Op '++', $2
    o 'SimpleAssignable --',                    -> new Op '--', $1, null, true
    o 'SimpleAssignable ++',                    -> new Op '++', $1, null, true

    # [存在性操作符](http://coffee-js.github.io/coffee-script/#existence).
    o 'Expression ?',                           -> new Existence $1

    o 'Expression +  Expression',               -> new Op '+' , $1, $3
    o 'Expression -  Expression',               -> new Op '-' , $1, $3

    o 'Expression MATH     Expression',         -> new Op $2, $1, $3
    o 'Expression **       Expression',         -> new Op $2, $1, $3
    o 'Expression SHIFT    Expression',         -> new Op $2, $1, $3
    o 'Expression COMPARE  Expression',         -> new Op $2, $1, $3
    o 'Expression LOGIC    Expression',         -> new Op $2, $1, $3
    o 'Expression RELATION Expression',         ->
      if $2.charAt(0) is '!'
        new Op($2[1..], $1, $3).invert()
      else
        new Op $2, $1, $3

    o 'SimpleAssignable COMPOUND_ASSIGN
       Expression',                             -> new Assign $1, $3, $2
    o 'SimpleAssignable COMPOUND_ASSIGN
       INDENT Expression OUTDENT',              -> new Assign $1, $4, $2
    o 'SimpleAssignable COMPOUND_ASSIGN TERMINATOR
       Expression',                             -> new Assign $1, $4, $2
    o 'SimpleAssignable EXTENDS Expression',    -> new Extends $1, $3
  ]


# 优先级
# ----------

# 在上面的操作符比下面的操作符优先级更高. 下面的规则使得 `2 + 3 * 4` 解析成:
#
#     2 + (3 * 4)
#
# 而不是:
#
#     (2 + 3) * 4
operators = [
  ['left',      '.', '?.', '::', '?::']
  ['left',      'CALL_START', 'CALL_END']
  ['nonassoc',  '++', '--']
  ['left',      '?']
  ['right',     'UNARY']
  ['right',     '**']
  ['right',     'UNARY_MATH']
  ['left',      'MATH']
  ['left',      '+', '-']
  ['left',      'SHIFT']
  ['left',      'RELATION']
  ['left',      'COMPARE']
  ['left',      'LOGIC']
  ['nonassoc',  'INDENT', 'OUTDENT']
  ['right',     '=', ':', 'COMPOUND_ASSIGN', 'RETURN', 'THROW', 'EXTENDS']
  ['right',     'FORIN', 'FOROF', 'BY', 'WHEN']
  ['right',     'IF', 'ELSE', 'FOR', 'WHILE', 'UNTIL', 'LOOP', 'SUPER', 'CLASS']
  ['left',      'POST_IF']
]

# 包装
# -----------

# 既然 **语法** 和 **操作符** 都有了, 我们终于可以创建 **Jison.Parser** 了.
# 我们的做法是遍历所有规则, 把全部终结符 (不在上面的规则中的符号) 标记记为 "token".
tokens = []
for name, alternatives of grammar
  grammar[name] = for alt in alternatives
    for token in alt[0].split ' '
      tokens.push token unless grammar[token]
    alt[1] = "return #{alt[1]}" if name is 'Root'
    alt

# 用 **token** 终结符和 **grammar** 规则初始化 **Parser**, 并指定根规则.
# 这里还逆序排列了操作符列表, 因为 Jison 需要从低到高的优先级排列操作符,
# 而我们的定义顺序是从高到低 (和 [Yacc](http://dinosaur.compilertools.net/yacc/index.html) 一样).
exports.parser = new Parser
  tokens      : tokens.join ' '
  bnf         : grammar
  operators   : operators.reverse()
  startSymbol : 'Root'
