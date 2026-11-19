const { FIELDS } = require("./catalog");

function actualValue(attributes, field) {
  if (!attributes || typeof attributes !== "object") return undefined;
  return attributes[field];
}

function asNumber(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return null;
}

function compare(field, operator, expected, actual) {
  const spec = FIELDS[field];
  if (!spec) return false;
  if (operator === "EXISTS") return actual !== undefined && actual !== null;
  if (actual === undefined || actual === null) return false;
  if (spec.type === "number") {
    const left = asNumber(actual);
    if (left == null) return false;
    if (operator === "BETWEEN") {
      return left >= expected[0] && left <= expected[1];
    }
    if (operator === "IN") return expected.some((item) => left === item);
    if (operator === "NOT_IN") return expected.every((item) => left !== item);
    if (operator === "EQUALS") return left === expected;
    if (operator === "NOT_EQUALS") return left !== expected;
    if (operator === "GREATER_THAN") return left > expected;
    if (operator === "LESS_THAN") return left < expected;
    if (operator === "GREATER_THAN_OR_EQUAL") return left >= expected;
    if (operator === "LESS_THAN_OR_EQUAL") return left <= expected;
    return false;
  }
  if (spec.type === "boolean") {
    if (typeof actual !== "boolean") return false;
    if (operator === "EQUALS") return actual === expected;
    if (operator === "NOT_EQUALS") return actual !== expected;
    return false;
  }
  const text = typeof actual === "string" ? actual : null;
  if (text == null) return false;
  if (operator === "EQUALS") return text === expected;
  if (operator === "NOT_EQUALS") return text !== expected;
  if (operator === "IN") return expected.includes(text);
  if (operator === "NOT_IN") return !expected.includes(text);
  return false;
}

function evaluateRules(tree, attributes) {
  const results = [];
  if (tree == null) {
    // A missing tree is not a pass. Campaign eligibility must go through assessCampaign.
    return { passed: false, results, reason: "Eligibility rules are not configured" };
  }
  const passed = evaluateNode(tree, attributes, "root", results);
  return { passed, results };
}

function evaluateNode(node, attributes, path, results) {
  if (node.conditions) {
    const childPasses = node.conditions.map((child, index) =>
      evaluateNode(child, attributes, `${path}.${index}`, results)
    );
    const passed = node.combinator === "OR" ? childPasses.some(Boolean) : childPasses.every(Boolean);
    results.push({ path, combinator: node.combinator, passed });
    return passed;
  }
  const actual = actualValue(attributes, node.field);
  const passed = compare(node.field, node.operator, node.value, actual);
  results.push({
    path,
    field: node.field,
    operator: node.operator,
    expected: node.value === undefined ? null : node.value,
    actual: actual === undefined ? null : actual,
    passed,
  });
  return passed;
}

module.exports = { evaluateRules };
