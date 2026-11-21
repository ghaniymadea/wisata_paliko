typedef JsonMap = Map<String, dynamic>;

JsonMap? asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return null;
}

String jsonString(Object? value, [String fallback = '']) =>
    value is String ? value : value?.toString() ?? fallback;

int? jsonInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

enum AppRole { penjelajah, kurator, admin }

AppRole appRoleFromJson(JsonMap? json) {
  final name = jsonString(asJsonMap(json)?['nama']).toLowerCase();
  if (name == 'admin') return AppRole.admin;
  if (name == 'kurator') return AppRole.kurator;
  return AppRole.penjelajah;
}

class Spot {
  const Spot({
    required this.id,
    required this.creatorId,
    required this.name,
    required this.area,
    this.districtId,
    required this.category,
    required this.image,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.creatorName,
    required this.creatorUsername,
    required this.createdAt,
  });

  final String id;
  final String creatorId;
  final String name;
  final String area;
  final int? districtId;
  final String category;
  final String image;
  final String description;
  final double? latitude;
  final double? longitude;
  final String creatorName;
  final String creatorUsername;
  final DateTime createdAt;

  factory Spot.fromJson(JsonMap json) {
    final district = asJsonMap(json['kecamatan']);
    final city = asJsonMap(district?['kabupaten_kota']);
    final category = asJsonMap(json['kategori']);
    final creator = asJsonMap(json['users']);
    final media = json['media_spot'];
    final mediaItems = media is List
        ? media.map(asJsonMap).whereType<JsonMap>().toList()
        : <JsonMap>[];
    final cover = mediaItems.where((item) => item['is_cover'] == true);
    final image = cover.isNotEmpty
        ? cover.first['url_media']
        : mediaItems.isNotEmpty
        ? mediaItems.first['url_media']
        : null;
    final districtName = jsonString(district?['nama']);
    final cityName = jsonString(city?['nama']);
    final area = [
      if (districtName.isNotEmpty) 'Kec. $districtName',
      if (cityName.isNotEmpty) cityName,
    ].join(', ');

    return Spot(
      id: jsonString(json['id']),
      creatorId: jsonString(json['id_pembuat']),
      name: jsonString(json['nama'], 'Tempat wisata'),
      area: area.isEmpty ? 'Luak Limopuluah' : area,
      districtId: jsonInt(json['id_kecamatan']),
      category: jsonString(category?['nama'], 'Wisata'),
      image: jsonString(image),
      description: jsonString(json['ringkasan_editorial']),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      creatorName: jsonString(creator?['nama'], 'Kontributor lokal'),
      creatorUsername: jsonString(creator?['username'], 'kontributor'),
      createdAt:
          DateTime.tryParse(jsonString(json['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class Story {
  const Story({
    required this.id,
    required this.spotId,
    required this.title,
    required this.image,
    required this.spotName,
  });

  final String id;
  final String spotId;
  final String title;
  final String image;
  final String spotName;

  factory Story.fromJson(JsonMap json) => Story(
    id: jsonString(json['id']),
    spotId: jsonString(json['id_spot']),
    title: jsonString(json['judul'], 'Cerita penjelajah'),
    image: jsonString(json['url_media']),
    spotName: jsonString(asJsonMap(json['spots'])?['nama']),
  );
}

class TravelCollection {
  const TravelCollection({
    required this.id,
    required this.title,
    required this.description,
    required this.coverImage,
    required this.duration,
    required this.isPublic,
    required this.spotCount,
  });

  final String id;
  final String title;
  final String description;
  final String coverImage;
  final String duration;
  final bool isPublic;
  final int spotCount;

  factory TravelCollection.fromJson(JsonMap json) {
    final details = json['detail_koleksi'];
    final detailRows = details is List ? details : const [];
    Object? count;
    if (detailRows.isNotEmpty) {
      count = asJsonMap(detailRows.first)?['count'];
    }
    return TravelCollection(
      id: jsonString(json['id']),
      title: jsonString(json['judul'], 'Koleksi'),
      description: jsonString(json['deskripsi']),
      coverImage: jsonString(json['url_sampul']),
      duration: jsonString(json['label_durasi']),
      isPublic: json['id_status_publikasi'] == 1,
      spotCount: count is num ? count.toInt() : 0,
    );
  }
}

class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.position,
    required this.curatorNote,
    required this.spot,
  });

  final String id;
  final int position;
  final String curatorNote;
  final Spot spot;

  factory CollectionEntry.fromJson(JsonMap json) => CollectionEntry(
    id: jsonString(json['id']),
    position: (json['urutan'] as num?)?.toInt() ?? 0,
    curatorNote: jsonString(json['catatan_kurator']),
    spot: Spot.fromJson(asJsonMap(json['spots']) ?? const {}),
  );
}

class ExplorerTip {
  const ExplorerTip({
    required this.id,
    required this.authorName,
    required this.content,
    required this.rating,
    required this.createdAt,
    required this.voteCount,
  });

  final String id;
  final String authorName;
  final String content;
  final double rating;
  final DateTime createdAt;
  final int voteCount;

  factory ExplorerTip.fromJson(JsonMap json) {
    final author = asJsonMap(json['users']);
    final votes = json['vote_tips'];
    final voteRows = votes is List ? votes : const [];
    Object? voteCount;
    if (voteRows.isNotEmpty) {
      voteCount = asJsonMap(voteRows.first)?['count'];
    }
    return ExplorerTip(
      id: jsonString(json['id']),
      authorName: jsonString(author?['nama'], 'Penjelajah lokal'),
      content: jsonString(json['isi_tips']),
      rating: _asDouble(json['rating_bintang']) ?? 0,
      createdAt:
          DateTime.tryParse(jsonString(json['created_at'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      voteCount: voteCount is num ? voteCount.toInt() : 0,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(jsonString(value));
}
