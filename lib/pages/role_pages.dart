import 'package:material_ui/material_ui.dart';

import '../data/explorer_repository.dart';
import '../data/models.dart';
import '../widgets/motion_card.dart';
import 'admin_workflow_pages.dart';

class _RoleRefreshState extends StatelessWidget {
  const _RoleRefreshState({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Center(child: child),
        ),
      ],
    ),
  );
}

class CuratorVerificationPage extends StatefulWidget {
  const CuratorVerificationPage({
    required this.repository,
    required this.onOpenSpot,
    this.showAppBar = true,
    super.key,
  });

  final ExplorerRepository repository;
  final ValueChanged<Spot> onOpenSpot;
  final bool showAppBar;

  @override
  State<CuratorVerificationPage> createState() =>
      _CuratorVerificationPageState();
}

class _CuratorVerificationPageState extends State<CuratorVerificationPage> {
  late Future<List<Spot>> _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.repository.getPendingSpots();
  }

  Future<void> _reload() async {
    final request = widget.repository.getPendingSpots();
    setState(() => _pending = request);
    await request;
  }

  Future<void> _verify(Spot spot, int statusId) async {
    final noteController = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(statusId == 2 ? 'Verifikasi spot' : 'Tolak spot'),
        content: TextField(
          controller: noteController,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Catatan untuk pengusul (opsional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (save != true) {
      noteController.dispose();
      return;
    }
    try {
      await widget.repository.verifySpot(
        spotId: spot.id,
        statusId: statusId,
        note: noteController.text.trim(),
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              statusId == 2 ? 'Spot berhasil diverifikasi.' : 'Spot ditolak.',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memproses spot: $error')));
      }
    } finally {
      noteController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Verifikasi Spot'),
              actions: [
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
              ],
            )
          : null,
      body: FutureBuilder<List<Spot>>(
        future: _pending,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _RoleRefreshState(
              onRefresh: _reload,
              child: const CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return _RoleRefreshState(
              onRefresh: _reload,
              child: Text('Gagal memuat: ${snapshot.error}'),
            );
          }
          final spots = snapshot.data ?? const <Spot>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                if (!widget.showAppBar) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Verifikasi spot',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tinjau usulan tempat sebelum ditampilkan ke publik.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Muat ulang',
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.pending_actions_rounded,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          spots.isEmpty
                              ? 'Semua usulan sudah ditangani.'
                              : '${spots.length} usulan menunggu ditinjau',
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (spots.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 42,
                            color: scheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Tidak ada usulan baru',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Semua pengajuan spot sudah selesai diproses.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final spot in spots) ...[
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => widget.onOpenSpot(spot),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.location_on_outlined,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      spot.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      spot.area,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        child: Text(
                                          'Usul oleh ${spot.creatorName}',
                                          style: TextStyle(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<int>(
                                tooltip: 'Tindakan',
                                icon: const Icon(Icons.more_vert_rounded),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onSelected: (value) => _verify(spot, value),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 2,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.check_circle_outline),
                                      title: Text('Verifikasi spot'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 3,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.close_rounded),
                                      title: Text('Tolak usulan'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({
    required this.repository,
    required this.onOpenSpot,
    required this.onDataChanged,
    super.key,
  });

  final ExplorerRepository repository;
  final ValueChanged<Spot> onOpenSpot;
  final Future<void> Function() onDataChanged;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _section = 0;

  static const _sections = [
    (label: 'Ringkasan', icon: Icons.dashboard_outlined),
    (label: 'Verifikasi spot', icon: Icons.verified_outlined),
    (label: 'Laporan', icon: Icons.flag_outlined),
    (label: 'Pengajuan Kurator', icon: Icons.person_add_alt_1_outlined),
    (label: 'Pengguna & role', icon: Icons.people_outline),
    (label: 'Data master', icon: Icons.tune),
    (label: 'Riwayat aktivitas', icon: Icons.history),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final pages = [
      AdminDashboardPage(repository: widget.repository),
      CuratorVerificationPage(
        repository: widget.repository,
        onOpenSpot: widget.onOpenSpot,
        showAppBar: false,
      ),
      AdminReportsPage(repository: widget.repository),
      CuratorApplicationsPage(repository: widget.repository),
      _UserRoleTab(repository: widget.repository),
      _MasterTab(
        repository: widget.repository,
        onDataChanged: widget.onDataChanged,
      ),
      _ActivityTab(repository: widget.repository),
    ];

    void selectSection(int index) {
      setState(() => _section = index);
      if (compact) Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(title: Text(_sections[_section].label)),
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 16, 16),
                      child: Text(
                        'MENU ADMIN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    for (var index = 0; index < _sections.length; index++)
                      ListTile(
                        selected: _section == index,
                        leading: Icon(_sections[index].icon),
                        title: Text(_sections[index].label),
                        onTap: () => selectSection(index),
                      ),
                  ],
                ),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!compact)
            NavigationRail(
              selectedIndex: _section,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: selectSection,
              destinations: [
                for (final section in _sections)
                  NavigationRailDestination(
                    icon: Icon(section.icon),
                    label: Text(section.label),
                  ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _section, children: pages),
          ),
        ],
      ),
    );
  }
}

class _UserRoleTab extends StatefulWidget {
  const _UserRoleTab({required this.repository});
  final ExplorerRepository repository;

  @override
  State<_UserRoleTab> createState() => _UserRoleTabState();
}

class _UserRoleTabState extends State<_UserRoleTab> {
  late Future<
    ({List<Map<String, dynamic>> roles, List<Map<String, dynamic>> users})
  >
  _usersAndRoles;

  @override
  void initState() {
    super.initState();
    _usersAndRoles = _load();
  }

  Future<({List<Map<String, dynamic>> roles, List<Map<String, dynamic>> users})>
  _load() async => (
    users: await widget.repository.getUsers(),
    roles: await widget.repository.getRoles(),
  );

  Future<void> _reload() async {
    final request = _load();
    setState(() => _usersAndRoles = request);
    await request;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({List<Map<String, dynamic>> roles, List<Map<String, dynamic>> users})
    >(
      future: _usersAndRoles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _RoleRefreshState(
            onRefresh: _reload,
            child: Text('Gagal memuat: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return _RoleRefreshState(
            onRefresh: _reload,
            child: const CircularProgressIndicator(),
          );
        }
        final users = snapshot.data!.users;
        final roles = snapshot.data!.roles;
        final scheme = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manajemen pengguna',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Atur akses dan peran akun.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${users.length} akun',
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: 'Muat ulang pengguna',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              ...users.map((user) {
                final roleId = jsonInt(user['id_role']);
                final roleItems = roles
                    .map((role) {
                      final id = jsonInt(role['id']);
                      return id == null
                          ? null
                          : DropdownMenuItem<int>(
                              value: id,
                              child: Text(jsonString(role['nama'], 'Role')),
                            );
                    })
                    .whereType<DropdownMenuItem<int>>()
                    .toList();
                final name = jsonString(user['nama'], 'Pengguna');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    tileColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    leading: CircleAvatar(
                      radius: 21,
                      backgroundColor: const Color(0xFFE8F3E8),
                      child: Text(
                        name.trim().isEmpty
                            ? 'P'
                            : name.trim().substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    titleTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    subtitleTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '@${jsonString(user['username'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      width: 132,
                      height: 42,
                      padding: const EdgeInsets.only(left: 12, right: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: roleItems.any((item) => item.value == roleId)
                              ? roleId
                              : null,
                          hint: Text(
                            'Pilih role',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          isExpanded: true,
                          isDense: true,
                          itemHeight: 48,
                          borderRadius: BorderRadius.circular(16),
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          elevation: 8,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: scheme.primary,
                            size: 19,
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          items: roleItems
                              .map(
                                (item) => DropdownMenuItem<int>(
                                  value: item.value,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: item.value == roleId
                                          ? scheme.secondaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (item.child as Text).data ?? 'Role',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (item.value == roleId)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 16,
                                            color: scheme.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            try {
                              await widget.repository.updateUserRole(
                                userId: jsonString(user['id']),
                                roleId: value,
                              );
                              await _reload();
                            } on Exception catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Gagal mengubah role: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _MasterTab extends StatefulWidget {
  const _MasterTab({required this.repository, required this.onDataChanged});
  final ExplorerRepository repository;
  final Future<void> Function() onDataChanged;

  @override
  State<_MasterTab> createState() => _MasterTabState();
}

class _MasterTabState extends State<_MasterTab> {
  late Future<
    ({
      List<Map<String, dynamic>> categories,
      List<Map<String, dynamic>> cities,
      List<Map<String, dynamic>> districts,
    })
  >
  _masterData;

  @override
  void initState() {
    super.initState();
    _masterData = _loadMasterData();
  }

  Future<
    ({
      List<Map<String, dynamic>> categories,
      List<Map<String, dynamic>> cities,
      List<Map<String, dynamic>> districts,
    })
  >
  _loadMasterData() async {
    final categories = await widget.repository.getCategories();
    final districts = await widget.repository.getDistricts();
    final cities = await widget.repository.getCities();

    int byName(Map<String, dynamic> left, Map<String, dynamic> right) {
      return jsonString(left['nama'])
          .toLowerCase()
          .compareTo(jsonString(right['nama']).toLowerCase());
    }

    categories.sort(byName);
    districts.sort(byName);
    cities.sort(byName);
    return (categories: categories, districts: districts, cities: cities);
  }

  Future<void> _reload() async {
    final request = _loadMasterData();
    setState(() => _masterData = request);
    await request;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({
        List<Map<String, dynamic>> categories,
        List<Map<String, dynamic>> cities,
        List<Map<String, dynamic>> districts,
      })
    >(
      future: _masterData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _RoleRefreshState(
            onRefresh: _reload,
            child: Text('Gagal memuat data master: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return _RoleRefreshState(
            onRefresh: _reload,
            child: const CircularProgressIndicator(),
          );
        }
        final data = snapshot.data!;
        final scheme = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                'Data master',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Kelola kategori dan wilayah yang digunakan di aplikasi.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F3E8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.category_outlined,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Kategori',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${data.categories.length} kategori tersedia',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _showCategoryDialog(context),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final category in data.categories)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.label_outline,
                                size: 18,
                                color: scheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  jsonString(category['nama']),
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                jsonString(category['slug']),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF1F8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.location_city_outlined,
                              color: Color(0xFF315B7D),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Kecamatan',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${data.districts.length} kecamatan tersedia',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: data.cities.isEmpty
                                ? null
                                : () =>
                                      _showDistrictDialog(context, data.cities),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final district in data.districts)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      jsonString(district['nama']),
                                      style: TextStyle(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      jsonString(
                                        asJsonMap(
                                          district['kabupaten_kota'],
                                        )?['nama'],
                                        'Kabupaten/kota tidak diketahui',
                                      ),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (data.cities.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Data kabupaten/kota belum tersedia.'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCategoryDialog(BuildContext context) async {
    final name = TextEditingController();
    final slug = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kategori baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            TextField(
              controller: slug,
              decoration: const InputDecoration(labelText: 'Slug'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama kategori wajib diisi.')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.repository.upsertCategory(
          name: name.text.trim(),
          slug: slug.text.trim(),
        );
        await widget.onDataChanged();
        if (mounted) _reload();
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan kategori: $error')),
          );
        }
      }
    }
    name.dispose();
    slug.dispose();
  }

  Future<void> _showDistrictDialog(
    BuildContext context,
    List<Map<String, dynamic>> cities,
  ) async {
    final name = TextEditingController();
    final slug = TextEditingController();
    var cityId = (cities.first['id'] as num).toInt();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Kecamatan baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: cityId,
                decoration: const InputDecoration(labelText: 'Kabupaten/kota'),
                items: cities
                    .map(
                      (city) => DropdownMenuItem(
                        value: (city['id'] as num).toInt(),
                        child: Text(jsonString(city['nama'])),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => cityId = value ?? cityId),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              TextField(
                controller: slug,
                decoration: const InputDecoration(labelText: 'Slug'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nama kecamatan wajib diisi.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.repository.upsertDistrict(
          cityId: cityId,
          name: name.text.trim(),
          slug: slug.text.trim(),
        );
        await widget.onDataChanged();
        if (mounted) _reload();
      } on Exception catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan kecamatan: $error')),
          );
        }
      }
    }
    name.dispose();
    slug.dispose();
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.repository});
  final ExplorerRepository repository;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  late Future<List<Map<String, dynamic>>> _activity;

  @override
  void initState() {
    super.initState();
    _activity = widget.repository.getActivity();
  }

  Future<void> _reload() async {
    final request = widget.repository.getActivity();
    setState(() => _activity = request);
    await request;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _activity,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return snapshot.hasError
              ? _RoleRefreshState(
                  onRefresh: _reload,
                  child: Text('Gagal memuat: ${snapshot.error}'),
                )
              : _RoleRefreshState(
                  onRefresh: _reload,
                  child: const CircularProgressIndicator(),
                );
        }
        final rows = snapshot.data!;
        final scheme = Theme.of(context).colorScheme;
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.65,
                  child: const Center(child: Text('Belum ada aktivitas.')),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Aktivitas terbaru',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${rows.length} aktivitas',
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final row in rows) ...[
                _ActivityCard(row: row),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = asJsonMap(row['users']);
    final activity = jsonString(row['aktivitas'], 'Aktivitas');
    final rawDate = jsonString(row['waktu']);
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : '—';
    return MotionCard(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.16
                    : 0.035,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.history_rounded,
                color: scheme.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    jsonString(user?['nama'], 'Pengguna'),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                date,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
