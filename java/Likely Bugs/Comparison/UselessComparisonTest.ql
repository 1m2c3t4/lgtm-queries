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
 * @name Useless comparison test
 * @description A comparison operation that always evaluates to true or always
 *              evaluates to false may indicate faulty logic and may result in
 *              dead code.
 * @kind problem
 * @problem.severity warning
 * @precision very-high
 * @tags correctness
 *       logic
 *       external/cwe/cwe-570
 *       external/cwe/cwe-571
 */
import UselessComparisonTest

from ConditionNode s, BinaryExpr test, boolean testIsTrue
where uselessTest(s, test, testIsTrue) and
  not exists(AssertStmt assert | assert.getExpr() = test.getParent*())
select test, "Test is always " + testIsTrue + ", because of $@.", s, "this condition"
