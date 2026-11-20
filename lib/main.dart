import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'data/explorer_repository.dart';
import 'data/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vuycmgoxepxwxemkiwpt.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_MzTtp6VZWJfn2A8xGopEVA_g08cCl9F',
  );
  final supabaseKey = supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;
  final configured = supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  }
  runApp(LuakExplorerApp(configured: configured));
}

const _forest = Color(0xFF1B5E20);
const _leaf = Color(0xFF2E7D32);
const _clay = Color(0xFFC27D38);
const _ink = Color(0xFF1E293B);
const _muted = Color(0xFF718096);
const _paper = Color(0xFFF7F8F4);

class LuakExplorerApp extends StatelessWidget {
  const LuakExplorerApp({required this.configured, super.key});

  final bool configured;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Luak Explorer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _forest,
        primary: _forest,
        secondary: _clay,
        surface: _paper,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: _ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: _ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: _ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: _ink, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: _muted, fontSize: 12, height: 1.4),
      ),
    ),
    home: SupabaseAuthGate(
      configured: configured,
      authenticatedBuilder: (context) => const ExplorerShell(),
    ),
  );
}

class ExplorerShell extends StatefulWidget {
  const ExplorerShell({super.key});

  @override
  State<ExplorerShell> createState() => _ExplorerShellState();
}

class _ExplorerShellState extends State<ExplorerShell> {
  final _repository = ExplorerRepository(Supabase.instance.client);
  int _tab = 0;
  List<Spot> _spots = [];
  List<Story> _stories = [];
  List<TravelCollection> _collections = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _districts = [];
  Set<String> _saved = {};
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final spots = await _repository.getApprovedSpots();
      final saved = await _repository.getBookmarkedSpotIds(userId);
      final stories = await _repository.getActiveStories();
      final collections = await _repository.getMyCollections();
      final categories = await _repository.getCategories();
      final districts = await _repository.getDistricts();
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _saved = saved;
        _stories = stories;
        _collections = collections;
        _categories = categories;
        _districts = districts;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<bool> _toggleSaved(Spot spot) async {
    try {
      final saved = await _repository.toggleBookmark(spot.id);
      if (!mounted) return false;
      setState(() {
        if (saved) {
          _saved.add(spot.id);
        } else {
          _saved.remove(spot.id);
        }
      });
      return true;
    } on Exception catch (error) {
      if (mounted) _showMessage(context, 'Bookmark gagal disimpan: $error');
      return false;
    }
  }

  Future<void> _refreshCollections() async {
    final collections = await _repository.getMyCollections();
    if (mounted) setState(() => _collections = collections);
  }

