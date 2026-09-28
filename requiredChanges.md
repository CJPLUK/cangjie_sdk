# 1. `Extern<T>` in the compiler

`std.core` declares a value of a foreign runtime `T` and the runtime interface:

```cangjie
public enum Extern<T> where T <: ForeignRuntime<T> {
    | ExternPayload(Any)
    | ExternMemberAccess(Extern<T>, String)
    | ExternIndexedAccess(Extern<T>, Any)
    | ExternMemberUpdate(Extern<T>, String, Any)
    | ExternIndexedUpdate(Extern<T>, Any, Any)
    | ExternFunctionCall(Extern<T>, Array<Any>)
    | ExternCompoundAssignment(Extern<T>, String, Any)
    | ...
}

public interface ForeignRuntime<T> where T <: ForeignRuntime<T> {
    static func fromExtern<R>(e: Extern<T>): R
    static func toExtern<R>(v: R): Extern<T>
    static func eval(t: Extern<T>): Extern<T>
}
```

The compiler introduces two rewrites:

| Rewrite | Source | Result |
|---|---|---|
| Implicit conversion | `e: U` where `Extern<T>` is expected | `T.toExtern<U>(e)` |
| Dynamic operation | `e.f`, `e[i]`, `e(args)`, `e.f = v`, `e[i] = v`, `e.f op= v` with `e: Extern<T>` | `T.eval(tree)` |

Sema only accepts these expressions and gives them their types. The rewrites happen in one pass after Sema, driven by the final types.

# 2. Helpers

- `Ty::IsCoreExternType()` in [Types.h](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/include/cangjie/AST/Types.h) / [Types.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/AST/Types.cpp): an enum of the core package named `Extern` with one type argument. It uses the new constants `STD_LIB_EXTERN` and `STD_LIB_FOREIGN_RUNTIME` from [ConstantsUtils.h](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/include/cangjie/Utils/ConstantsUtils.h).

- `NeedExternConversion(from, to)` in [TypeCheckerImpl.h](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckerImpl.h) / [TypeChecker.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeChecker.cpp), shared by Sema and the desugaring:
  ```cpp
  // `to` is `Extern<T>`, `from` is a valid type, not `Nothing`, and not the same as `to`
  bool NeedExternConversion(Ty& from, Ty& to);
  ```
- Dynamic-node predicates in [TypeCheckUtil.h](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckUtil.h) / [TypeCheckUtil.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckUtil.cpp), shared by Sema and the desugaring:
  ```cpp
  // e is a value of type Extern<T>, not the type name Extern<T> itself
  // (so Extern<T>.ExternPayload(v) is a normal enum constructor call, not a dynamic access)
  bool IsExternValue(const Expr& e);

  // ma is a read of any member f of an Extern<T> value e: e.f
  // (a left value e.f in e.f = v is handled by IsDynamicExternUpdate)
  bool IsDynamicExternMemberAccess(const MemberAccess& ma);

  // se is a read of an index of any type on an Extern<T> value e: e[i]
  // (a left value e[i] in e[i] = v is handled by IsDynamicExternUpdate)
  bool IsDynamicExternSubscript(const SubscriptExpr& se);

  // ae assigns to a member or to an index of an Extern<T> value e:
  // e.f = v, e[i] = v, e.f op= v, e[i] op= v
  bool IsDynamicExternUpdate(const AssignExpr& ae);

  // ce calls an Extern<T> value e with arguments of any type: e(a1, ..., an)
  // (this includes e.f(a1, ..., an), whose callee e.f is itself a dynamic member access)
  bool IsDynamicExternCall(const CallExpr& ce);
  ```
- `LookupForeignRuntimeFunc(ctx, T, name, pos)` in [TypeCheckerImpl.h](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckerImpl.h) / [ExternDesugaring.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/Desugar/AfterTypeCheck/ExternDesugaring.cpp), used by the desugaring to find `toExtern` and `eval`.

# 3. Type checking

## 3.1. `Extern` cannot be extended

`CheckExtendedTypeValidity` in [TypeCheckExtend.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExtend.cpp) reports `sema_illegal_extended_type` for `extend Extern<T>`, including through a type alias.

## 3.2. Implicit conversions

### `Check` gets an opt-in flag

Function `Check` declared in `https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeChecker.cpp` is modified to receive an extra argument: `allowToExternConv`. This indicates whether an implicit extern conversion is allowed to be inserted.

