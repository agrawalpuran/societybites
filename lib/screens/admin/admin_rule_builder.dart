import 'package:flutter/material.dart';

/// Visual rule tree. The saved JSON matches the incentive rule schema.
/// Field names come from the backend allowlist in rules/catalog.js.
const int kMaxRuleDepth = 4;

const Map<String, String> kRuleFieldTypes = {
  'user.role': 'string',
  'user.isNew': 'boolean',
  'user.societyId': 'string',
  'user.cityKey': 'string',
  'order.status': 'string',
  'order.paymentStatus': 'string',
  'order.paymentMethod': 'string',
  'order.subtotal': 'number',
  'order.total': 'number',
  'order.societyId': 'string',
  'order.sellerId': 'string',
  'order.itemCount': 'number',
  'order.isFirstCompleted': 'boolean',
  'listing.status': 'string',
  'listing.catalogType': 'string',
  'review.rating': 'number',
  'referral.acquisitionKind': 'string',
  'referral.qualifiedCount': 'number',
  'event.type': 'string',
};

const Map<String, List<String>> kRuleFieldValues = {
  'user.role': ['buyer', 'seller'],
  'referral.acquisitionKind': ['BUYER_ACQUISITION', 'SELLER_ACQUISITION'],
};

const List<String> _stringOperators = ['EQUALS', 'NOT_EQUALS', 'IN', 'NOT_IN', 'EXISTS'];
const List<String> _numberOperators = [
  'EQUALS',
  'NOT_EQUALS',
  'IN',
  'NOT_IN',
  'EXISTS',
  'GREATER_THAN',
  'LESS_THAN',
  'GREATER_THAN_OR_EQUAL',
  'LESS_THAN_OR_EQUAL',
  'BETWEEN',
];
const List<String> _booleanOperators = ['EQUALS', 'NOT_EQUALS', 'EXISTS'];

List<String> operatorsForField(String field) {
  final type = kRuleFieldTypes[field] ?? 'string';
  if (type == 'number') return _numberOperators;
  if (type == 'boolean') return _booleanOperators;
  return _stringOperators;
}

class RuleNode {
  RuleNode.group([this.combinator = 'AND'])
      : conditions = [RuleNode.leaf()],
        field = null,
        operator = null;

  RuleNode.leaf()
      : combinator = null,
        conditions = [],
        field = 'event.type',
        operator = 'EQUALS';

  String? combinator;
  List<RuleNode> conditions;
  String? field;
  String? operator;
  String valueText = '';

  bool get isGroup => combinator != null;

  Map<String, dynamic> toJson() {
    if (isGroup) {
      return {
        'combinator': combinator,
        'conditions': [for (final child in conditions) child.toJson()],
      };
    }
    final selected = field ?? 'event.type';
    final selectedOperator = operator ?? 'EQUALS';
    return {
      'field': selected,
      'operator': selectedOperator,
      if (selectedOperator != 'EXISTS') 'value': encodedValue(selected, selectedOperator, valueText),
    };
  }

  static RuleNode fromJson(dynamic source) {
    if (source is! Map) return RuleNode.group();
    if (source['conditions'] is List) {
      final node = RuleNode.group(source['combinator']?.toString() == 'OR' ? 'OR' : 'AND');
      node.conditions = [
        for (final child in source['conditions'] as List) RuleNode.fromJson(child),
      ];
      if (node.conditions.isEmpty) node.conditions = [RuleNode.leaf()];
      return node;
    }
    final node = RuleNode.leaf();
    final field = source['field']?.toString();
    node.field = kRuleFieldTypes.containsKey(field) ? field : 'event.type';
    final operator = source['operator']?.toString() ?? source['op']?.toString();
    node.operator = operatorsForField(node.field!).contains(operator) ? operator : 'EQUALS';
    node.valueText = _valueText(source['value']);
    return node;
  }
}

String _valueText(dynamic value) {
  if (value == null) return '';
  if (value is List) return value.map((item) => item.toString()).join(', ');
  return value.toString();
}

Object encodedValue(String field, String operator, String raw) {
  if (operator == 'IN' || operator == 'NOT_IN' || operator == 'BETWEEN') {
    return raw.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).map((item) => _coerce(field, item)).toList();
  }
  return _coerce(field, raw.trim());
}

Object _coerce(String field, String raw) {
  final type = kRuleFieldTypes[field];
  if (type == 'boolean') return raw == 'true';
  if (type == 'number') {
    final number = num.tryParse(raw);
    if (number != null) return number;
  }
  return raw;
}

