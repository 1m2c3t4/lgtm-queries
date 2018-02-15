// Copyright 2018 Semmle Ltd.
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

import semmle.code.java.arithmetic.Overflow
import semmle.code.java.controlflow.Dominance
import semmle.code.java.dataflow.DefUse
import semmle.code.java.dataflow.Guards

/*
 * The type of `exp` is narrower than or equal to `numType`,
 * or there is an enclosing cast to a type at least as narrow as 'numType'.
 */
predicate narrowerThanOrEqualTo(ArithExpr exp, NumType numType) {
  exp.getType().(NumType).widerThan(numType) implies
   exists(CastExpr cast | cast.getAChildExpr().getProperExpr() = exp |
     numType.widerThanOrEqualTo((NumType)cast.getType())
   )
}

/** Holds if the size of this use is guarded using `Math.abs`. */
predicate guardedAbs(ArithExpr e, Expr use) {
  exists(MethodAccess m |
    m.getMethod() instanceof MethodAbs |
    m.getArgument(0) = use
    and guardedLesser(e, m)
  )
}

/** Holds if the size of this use is guarded to be less than something. */
predicate guardedLesser(ArithExpr e, Expr use) {
  exists(ConditionBlock c, ComparisonExpr guard |
    use = guard.getLesserOperand() and
    guard = c.getCondition() and
    c.controls(e.getBasicBlock(), true)
  )
  or guardedAbs(e, use)
}

/** Holds if the size of this use is guarded to be greater than something. */
predicate guardedGreater(ArithExpr e, Expr use) {
  exists(ConditionBlock c, ComparisonExpr guard |
    use = guard.getGreaterOperand() and
    guard = c.getCondition() and
    c.controls(e.getBasicBlock(), true)
  )
  or guardedAbs(e, use)
}

/** Holds if this expression is (crudely) guarded by `use`. */
predicate guarded(ArithExpr e, Expr use) {
  exists(ConditionBlock c, ComparisonExpr guard |
    use = guard.getAnOperand() and
    guard = c.getCondition() and
    c.controls(e.getBasicBlock(), true)
  )
}

/** A prior use of the same variable that could see the same value. */
VarAccess priorAccess(VarAccess access) {
  useUsePair(result, access)
}

/** Holds if `e` is guarded against overflow by `use`. */
predicate guardedAgainstOverflow(ArithExpr e, VarAccess use) {
  use = e.getAnOperand() and
  (
    // overflow possible if large
    (e instanceof AddExpr and guardedLesser(e, priorAccess(use))) or
    // overflow unlikely with subtraction
    (e instanceof SubExpr) or
    // overflow possible if large or small
    (e instanceof MulExpr and guardedLesser(e, priorAccess(use)) and
      guardedGreater(e, priorAccess(use))) or
    // overflow possible if MIN_VALUE
    (e instanceof DivExpr and guardedGreater(e, priorAccess(use)))
  )
}

/** Holds if `e` is guarded against underflow by `use`. */
predicate guardedAgainstUnderflow(ArithExpr e, VarAccess use) {
  use = e.getAnOperand() and
  (
    // underflow unlikely for addition
    (e instanceof AddExpr) or
    // underflow possible if use is left operand and small
    (e instanceof SubExpr and (use = e.getRightOperand() or guardedGreater(e, priorAccess(use)))) or
    // underflow possible if large or small
    (e instanceof MulExpr and guardedLesser(e, priorAccess(use)) and
      guardedGreater(e, priorAccess(use))) or
    // underflow possible if MAX_VALUE
    (e instanceof DivExpr and guardedLesser(e, priorAccess(use)))
  )
}

/** Holds if the result of `exp` has certain bits filtered by a bitwise and. */
private predicate inBitwiseAnd(Expr exp) {
  exists(AndBitwiseExpr a | a.getAnOperand() = exp) or
  inBitwiseAnd(exp.(ParExpr).getExpr()) or
  inBitwiseAnd(exp.(LShiftExpr).getAnOperand()) or
  inBitwiseAnd(exp.(RShiftExpr).getAnOperand()) or
  inBitwiseAnd(exp.(URShiftExpr).getAnOperand())
}

/** Holds if overflow/underflow is irrelevant for this expression. */
predicate overflowIrrelevant(ArithExpr exp) {
  inBitwiseAnd(exp) or
  exp.getEnclosingCallable() instanceof HashCodeMethod
}
