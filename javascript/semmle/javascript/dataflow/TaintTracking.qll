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

/**
 * Provides classes for performing customized taint tracking.
 *
 * The classes in this module allow performing inter-procedural taint tracking
 * from a custom set of source nodes to a custom set of sink nodes. In addition
 * to normal data flow edges, taint is propagated along _taint edges_ that do
 * not preserve the value of their input but only its taintedness, such as taking
 * substrings. As for data flow configurations, additional flow edges can be
 * specified, and conversely certain nodes or edges can be designated as taint
 * _sanitizers_ that block flow.
 *
 * NOTE: The API of this library is not stable yet and may change in
 *       the future.
 */

import javascript
import semmle.javascript.dataflow.CallGraph
private import semmle.javascript.dataflow.InferredTypes

/**
 * Provides classes for modelling taint propagation.
 */
module TaintTracking {
  /**
   * A data flow tracking configuration that considers taint propagation through
   * objects, arrays, promises and strings in addition to standard data flow.
   *
   * If a different set of flow edges is desired, extend this class and override
   * `isAdditionalTaintStep`.
   */
  abstract class Configuration extends DataFlow::Configuration {
    bindingset[this]
    Configuration() { any() }

    /**
     * Holds if `source` is a relevant taint source.
     *
     * The smaller this predicate is, the faster `hasFlow()` will converge.
     */
    // overridden to provide taint-tracking specific qldoc
    abstract override predicate isSource(DataFlow::Node source);

    /**
     * Holds if `sink` is a relevant taint sink.
     *
     * The smaller this predicate is, the faster `hasFlow()` will converge.
     */
    // overridden to provide taint-tracking specific qldoc
    abstract override predicate isSink(DataFlow::Node sink);

    /** Holds if the intermediate node `node` is a taint sanitizer. */
    predicate isSanitizer(DataFlow::Node node) {
      sanitizedByGuard(this, node)
    }

    /** Holds if the edge from `source` to `sink` is a taint sanitizer. */
    predicate isSanitizer(DataFlow::Node source, DataFlow::Node sink) {
      none()
    }

    final
    override predicate isBarrier(DataFlow::Node node) { isSanitizer(node) }

    final
    override predicate isBarrier(DataFlow::Node source, DataFlow::Node sink) {
      isSanitizer(source, sink)
    }

    /**
     * Holds if the additional taint propagation step from `pred` to `succ`
     * must be taken into account in the analysis.
     */
    predicate isAdditionalTaintStep(DataFlow::Node pred, DataFlow::Node succ) {
      none()
    }

