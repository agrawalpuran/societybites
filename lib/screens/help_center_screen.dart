import 'package:flutter/material.dart';

import '../models/help_center.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _expandedSearchId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchHelpFaqs(_query);
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF101617),
        title: const Text(
          'Help Center',
          style: TextStyle(
            color: Color(0xFF101617),
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Color(0xFF3A4644),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text(
            'How can we help?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 14),
          _HelpSearchField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value;
                _expandedSearchId = null;
              });
            },
          ),
          const SizedBox(height: 22),
          if (searching) ...[
            Text(
              hits.isEmpty
                  ? 'No matching help articles'
                  : '${hits.length} result${hits.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6A7774),
              ),
            ),
            const SizedBox(height: 10),
            ...hits.map(
              (hit) => _FaqTile(
                faq: hit.faq,
                caption: hit.category.title,
                expanded: _expandedSearchId == hit.faq.id,
                onTap: () {
                  setState(() {
                    _expandedSearchId =
                        _expandedSearchId == hit.faq.id ? null : hit.faq.id;
                  });
                },
              ),
            ),
          ] else ...[
            const Text(
              'BROWSE TOPICS',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A9491),
              ),
            ),
            const SizedBox(height: 10),
            ...helpCategories.map(
              (category) => _CategoryCard(
                category: category,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HelpCategoryScreen(category: category),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HelpCategoryScreen extends StatefulWidget {
  const HelpCategoryScreen({super.key, required this.category});

  final HelpCategory category;

  @override
  State<HelpCategoryScreen> createState() => _HelpCategoryScreenState();
}

class _HelpCategoryScreenState extends State<HelpCategoryScreen> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF101617),
        title: Text(
          widget.category.title,
          style: const TextStyle(
            color: Color(0xFF101617),
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Color(0xFF3A4644),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: widget.category.faqs
            .map(
              (faq) => _FaqTile(
                faq: faq,
                expanded: _expandedId == faq.id,
                onTap: () {
                  setState(() {
                    _expandedId = _expandedId == faq.id ? null : faq.id;
                  });
                },
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HelpSearchField extends StatelessWidget {
  const _HelpSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search_rounded, color: Color(0xFF8A9491), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: 'Search help',
                hintStyle: TextStyle(
                  color: Color(0xFFADB5B2),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(
                color: Color(0xFF223531),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final HelpCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(category.icon, color: const Color(0xFF0E5A47), size: 22),
          ),
          title: Text(
            category.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          subtitle: Text(
            '${category.faqs.length} questions',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFFADB5B2),
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.faq,
    required this.expanded,
    required this.onTap,
    this.caption,
  });

  final HelpFaq faq;
  final bool expanded;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (caption != null) ...[
                            Text(
                              caption!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0E5A47),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            faq.question,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF101617),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFF8A9491),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 10),
                  Text(
                    faq.answer,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF3A4644),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
