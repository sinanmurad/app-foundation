/// Örnek veri modeli — `public.items` tablosuyla eşleşir
/// (supabase/migrations/0001_starter_base.sql).
///
/// Yeni uygulamada bunu kendi ana varlığına (not, görev, ürün...) dönüştür.
class Item {
  final String id;
  final String userId;
  final String title;
  final String? content;
  final String? url;
  final String? note;
  final List<String> tags;
  final DateTime createdAt;

  const Item({
    required this.id,
    required this.userId,
    required this.title,
    this.content,
    this.url,
    this.note,
    this.tags = const [],
    required this.createdAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: (json['title'] as String?) ?? '',
      content: json['content'] as String?,
      url: json['url'] as String?,
      note: json['note'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
