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

import java
import semmle.code.java.JDKAnnotations

/**
 * Direct flow of values (i.e. object references) through expressions.
 */
Expr valueFlow(Expr src) {
  result = src or
  exists(ConditionalExpr c | result = c |
    src = c.getTrueExpr() or
    src = c.getFalseExpr()
  ) or
  src = result.(ParExpr).getExpr()
}

/**
 * An access to an enum constant, where the reference to the constant may
 * be stored and used by the enclosing program rather than just being
 * compared and discarded.
 */
VarAccess valueAccess(EnumConstant e) {
  result = e.getAnAccess() and (
    exists(Call c |
      c.getAnArgument() = valueFlow+(result) or
      c.(MethodAccess).getQualifier() = valueFlow+(result)
    ) or
    exists(Assignment a | a.getSource() = valueFlow+(result)) or
    exists(ReturnStmt r | r.getResult() = valueFlow+(result)) or
    exists(LocalVariableDeclExpr v | v.getInit() = valueFlow+(result)) or
    exists(AddExpr a | a.getAnOperand() = valueFlow+(result))
  )
}

/**
 * Exceptions to the "must have its value used" rule.
 */
predicate exception(EnumConstant e) {
  exists(EnumType t | t = e.getDeclaringType() |
    // It looks like a method is trying to return the right constant for a string.
    exists(Method fromString | fromString = t.getAMethod() |
      fromString.isStatic() and
      fromString.getReturnType() = t and
      exists(EnhancedForStmt s | s.getEnclosingCallable() = fromString |
        s.getVariable().getType() = t
      )
    ) or
    // A method iterates over the values of an enum.
    exists(MethodAccess values | values.getMethod().getDeclaringType() = t |
      values.getParent() instanceof EnhancedForStmt or
      values.getParent().(MethodAccess).getMethod().hasName("findThisIn")
    ) or
    /*
     * The `valueOf` method is called, meaning that depending on the string any constant
     * could be retrieved.
     */
    exists(MethodAccess valueOf | valueOf.getMethod().getDeclaringType() = t |
      valueOf.getMethod().hasName("valueOf")
    ) or
    // Entire `Enum` annotated with reflective annotation.
    exists(ReflectiveAccessAnnotation ann | ann = t.getAnAnnotation())

  ) or
  // Enum field annotated with reflective annotation.
  e.getAnAnnotation() instanceof ReflectiveAccessAnnotation
}

class UnusedEnumConstant extends EnumConstant {
  UnusedEnumConstant() {
    not exists(valueAccess(this)) and
    this.fromSource() and
    not exception(this)
  }

  predicate whitelisted() {
    none()
  }
}