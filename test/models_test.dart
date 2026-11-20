import 'package:flutter_test/flutter_test.dart';

import 'package:wisata_paliko/data/models.dart';

void main() {
  test('spot uses cover media and nested region names', () {
    final spot = Spot.fromJson({
      'id': 'spot-1',
      'nama': 'Lembah Harau',
      'ringkasan_editorial': 'Tebing dan air terjun',
      'latitude': -0.1,
      'longitude': 100.6,
      'created_at': '2026-01-01T00:00:00Z',
      'kecamatan': {
        'nama': 'Harau',
        'kabupaten_kota': {'nama': 'Lima Puluh Kota'},
      },
      'kategori': {'nama': 'Alam & Air Terjun'},
      'users': {'nama': 'Rani', 'username': 'rani'},
      'media_spot': [
        {'url_media': 'https://example.test/other.jpg', 'is_cover': false},
        {'url_media': 'https://example.test/cover.jpg', 'is_cover': true},
      ],
    });

    expect(spot.id, 'spot-1');
    expect(spot.area, 'Kec. Harau, Lima Puluh Kota');
    expect(spot.category, 'Alam & Air Terjun');
    expect(spot.image, 'https://example.test/cover.jpg');
    expect(spot.creatorUsername, 'rani');
  });

  test('tip maps rating, author, and vote count', () {
    final tip = ExplorerTip.fromJson({
      'id': 'tip-1',
      'isi_tips': 'Datang pagi hari',
      'rating_bintang': 4.5,
      'created_at': '2026-01-01T00:00:00Z',
      'users': {'nama': 'Rani'},
      'vote_tips': [
        {'count': 3},
      ],
    });

    expect(tip.authorName, 'Rani');
    expect(tip.rating, 4.5);
    expect(tip.voteCount, 3);
  });

  test('missing spot relations use safe display values', () {
    final spot = Spot.fromJson({'id': 'spot-2', 'nama': 'Ngalau'});

    expect(spot.area, 'Luak Limopuluah');
    expect(spot.category, 'Wisata');
    expect(spot.image, isEmpty);
    expect(spot.latitude, isNull);
  });
}
