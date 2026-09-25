# `Extern<T>` in the compiler

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

# Type checking

## Helpers

- `Ty::IsCoreExternType()` in [Types.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/include/cangjie/AST/Types.h) / [Types.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/AST/Types.cpp): an enum of the core package named `Extern` with one type argument. It uses the new constants `STD_LIB_EXTERN` and `STD_LIB_FOREIGN_RUNTIME` from [ConstantsUtils.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/include/cangjie/Utils/ConstantsUtils.h).
- `NeedExternConversion(from, to)` in [TypeCheckerImpl.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckerImpl.h) / [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp), shared by Sema and the desugaring:
  ```cpp
  // `to` is `Extern<T>`, `from` is a valid type, not `Nothing`, and not the same as `to`
  bool NeedExternConversion(Ty& from, Ty& to);
  ```
- Dynamic-node predicates in [TypeCheckUtil.h](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckUtil.h) / [TypeCheckUtil.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckUtil.cpp), shared by Sema and the desugaring:
  ```cpp
  // e has type Extern<T> and is a value, not a reference to the type (Extern<T>.ExternPayload(v) stays static)
  bool IsExternValue(const Expr& e);
  bool IsDynamicExternMemberAccess(const MemberAccess& ma); // e.f, not a left value
  bool IsDynamicExternSubscript(const SubscriptExpr& se);   // e[i1, ..., in], not a left value
  bool IsDynamicExternUpdate(const AssignExpr& ae);         // e.f = v, e[i1, ..., in] = v, and their op= forms
  bool IsDynamicExternCall(const CallExpr& ce);             // e(args), including e.f(args)
  ```

## `Extern` cannot be extended

`CheckExtendedTypeValidity` in [TypeCheckExtend.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExtend.cpp) reports `sema_illegal_extended_type` for `extend Extern<T>`, including through a type alias.

## For `toExtern`

### `Check` gets an opt-in flag

```cpp
bool Check(ASTContext& ctx, Ptr<Ty> target, Ptr<Node> node, bool allowToExternConv = false);
```

```text
if allowToExternConv and target is Extern<T> and node is an Expr:
    synthesize node without a target
    succeed if its type U is valid; U stays on the node
else:
    check as before
```

### Positions that pass `allowToExternConv = true`

| Position | Function | File |
|---|---|---|
| Variable initializer, including member variables | `SynchronizeTypeAndInitializer` | [TypeCheckDecl.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckDecl.cpp) |
| Assignment right-hand side | `SynAssignExpr` | [AssignExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/AssignExpr.cpp) |
| Call argument | `ChkFuncArg` | [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp) |
| `return` argument | `SynReturnExpr` | [ReturnExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/ReturnExpr.cpp) |
| Function body: functions, lambdas, property getters | `CheckBodyRetType` | [TypeChecker.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeChecker.cpp) |

Everything else keeps the normal check against `Extern<T>`, so these are errors:
- array and tuple literal elements;
- default parameter values;
- individual `if`/`match`/`try` branches. The whole expression can still be converted when it is itself in an allowed position.

### Overload ranking

In [TypeCheckCall.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckCall.cpp):

```text
CheckCandidate:   fmu.usesExternConversion = some argument needs NeedExternConversion to its parameter
CheckMatchResult: if some legal candidate has !usesExternConversion, drop the ones with usesExternConversion
```

## For `eval`

A dynamic node is typed `Extern<T>`, the type of its receiver. It has no target and no `desugarExpr`, and its operands are synthesized without a target, because the tree takes them as `Any`. So none of them is a `toExtern` position.

| Source | Where | Rule |
|---|---|---|
| `e.f` | `InferMemberAccess` in [NameReferenceExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp) | no member lookup, `ty = Extern<T>` |
| `e[i1, ..., in]` | `ChkSubscriptExpr` → `ChkExternSubscript` in [SubscriptExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/SubscriptExpr.cpp), before the `e.[](i)` rewrite | indices of any type |
| `e(args)`, `e.f(args)` | `ChkCallExpr` → `ChkExternCall` in [TypeCheckCall.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckCall.cpp), before candidate lookup; `ChkCallBaseMemberAccess` accepts the callee `e.f` | arguments of any type; named and `inout` arguments are errors |
| `e.f = v`, `e[i1, ..., in] = v` | `SynAssignExpr` → `SynExternUpdate` in [AssignExpr.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/TypeCheckExpr/AssignExpr.cpp), before operator overloading | no `IsAssignable` check, value of any type, `ty = Extern<T>` (not `Unit`) |
| `e.f op= v`, `e[i] op= v` | same as the update | `ty = Extern<T>` |

