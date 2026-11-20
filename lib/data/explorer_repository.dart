import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class ExplorerRepository {
  ExplorerRepository(this._client);

  final SupabaseClient _client;

  Future<List<Spot>> getApprovedSpots() async {
    final rows = await _client
        .from('spots')
        .select(
          'id,nama,ringkasan_editorial,latitude,longitude,created_at,'
          'kecamatan(nama,kabupaten_kota(nama)),kategori(nama),'
          'media_spot(url_media,is_cover),'
          'users!spots_id_pembuat_fkey(nama,username)',
        )
        .eq('id_status_verifikasi', 2)
        .order('created_at', ascending: false);
    return rows.map((row) => Spot.fromJson(row)).toList();
  }

  Future<List<Story>> getActiveStories() async {
    final rows = await _client
        .from('cerita')
        .select('id,id_spot,judul,url_media,spots(nama)')
        .gt('kedaluwarsa_pada', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return rows.map((row) => Story.fromJson(row)).toList();
  }

  Future<void> recordStoryView(String storyId) async {
    await _client.rpc('record_story_view', params: {'p_id_cerita': storyId});
  }

  Future<Set<String>> getBookmarkedSpotIds(String userId) async {
    final rows = await _client
        .from('bookmark')
        .select('id_spot')
        .eq('id_user', userId);
    return rows.map((row) => jsonString(row['id_spot'])).toSet();
  }

  Future<bool> toggleBookmark(String spotId) async {
    final saved = await _client.rpc<bool>(
      'toggle_bookmark',
      params: {'p_id_spot': spotId},
    );
    return saved;
  }

  Future<List<ExplorerTip>> getTips(String spotId) async {
    final rows = await _client
        .from('tips_warga')
        .select(
          'id,isi_tips,rating_bintang,created_at,'
          'users!tips_warga_id_penulis_fkey(nama),vote_tips(count)',
        )
        .eq('id_spot', spotId)
        .order('created_at', ascending: false);
    return rows.map((row) => ExplorerTip.fromJson(row)).toList();
  }

  Future<void> addTip({
    required String spotId,
    required String content,
    required double rating,
  }) async {
    final userId = _requireUserId();
    await _client.from('tips_warga').insert({
      'id_spot': spotId,
      'id_penulis': userId,
      'isi_tips': content,
      'rating_bintang': rating,
    });
  }

  Future<bool> toggleTipVote(String tipId) async {
    final helpful = await _client.rpc<bool>(
      'toggle_vote_tips',
      params: {'p_id_tips': tipId},
    );
    return helpful;
  }

  Future<List<TravelCollection>> getMyCollections() async {
    final rows = await _client
        .from('koleksi')
        .select(
          'id,judul,deskripsi,url_sampul,label_durasi,id_status_publikasi,'
          'detail_koleksi(count)',
        )
        .eq('id_kurator', _requireUserId())
        .order('created_at', ascending: false);
    return rows.map((row) => TravelCollection.fromJson(row)).toList();
  }

  Future<List<CollectionEntry>> getCollectionEntries(
    String collectionId,
  ) async {
    final rows = await _client
        .from('detail_koleksi')
        .select(
          'id,urutan,catatan_kurator,'
          'spots(id,nama,ringkasan_editorial,latitude,longitude,created_at,'
          'kecamatan(nama,kabupaten_kota(nama)),kategori(nama),'
          'media_spot(url_media,is_cover),'
          'users!spots_id_pembuat_fkey(nama,username))',
        )
        .eq('id_koleksi', collectionId)
        .order('urutan');
    return rows.map((row) => CollectionEntry.fromJson(row)).toList();
  }

  Future<String> createCollection({
    required String title,
    required String description,
    required bool isPublic,
  }) async {
    final row = await _client
        .from('koleksi')
        .insert({
          'id_kurator': _requireUserId(),
          'id_status_publikasi': isPublic ? 1 : 2,
          'judul': title,
          'deskripsi': description,
        })
        .select('id')
        .single();
    return jsonString(row['id']);
  }

  Future<void> addSpotToCollection({
    required String collectionId,
    required String spotId,
    String? curatorNote,
  }) async {
    await _client.rpc<void>(
      'add_spot_to_collection',
      params: {
        'p_id_koleksi': collectionId,
        'p_id_spot': spotId,
        'p_catatan_kurator': curatorNote,
      },
    );
  }

  Future<String> createSpot({
    required String name,
    required String slug,
    required String summary,
    required int districtId,
    required int categoryId,
    double? latitude,
    double? longitude,
  }) async {
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError('Latitude dan longitude harus diisi bersama.');
    }
    if (latitude != null &&
        longitude != null &&
        (latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180)) {
      throw ArgumentError(
        'Koordinat latitude/longitude berada di luar rentang.',
      );
    }
    final userId = _requireUserId();
    final row = await _client
        .from('spots')
        .insert({
          'id_kecamatan': districtId,
          'id_kategori': categoryId,
          'id_pembuat': userId,
          'id_status_verifikasi': 1,
          'nama': name,
          'slug': slug,
          'ringkasan_editorial': summary,
          'latitude': latitude,
          'longitude': longitude,
        })
        .select('id')
        .single();
    return jsonString(row['id']);
  }

  Future<void> addSpotMedia({
    required String spotId,
    required String mediaUrl,
    required int mediaTypeId,
    String? aspectRatio,
    String? caption,
    bool isCover = false,
  }) async {
    await _client.from('media_spot').insert({
      'id_spot': spotId,
      'id_pengunggah': _requireUserId(),
      'id_jenis_media': mediaTypeId,
      'url_media': mediaUrl,
      'rasio_aspek': aspectRatio,
      'keterangan': caption,
      'is_cover': isCover,
    });
  }

  Future<void> createStory({
    required String spotId,
    required String title,
    required String mediaUrl,
    required DateTime expiresAt,
  }) async {
    await _client.from('cerita').insert({
      'id_spot': spotId,
      'id_penulis': _requireUserId(),
      'judul': title,
      'url_media': mediaUrl,
      'kedaluwarsa_pada': expiresAt.toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    return _client
        .from('kategori')
        .select('id,nama,slug,warna_aksen')
        .order('nama');
  }

  Future<List<Map<String, dynamic>>> getDistricts() async {
    return _client
        .from('kecamatan')
        .select('id,nama,slug,id_kabupaten_kota')
        .order('nama');
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Silakan masuk untuk melakukan tindakan ini.');
    }
    return userId;
  }
}
