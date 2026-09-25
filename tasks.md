# Remaining Extern tasks

Scope: dynamic operations on `Extern<T>` from `extern_architecture.md`, excluding the forced cast `(U)e` and the CHIR `ExternSequence` optimizations (section 4.2).

Implement in vertical slices: for each operation, add the Sema typing and the desugaring together, then enable its tests. A type-checked dynamic node without desugaring has no target or call kind and breaks CHIR.

After every step, rerun the `toExtern` tests (11/11) and the `compiler/Sema` suite (14 known failures).

## Agreed semantics

- A dynamic operation is `e.f`, `e[i]`, `e(args)`, `e.f = v`, `e[i] = v`, or `e op= v` whose receiver `e` is an `Extern<T>` value (not the type `Extern<T>`). Its type is `Extern<T>`, including `e.f = v` and `e[i] = v`, because it desugars to `T.eval(...)`.
- A multi-index subscript `e[i, j, k]` means `e[i][j][k]`. Only the last index is updated:
  ```cangjie
  // e[i, j, k]
  T.eval(ExternIndexedAccess(ExternIndexedAccess(ExternIndexedAccess(e, i), j), k))
  // e[i, j, k] = v
  T.eval(ExternIndexedUpdate(ExternIndexedAccess(ExternIndexedAccess(e, i), j), k, v))
  ```
- `BUILD_TREE` only builds a tree for dynamic operations. Any other expression, including a plain `Extern` variable, is kept as is, and its sub-expressions are desugared normally.
- Compound assignment is decided by the last access on the left-hand side:
  - **Statically resolved** (a local variable, a field of a Cangjie object, or an element of a Cangjie array) of type `Extern<T>`: normal Cangjie compound assignment. The left side must be mutable, and the type is `Unit`. The receiver is evaluated once.
    ```cangjie
    // obj1.f().x op= xpto
    let tmp = obj1.f()
    tmp.x = T.eval(ExternFunctionCall(ExternMemberAccess(tmp.x, "op"), [xpto]))
    ```
  - **Dynamic** (`.y` or `[i]` on an `Extern` receiver): the type is `Extern<T>`.
    ```cangjie
    // obj1.f().x.y op= xpto
    T.eval(ExternCompoundAssignment(ExternMemberAccess(obj1.f().x, "y"), "op", xpto))
    ```
- Binary and unary operators on `Extern` are dynamic calls of the operator, e.g. `e1 + e2` is `T.eval(ExternFunctionCall(ExternMemberAccess(e1, "+"), [e2]))` of type `Extern<T>`. `binaryOps.cj` expects this: `if (e1 < e2)` fails because the condition is not `Bool`.
- `++` and `--` on `Extern` remain errors, since they require an integer type.

## Tasks

1. **Reject `extend Extern`**, including through a type alias.
   - Independent and small.
   - Tests: `extendExtern.cj`, `alias2.cj`.

2. **`e.f`, together with the skeleton of the new desugar pass.**
   - Sema: when the receiver is an `Extern` value, the member access is dynamic (`InferMemberAccess`/`SynMemberAccess`). `Extern<T>.ExternPayload(v)` keeps working.
   - Set up the shared pieces:
     - the check "is the receiver an `Extern` value";
     - the dynamic-node convention (type `Extern<T>`, no target, no `desugarExpr`);
     - the `BUILD_TREE` recursion and the `T.eval` wrapping;
     - the lookup of `eval`, reusing the `toExtern` lookup for concrete and generic runtimes;
     - the position of the pass relative to the `toExtern` pass.
   - Check that the checks running between Sema and the desugar pass tolerate nodes without a target.
   - Tests: `memberAccess*`, `alias1`.

3. **`e[i]`.**
   - Branch in `ChkSubscriptExpr` next to the tuple/`VArray` cases, before the `e.[](i)` rewrite.
   - Desugar to `ExternIndexedAccess`.
   - Tests: `indexAccess*`, then `indexAndMemberAccess*`.

4. **`e(args)` and `e.f(args)`.**
   - Branch in `ChkCallExpr` before candidate lookup and before the `e.()(args)` rewrite.
   - Synthesize the arguments; they are not `toExtern` conversion positions.
   - Decide about named arguments, trailing or untyped lambdas, and `x |> e`.
   - Desugar to `ExternFunctionCall`.
   - Tests: `functionCall*`, `nestedExterns`.

5. **`e.f = v` and `e[i] = v`.**
   - Branch in `SynAssignExpr` (skip `IsAssignable` and the check of `v` against the left type).
   - Branch in `InferAssignExprCheckCaseOverloading` before `DesugarSubscriptOverloadExpr`.
   - The result type is `Extern<T>`.
   - Desugar to `ExternMemberUpdate` and `ExternIndexedUpdate`, with nested `ExternIndexedAccess` nodes for all but the last index of `e[i, j, k] = v`.
   - Tests: `memberAccessUpdate*`, `indexAccessUpdate*`, `indexAccessAndUpdate`.

6. **Compound assignment.** Depends on tasks 4 and 5.
   - Dynamic last access: branch at the start of `InferAssignExprCheckCaseOverloading`, and desugar to `ExternCompoundAssignment`.
   - Statically resolved left side: the existing rewrite `lhs = lhs.op(v)` type checks as a dynamic call. The copy of `lhs` in the tree must not keep its `mapExpr`, which CHIR resolves to a reference to `lhs`. If the receiver of `lhs` may have side effects, it is stored first: `{ let tmp = base; tmp.x = T.eval(...tmp.x...) }`.
   - Tests: `compoundAssignment.cj`.

7. **Generics and the remaining tests.**
   - `generics/`, `extern_exceptions`, `inheritedRuntimeImpl`, `interfaceRuntimeUnimplemented`, and `getPayload*`, renamed to `externPayload*` because they don't use `getPayload`.
   - `interfaceRuntimeUnimplemented`: the desugaring reports calls of `eval` and `toExtern` that a runtime doesn't implement, like Sema does for a hand-written call. The desugaring doesn't run after a Sema error, so the `fromExtern` case moved to `interfaceRuntimeUnimplementedFromExtern`.
   - The negative test `binaryOps`.
   - A new test for multiple assignment `(e.x, b) = (1, 2)`: `multipleAssignment`.
   - Add all of them to `extern_testlist` (excluding `forced_cast/`).

8. **Cleanup.**
   - Check `.cjo` export and incremental compilation for generic functions that use dynamic operations.
   - Extend `requiredChanges.md`.