```cpp
bool Check(ASTContext& ctx, Ptr<Ty> target, Ptr<Node> node, bool allowToExternConv = false);
```

```text
if allowToExternConv and target is Extern<T> and node is an Expr that is not Extern<T>:
    synthesize node without a target
    succeed if the resulting type is a valid type
else:
    check as before
```

### Positions that pass `allowToExternConv = true`

| Position | Function | File |
|---|---|---|
| Variable initializer, including member variables | `SynchronizeTypeAndInitializer` | [TypeCheckDecl.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckDecl.cpp) |
| Assignment right-hand side | `SynAssignExpr` | [AssignExpr.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExpr/AssignExpr.cpp) |
| Call argument | `ChkFuncArg` | [TypeChecker.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeChecker.cpp) |
| `return` argument | `SynReturnExpr` | [ReturnExpr.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExpr/ReturnExpr.cpp) |
| Function body: functions, lambdas, property getters | `CheckBodyRetType` | [TypeChecker.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeChecker.cpp) |

Everything else keeps the normal check against `Extern<T>`, so these are errors:
- default parameter values;
- array and tuple literal elements;
- individual `if`/`match`/`try` branches. The whole expression can still be converted when it is itself in an allowed position.

### Overload ranking

In [TypeCheckCall.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckCall.cpp):

Candidates that need no conversion are preferred. Among the remaining candidates the usual most-specific rule applies, and an ambiguity is an error.

## 3.3. Dynamic operations

A dynamic node is typed `Extern<T>`, the type of its receiver.

| Source | Where | Rule |
|---|---|---|
| `e.f` | `InferMemberAccess` in [NameReferenceExpr.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp) | if `e: Extern<T>` then `ty = Extern<T>` |
| `e[idx]` | `ChkSubscriptExpr` in [SubscriptExpr.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExpr/SubscriptExpr.cpp)  |  if `e: Extern<T>` then `ty = Extern<T>`, `idx` has any valid type |
| `e(args)`, `e.f(args)` | `ChkCallExpr` in [TypeCheckCall.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckCall.cpp), before candidate lookup | if `e: Extern<T>`/`e.f : Extern<T>` then `ty = Extern<T>`; arguments of any type; named and `inout` arguments are errors |
| `e.f = v`, `e[idx] = v` | `SynAssignExpr` in [AssignExpr.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/TypeCheckExpr/AssignExpr.cpp), before operator overloading | if `e : Extern<T>` then `ty = Extern<T>`; `v`, `idx` of any type |
| `e.f op= v`, `e[i] op= v` | same as the update | `ty = Extern<T>` |

synthesize `e.f` in pseudocode:

```text
synthesize e
if IsDynamicExternMemberAccess(ma):    // e is an Extern<T> value, e.f is not a left value
    ma.ty = e.ty                       // no member lookup, no target
```

synthesize `e[idx]` in pseudocode:

```text
synthesize e and the index             // already done for every subscript
if IsDynamicExternSubscript(se):       // before the rewrite into e.[](idx)
    se.ty = e.ty
```

synthesize `e(args)`, `e.f(args)` in pseudocode:

```text
synthesize the callee e                // a dynamic callee e.f is accepted as it is
if IsDynamicExternCall(ce):            // before candidate lookup
    report named and inout arguments
    synthesize the arguments without a target
    ce.ty = e.ty
```

synthesize `e.f = v`, `e[idx] = v` in pseudocode:

```text
if ae.leftValue is e.f or e[idx]:
    synthesize e
    if IsDynamicExternUpdate(ae):
        synthesize the index and v without a target
        ae.leftValue.ty = ae.ty = e.ty
```

When one of these nodes is checked against an expected type, `Extern<T>` must be a subtype of it.

No other change is needed for:
- **Operators.** `e1 + e2` and `-e` are already rewritten into `e1.+(e2)` and `e.-()`, which are dynamic calls of type `Extern<T>`. So `if (e1 < e2)` is an error: the condition is not `Bool`.
- **`++` and `--`,** which stay errors: they need an integer type.
- **A multiple assignment `(e.x, b) = (1, 2)`,** which becomes one dynamic update per element.

# 4. Desugaring

## 4.1. The pass

New file [ExternDesugaring.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/Desugar/AfterTypeCheck/ExternDesugaring.cpp):

```cpp
void TypeCheckerImpl::DesugarExtern(ASTContext& ctx, Package& pkg);
```

