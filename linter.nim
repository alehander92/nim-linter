import strformat, sequtils, strutils, tables, macros, terminal, typetraits
import compiler / [ast, lexer, parser, idents, msgs, llstream], deeptext

type
  C* {.pure.} = enum
    NamingTypes,
    NamingVariables

  N {.pure.} = enum
    SnakeCase,  # ax_b
    CamelCase,  # axB
    PascalCase, # AxB
    CapitalCase # AX_B

  # I hate method polymorphism, but variants are not well suited here
  # it leads to my own tokens/ast handlers and expectKind in each function
  
  Check* = ref object of RootObj

  NamingCheck* = ref object of Check
    convention*:  N

  NamingTypesCheck* = ref object of NamingCheck

  NamingVariablesCheck* = ref object of NamingCheck

  Result* = ref object
    problems*:    seq[Problem]
    currentPath*: string
    sources*:     Table[string, tuple[source: string, lines: seq[string]]]

  Problem* = ref object
    location*:    Location
    message*:     string
    hint*:        string
    check*:       string # TODO C

  Location* = ref object
    path*:        string  
    lines*:       tuple[first: int, last: int]
    columns*:     tuple[first: int, last: int]

  HandlerKind* = enum HClosure, HProcedure

  Handler* = ref object
    case kind*:   HandlerKind
    of HClosure:
      closure*:   proc(node: PNode)
    of HProcedure:
      procedure*: proc(check: Check, node: PNode, res: Result)

  FindOption* = enum FName

var t: TToken

proc handle*(i: TLineInfo, m: TMsgKind, a: string) =
  discard
  # echo a

proc findNode*(node: PNode, kind: TNodeKind, options: set[FindOption] = {}): PNode =
  if node.kind == kind:
    result = node
  else:
    for son in node.sons:
      if son.kind == nkPostfix and FName in options:
        result = son[1].findNode(kind, options)
      else:
        result = son.findNode(kind, options)
      if not result.isNil:
        return

proc findTypeName*(node: PNode): PNode =
  result = node.findNode(nkIdent, {FName})

proc pretty*(convention: N): string =
  case convention:
    of N.SnakeCase: "snake_case"
    of N.CamelCase: "camelCase"
    of N.PascalCase: "PascalCase"
    of N.CapitalCase: "CAPITAL_CASE"

proc tokenize*(name: string): seq[string] =
  if "_" in name:
    result = name.split("_")
  else:
    result = @[]
    var token = ""
    for s in name:
      if s.isUpperAscii:
        if token.len > 0:
          result.add(token)
        token = $s
      else:
        token.add(s)  
    if token.len > 0:
      result.add(token) 
  result = result.mapIt(it.toLowerAscii)

proc generate*(tokens: seq[string], convention: N): string =
  case convention:
    of N.SnakeCase:
      tokens.join("_")
    of N.CamelCase:
      let first = tokens[0]
      let others = tokens[1..^1].mapIt(it.capitalizeAscii).join("")
      &"{first}{others}"
    of N.PascalCase:
      tokens.mapIt(it.capitalizeAscii).join("")
    of N.CAPITAL_CASE:
      tokens.mapIt(it.toUpperAscii).join("_")

proc toConvention*(name: string, convention: N): string =
  let tokens = tokenize(name)
  generate(tokens, convention)

proc validConvention*(name: string, convention: N): bool =
  # TODO faster
  name.toConvention(convention) == name

proc hint*(convention: N, node: PNode): string =
  ($node.ident).toConvention(convention)

# visit

method visitTokens*(check: Check, tokens: seq[TToken], res: Result) {.base.} =
  discard

method visitAst*(check: Check, ast: PNode, res: Result) {.base.} =
  discard



macro visit*(check: untyped, ast: untyped, res: untyped, handlers: untyped): untyped =
  var nodeHandlers: NimNode = nnkCall.newTree(nnkDotExpr.newTree(nnkTableConstr.newTree(), ident("toTable")))
  for handler in handlers:
    expectKind(handler, nnkCommand)
    if handler[0].repr != "on":
      error("expected on")
    var kind = handler[1]
    var h: NimNode 
    if handler[2].kind != nnkIdent:
      let code = handler[2]
      let node = ident("node")
      h = quote:
        Handler(kind: HClosure, closure: proc(`node`: PNode) =
          `code`)
    else:
      let procedure = handler[2]
      h = quote:
        Handler(kind: HProcedure, procedure: `procedure`)
    let nodeHandler = nnkExprColonExpr.newTree(kind, h)
    nodeHandlers[0][0].add(nodeHandler)

  result = quote:
    `check`.visitNode(`ast`, `res`, `nodeHandlers`) 
  echo result.repr


