const { httpError } = require("../lib/httpError");
const { FIELDS, MAX_CONDITIONS, MAX_RULE_DEPTH, operatorsFor } = require("./catalog");

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function assertValue(field, operator, value) {
  const spec = FIELDS[field];
  if (operator === "EXISTS") {
    if (value !== undefined && value !== null) {
      throw httpError(400, `${field} EXISTS does not take a value`);
    }
    return;
  }
  if (operator === "BETWEEN") {
    if (!Array.isArray(value) || value.length !== 2 || value.some((item) => typeof item !== "number" || !Number.isFinite(item))) {
      throw httpError(400, `${field} BETWEEN requires [min, max] numbers`);
    }
    if (value[0] > value[1]) throw httpError(400, `${field} BETWEEN minimum is greater than maximum`);
    return;
  }
  if (operator === "IN" || operator === "NOT_IN") {
    if (!Array.isArray(value) || value.length === 0 || value.length > 50) {
      throw httpError(400, `${field} ${operator} requires a list of 1 to 50 values`);
    }
    for (const item of value) assertScalar(field, spec, item);
    return;
  }
  assertScalar(field, spec, value);
}

function assertScalar(field, spec, value) {
  if (spec.type === "number") {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      throw httpError(400, `${field} requires a number`);
    }
    return;
  }
  if (spec.type === "boolean") {
    if (typeof value !== "boolean") throw httpError(400, `${field} requires true or false`);
    return;
  }
  if (typeof value !== "string" || !value.trim()) {
    throw httpError(400, `${field} requires text`);
  }
  if (spec.values && !spec.values.includes(value)) {
    throw httpError(400, `${field} must be one of: ${spec.values.join(", ")}`);
  }
}

function validateNode(node, depth, state) {
  if (depth > MAX_RULE_DEPTH) {
    throw httpError(400, `Rule nesting cannot exceed ${MAX_RULE_DEPTH}`);
  }
  if (!isObject(node)) throw httpError(400, "Each rule node must be an object");
  const group = Array.isArray(node.conditions);
  const leaf = node.field != null || node.operator != null || node.op != null;
  if (group && leaf) throw httpError(400, "A rule node cannot be both a group and a condition");
  if (!group && !leaf) throw httpError(400, "A rule node needs conditions or a field");
  if (group) {
    if (node.combinator !== "AND" && node.combinator !== "OR") {
      throw httpError(400, "A rule group combinator must be AND or OR");
    }
    if (node.conditions.length === 0) throw httpError(400, "A rule group needs at least one condition");
    for (const child of node.conditions) validateNode(child, depth + 1, state);
    return;
  }
  state.count += 1;
  if (state.count > MAX_CONDITIONS) {
    throw httpError(400, `A campaign cannot have more than ${MAX_CONDITIONS} conditions`);
  }
  const field = node.field;
  const operator = node.operator || node.op;
  if (!FIELDS[field]) throw httpError(400, `Unsupported rule field: ${field}`);
  if (!operatorsFor(FIELDS[field].type).includes(operator)) {
    throw httpError(400, `${operator || "missing operator"} is not allowed for ${field}`);
  }
  assertValue(field, operator, node.value);
}

function validateRules(tree) {
  if (tree == null) return null;
  if (!isObject(tree)) throw httpError(400, "Rules must be an object");
  const state = { count: 0 };
  validateNode(tree, 1, state);
  return normalizeRules(tree);
}

function normalizeRules(node) {
  if (Array.isArray(node.conditions)) {
    return {
      combinator: node.combinator,
      conditions: node.conditions.map((child) => normalizeRules(child)),
    };
  }
  const operator = node.operator || node.op;
  const normalized = { field: node.field, operator };
  if (operator !== "EXISTS") normalized.value = node.value;
  return normalized;
}

function flattenRules(tree) {
  const rows = [];
  let sortOrder = 0;
  function walk(node, parentGroupKey, groupKey) {
    if (node.conditions) {
      rows.push({
        groupKey,
        parentGroupKey,
        combinator: node.combinator,
        field: null,
        operator: null,
        value: null,
        sortOrder: sortOrder++,
      });
      node.conditions.forEach((child, index) => walk(child, groupKey, `${groupKey}.${index}`));
      return;
    }
    rows.push({
      groupKey,
      parentGroupKey,
      combinator: null,
      field: node.field,
      operator: node.operator,
      value: node.value === undefined ? null : node.value,
      sortOrder: sortOrder++,
    });
  }
  if (tree) walk(tree, null, "root");
  return rows;
}

module.exports = { validateRules, flattenRules };