  void _openSpot(Spot spot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SpotDetailPage(
          spot: spot,
          isSaved: _saved.contains(spot.id),
          onSave: () => _toggleSaved(spot),
          repository: _repository,
          onCollectionChanged: _refreshCollections,
        ),
      ),
    );
  }

  void _openCollection(TravelCollection collection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CollectionDetailPage(
          collection: collection,
          entries: _repository.getCollectionEntries(collection.id),
          onOpenSpot: _openSpot,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42, color: _forest),
                const SizedBox(height: 12),
                const Text(
                  'Data Supabase gagal dimuat',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                SelectableText('$_loadError', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadData,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            FeedPage(
              spots: _spots,
              stories: _stories,
              saved: _saved,
              onSave: _toggleSaved,
              onOpen: _openSpot,
              onOpenStory: (story) async {
                try {
                  await _repository.recordStoryView(story.id);
                  final spot = _spots.where((item) => item.id == story.spotId);
                  if (spot.isNotEmpty) _openSpot(spot.first);
                } on Exception catch (error) {
                  if (context.mounted) {
                    _showMessage(context, 'Cerita gagal dibuka: $error');
                  }
                }
              },
              onExplore: () => setState(() => _tab = 1),
            ),
            ExplorePage(
              spots: _spots,
              categories: _categories,
              districts: _districts,
              saved: _saved,
              onSave: _toggleSaved,
              onOpen: _openSpot,
              onSubmitSpot:
                  ({
                    required name,
                    required slug,
                    required summary,
                    required districtId,
                    required categoryId,
                    latitude,
                    longitude,
                  }) async {
                    await _repository.createSpot(
                      name: name,
                      slug: slug,
                      summary: summary,
                      districtId: districtId,
                      categoryId: categoryId,
                      latitude: latitude,
                      longitude: longitude,
                    );
                    if (context.mounted) {
                      _showMessage(
                        context,
                        'Usulan spot terkirim dan menunggu verifikasi.',
                      );
                    }
                  },
            ),
            NearbyPage(spots: _spots, onOpen: _openSpot),
            SavedPage(
              savedSpots: _spots
                  .where((spot) => _saved.contains(spot.id))
                  .toList(),
              collections: _collections,
              profileName:
                  (Supabase
                          .instance
                          .client
                          .auth
                          .currentUser
                          ?.userMetadata?['nama']
                      as String?) ??
                  Supabase.instance.client.auth.currentUser?.email ??
                  'Penjelajah',
              username:
                  (Supabase
                          .instance
                          .client
                          .auth
                          .currentUser
                          ?.userMetadata?['username']
                      as String?) ??
                  'penjelajah',
              onOpen: _openSpot,
              onOpenCollection: _openCollection,
              onSignOut: () => Supabase.instance.client.auth.signOut(),
              onRefresh: _loadData,
              onCreateCollection:
                  ({
                    required title,
                    required description,
                    required isPublic,
                  }) async {
                    await _repository.createCollection(
                      title: title,
                      description: description,
                      isPublic: isPublic,
                    );
                    await _loadData();
                  },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE5F1E5),
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Jelajah',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on_rounded),
            label: 'Peta Spot',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'Tersimpan',
          ),
        ],
      ),
    );
  }
}

class FeedPage extends StatefulWidget {
  const FeedPage({
    required this.spots,
    required this.stories,
    required this.saved,
    required this.onSave,
    required this.onOpen,
    required this.onOpenStory,
    required this.onExplore,
    super.key,
  });

  final List<Spot> spots;
  final List<Story> stories;
  final Set<String> saved;
  final ValueChanged<Spot> onSave;
  final ValueChanged<Spot> onOpen;
  final ValueChanged<Story> onOpenStory;
  final VoidCallback onExplore;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final stories = widget.stories;
    final feedSpots = widget.spots.where((spot) {
      if (_category == 2) {
        return spot.category.toLowerCase().contains('kuliner');
      }
      if (_category == 3) {
        return spot.category.toLowerCase().contains('alam') ||
            spot.category.toLowerCase().contains('air');
      }
      return true;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const _BrandMark(),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Luak Explorer',
                        style: TextStyle(
                          color: _forest,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'PAYAKUMBUH & 50 KOTA',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cari tempat',
                  onPressed: widget.onExplore,
                  icon: const Icon(Icons.search_rounded, color: _ink),
                ),
                IconButton(
                  tooltip: 'Notifikasi',
                  onPressed: () =>
                      _showMessage(context, 'Belum ada notifikasi'),
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Icon(Icons.explore, size: 16, color: _forest),
                const SizedBox(width: 6),
                const Text(
                  'Menjelajah sekitar',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Payakumbuh',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 17, color: _ink),
                const Spacer(),
                _tag('Sumatera Barat', const Color(0xFFE8F1E8), _forest),
              ],
            ),
          ),
        ),
        if (stories.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    'Cerita di sekitar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onExplore,
                    child: const Text('Lihat semua'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 104,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: stories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 15),
                itemBuilder: (context, index) => _StoryBubble(
                  title: stories[index].title,
                  image: stories[index].image,
                  isNew: index == 0,
                  onTap: () => widget.onOpenStory(stories[index]),
                ),
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          sliver: SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('Untuk Anda', 0),
                  const SizedBox(width: 8),
                  _filterChip('Terbaru', 1),
                  const SizedBox(width: 8),
                  _filterChip('Kuliner Autentik', 2),
                  const SizedBox(width: 8),
                  _filterChip('Spot Alam', 3),
                ],
              ),
            ),
          ),
        ),
        if (feedSpots.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('Belum ada spot untuk kategori ini.')),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _FeedPost(
                  spot: feedSpots[index],
                  isSaved: widget.saved.contains(feedSpots[index].id),
                  onSave: () => widget.onSave(feedSpots[index]),
                  onOpen: () => widget.onOpen(feedSpots[index]),
                ),
              ),
              childCount: feedSpots.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }

  Widget _filterChip(String label, int index) {
    final selected = _category == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _category = index),
      backgroundColor: Colors.white,
      selectedColor: _forest,
      side: BorderSide(color: selected ? _forest : const Color(0xFFE5E8E3)),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 7),
    );
  }
}