It is called in `PerformDesugarAfterSema` in [AfterTypeCheck.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Sema/Desugar/AfterTypeCheck.cpp):

```cpp
for (auto& pkg : pkgs) {
    PerformDesugarAfterTypeCheck(*ci->pkgCtxMap[pkg], *pkg);
    TryDesugarForCoalescing(*pkg);
    DesugarExtern(*ci->pkgCtxMap[pkg], *pkg); // new
    AutoBoxing autoBox(typeManager);
    autoBox.AddOptionBox(*pkg);
}
```

`PerformDesugarAfterSema` is the `DESUGAR_AFTER_SEMA` stage: after `SEMA`, before `GENERIC_INSTANTIATION` (see [CompilerInstance.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Frontend/CompilerInstance.cpp) and [CompileStrategy.cpp](https://github.com/CJPLUK/cangjie_compiler/blob/feature_extern_with_enum/src/Frontend/CompileStrategy.cpp)). So generic bodies are rewritten once, including calls on a generic runtime `T`. The stage doesn't run when Sema reported errors.

| # | Pass | Before | After |
|---|---|---|---|
| 1 | `PerformDesugarAfterTypeCheck`: interop, declarations, and per-node rewrites such as `is`/`as`, ranges, string interpolation | `e is T` | `match (e) { case _: T => true case _ => false }` |
| 2 | `TryDesugarForCoalescing` | `opt ?? 11` | `match (opt) { case Some(x) => x case None => 11 }` |
| 3 | `DesugarExtern` **(new)** | `let e: Extern<RT> = 1` | `let e: Extern<RT> = RT.toExtern<Int64>(1)` |
| 4 | `AutoBoxing::AddOptionBox` | `let o: ?Int64 = 1` | `let o: ?Int64 = Some(1)` |

## 4.2. Implicit conversions

The pass converts a value `e: U` wherever `Extern<T>` is expected in the following cases:

| Node | Value `e` | Expected type | Example | Desugared |
|---|---|---|---|---|
| `VarDecl` | `initializer expression` | type of the declaration | `let x: Extern<RT> = 1` | `let x: Extern<RT> = RT.toExtern<Int64>(1)` |
| `AssignExpr` | `rightExpr` | type of `leftValue` | `x = "a"` | `x = RT.toExtern<String>("a")` |
| `CallExpr` | each argument | the matching parameter type of `baseFunc` | `f(1)` with `func f(p: Extern<RT>)` | `f(RT.toExtern<Int64>(1))` |
| `ReturnExpr` | `expr` | return type of the enclosing function | `return true` in `func g(): Extern<RT>` | `return RT.toExtern<Bool>(true)` |
| `FuncBody` | last expression of `body` | return type | `func g(): Extern<RT> { 1 }` | `func g(): Extern<RT> { RT.toExtern<Int64>(1) }` |

```text
if NeedExternConversion(U, Extern<T>):
    e.desugarExpr = T.toExtern<U>(e.desugarExpr /* or a clone of e */)
    e.ty          = Extern<T>
```

## 4.3. Dynamic operations

A dynamic node is one of the expressions recognized by the `IsDynamicExtern*` predicates (section 2) that has no `desugarExpr` yet. It becomes `T.eval(tree)`, where `tree` is a value of `Extern<T>` that describes the operation with the constructors of `Extern<T>`. A chain of dynamic nodes, such as `e.a.b(1)`, gets a single `T.eval` around the tree of the whole chain.

### Finding the outermost dynamic node

The walk visits parents before children:

```text
visit(node):
    if node is dynamic:
        node.desugarExpr = T.eval(BuildTree(node))
        visit(node.desugarExpr)      // the leaves of the tree may contain dynamic nodes of their own
        skip the children of node    // the nested dynamic nodes are already part of the tree
    else:
        visit the children of node
```

So the first dynamic node met on the way down is the outermost one:
- in `e.a.b(1)`, the call is visited before `e.a.b` and `e.a`;
- in `f(e.a)`, the call `f(...)` is a normal Cangjie call, so the walk goes on into its argument, and `e.a` is the outermost dynamic node there.

### Building the tree

`BuildTree` turns a dynamic node into a constructor call of `Extern<T>`, and applies itself to the operands. An operand that is not dynamic (a variable, a literal, a normal call, a lambda, ...) is copied unchanged into the tree, as a leaf:

```text
BuildTree(x):
    if x is not dynamic:
        return clone(x)
    match x:
        e.f                  => ExternMemberAccess(BuildTree(e), "f")
        e(a1, ..., an)       => ExternFunctionCall(BuildTree(e), [BuildTree(a1), ..., BuildTree(an)])
        e[i]                 => ExternIndexedAccess(BuildTree(e), BuildTree(i))
        e.f = v              => ExternMemberUpdate(BuildTree(e), "f", BuildTree(v))
        e[i] = v             => ExternIndexedUpdate(BuildTree(e), BuildTree(i), BuildTree(v))
        a op= v              => ExternCompoundAssignment(<tree of the access a>, "op", BuildTree(v))   // "+" for +=
```

Parentheses around a dynamic node are dropped: `(e.a).b` is built like `e.a.b`.

Examples:

```cangjie
e.a.b(1)           // T.eval(ExternFunctionCall(ExternMemberAccess(ExternMemberAccess(e, "a"), "b"), [1]))
e[i] = v           // T.eval(ExternIndexedUpdate(e, i, v))
obj.f().x.y += v   // T.eval(ExternCompoundAssignment(ExternMemberAccess(obj.f().x, "y"), "+", v))
                   // obj.f().x is a Cangjie field of type Extern<T>, so it is a leaf
g(e.a).b           // T.eval(ExternMemberAccess(g(T.eval(ExternMemberAccess(e, "a"))), "b"))
                   // g returns Extern<T>; the leaf g(e.a) gets its own T.eval when the walk visits it
e.f(x, { y: Extern<T> => y.g })
                   // T.eval(ExternFunctionCall(ExternMemberAccess(e, "f"), [x, { y => T.eval(ExternMemberAccess(y, "g")) }]))
```

## 4.4. The generated calls

The pass creates fully typed ASTs, which are not type checked again. The calls, their callees and the `Array` literal are marked `IMPLICIT_ADD`. The created nodes take the source position of the node they replace.

### `T.toExtern<U>(e)`

```text
CallExpr [CALL_DECLARED_FUNCTION, resolvedFunction = toExtern, ty = Extern<T>]
├─ MemberAccess "toExtern" [target = toExtern, instTys = {U}, ty = (U) -> Extern<T>]
│  └─ RefExpr T [ty = T]    // the runtime's declaration, or the GenericParamDecl for a generic T
└─ FuncArg [ty = U]
   └─ e                     // its previous desugarExpr, or a clone of e
```

### `T.eval(tree)`

```text
CallExpr [CALL_DECLARED_FUNCTION, resolvedFunction = eval, ty = Extern<T>]
├─ MemberAccess "eval" [target = eval, ty = (Extern<T>) -> Extern<T>]
│  └─ RefExpr T [ty = T]
└─ FuncArg [ty = Extern<T>]
   └─ tree
```

`matchedParentTy` is set when the function is found in an interface (see `LookupForeignRuntimeFunc` in section 2).

### Tree nodes

Every node of the tree is a call of a constructor of `Extern<T>`:

```text
CallExpr [CALL_DECLARED_FUNCTION, resolvedFunction = C, ty = Extern<T>]
├─ RefExpr C [ty = the type of C with T substituted, e.g. (Extern<T>, String) -> Extern<T>]
└─ FuncArg [ty = type of the argument] x one per parameter of C
```

The arguments of each constructor:

| Constructor `C` | Arguments |
|---|---|
| `ExternMemberAccess` | `BuildTree(e)`; the name `f` as a `String` literal |
| `ExternIndexedAccess` | `BuildTree(e)`; `BuildTree(i)` |
| `ExternFunctionCall` | `BuildTree(e)`; an `Array<Any>` literal, with its constructor set, holding `BuildTree(a)` for each argument `a` |
| `ExternMemberUpdate` | `BuildTree(e)`; the name `f` as a `String` literal; `BuildTree(v)` |
| `ExternIndexedUpdate` | `BuildTree(e)`; `BuildTree(i)`; `BuildTree(v)` |
| `ExternCompoundAssignment` | the constructor call for the access `e.f` or `e[i]`; the operator without `=` as a `String` literal (`"+"` for `+=`); `BuildTree(v)` |

`BuildTree(x)` is a nested constructor call of type `Extern<T>` only when `x` is dynamic. Otherwise it is a clone of `x`, with its own type, even where the parameter is `Any`.