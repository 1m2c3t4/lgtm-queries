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
 * @name User-controlled bypass of sensitive method
 * @description User-controlled bypassing of sensitive methods may allow attackers to avoid
 *              passing through authentication systems.
 * @kind problem
 * @problem.severity error
 * @precision high
 * @tags security
 *       external/cwe/cwe-807
 *       external/cwe/cwe-290
 */
import java
import semmle.code.java.security.DataFlow
import semmle.code.java.security.SensitiveActions
import semmle.code.java.controlflow.Dominance
import semmle.code.java.dataflow.Guards

/**
 * Calls to a sensitive method that are controlled by a condition
 * on the given expression.
 */
predicate conditionControlsMethod(MethodAccess m, Expr e) {
  exists (ConditionBlock cb, SensitiveExecutionMethod def, boolean cond |
    cb.controls(m.getBasicBlock(), cond) and
    def = m.getMethod() and
    not cb.controls(def.getAReference().getBasicBlock(), cond.booleanNot()) and
    e = cb.getCondition()
  )
}

from UserInput u, MethodAccess m, Expr e
where
  conditionControlsMethod(m, e) and
  u.flowsTo(e)
select m, "Sensitive method may not be executed depending on $@, which flows from $@.", 
  e, "this condition", u, "user input"