method visitNode*(check: Check, node: PNode, res: Result, handlers: Table[TNodeKind, Handler]) =
  if node.isNil:
    return
  if handlers.hasKey(node.kind):
    let handler = handlers[node.kind]
    if handler.kind == HClosure:
      handler.closure(node)
    else:
      handler.procedure(check, node, res)
  else:
     for son in node:
      check.visitNode(son, res, handlers)

template problem*(node: PNode, subclass: typedesc, aMessage: string, aHint: string) =
  let column = `node`.info.col.int
  let last = if node.kind == nkIdent: column + ($(node.ident)).len else: 10
  res.problems.add(
    Problem(
      location: Location(
        path: res.currentPath,
        lines: (first: `node`.info.line.int, last: `node`.info.line.int),
        columns: (first: column, last: last)),
      message: `aMessage`,
      hint: `aHint`,
      check: subclass.name[0 ..< ^5]))

method visitAst*(ch: NamingTypesCheck, ast: PNode, res: Result) =
  var check = ch
  check.visit(ast, res):
    on nkTypeDef: 
      let typeName = node.findTypeName
      if not ($(typeName.ident)).validConvention(check.convention):
        problem(
          typeName,
          ch.type,
          &"{$(typeName.ident)} is not {check.convention.pretty}",
          check.convention.hint(typeName))

    #@[nkTypeDef, (inline: proc = if .. , f: onTypeDef: proc(check: var Check, node: PNode, res: var Result)]

proc lex*(path: string, cache: IdentCache): seq[TToken] =
  result = @[]
  var s = llStreamOpen(path, fmRead)
  if not s.isNil:
    var l: TLexer
    var token: TToken
    initToken(token)
    openLexer(l, path, s, cache)
    while true:
      rawGetTok(l, token)
      result.add(token)
      if token.tokType == tkEof:
        break
    closeLexer(l)

proc displayProblem*(res: Result, problem: Problem) =
  let lines = res.sources[problem.location.path].lines
  var highlight = ""
  let l = problem.location.lines
  let c = problem.location.columns
  let before = lines[l.first - 1][0 ..< c.first]
  let after = lines[l.last - 1][c.last + 1 .. ^1] & "\n"
  if l.first == l.last:
    highlight = lines[l.first - 1][c.first .. c.last]
  else:
    let first = lines[l.first - 1][c.first .. ^1] & "\n"
    let middle = lines[l.first .. l.last - 2].mapIt(it & "\n").join("")
    let last = lines[l.last - 1][0 .. c.last]
    highlight = first & middle & last
  
  # before (yellow)highlight after
  # (yellow)check: message
  # (green)hint: hint
  echo "\n====================\n\n"
  echo &"{problem.location.path}:{l.first}\n"
  styledWriteLine(stdout, before, fgYellow, highlight, resetStyle, after)
  styledWriteLine(stdout, fgYellow, &"{problem.check}: {problem.message}", resetStyle)
  if problem.hint.len > 0:
    styledWriteLine(stdout, fgGreen, &"hint: {problem.hint}", resetStyle)

proc displayProblems*(res: Result) =
  for problem in res.problems:
    res.displayProblem(problem)
  if res.problems.len > 0:
    echo &"{res.problems.len} problems"
  else:
    echo "OK"

proc check*(path: string, checks: seq[Check]) =
  # TODO: reuse file for stream
  var res = Result(problems: @[], currentPath: path, sources: initTable[string, tuple[source: string, lines: seq[string]]]())
  var source = readFile(path)
  res.sources[path] = (source: source, lines: source.splitLines())
  var cache = newIdentCache()
  var tokens = lex(path, cache)
  var ast = parseString(source, cache, path, 0, handle)
  for ch in checks:
    ch.visitTokens(tokens, res)
    ch.visitAst(ast, res)
  res.displayProblems()

check("linter.nim", cast[seq[Check]](@[NamingTypesCheck(convention: N.PascalCase)]))