`SynExternUpdate` in pseudocode:

```text
if ae.leftValue is e.f or e[i1, ..., in]:
    synthesize e
    if IsDynamicExternUpdate(ae):
        synthesize the indices and v without a target
        ae.leftValue.ty = ae.ty = e.ty
```

No other change is needed for:
- **Operators.** `e1 + e2` and `-e` are already rewritten into `e1.+(e2)` and `e.-()`, which are dynamic calls of type `Extern<T>`. So `if (e1 < e2)` is an error: the condition is not `Bool`.
- **`++` and `--`,** which stay errors: they need an integer type.
- **A statically resolved compound assignment `lhs op= v`** (a variable, a Cangjie field or a Cangjie array element of type `Extern<T>`). Sema's rewrite `lhs = lhs.op(v)` checks as usual: `lhs` must be mutable, the type is `Unit`, and `lhs.op(v)` is a dynamic call.
- **A multiple assignment `(e.x, b) = (1, 2)`,** which becomes one dynamic update per element.

### Type check cache

Sema may check a node several times and restore its targets from a cache. `CollectTargets` only records the target of the receiver of a member access that has a target. `RestoreTargets` in [Cache.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/AST/Cache.cpp) must match, otherwise it clears the target of `e` in a dynamic `e.f`:

```cpp
if (auto ma = DynamicCast<const MemberAccess*>(&node);
       targets.first && ma && ma->baseExpr && ma->baseExpr->IsReferenceExpr()) { // targets.first is new
    ma->baseExpr->SetTarget(targets.second);
}
```

# Desugaring

## The pass

New file `src/Sema/Desugar/AfterTypeCheck/ExternDesugaring.cpp`:

```cpp
void TypeCheckerImpl::DesugarExtern(ASTContext& ctx, Package& pkg);
```

It is called in `PerformDesugarAfterSema` in [AfterTypeCheck.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Sema/Desugar/AfterTypeCheck.cpp):

```cpp
for (auto& pkg : pkgs) {
    PerformDesugarAfterTypeCheck(*ci->pkgCtxMap[pkg], *pkg);
    TryDesugarForCoalescing(*pkg);
    DesugarExtern(*ci->pkgCtxMap[pkg], *pkg); // new
    AutoBoxing autoBox(typeManager);
    autoBox.AddOptionBox(*pkg);
}
```