class _FeedPost extends StatelessWidget {
  const _FeedPost({
    required this.spot,
    required this.isSaved,
    required this.onSave,
    required this.onOpen,
  });

  final Spot spot;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isFood = spot.category == 'Kuliner Legendaris';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECEFEA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE8F1E8),
              child: Icon(Icons.person, color: _forest),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    spot.creatorName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: _leaf, size: 15),
              ],
            ),
            subtitle: Text(
              '@${spot.creatorUsername} · ${spot.area}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
            trailing: IconButton(
              onPressed: () => _showMessage(context, 'Opsi postingan'),
              icon: const Icon(Icons.more_horiz),
            ),
          ),
          GestureDetector(
            onTap: onOpen,
            child: AspectRatio(
              aspectRatio: 1.18,
              child: _NetworkPhoto(image: spot.image),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onOpen,
                      icon: const Icon(Icons.mode_comment_outlined, size: 21),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showMessage(context, 'Siap dibagikan'),
                      icon: const Icon(Icons.send_outlined, size: 21),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onSave,
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? _forest : _ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${spot.name} — ${spot.description}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      isFood ? Icons.lightbulb_outline : Icons.location_on,
                      size: 14,
                      color: isFood ? _clay : _forest,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isFood ? 'Tips Warga Lokal' : spot.area,
                        style: TextStyle(
                          color: isFood ? _clay : _muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _timeAgo(spot.createdAt),
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    required this.spots,
    required this.categories,
    required this.districts,
    required this.saved,
    required this.onSave,
    required this.onOpen,
    required this.onSubmitSpot,
    super.key,
  });

  final List<Spot> spots;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> districts;
  final Set<String> saved;
  final ValueChanged<Spot> onSave;
  final ValueChanged<Spot> onOpen;
  final Future<void> Function({
    required String name,
    required String slug,
    required String summary,
    required int districtId,
    required int categoryId,
    double? latitude,
    double? longitude,
  })
  onSubmitSpot;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _category = 'Semua';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final categories = [
      'Semua',
      ...widget.categories.map((row) => jsonString(row['nama'])),
    ];
    final filtered = widget.spots.where((spot) {
      final matchesCategory =
          _category == 'Semua' || spot.category == _category;
      final matchesQuery = '${spot.name} ${spot.area}'.toLowerCase().contains(
        _query.toLowerCase(),
      );
      return matchesCategory && matchesQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 15),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Temukan pesona', style: TextStyle(color: _muted)),
                Text(
                  'Luak Limopuluah',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Cari tempat, kecamatan, atau kuliner',
                    prefixIcon: const Icon(Icons.search, color: _forest),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE7EAE5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE7EAE5)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _suggestSpot,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Usulkan Spot'),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 43,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = _category == category;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = category),
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: _forest,
                  side: BorderSide(
                    color: selected ? _forest : const Color(0xFFE5E8E3),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : _ink,
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.spots.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
            sliver: SliverToBoxAdapter(
              child: _CuratedBanner(
                image: widget.spots.first.image,
                onTap: () => widget.onOpen(widget.spots.first),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Spot pilihan',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${filtered.length} tempat',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Belum ada tempat yang cocok.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SpotCard(
                  spot: filtered[index],
                  isSaved: widget.saved.contains(filtered[index].id),
                  onSave: () => widget.onSave(filtered[index]),
                  onTap: () => widget.onOpen(filtered[index]),
                ),
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _suggestSpot() async {
    if (widget.categories.isEmpty || widget.districts.isEmpty) {
      _showMessage(context, 'Data kategori atau kecamatan belum tersedia.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final summary = TextEditingController();
    final latitude = TextEditingController();
    final longitude = TextEditingController();
    var categoryId = (widget.categories.first['id'] as num).toInt();
    var districtId = (widget.districts.first['id'] as num).toInt();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Usulkan spot wisata'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Nama spot'),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    TextFormField(
                      controller: summary,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Ringkasan editorial',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Ringkasan wajib diisi'
                          : null,
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: widget.categories
                          .map(
                            (row) => DropdownMenuItem(
                              value: (row['id'] as num).toInt(),
                              child: Text(jsonString(row['nama'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => categoryId = value);
                        }
                      },
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: districtId,
                      decoration: const InputDecoration(labelText: 'Kecamatan'),
                      items: widget.districts
                          .map(
                            (row) => DropdownMenuItem(
                              value: (row['id'] as num).toInt(),
                              child: Text(jsonString(row['nama'])),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => districtId = value);
                        }
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: latitude,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Latitude (opsional)',
                            ),
                            validator: (value) =>
                                _coordinateValidator(value, -90, 90),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: longitude,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Longitude (opsional)',
                            ),
                            validator: (value) =>
                                _coordinateValidator(value, -180, 180),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  if (latitude.text.trim().isEmpty !=
                      longitude.text.trim().isEmpty) {
                    _showMessage(
                      context,
                      'Isi latitude dan longitude bersama-sama.',
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Kirim untuk verifikasi'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final spotName = name.text.trim();
      final slugBase = spotName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final slug = slugBase.isEmpty
          ? 'spot-${DateTime.now().millisecondsSinceEpoch}'
          : slugBase;
      try {
        await widget.onSubmitSpot(
          name: spotName,
          slug: slug,
          summary: summary.text.trim(),
          districtId: districtId,
          categoryId: categoryId,
          latitude: double.tryParse(latitude.text.trim()),
          longitude: double.tryParse(longitude.text.trim()),
        );
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Usulan gagal dikirim: $error');
      }
    }

    name.dispose();
    summary.dispose();
    latitude.dispose();
    longitude.dispose();
  }

  String? _coordinateValidator(String? value, double minimum, double maximum) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final coordinate = double.tryParse(text);
    if (coordinate == null || coordinate < minimum || coordinate > maximum) {
      return 'Koordinat tidak valid';
    }
    return null;
  }
}

class _CuratedBanner extends StatelessWidget {
  const _CuratedBanner({required this.image, required this.onTap});

  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 155,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: _forest,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _NetworkPhoto(image: image),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _tag('KURASI BULAN INI', const Color(0xFFF7E4C8), _forest),
                  const SizedBox(height: 8),
                  const Text(
                    'Sudut paling estetik\nLembah Harau',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.isSaved,
    required this.onSave,
    required this.onTap,
  });

  final Spot spot;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _NetworkPhoto(image: spot.image),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onSave,
                        icon: Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border,
                          size: 19,
                          color: _forest,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _tag(
                      spot.category == 'Kuliner Legendaris'
                          ? 'KULINER'
                          : 'ALAM',
                      Colors.white.withValues(alpha: 0.94),
                      _forest,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: _muted,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          spot.area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.verified, size: 13, color: _leaf),
                      const SizedBox(width: 3),
                      const Text(
                        'Terverifikasi',
                        style: TextStyle(
                          fontSize: 10,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyPage extends StatelessWidget {
  const NearbyPage({required this.spots, required this.onOpen, super.key});

  final List<Spot> spots;
  final ValueChanged<Spot> onOpen;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 15),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Jelajahi sekitar', style: TextStyle(color: _muted)),
                Text(
                  'Peta Spot',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Container(
              height: 325,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFE4EBDD),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (spots.isNotEmpty)
                    _NetworkPhoto(image: spots.first.image)
                  else
                    const ColoredBox(color: Color(0xFFE4EBDD)),
                  Container(color: const Color(0x66E4EBDD)),
                  for (
                    var index = 0;
                    index < spots.length && index < 3;
                    index++
                  )
                    Positioned(
                      left: index == 0
                          ? 42
                          : index == 2
                          ? 70
                          : null,
                      right: index == 1 ? 22 : null,
                      top: index == 0
                          ? 50
                          : index == 1
                          ? 128
                          : null,
                      bottom: index == 2 ? 72 : null,
                      child: _MapPin(label: spots[index].name),
                    ),
                  if (spots.isEmpty)
                    const Center(
                      child: Text(
                        'Belum ada spot terverifikasi',
                        style: TextStyle(
                          color: _forest,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 13,
                    bottom: 13,
                    child: FloatingActionButton.small(
                      heroTag: 'current-location',
                      backgroundColor: Colors.white,
                      foregroundColor: _forest,
                      onPressed: () =>
                          _showMessage(context, 'Lokasi Payakumbuh dipilih'),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                  Positioned(
                    left: 13,
                    right: 70,
                    bottom: 13,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_on, color: _forest, size: 18),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Payakumbuh & Lima Puluh Kota',
                              style: TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Icon(Icons.tune, color: _muted, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 23, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Spot populer dekat sini',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const Text('Lihat peta', style: TextStyle(color: _forest)),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _NearbyTile(
              spot: spots[index],
              onTap: () => onOpen(spots[index]),
            ),
            childCount: spots.length < 4 ? spots.length : 4,
          ),
        ),
      ],
    );
  }
}

class _NearbyTile extends StatelessWidget {
  const _NearbyTile({required this.spot, required this.onTap});

  final Spot spot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 58,
          height: 58,
          child: _NetworkPhoto(image: spot.image),
        ),
      ),
      title: Text(
        spot.name,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(
        spot.area,
        style: const TextStyle(fontSize: 11, color: _muted),
      ),
      trailing: const Icon(Icons.chevron_right, color: _muted),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: _forest,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.landscape, color: Colors.white, size: 17),
        ),
        Container(width: 2, height: 9, color: _forest),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class SavedPage extends StatefulWidget {
  const SavedPage({
    required this.savedSpots,
    required this.collections,
    required this.profileName,
    required this.username,
    required this.onOpen,
    required this.onOpenCollection,
    required this.onSignOut,
    required this.onRefresh,
    required this.onCreateCollection,
    super.key,
  });

  final List<Spot> savedSpots;
  final List<TravelCollection> collections;
  final String profileName;
  final String username;
  final ValueChanged<Spot> onOpen;
  final ValueChanged<TravelCollection> onOpenCollection;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onRefresh;
  final Future<void> Function({
    required String title,
    required String description,
    required bool isPublic,
  })
  onCreateCollection;

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Profil penjelajah',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Muat ulang',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Keluar',
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: const Color(0xFFECEFEA)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFFE8F1E8),
                        child: Icon(Icons.person, size: 32, color: _forest),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.profileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '@${widget.username}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat(
                        value: '${widget.savedSpots.length}',
                        label: 'Spot Disimpan',
                      ),
                      _Stat(
                        value: '${widget.collections.length}',
                        label: 'Koleksi',
                      ),
                      const _Stat(value: '—', label: 'Ulasan Dibagi'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Koleksi (Boards)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _createCollection,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Buat'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 18),
          sliver: SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _viewChip('Semua Spot', 0),
                  const SizedBox(width: 8),
                  _viewChip('Papan Perjalanan', 1),
                ],
              ),
            ),
          ),
        ),
        if (_view == 0)
          if (widget.savedSpots.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Spot tersimpan akan muncul di sini.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _SpotCard(
                    spot: widget.savedSpots[index],
                    isSaved: true,
                    onSave: () {},
                    onTap: () => widget.onOpen(widget.savedSpots[index]),
                  ),
                  childCount: widget.savedSpots.length,
                ),
              ),
            )
        else if (widget.collections.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Buat koleksi perjalanan pertama Anda.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            sliver: SliverList.builder(
              itemCount: widget.collections.length,
              itemBuilder: (context, index) => _BoardCard(
                collection: widget.collections[index],
                onTap: () => widget.onOpenCollection(widget.collections[index]),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _createCollection() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var isPublic = true;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Buat koleksi'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Judul'),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Judul wajib diisi'
                      : null,
                ),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPublic,
                  title: const Text('Koleksi publik'),
                  onChanged: (value) => setDialogState(() => isPublic = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        await widget.onCreateCollection(
          title: titleController.text.trim(),
          description: descriptionController.text.trim(),
          isPublic: isPublic,
        );
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Koleksi gagal dibuat: $error');
      }
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  Widget _viewChip(String label, int index) {
    final selected = _view == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _view = index),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE5F1E5),
      side: BorderSide(
        color: selected ? const Color(0xFFB7D1B7) : const Color(0xFFE5E8E3),
      ),
      labelStyle: TextStyle(
        color: selected ? _forest : _ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SpotDetailPage extends StatefulWidget {
  const SpotDetailPage({
    required this.spot,
    required this.isSaved,
    required this.onSave,
    required this.repository,
    required this.onCollectionChanged,
    super.key,
  });

  final Spot spot;
  final bool isSaved;
  final Future<bool> Function() onSave;
  final ExplorerRepository repository;
  final Future<void> Function() onCollectionChanged;

  @override
  State<SpotDetailPage> createState() => _SpotDetailPageState();
}

class _SpotDetailPageState extends State<SpotDetailPage> {
  late bool _isSaved;
  late Future<List<ExplorerTip>> _tips;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSaved;
    _tips = widget.repository.getTips(widget.spot.id);
  }

  Future<void> _saveSpot() async {
    final success = await widget.onSave();
    if (success && mounted) setState(() => _isSaved = !_isSaved);
  }

  Future<void> _writeTip() async {
    final contentController = TextEditingController();
    var rating = 5.0;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tulis tips warga'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: contentController,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Tips pengalaman Anda',
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Tips tidak boleh kosong'
                      : null,
                ),
                Row(
                  children: [
                    const Text('Rating'),
                    const SizedBox(width: 12),
                    DropdownButton<double>(
                      value: rating,
                      items: [1, 2, 3, 4, 5]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value.toDouble(),
                              child: Text('$value bintang'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => rating = value);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      try {
        await widget.repository.addTip(
          spotId: widget.spot.id,
          content: contentController.text.trim(),
          rating: rating,
        );
        if (mounted) {
          setState(() => _tips = widget.repository.getTips(widget.spot.id));
        }
      } on Exception catch (error) {
        if (mounted) _showMessage(context, 'Tips gagal dikirim: $error');
      }
    }
    contentController.dispose();
  }

  Future<void> _addToCollection() async {
    try {
      final collections = await widget.repository.getMyCollections();
      if (!mounted) return;
      if (collections.isEmpty) {
        _showMessage(context, 'Buat koleksi terlebih dahulu di tab Tersimpan.');
        return;
      }

      String selectedId = collections.first.id;
      final noteController = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Simpan ke koleksi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(labelText: 'Koleksi'),
                  items: collections
                      .map(
                        (collection) => DropdownMenuItem(
                          value: collection.id,
                          child: Text(collection.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedId = value);
                    }
                  },
                ),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan kurator (opsional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      if (result == true) {
        final curatorNote = noteController.text.trim();
        noteController.dispose();
        await widget.repository.addSpotToCollection(
          collectionId: selectedId,
          spotId: widget.spot.id,
          curatorNote: curatorNote.isEmpty ? null : curatorNote,
        );
        await widget.onCollectionChanged();
        if (mounted) _showMessage(context, 'Spot ditambahkan ke koleksi.');
      } else {
        noteController.dispose();
      }
    } on Exception catch (error) {
      if (mounted) _showMessage(context, 'Gagal menambahkan spot: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 290,
            pinned: true,
            foregroundColor: Colors.white,
            backgroundColor: _forest,
            actions: [
              IconButton(
                tooltip: 'Bagikan',
                onPressed: () => _showMessage(context, 'Siap dibagikan'),
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: _isSaved ? 'Hapus dari koleksi' : 'Simpan',
                onPressed: _saveSpot,
                icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Detail Spot Wisata',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _NetworkPhoto(image: spot.image),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0xAA000000)],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    bottom: 62,
                    child: _tag(
                      'TRENDING DI LUAK 50',
                      const Color(0xFFF7E4C8),
                      _forest,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  spot.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, color: _forest, size: 17),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        spot.area,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _tag(spot.category, const Color(0xFFE8F1E8), _forest),
                  ],
                ),
                const SizedBox(height: 20),
                _InfoGrid(spot: spot),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addToCollection,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Tambah ke koleksi'),
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeading(
                  icon: Icons.auto_stories,
                  title: 'Tentang ${spot.name}',
                ),
                const SizedBox(height: 9),
                Text(
                  spot.description.isEmpty
                      ? 'Belum ada ringkasan editorial untuk spot ini.'
                      : spot.description,
                  style: const TextStyle(
                    color: _muted,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                _SectionHeading(
                  icon: Icons.add_a_photo_outlined,
                  title: 'Spot Foto Wajib',
                  trailing: '4 titik',
                ),
                const SizedBox(height: 10),
                const _ChecklistRow(
                  number: '01',
                  title: 'Gerbang Tebing Harau',
                  detail: 'Foto simetris dengan dua tebing raksasa',
                ),
                const _ChecklistRow(
                  number: '02',
                  title: 'Jembatan Kayu Sarasah Bunta',
                  detail: 'Cipratan air sejuk dan latar batu bertingkat',
                ),
                const _ChecklistRow(
                  number: '03',
                  title: 'Kampung Eropa & Harau Sky Balon',
                  detail: 'Warna-warni kincir angin dan spot santai',
                ),
                const _ChecklistRow(
                  number: '04',
                  title: 'Puncak Bukik Bulek',
                  detail: 'Panorama lembah berkanopi hijau',
                ),
                const SizedBox(height: 20),
                const _SectionHeading(
                  icon: Icons.tips_and_updates_outlined,
                  title: 'Etika & Tips Berkunjung',
                ),
                const SizedBox(height: 10),
                const _TipRow(
                  icon: Icons.hiking,
                  title: 'Gunakan alas kaki anti-selip',
                  detail: 'Bebatuan di dekat air terjun dapat licin.',
                ),
                const _TipRow(
                  icon: Icons.volunteer_activism,
                  title: 'Hormati norma adat setempat',
                  detail: 'Berbusana sopan dan ramah kepada warga lokal.',
                ),
                const _TipRow(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Bawa pulang sampah',
                  detail: 'Jaga kebersihan kawasan geopark.',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: _SectionHeading(
                        icon: Icons.chat_bubble_outline,
                        title: 'Catatan Penjelajah',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _writeTip,
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Tulis Tips'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FutureBuilder<List<ExplorerTip>>(
                  future: _tips,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        'Tips gagal dimuat: ${snapshot.error}',
                        style: const TextStyle(color: Color(0xFFB42318)),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tips = snapshot.data ?? [];
                    if (tips.isEmpty) {
                      return const Text(
                        'Belum ada tips warga. Bagikan pengalaman pertama Anda.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      );
                    }
                    return Column(
                      children: tips
                          .map(
                            (tip) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ReviewCard(
                                tip: tip,
                                onHelpful: () async {
                                  try {
                                    await widget.repository.toggleTipVote(
                                      tip.id,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _tips = widget.repository.getTips(
                                          widget.spot.id,
                                        );
                                      });
                                    }
                                  } on Exception catch (error) {
                                    if (context.mounted) {
                                      _showMessage(
                                        context,
                                        'Vote gagal disimpan: $error',
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFECEFEA))),
          ),
          child: Row(
            children: [
              Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _forest,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveSpot,
                  icon: Icon(
                    _isSaved ? Icons.bookmark_remove : Icons.bookmark_add,
                  ),
                  label: Text(_isSaved ? 'Tersimpan' : 'Simpan Spot'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _forest,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final items = [
      _InfoItem(
        icon: Icons.category_outlined,
        title: 'KATEGORI',
        value: spot.category,
        detail: 'Kategori wisata',
      ),
      _InfoItem(
        icon: Icons.location_on_outlined,
        title: 'WILAYAH',
        value: spot.area,
        detail: 'Lokasi administratif',
      ),
      _InfoItem(
        icon: Icons.near_me,
        title: 'LATITUDE',
        value: spot.latitude?.toStringAsFixed(5) ?? 'Belum tersedia',
        detail: 'Koordinat spot',
      ),
      _InfoItem(
        icon: Icons.explore_outlined,
        title: 'LONGITUDE',
        value: spot.longitude?.toStringAsFixed(5) ?? 'Belum tersedia',
        detail: 'Koordinat spot',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEFEA)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.25,
        children: items,
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1E8),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 17, color: _forest),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: _forest),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: _forest,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_outline, size: 18, color: _leaf),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4EB),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, color: _forest, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.tip, required this.onHelpful});

  final ExplorerTip tip;
  final Future<void> Function() onHelpful;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFECEFEA)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xFFE8F1E8),
                child: Icon(Icons.person, color: _forest, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tip.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      tip.createdAt.toLocal().toString().split(' ').first,
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star, color: _clay, size: 15),
              Text(
                ' ${tip.rating.toStringAsFixed(1)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(tip.content, style: const TextStyle(fontSize: 12, height: 1.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () async => onHelpful(),
                icon: const Icon(
                  Icons.thumb_up_outlined,
                  color: _muted,
                  size: 15,
                ),
              ),
              SizedBox(width: 5),
              Text(
                'Membantu (${tip.voteCount})',
                style: TextStyle(color: _muted, fontSize: 10),
              ),
              SizedBox(width: 15),
              Icon(Icons.reply, color: _muted, size: 15),
              SizedBox(width: 5),
              Text('Tanggapi', style: TextStyle(color: _muted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.collection, required this.onTap});

  final TravelCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFEA)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(9),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 58,
            height: 58,
            child: _NetworkPhoto(image: collection.coverImage),
          ),
        ),
        title: Text(
          collection.title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${collection.description.isEmpty ? 'Koleksi perjalanan' : collection.description}\n'
            '${collection.spotCount} spot · '
            '${collection.duration.isEmpty ? '' : '${collection.duration} · '}${collection.isPublic ? 'Publik' : 'Pribadi'}',
            style: const TextStyle(color: _muted, fontSize: 10, height: 1.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: _muted),
        isThreeLine: true,
      ),
    );
  }
}

