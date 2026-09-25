# Implicit conversion `toExtern` where an Extern is expected

Goal: in the allowed positions, an expression `e: U` with `U` not a subtype of `Extern<T>` is accepted where `Extern<T>` is expected, and rewritten into `T.toExtern<U>(e)`.

Sema only accepts `e` and leaves its type as `U`. The rewrite happens in a separate pass after Sema, and it is driven purely by the final types.

## Changes in TypeChecking stage

### Helpers

- `Ty::IsCoreExternType()` in [Types.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/include/cangjie/AST/Types.h) / [Types.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/AST/Types.cpp): true for `std.core`'s `Extern<T>`, i.e. an enum from the core package named `Extern` with one type argument. It uses the new constants `STD_LIB_EXTERN` and `STD_LIB_FOREIGN_RUNTIME` from [ConstantsUtils.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/include/cangjie/Utils/ConstantsUtils.h).
- `NeedExternConversion(from, to)` in [TypeCheckerImpl.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckerImpl.h) / [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp): the single predicate shared by Sema and the desugar pass.

```cpp
// returns true if `to` is Extern<T>, `from` is a valid type, `from` is not Nothing, and `from` is not `Extern<T>`
bool NeedExternConversion(Ty& from, Ty& to);
```

### Existing `Check` function gets an opt-in flag

The existing function `Check`, declared in [TypeCheckerImpl.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckerImpl.h) and implemented in [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp), returns `true` if a certain `node` corresponding to an expression has a certain type `target`.

We add an extra argument `bool allowToExternConv` with the default value false.

```cpp
bool Check(ASTContext& ctx, Ptr<Ty> target, Ptr<Node> node, bool allowToExternConv = false);
```

1. When `allowToExternConv` is set, the target is `Extern<T>`, and `node` is an `Expr`:
    - the node is synthesized without a target;
    - the check succeeds if the resulting type `U` is valid;
    - `U` stays on the node, and diagnostics are the ones from synthesis.
2. Otherwise `Check` behaves exactly as before.

### Positions that pass `allowToExternConv = true`

| Position | Function | File |
|---|---|---|---|
| Variable initializer, including member variables | `SynchronizeTypeAndInitializer` | [TypeCheckDecl.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckDecl.cpp) |
| Assignment right-hand side | `SynAssignExpr` |[AssignExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/AssignExpr.cpp) |
| Call argument | `ChkFuncArg` | [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp) |
| `return` argument | `SynReturnExpr` | [ReturnExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/ReturnExpr.cpp) |
| Function body: functions, lambdas, property getters | `CheckBodyRetType` | | [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp) |

Everything else keeps the normal check against `Extern<T>`, so these are errors:
- array and tuple literal elements;
- default parameter values, which are checked separately;
- individual `if`/`match`/`try` branches. The whole expression can still be converted when it is itself in an allowed position.

### Overload ranking

Candidates that need no conversion are preferred over those that need one.

## Changes in DesugarAfterSema stage

### New pass

New file `src/Sema/Desugar/AfterTypeCheck/ExternDesugaring.cpp`. It rewrites both implicit conversions to `Extern<T>` (into `T.toExtern<U>(e)`) and dynamic operations on `Extern<T>` values (into `T.eval(tree)`), in a single walk.

```cpp
void TypeCheckerImpl::DesugarExtern(ASTContext& ctx, Package& pkg);
```

It is called in `PerformDesugarAfterSema` after `TryDesugarForCoalescing` and before `AutoBoxing::AddOptionBox`. This is before generic instantiation, so generic bodies are rewritten once, including `T.toExtern` on a generic `T`.

Call site in [AfterTypeCheck.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/Desugar/AfterTypeCheck.cpp):

```cpp
void TypeChecker::TypeCheckerImpl::PerformDesugarAfterSema(std::vector<Ptr<AST::Package>>& pkgs)
{
    TyVarScope ts(typeManager);
    for (auto& pkg : pkgs) {
        PerformDesugarAfterTypeCheck(*ci->pkgCtxMap[pkg], *pkg);
        TryDesugarForCoalescing(*pkg);
        DesugarExtern(*ci->pkgCtxMap[pkg], *pkg); // new
        AutoBoxing autoBox(typeManager);
        autoBox.AddOptionBox(*pkg);
    }
    ...
}
```

`PerformDesugarAfterSema` runs as the `DESUGAR_AFTER_SEMA` compile stage: after `SEMA`, before `GENERIC_INSTANTIATION`. See [CompilerInstance.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Frontend/CompilerInstance.cpp) and [CompileStrategy.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Frontend/CompileStrategy.cpp):

Passes in `PerformDesugarAfterSema`, in order, one example each:

| # | Pass | Before | After |
|---|---|---|---|
| 1 | `PerformDesugarAfterTypeCheck`: interop (Java, Objective-C, including glue code generation), declarations, and per-node rewrites such as `is`/`as`, ranges, string interpolation | `e is T` | `match (e) { case _: T => true case _ => false }` |
| 2 | `TryDesugarForCoalescing` | `opt ?? 11` | `match (opt) { case Some(x) => x case None => 11 }` |
| 3 | `DesugarExtern` **(new)** | `let e: Extern<RT> = 1` | `let e: Extern<RT> = RT.toExtern<Int64>(1)` |
| 4 | `AutoBoxing::AddOptionBox` | `let o: ?Int64 = 1` | `let o: ?Int64 = Some(1)` |

Each pass wraps the result of the earlier ones, because it takes the existing `desugarExpr` as its input. For example, `let e: Extern<RT> = opt ?? 11` becomes a `match` in pass 2, and pass 3 then wraps that: `RT.toExtern<Int64>(match (opt) { ... })`.

### Positions: one handler per allowed Sema position

A `Walker` visits the package. Each handler pairs a value with the type expected at its position:

| Node | Value | Expected type |
|---|---|---|
| `VarDecl` | `initializer` | type of the declaration |
| `AssignExpr` | `rightExpr` | type of `leftValue` |
| `CallExpr` | each argument | the matching parameter type in `baseFunc`'s function type |
| `ReturnExpr` | `expr` | return type of the enclosing function |
| `FuncBody` | last expression of `body` | return type |

### Rewrite

```text
if NeedExternConversion(U, Extern<T>):
    e.desugarExpr = T.toExtern<U>(e.desugarExpr, or a clone of e)
    e.ty          = Extern<T>
```

### The generated call

It is a fully typed AST and is not type checked again:

```text
CallExpr [IMPLICIT_ADD, CALL_DECLARED_FUNCTION, ty = Extern<T>, resolvedFunction = toExtern]
└─ MemberAccess "toExtern" [IMPLICIT_ADD, instTys = {U}, ty = (U) -> Extern<T>, matchedParentTy]
   └─ RefExpr T  (the runtime's declaration, or the GenericParamDecl for a generic T)
└─ FuncArg e
```

How `toExtern` is found:
- **Concrete `T`:** `FieldLookup(ctx, decl(T), "toExtern", {T, file})`, keeping a `static` function and preferring an implementation over the abstract declaration. This handles inheritance from a superclass or an interface default. When the method comes from an interface, `matchedParentTy = Promote(T, interface)`.
- **Generic `T`:** `ForeignRuntime<T>.toExtern`.