    final
    override predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
      isAdditionalTaintStep(pred, succ) or
      pred = succ.(FlowTarget).getATaintSource() or
      any(DefaultTaintStep dts).step(pred, succ)
    }
  }

  /**
   * Holds if data flow node `nd` acts as a sanitizer for the purposes of taint-tracking
   * configuration `cfg`.
   */
  private predicate sanitizedByGuard(Configuration cfg, DataFlow::Node nd) {
    // 1) `nd` is a use of a refinement node that sanitizes its input variable
    exists (SsaRefinementNode ref |
      nd = DataFlow::ssaDefinitionNode(ref) and
      forex (SsaVariable input | input = ref.getAnInput() |
        guardSanitizes(cfg, ref.getGuard(), input)
      )
    )
    or
    // 2) `nd` is a use of an SSA variable `ssa`, and dominated by a sanitizer for `ssa`
    exists (SsaVariable ssa, BasicBlock bb |
      nd = DataFlow::valueNode(ssa.getAUseIn(bb)) and
      exists (ConditionGuardNode guard |
        guardSanitizes(cfg, guard, ssa) and
        guard.dominates(bb)
      )
    )
    or
    // 3) `nd` is a property access `ssa.p.q` on an SSA variable `ssa`, and dominated by
    // a sanitizer for `ssa.p.q`
    exists (SsaVariable ssa, string props, BasicBlock bb |
      nd = DataFlow::valueNode(nestedPropAccessOnSsaVar(ssa, props)) and
      bb = nd.getBasicBlock() |
      exists (ConditionGuardNode guard |
        guard.getTest().(SanitizingGuard).sanitizes(cfg, guard.getOutcome(), nestedPropAccessOnSsaVar(ssa, props)) and
        guard.dominates(bb)
      )
    )
  }

  /**
   * Holds if props is a string of the form `p.q.r`, and the result is a property access
   * of the form `v.p.q.r`.
   */
  private DotExpr nestedPropAccessOnSsaVar(SsaVariable v, string props) {
    exists (Expr base, string prop | result.accesses(base, prop) |
      base = v.getAUse() and props = prop
      or
      exists (string prevProps |
        base = nestedPropAccessOnSsaVar(v, prevProps) and
        props = prevProps + "." + prop
      )
    )
  }

  /**
   * Holds if `guard` is sanitizes `v` for the purposes of taint-tracking
   * configuration `cfg`.
   */
  private predicate guardSanitizes(Configuration cfg,
                                   ConditionGuardNode guard, SsaVariable v) {
    exists (SanitizingGuard sanitizer | sanitizer = guard.getTest() |
      sanitizer.sanitizes(cfg, guard.getOutcome(), v.getAUse())
    )
  }

  /**
   * An expression that can act as a sanitizer for a variable when appearing
   * in a condition.
   */
  abstract class SanitizingGuard extends Expr {
    /**
     * Holds if this expression sanitizes expression `e` for the purposes of taint-tracking
     * configuration `cfg`, provided it evaluates to `outcome`.
     */
    abstract predicate sanitizes(Configuration cfg, boolean outcome, Expr e);
  }

  /**
   * A custom taint-propagating data flow edge, represented by its target node.
   */
  abstract class FlowTarget extends DataFlow::Node {
    /** Gets another data flow node from which taint is propagated to this node. */
    abstract DataFlow::Node getATaintSource();
  }

  /**
   * A standard taint-propagating data flow edge.
   *
   * Note: For performance reasons, all subclasses of this class should be part
   * of the standard library. Use `FlowTarget` for analysis-specific flow edges.
   */
  abstract class DefaultTaintStep extends DataFlow::Node {
    /**
     * Holds if `pred` &rarr; `succ` should be considered a taint-propagating
     * data flow edge.
     */
    abstract cached predicate step(DataFlow::Node pred, DataFlow::Node succ);
  }

  /**
   * A taint propagating data flow edge through object or array elements and
   * promises.
   */
  private class HeapTaintStep extends DefaultTaintStep {
    HeapTaintStep() {
      this = DataFlow::valueNode(_) or
      this = DataFlow::parameterNode(_)
    }

    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      succ = this and
      (
        exists (Expr e, Expr f | e = this.asExpr() and f = pred.asExpr() |
          // iterating over a tainted iterator taints the loop variable
          exists (EnhancedForLoop efl | f = efl.getIterationDomain() |
            e = efl.getAnIterationVariable().getAnAccess()
          )
          or
          // arrays with tainted elements and objects with tainted property names are tainted
          e.(ArrayExpr).getAnElement() = f or
          exists (Property prop | e.(ObjectExpr).getAProperty() = prop |
            prop.isComputed() and f = prop.getNameExpr()
          )
          or
          // reading from a tainted object yields a tainted result
          e.(PropAccess).getBase() = f
          or
          // awaiting a tainted expression gives a tainted result
          e.(AwaitExpr).getOperand() = f
          or
          // comparing a tainted expression against a constant gives a tainted result
          e.(Comparison).hasOperands(f, any(ConstantExpr c))
        )
        or
        // `array.map(function (elt, i, ary) { ... })`: if `array` is tainted, then so are
        // `elt` and `ary`; similar for `forEach`
        exists (MethodCallExpr m, Function f, int i, SimpleParameter p |
          (m.getMethodName() = "map" or m.getMethodName() = "forEach") and
          (i = 0 or i = 2) and
          m.getArgument(0).analyze().getAValue().(AbstractFunction).getFunction() = f and
          p = f.getParameter(i) and
          this = DataFlow::parameterNode(p) and
          pred.asExpr() = m.getReceiver()
        )
      )
    }
  }

  /**
   * A taint propagating data flow edge for assignments of the form `o[k] = v`, where
   * `k` is not a constant and `o` refers to some object literal; in this case, we consider
   * taint to flow from `v` to any variable that refers to the object literal.
   *
   * The rationale for this heuristic is that if properties of `o` are accessed by
   * computed (that is, non-constant) names, then `o` is most likely being treated as
   * a map, not as a real object. In this case, it makes sense to consider the entire
   * map to be tainted as soon as one of its entries is.
   */
  private class DictionaryTaintStep extends DefaultTaintStep, DataFlow::ValueNode {
    override VarAccess astNode;
    DataFlow::Node source;

    DictionaryTaintStep() {
      exists (AssignExpr assgn, IndexExpr idx, AbstractObjectLiteral obj |
        assgn.getTarget() = idx and
        idx.getBase().analyze().getAValue() = obj and
        not exists(idx.getPropertyName()) and
        astNode.analyze().getAValue() = obj and
        source = DataFlow::valueNode(assgn.getRhs())
      )
    }

    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      pred = source and succ = this
    }
  }

  /**
   * A taint propagating data flow edge arising from string append and other string
   * operations defined in the standard library.
   *
   * Note that since we cannot easily distinguish string append from addition, we consider
   * any `+` operation to propagate taint.
   */
  private class StringManipulationTaintStep extends DefaultTaintStep, DataFlow::ValueNode {
    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      succ = this and
      (
        // addition propagates taint
        astNode.(AddExpr).getAnOperand() = pred.asExpr() or
        astNode.(AssignAddExpr).getAChildExpr() = pred.asExpr() or
        exists (SsaExplicitDefinition ssa |
          astNode = ssa.getVariable().getAUse() and
          pred.asExpr().(AssignAddExpr) = ssa.getDef()
        )
        or
        // templating propagates taint
        astNode.(TemplateLiteral).getAnElement() = pred.asExpr()
        or
        // other string operations that propagate taint
        exists (string name | name = astNode.(MethodCallExpr).getMethodName() |
          pred.asExpr() = astNode.(MethodCallExpr).getReceiver() and
          ( // sorted, interesting, properties of String.prototype
            name = "anchor" or
            name = "big" or
            name = "blink" or
            name = "bold" or
            name = "concat" or
            name = "fixed" or
            name = "fontcolor" or
            name = "fontsize" or
            name = "italics" or
            name = "link" or
            name = "padEnd" or
            name = "padStart" or
            name = "repeat" or
            name = "replace" or
            name = "slice" or
            name = "small" or
            name = "split" or
            name = "strike" or
            name = "sub" or
            name = "substr" or
            name = "substring" or
            name = "sup" or
            name = "toLocaleLowerCase" or
            name = "toLocaleUpperCase" or
            name = "toLowerCase" or
            name = "toString" or
            name = "toUpperCase" or
            name = "trim" or
            name = "trimLeft" or
            name = "trimRight" or
            name = "valueOf"
          ) or
          exists (int i | pred.asExpr() = astNode.(MethodCallExpr).getArgument(i) |
            name = "concat" or
            name = "replace" and i = 1
          )
        )
        or
        // standard library constructors that propagate taint: `RegExp` and `String`
        exists (DataFlow::InvokeNode invk, string gv |
          gv = "RegExp" or gv = "String" |
          this = invk and
          invk = DataFlow::globalVarRef(gv).getAnInvocation() and
          pred = invk.getArgument(0)
        )
        or
        // String.fromCharCode and String.fromCodePoint
        exists (int i, MethodCallExpr mce |
          mce = astNode and
          pred.asExpr() = mce.getArgument(i) and
          (mce.getMethodName() = "fromCharCode" or mce.getMethodName() = "fromCodePoint")
        )
        or
        // `(encode|decode)URI(Component)?` and `escape` propagate taint
        exists (DataFlow::CallNode c, string name |
          this = c and c = DataFlow::globalVarRef(name).getACall() and
          pred = c.getArgument(0) |
          name = "encodeURI" or name = "decodeURI" or
          name = "encodeURIComponent" or name = "decodeURIComponent"
        )
      )
    }
  }

  /**
   * A taint propagating data flow edge arising from JSON parsing or unparsing.
   */
  private class JsonManipulationTaintStep extends DefaultTaintStep, DataFlow::MethodCallNode {
    JsonManipulationTaintStep() {
      exists (string methodName |
        methodName = "parse" or methodName = "stringify" |
        this = DataFlow::globalVarRef("JSON").getAMemberCall(methodName)
      )
    }

    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      pred = getArgument(0) and succ = this
    }
  }

  /**
   * A taint-propagating data flow edge arising from a destructuring assignment.
   */
  private class DestructuringAssignTaintStep extends DefaultTaintStep, DataFlow::SsaDefinitionNode {
    override SsaExplicitDefinition ssa;

    DestructuringAssignTaintStep() {
      ssa.getDef().getTarget() instanceof DestructuringPattern
    }

    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      pred = DataFlow::valueNode(ssa.getDef().getSource()) and succ = this
    }
  }

  /**
   * Holds if `params` is a `URLSearchParams` object providing access to
   * the parameters encoded in `input`.
   */
  predicate isUrlSearchParams(DataFlow::SourceNode params, DataFlow::Node input) {
    exists (DataFlow::GlobalVarRefNode urlSearchParams, NewExpr newUrlSearchParams |
      urlSearchParams.getName() = "URLSearchParams" and
      newUrlSearchParams = urlSearchParams.getAnInstantiation().asExpr() and
      params.asExpr() = newUrlSearchParams and
      input.asExpr() = newUrlSearchParams.getArgument(0)
    )
    or
    exists (DataFlow::NewNode newUrl |
      newUrl = DataFlow::globalVarRef("URL").getAnInstantiation() and
      params = newUrl.getAPropertyRead("searchParams") and
      input = newUrl.getArgument(0)
    )
  }

  /**
   * A taint propagating data flow edge arising from URL parameter parsing.
   */
  private class UrlSearchParamsTaintStep extends DefaultTaintStep, DataFlow::ValueNode {
    DataFlow::Node source;

    UrlSearchParamsTaintStep() {
      // either this is itself an `URLSearchParams` object
      isUrlSearchParams(this, source)
      or
      // or this is a call to `get` or `getAll` on a `URLSearchParams` object
      exists (DataFlow::SourceNode searchParams, string m |
        isUrlSearchParams(searchParams, source) and
        this = searchParams.getAMethodCall(m) and
        m.matches("get%")
      )
    }

    override predicate step(DataFlow::Node pred, DataFlow::Node succ) {
      pred = source and succ = this
    }
  }

  /**
   * Holds if `cfg` is any taint tracking configuration.
   *
   * This is an auxiliary predicate used in the definition of sanitizing guards
   * that intentionally do not restrict the set of configurations they apply to.
   */
  private predicate anyCfg(Configuration cfg) {
    any()
  }

  /**
   * A conditional checking a tainted string against a regular expression, which is
   * considered to be a sanitizer for all configurations.
   */
  class SanitizingRegExpTest extends SanitizingGuard, Expr {
    Expr expr;

    SanitizingRegExpTest() {
      exists (MethodCallExpr mce, Expr base, string m, Expr firstArg |
        mce = this and mce.calls(base, m) and firstArg = mce.getArgument(0) |
        // /re/.test(u) or /re/.exec(u)
        base.analyze().getAType() = TTRegExp() and
        (m = "test" or m = "exec") and
        firstArg = expr
        or
        // u.match(/re/) or u.match("re")
        base = expr and
        m = "match" and
        exists (InferredType firstArgType | firstArgType = firstArg.analyze().getAType() |
          firstArgType = TTRegExp() or firstArgType = TTString()
        )
      )
      or
      // m = /re/.exec(u) and similar
      this.(AssignExpr).getRhs().(SanitizingRegExpTest).getSanitizedExpr() = expr
    }

    private Expr getSanitizedExpr() {
      result = expr
    }

    override predicate sanitizes(Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      (outcome = true or outcome = false) and
      e = expr
    }
  }

  /**
   * A check of the form `if(o.<contains>(x))`, which sanitizes `x` in its "then" branch.
   *
   * `<contains>` is one of: `contains`, `has`, `hasOwnProperty`, `includes`
   */
  class WhitelistContainmentCallSanitizer extends TaintTracking::SanitizingGuard, MethodCallExpr {
    WhitelistContainmentCallSanitizer() {
      exists (string name |
        name = "contains" or
        name = "has" or
        name = "hasOwnProperty" or
        name = "includes" |
        getMethodName() = name
      )
    }

    override predicate sanitizes(TaintTracking::Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      outcome = true and
      e = getArgument(0)
    }
  }

  /** A check of the form `if(x in o)`, which sanitizes `x` in its "then" branch. */
  class InSanitizer extends TaintTracking::SanitizingGuard, InExpr {
    override predicate sanitizes(TaintTracking::Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      outcome = true and
      e = getLeftOperand()
    }
  }

  /** A check of the form `if(o[x] != undefined)`, which sanitizes `x` in its "then" branch. */
  class UndefinedCheckSanitizer extends TaintTracking::SanitizingGuard, EqualityTest {
    Expr x;

    UndefinedCheckSanitizer() {
      exists (IndexExpr idx, DataFlow::AnalyzedNode undef | hasOperands(idx, undef.asExpr()) |
        // one operand is of the form `o[x]`
        idx = getAnOperand() and idx.getPropertyNameExpr() = x and
        // and the other one is guaranteed to be `undefined`
        undef.getTheType() = TTUndefined()
      )
    }

    override predicate sanitizes(TaintTracking::Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      outcome = getPolarity().booleanNot() and
      e = x
    }
  }

  /** A check of the form `if(o.indexOf(x) != -1)`, which sanitizes `x` in its "then" branch. */
  class IndexOfSanitizer extends TaintTracking::SanitizingGuard, EqualityTest {
    MethodCallExpr indexOf;

    IndexOfSanitizer() {
      exists (Expr index | hasOperands(indexOf, index) |
        // one operand is of the form `o.indexOf(x)`
        indexOf.getMethodName() = "indexOf" and
        // and the other one is -1
        index.getIntValue() = -1
      )
    }

    override predicate sanitizes(TaintTracking::Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      outcome = getPolarity().booleanNot() and
      e = indexOf.getArgument(0)
    }
  }


  /** A check of the form `if(x == 'some-constant')`, which sanitizes `x` in its "then" branch. */
  class ConstantComparison extends TaintTracking::SanitizingGuard, EqualityTest {
    Expr x;

    ConstantComparison() {
      hasOperands(x, any(ConstantExpr c))
    }

    override predicate sanitizes(TaintTracking::Configuration cfg, boolean outcome, Expr e) {
      anyCfg(cfg) and
      outcome = getPolarity() and x = e
    }

  }

}