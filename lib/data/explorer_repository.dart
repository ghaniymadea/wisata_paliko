import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class ExplorerRepository {
  ExplorerRepository(this._client);

  final SupabaseClient _client;

  static const _spotSelectBase =
      'id,id_pembuat,id_kecamatan,nama,ringkasan_editorial,latitude,longitude,created_at,'
      'kecamatan(nama,kabupaten_kota(nama)),kategori(nama),'
      'media_spot(url_media,is_cover),'
      'users!spots_id_pembuat_fkey(nama,username)';

  static const _spotSelectWithEngagement =
      'id,id_pembuat,id_kecamatan,nama,ringkasan_editorial,latitude,longitude,created_at,'
      'kecamatan(nama,kabupaten_kota(nama)),kategori(nama),'
      'media_spot(url_media,is_cover),'
      'spot_likes(count),tips_warga(count),spot_shares(count),'
      'users!spots_id_pembuat_fkey(nama,username)';

  Future<JsonMap> getMyProfile() async {
    final row = await _client
        .from('users')
        .select('id,username,nama,email,id_role,roles(id,nama)')
        .eq('id', _requireUserId())
        .maybeSingle();
    if (row == null) {
      throw StateError(
        'Profil Supabase belum tersedia. Jalankan schema.sql untuk backfill akun Auth lama.',
      );
    }
    return row;
  }

  Future<AppRole> getMyRole() async {
    final row = await getMyProfile();
    return appRoleFromJson(asJsonMap(row['roles']));
  }

  Future<List<Spot>> getPendingSpots() async {
    final rows = await _client
        .from('spots')
        .select(_spotSelectBase)
        .eq('id_status_verifikasi', 1)
        .order('created_at', ascending: false);
    return rows.map((row) => Spot.fromJson(row)).toList();
  }

  Future<void> verifySpot({
    required String spotId,
    required int statusId,
    String? note,
  }) async {
    await _client.rpc(
      'verifikasi_spot',
      params: {'p_id': spotId, 'p_status': statusId, 'p_catatan': note},
    );
  }

  Future<JsonMap> getAdminStats() async {
    final result = await _client.rpc<JsonMap>('statistik_admin');
    return result;
  }

  Future<List<Map<String, dynamic>>> getReports() async {
    return _client
        .from('laporan')
        .select(
          'id,jenis_target,id_target,alasan,status,catatan_admin,created_at',
        )
        .order('created_at', ascending: false);
  }

  Future<void> createReport({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    await _client.from('laporan').insert({
      'id_pelapor': _requireUserId(),
      'jenis_target': targetType,
      'id_target': targetId,
      'alasan': reason,
    });
  }

  Future<void> updateReport({
    required String reportId,
    required String status,
    String? adminNote,
  }) async {
    await _client
        .from('laporan')
        .update({
          'status': status,
          'ditangani_oleh': _requireUserId(),
          'catatan_admin': adminNote,
        })
        .eq('id', reportId);
  }

  Future<Map<String, dynamic>?> getMyCuratorApplication() async {
    final rows = await _client
        .from('pengajuan_kurator')
        .select('id,alasan,status,catatan_admin,created_at,ditinjau_pada')
        .eq('id_user', _requireUserId())
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> submitCuratorApplication(String reason) async {
    await _client.from('pengajuan_kurator').insert({
      'id_user': _requireUserId(),
      'alasan': reason,
    });
  }

  Future<List<Map<String, dynamic>>> getCuratorApplications() async {
    return _client
        .from('pengajuan_kurator')
        .select(
          'id,id_user,alasan,status,catatan_admin,created_at,'
          'users!pengajuan_kurator_id_user_fkey(nama,username)',
        )
        .eq('status', 'menunggu')
        .order('created_at');
  }

  Future<void> reviewCuratorApplication({
    required String applicationId,
    required bool approve,
    String? note,
  }) async {
    await _client.rpc(
      'tinjau_pengajuan_kurator',
      params: {'p_id': applicationId, 'p_setuju': approve, 'p_catatan': note},
    );
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    return _client
        .from('notifikasi')
        .select('id,judul,isi,tautan_jenis,tautan_id,sudah_dibaca,created_at')
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<void> markAllNotificationsRead() async {
    await _client.rpc('tandai_semua_notifikasi_dibaca');
  }

  Future<void> deleteSpot(String spotId) async {
    await _client.rpc(
      'delete_spot_as_moderator',
      params: {'p_id_spot': spotId},
    );
  }

  Future<void> deleteContent({
    required String table,
    required String id,
  }) async {
    await _client.rpc(
      'delete_moderated_content',
      params: {'p_table_name': table, 'p_id': id},
    );
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    return _client
        .from('users')
        .select('id,username,nama,email,id_role,roles(nama)')
        .order('nama');
  }

  Future<List<Map<String, dynamic>>> getRoles() async {
    return _client.from('roles').select('id,nama').order('id');
  }

  Future<List<Map<String, dynamic>>> getCities() async {
    return _client.from('kabupaten_kota').select('id,nama').order('nama');
  }

  Future<void> updateUserRole({
    required String userId,
    required int roleId,
  }) async {
    await _client.rpc(
      'update_user_role',
      params: {'p_id_user': userId, 'p_id_role': roleId},
    );
  }

  Future<List<Map<String, dynamic>>> getActivity() async {
    return _client
        .from('log_aktivitas')
        .select('id,aktivitas,waktu,users(nama,username)')
        .order('waktu', ascending: false)
        .limit(200);
  }

  Future<void> upsertCategory({
    required String name,
    required String slug,
  }) async {
    final categoryName = name.trim();
    final categorySlug = slug.trim().isEmpty
        ? categoryName
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), '')
        : slug.trim().toLowerCase();
    if (categoryName.isEmpty || categorySlug.isEmpty) {
      throw ArgumentError('Nama dan slug kategori wajib diisi.');
    }
    await _client.rpc(
      'upsert_category',
      params: {'p_nama': categoryName, 'p_slug': categorySlug},
    );
  }

  Future<void> upsertDistrict({
    required int cityId,
    required String name,
    required String slug,
  }) async {
    final districtName = name.trim();
    final districtSlug = slug.trim().isEmpty
        ? districtName
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), '')
        : slug.trim().toLowerCase();
    if (districtName.isEmpty || districtSlug.isEmpty) {
      throw ArgumentError('Nama dan slug kecamatan wajib diisi.');
    }
    await _client.rpc(
      'upsert_district',
      params: {
        'p_id_kota': cityId,
        'p_nama': districtName,
        'p_slug': districtSlug,
      },
    );
  }

  Future<List<Spot>> getApprovedSpots() async {
    late final List<Map<String, dynamic>> approvedRows;
    var engagementAvailable = true;
    try {
      approvedRows = await _client
          .from('spots')
          .select(_spotSelectWithEngagement)
          .eq('id_status_verifikasi', 2)
          .order('created_at', ascending: false);
    } on PostgrestException {
      // Fallback agar aplikasi tetap bisa dibuka sebelum migration engagement
      // dijalankan di Supabase. Angka akan tampil setelah migration aktif.
      engagementAvailable = false;
      approvedRows = await _client
          .from('spots')
          .select(_spotSelectBase)
          .eq('id_status_verifikasi', 2)
          .order('created_at', ascending: false);
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return approvedRows.map((row) => Spot.fromJson(row)).toList();
    }

    final likedRows = engagementAvailable
        ? await _client
            .from('spot_likes')
            .select('id_spot')
            .eq('id_user', userId)
        : <Map<String, dynamic>>[];
    final likedIds = likedRows.map((row) => jsonString(row['id_spot'])).toSet();
    Spot parseSpot(Map<String, dynamic> row) => Spot.fromJson({
      ...row,
      'liked_by_me': likedIds.contains(jsonString(row['id'])),
    });

    // Spot milik sendiri yang sedang menunggu verifikasi tetap ditampilkan
    // kepada pemiliknya setelah diedit, tetapi tidak ditampilkan ke user lain.
    final pendingRows = await _client
        .from('spots')
        .select(engagementAvailable ? _spotSelectWithEngagement : _spotSelectBase)
        .eq('id_status_verifikasi', 1)
        .eq('id_pembuat', userId)
        .order('created_at', ascending: false);
    return [...approvedRows.map(parseSpot), ...pendingRows.map(parseSpot)];
  }

  Future<bool> toggleSpotLike(String spotId) async {
    return _client.rpc<bool>('toggle_spot_like', params: {'p_id_spot': spotId});
  }

  Future<void> recordSpotShare(String spotId) async {
    await _client.from('spot_shares').insert({
      'id_spot': spotId,
      'id_user': _requireUserId(),
    });
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

  Future<List<TravelCollection>> getPublicCollections() async {
    final rows = await _client
        .from('koleksi')
        .select(
          'id,judul,deskripsi,url_sampul,label_durasi,id_status_publikasi,'
          'detail_koleksi(count)',
        )
        .eq('id_status_publikasi', 1)
        .order('unggulan', ascending: false)
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
          'spots(id,id_pembuat,id_kecamatan,nama,ringkasan_editorial,latitude,longitude,created_at,'
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

  Future<void> updateSpot({
    required String spotId,
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
    await _client
        .from('spots')
        .update({
          'id_kecamatan': districtId,
          'id_kategori': categoryId,
          'nama': name,
          'slug': slug,
          'ringkasan_editorial': summary,
          'latitude': latitude,
          'longitude': longitude,
          'id_status_verifikasi': 1,
        })
        .eq('id', spotId);
  }

  Future<void> updateSpotBasic({
    required String spotId,
    required String name,
    required String summary,
    int? districtId,
    double? latitude,
    double? longitude,
  }) async {
    final values = <String, dynamic>{
      'nama': name,
      'ringkasan_editorial': summary,
      'latitude': latitude,
      'longitude': longitude,
      'id_status_verifikasi': 1,
    };
    if (districtId != null) values['id_kecamatan'] = districtId;
    await _client.from('spots').update(values).eq('id', spotId);
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
    final uniqueSlug = await _uniqueSpotSlug(slug);
    final row = await _client
        .from('spots')
        .insert({
          'id_kecamatan': districtId,
          'id_kategori': categoryId,
          'id_pembuat': userId,
          'id_status_verifikasi': 1,
          'nama': name,
          'slug': uniqueSlug,
          'ringkasan_editorial': summary,
          'latitude': latitude,
          'longitude': longitude,
        })
        .select('id')
        .single();
    return jsonString(row['id']);
  }

  Future<String> _uniqueSpotSlug(String requestedSlug) async {
    final base = requestedSlug.trim().isEmpty ? 'spot' : requestedSlug.trim();
    final existing = await _client
        .from('spots')
        .select('id')
        .eq('slug', base)
        .maybeSingle();
    if (existing == null) return base;

    final suffix = DateTime.now().millisecondsSinceEpoch.toString();
    return '$base-$suffix';
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

  Future<String> uploadSpotMedia({
    required String spotId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required int mediaTypeId,
    bool isCover = true,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final resolvedContentType = _resolveImageContentType(fileName, contentType);
    final path = '$spotId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final storage = _client.storage.from('media-spot');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: resolvedContentType, upsert: false),
    );
    final url = storage.getPublicUrl(path);
    try {
      if (isCover) {
        await _client
            .from('media_spot')
            .update({'is_cover': false})
            .eq('id_spot', spotId)
            .eq('is_cover', true);
      }
      await addSpotMedia(
        spotId: spotId,
        mediaUrl: url,
        mediaTypeId: mediaTypeId,
        caption: fileName,
        isCover: isCover,
      );
    } on Exception catch (error) {
      try {
        await storage.remove([path]);
      } on Exception catch (cleanupError) {
        throw StateError(
          'Media gagal dicatat: $error. File sementara gagal dihapus: $cleanupError',
        );
      }
      rethrow;
    }
    return url;
  }

  String _resolveImageContentType(String fileName, String contentType) {
    if (contentType != 'image/*' && contentType.isNotEmpty) {
      return contentType;
    }
    switch (fileName.toLowerCase().split('.').last) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
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

  Future<String> uploadStoryMedia({
    required String spotId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final path =
        '$spotId/stories/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final storage = _client.storage.from('media-spot');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return storage.getPublicUrl(path);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    return _client
        .from('kategori')
        .select('id,nama,slug,warna_aksen')
        .order('nama');
  }

  Future<List<Map<String, dynamic>>> getMediaTypes() async {
    return _client.from('jenis_media').select('id,nama').order('id');
  }

  Future<List<Map<String, dynamic>>> getDistricts() async {
    return _client
        .from('kecamatan')
        .select('id,nama,slug,id_kabupaten_kota,kabupaten_kota(nama)')
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