`PerformDesugarAfterSema` is the `DESUGAR_AFTER_SEMA` stage: after `SEMA`, before `GENERIC_INSTANTIATION` (see [CompilerInstance.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Frontend/CompilerInstance.cpp) and [CompileStrategy.cpp](https://gitcode.com/Cangjie/cangjie_compiler/blob/main/src/Frontend/CompileStrategy.cpp)). So generic bodies are rewritten once, including calls on a generic runtime `T`. The stage doesn't run when Sema reported errors.

| # | Pass | Before | After |
|---|---|---|---|
| 1 | `PerformDesugarAfterTypeCheck`: interop, declarations, and per-node rewrites such as `is`/`as`, ranges, string interpolation | `e is T` | `match (e) { case _: T => true case _ => false }` |
| 2 | `TryDesugarForCoalescing` | `opt ?? 11` | `match (opt) { case Some(x) => x case None => 11 }` |
| 3 | `DesugarExtern` **(new)** | `let e: Extern<RT> = 1` | `let e: Extern<RT> = RT.toExtern<Int64>(1)` |
| 4 | `AutoBoxing::AddOptionBox` | `let o: ?Int64 = 1` | `let o: ?Int64 = Some(1)` |

Each pass wraps the `desugarExpr` of the earlier ones. For example `let e: Extern<RT> = opt ?? 11` becomes `RT.toExtern<Int64>(match (opt) { ... })`.

A single `Walker` does both rewrites:

```text
visit(node):
    if node is a static compound assignment on Extern<T>: prepare it (see below)
    if node is dynamic:
        node.desugarExpr = T.eval(BuildTree(node))
        visit(node.desugarExpr)   // the leaves may contain conversions and dynamic operations
        skip children
    else:
        apply the conversion handler of node
```

## Conversions

Each handler pairs a value with the type expected at its Sema position:

| Node | Value | Expected type |
|---|---|---|
| `VarDecl` | `initializer` | type of the declaration |
| `AssignExpr` | `rightExpr` | type of `leftValue` |
| `CallExpr` | each argument | the matching parameter type of `baseFunc` |
| `ArrayExpr` | the item of `Array<E>(n, item: v)` or `VArray` | `E` |
| `ReturnExpr` | `expr` | return type of the enclosing function |
| `FuncBody` | last expression of `body` | return type |

```text
if NeedExternConversion(U, Extern<T>):
    e.desugarExpr = T.toExtern<U>(e.desugarExpr, or a clone of e)
    e.ty          = Extern<T>
```

## Dynamic operations

The outermost dynamic node becomes `T.eval(tree)`. Nested dynamic nodes become nodes of the tree. Any other expression, including a plain `Extern` variable, is a leaf: it is cloned and desugared on its own.

```text
BuildTree(x) = x is dynamic ? node for x : clone(x)
```

| Source | Tree |
|---|---|
| `e.f` | `ExternMemberAccess(BuildTree(e), "f")` |
| `e[i]` | `ExternIndexedAccess(BuildTree(e), BuildTree(i))` |
| `e[i, j, k]` | `ExternIndexedAccess(ExternIndexedAccess(ExternIndexedAccess(BuildTree(e), i), j), k)`, each index built |
| `e(a1, ..., an)` | `ExternFunctionCall(BuildTree(e), [BuildTree(a1), ..., BuildTree(an)])` |
| `e.f = v` | `ExternMemberUpdate(BuildTree(e), "f", BuildTree(v))` |
| `e[i, j, k] = v` | `ExternIndexedUpdate(<tree of e[i, j]>, BuildTree(k), BuildTree(v))` |
| `a op= v`, `a` a dynamic access | `ExternCompoundAssignment(<tree of a>, "op", BuildTree(v))`, `op` without `=` |

Examples:

```cangjie
e.a.b(1)           // T.eval(ExternFunctionCall(ExternMemberAccess(ExternMemberAccess(e, "a"), "b"), [1]))
obj.f().x.y += v   // T.eval(ExternCompoundAssignment(ExternMemberAccess(obj.f().x, "y"), "+", v))
e.f(x, { y: Extern<T> => y.g })
                   // T.eval(ExternFunctionCall(ExternMemberAccess(e, "f"), [x, { y => T.eval(ExternMemberAccess(y, "g")) }]))
```

Evaluation order of the operands is left to the runtime's `eval`.

### Statically resolved compound assignment

Sema rewrites `lhs op= v` into `lhs = lhs'.op(v)`, where the copy `lhs'` has `mapExpr = lhs` so that the receiver is evaluated once. `lhs'` becomes a leaf of the tree and is read as a value, while CHIR resolves `mapExpr` to a reference to `lhs`. So the pass, before building the tree:

```text
lhs'.mapExpr = null
if lhs is base.x and base may have side effects:   // anything but a variable, a type or a package, possibly through fields
    { let tmp = base; tmp.x = T.eval(ExternFunctionCall(ExternMemberAccess(tmp.x, "op"), [v])) }
```

## The generated calls

They are fully typed ASTs and are not type checked again:

```text
CallExpr [IMPLICIT_ADD, CALL_DECLARED_FUNCTION, ty = Extern<T>, resolvedFunction = toExtern | eval]
└─ MemberAccess [IMPLICIT_ADD, instTys = {U} for toExtern, ty = (U) -> Extern<T> | (Extern<T>) -> Extern<T>, matchedParentTy]
   └─ RefExpr T  (the runtime's declaration, or the GenericParamDecl for a generic T)
└─ FuncArg e | tree
```

The tree nodes are calls of the enum constructors, instantiated for `Extern<T>`, with `IMPLICIT_ADD`. The arguments of `ExternFunctionCall` are an `Array<Any>` literal.

### Runtime function lookup

`LookupForeignRuntimeFunc(ctx, T, name, pos)` is shared by `toExtern` and `eval`:

- **Concrete `T`:** `FieldLookup(ctx, decl(T), name, {T, pos.curFile})`, keeping a `static` function and preferring an implementation over the abstract declaration. This handles inheritance from a superclass or an interface default. When the function comes from an interface, `matchedParentTy = Promote(T, interface)`. If only the abstract declaration is found, it reports `sema_interface_call_with_unimplemented_call` at `pos`, like a hand-written `T.name(...)`.
- **Generic `T`:** `ForeignRuntime<T>.name`.