class CollectionDetailPage extends StatelessWidget {
  const CollectionDetailPage({
    required this.collection,
    required this.entries,
    required this.onOpenSpot,
    super.key,
  });

  final TravelCollection collection;
  final Future<List<CollectionEntry>> entries;
  final ValueChanged<Spot> onOpenSpot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(collection.title)),
      body: FutureBuilder<List<CollectionEntry>>(
        future: entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Isi koleksi gagal dimuat: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Belum ada spot di dalam koleksi ini.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                color: Colors.white,
                child: ListTile(
                  onTap: () => onOpenSpot(item.spot),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: _NetworkPhoto(image: item.spot.image),
                    ),
                  ),
                  title: Text(
                    item.spot.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    item.curatorNote.isEmpty
                        ? item.spot.area
                        : '${item.spot.area}\n${item.curatorNote}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${item.position}',
                    style: const TextStyle(
                      color: _forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.title,
    required this.image,
    required this.isNew,
    required this.onTap,
  });

  final String title;
  final String image;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isNew ? _clay : const Color(0xFFD9E5D8),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 27,
                backgroundColor: const Color(0xFFE8F1E8),
                backgroundImage: image.isEmpty ? null : NetworkImage(image),
                child: image.isEmpty
                    ? const Icon(Icons.landscape, color: _forest)
                    : null,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.landscape_rounded, color: _forest, size: 25),
    );
  }
}

class _NetworkPhoto extends StatelessWidget {
  const _NetworkPhoto({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    if (image.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFDCE8D8),
        child: Center(child: Icon(Icons.landscape, color: _forest, size: 42)),
      );
    }
    return Image.network(
      image,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: const Color(0xFFDCE8D8),
        alignment: Alignment.center,
        child: const Icon(Icons.landscape, color: _forest, size: 42),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFFE8F1E8),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _forest),
          ),
        );
      },
    );
  }
}

Widget _tag(String label, Color background, Color foreground) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    ),
  );
}

String _timeAgo(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.isNegative || difference.inMinutes < 1) return 'baru saja';
  if (difference.inMinutes < 60) return '${difference.inMinutes} menit lalu';
  if (difference.inHours < 24) return '${difference.inHours} jam lalu';
  if (difference.inDays < 30) return '${difference.inDays} hari lalu';
  return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
