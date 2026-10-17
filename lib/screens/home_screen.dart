import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../models/item.dart';
import '../services/embedding_service.dart';
import '../services/item_repository.dart';
import '../services/share_service.dart';
import 'settings_screen.dart';

/// Örnek ana ekran: kayıtları listeler, hybrid search ile arar.
/// Paylaşılan yeni içerik işlendiğinde liste otomatik yenilenir.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ItemRepository _repo = ItemRepository();
  final EmbeddingService _embedding = EmbeddingService(
    apiKey: AppConfig.googleApiKey,
    openRouterApiKey: AppConfig.openRouterApiKey,
  );
  final TextEditingController _search = TextEditingController();

  List<Item> _items = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ShareService.instance.processedCount.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ShareService.instance.processedCount.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _search.text.trim();
    try {
      final List<Item> result;
      if (query.isEmpty) {
        result = await _repo.list();
      } else {
        final vector = await _embedding.embed(query);
        result = await _repo.hybridSearch(query, queryEmbedding: vector);
      }
      if (mounted) setState(() => _items = result);
    } catch (e) {
      debugPrint('HomeScreen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _delete(Item item) async {
    setState(() => _items.removeWhere((i) => i.id == item.id));
    try {
      await _repo.delete(item.id);
    } catch (e) {
      debugPrint('HomeScreen.delete: $e');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: l10n.searchHint,
              leading: const Icon(Icons.search),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.homeEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _items[index];
          final subtitle = [
            if (item.tags.isNotEmpty) item.tags.map((t) => '#$t').join(' '),
            if (item.url != null && item.url!.isNotEmpty) item.url!,
          ].join('\n');
          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            onDismissed: (_) => _delete(item),
            child: ListTile(
              title: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle.isEmpty
                  ? null
                  : Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          );
        },
      ),
    );
  }
}
