# nim-linter

niminal

```yaml
# .nimlinter.yml
checks:
  NamingTypes: PascalCase
```

```bash
./linter linter.nim
```

# Checks

## Naming

Naming checks the convention of names

Currently we have 4: snake_case, camelCase, PascalCase and CAPITAL_CASE

### NamingTypes

```yaml
NamingTypes: convention
```

Checks the type naming. I visit the type sections only currently which should be probably sufficient for now. Default: PascalCase

### NamingVariables

```yaml
NamingVariables: convention
```

Checks variable naming: basically visiting idents that aren't supposed to be a type.
Default: camelCase

### NamingConstants

```yaml
NamingConstants: convention
```

Checks `const <name>`. Default: camelCase (but I really love CAPITAL_CASE for constants)

### NamingEnums

```yaml
NamingEnums:on/off
```

Checks impure enums for having the same prefix

## Layout

### FunctionSpacing

```yaml
FunctionSpacing: lines
```

Checks that at least `lines` lines are left between top level function definitions


## Logic

### NilCheck

```yaml
NilCheck:on/off
```

Warns against `<value> == nil` and hints `value.isNil`

### Cyclomatic

```yaml
Cyclomatic:depth
```

Warns on highly nested loops and conditions

### FunctionalLoop

```yaml
FunctionalLoop:on/off
```

Warn when a loop can be expressed as a single `mapIt` / `filterIt` etc and hint a refactoring

### NilFlow

```yaml
NilFlow:on/off
```

Warn when a normal value is nil in a branch and it is used (with a field access / call): that leads to some false positives, so it's just a warning