String? validateRuleTree(RuleNode node, int depth) {
  if (depth > kMaxRuleDepth) return 'Rule nesting cannot exceed $kMaxRuleDepth.';
  if (node.isGroup) {
    if (node.combinator != 'AND' && node.combinator != 'OR') return 'A rule group must be AND or OR.';
    if (node.conditions.isEmpty) return 'A rule group needs at least one condition.';
    if (depth >= 3 && node.conditions.any((child) => child.isGroup)) {
      return 'A nested group at this level cannot contain another group.';
    }
    for (final child in node.conditions) {
      final error = validateRuleTree(child, depth + 1);
      if (error != null) return error;
    }
    return _count(node) > 30 ? 'A campaign cannot have more than 30 conditions.' : null;
  }
  final field = node.field;
  if (field == null || !kRuleFieldTypes.containsKey(field)) return 'Choose a rule field from the list.';
  final operator = node.operator;
  if (operator == null || !operatorsForField(field).contains(operator)) return 'That operator is not allowed for $field.';
  if (operator == 'EXISTS') return null;
  if (node.valueText.trim().isEmpty) return 'Enter a value for $field.';
  final allowed = kRuleFieldValues[field];
  if (allowed != null && operator != 'IN' && operator != 'NOT_IN' && !allowed.contains(node.valueText.trim())) {
    return '$field must be one of: ${allowed.join(', ')}.';
  }
  return null;
}

int _count(RuleNode node) {
  if (!node.isGroup) return 1;
  return node.conditions.fold(0, (total, child) => total + _count(child));
}

class RuleBuilder extends StatelessWidget {
  const RuleBuilder({
    super.key,
    required this.node,
    required this.depth,
    required this.readOnly,
    required this.onChanged,
    this.onRemove,
  });

  final RuleNode node;
  final int depth;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    if (node.isGroup) {
      final canNest = depth < 3;
      return Padding(
        padding: EdgeInsets.only(left: depth == 1 ? 0 : 12, top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('group-$depth-${node.combinator}-${identityHashCode(node)}'),
              initialValue: node.combinator,
              decoration: InputDecoration(labelText: depth == 1 ? 'Rule group' : 'Nested group'),
              items: const [
                DropdownMenuItem(value: 'AND', child: Text('AND')),
                DropdownMenuItem(value: 'OR', child: Text('OR')),
              ],
              onChanged: readOnly
                  ? null
                  : (value) {
                      node.combinator = value ?? 'AND';
                      onChanged();
                    },
            ),
            for (var index = 0; index < node.conditions.length; index++)
              RuleBuilder(
                node: node.conditions[index],
                depth: depth + 1,
                readOnly: readOnly,
                onChanged: onChanged,
                onRemove: readOnly || node.conditions.length == 1
                    ? null
                    : () {
                        node.conditions.removeAt(index);
                        onChanged();
                      },
              ),
            if (!readOnly)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: node.conditions.length >= 30
                        ? null
                        : () {
                            node.conditions.add(RuleNode.leaf());
                            onChanged();
                          },
                    child: const Text('Add condition'),
                  ),
                  if (canNest)
                    TextButton(
                      onPressed: () {
                        node.conditions.add(RuleNode.group());
                        onChanged();
                      },
                      child: const Text('Add group'),
                    ),
                  if (onRemove != null) TextButton(onPressed: onRemove, child: const Text('Remove group')),
                ],
              ),
          ],
        ),
      );
    }

    final field = node.field ?? 'event.type';
    final operators = operatorsForField(field);
    final operator = operators.contains(node.operator) ? node.operator! : operators.first;
    final choices = kRuleFieldValues[field];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('field-${identityHashCode(node)}-$field'),
            initialValue: field,
            items: [for (final name in kRuleFieldTypes.keys) DropdownMenuItem(value: name, child: Text(name))],
            onChanged: readOnly
                ? null
                : (value) {
                    node.field = value ?? field;
                    if (!operatorsForField(node.field!).contains(node.operator)) node.operator = 'EQUALS';
                    onChanged();
                  },
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('operator-${identityHashCode(node)}-$operator'),
            initialValue: operator,
            items: [for (final name in operators) DropdownMenuItem(value: name, child: Text(name))],
            onChanged: readOnly
                ? null
                : (value) {
                    node.operator = value ?? operator;
                    onChanged();
                  },
          ),
          if (operator != 'EXISTS' && choices != null)
            DropdownButtonFormField<String>(
              key: ValueKey('value-${identityHashCode(node)}-${node.valueText}'),
              initialValue: choices.contains(node.valueText) ? node.valueText : null,
              decoration: const InputDecoration(labelText: 'Value'),
              items: [for (final name in choices) DropdownMenuItem(value: name, child: Text(name))],
              onChanged: readOnly
                  ? null
                  : (value) {
                      node.valueText = value ?? '';
                      onChanged();
                    },
            )
          else if (operator != 'EXISTS')
            SizedBox(
              width: 180,
              child: TextFormField(
                initialValue: node.valueText,
                readOnly: readOnly,
                decoration: const InputDecoration(labelText: 'Value'),
                onChanged: (value) => node.valueText = value,
              ),
            ),
          if (!readOnly && onRemove != null) TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}
