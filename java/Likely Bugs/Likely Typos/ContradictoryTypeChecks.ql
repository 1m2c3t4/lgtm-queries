// Copyright 2017 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * @name Contradictory type checks
 * @description Contradictory dynamic type checks in `instanceof` expressions
 *              and casts may cause dead code or even runtime errors, and usually
 *              indicate a logic error.
 * @kind problem
 * @problem.severity warning
 * @precision very-high
 * @tags correctness
 *       logic
 */

import java
import semmle.code.java.dataflow.Guards
import semmle.code.java.dataflow.SSA

/** `ioe` is of the form `va instanceof t`. */
predicate instanceOfCheck(InstanceOfExpr ioe, VarAccess va, RefType t) {
  ioe.getExpr().getProperExpr() = va and
  ioe.getTypeName().getType().(RefType).getSourceDeclaration() = t
}

/** Expression `e` assumes that `va` could be of type `t`. */
predicate requiresInstanceOf(Expr e, VarAccess va, RefType t) {
  // `e` is a cast of the form `(t)va`
  e.(CastExpr).getExpr() = va and t = e.getType().(RefType).getSourceDeclaration() or
  // `e` is `va instanceof t`
  instanceOfCheck(e, va, t)
}

/**
 * `e` assumes that `v` could be of type `t`, but `cond`, in fact, ensures that
 * `v` is not of type `sup`, which is a supertype of `t`.
 */
predicate contradictoryTypeCheck(Expr e, Variable v, RefType t, RefType sup, Expr cond) {
  exists(SsaVariable ssa, ConditionBlock cb |
    ssa.getSourceVariable().getVariable() = v and
    requiresInstanceOf(e, ssa.getAUse(), t) and
    sup = t.getASupertype*() and
    cb.getCondition() = cond and
    instanceOfCheck(cond, ssa.getAUse(), sup) and
    cb.controls(e.getBasicBlock(), false)
  )
}

from Expr e, Variable v, RefType t, RefType sup, Expr cond
where
  contradictoryTypeCheck(e, v, t, sup, cond)
select e, "Variable $@ cannot be of type $@ here, since $@ ensures that it is not of type $@.",
          v, v.getName(), t, t.getName(), cond, "this expression", sup, sup.getName()
