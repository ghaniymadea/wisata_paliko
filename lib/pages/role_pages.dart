import 'package:material_ui/material_ui.dart';

import '../data/explorer_repository.dart';
import '../data/models.dart';
import 'admin_workflow_pages.dart';

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
    _reload();
  }

  void _reload() {
    _pending = widget.repository.getPendingSpots();
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
      setState(_reload);
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
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Verifikasi Spot'),
              actions: [
                IconButton(
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
      body: FutureBuilder<List<Spot>>(
        future: _pending,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat: ${snapshot.error}'));
          }
          final spots = snapshot.data ?? const <Spot>[];
          if (spots.isEmpty) {
            return const Center(
              child: Text('Tidak ada usulan spot yang menunggu verifikasi.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: spots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final spot = spots[index];
              return Card(
                child: ListTile(
                  title: Text(spot.name),
                  subtitle: Text('${spot.area}\nUsul oleh ${spot.creatorName}'),
                  isThreeLine: true,
                  onTap: () => widget.onOpenSpot(spot),
                  trailing: PopupMenuButton<int>(
                    onSelected: (value) => _verify(spot, value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 2, child: Text('Verifikasi')),
                      PopupMenuItem(value: 3, child: Text('Tolak')),
                    ],
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

  void _reload() => setState(() => _usersAndRoles = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
      ({List<Map<String, dynamic>> roles, List<Map<String, dynamic>> users})
    >(
      future: _usersAndRoles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Gagal memuat: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshot.data!.users;
        final roles = snapshot.data!.roles;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              return ListTile(
                title: Text(jsonString(user['nama'])),
                subtitle: Text('@${jsonString(user['username'])}'),
                trailing: DropdownButton<int>(
                  value: roleItems.any((item) => item.value == roleId)
                      ? roleId
                      : null,
                  hint: const Text('Belum ada role'),
                  items: roleItems,
                  onChanged: (value) async {
                    if (value == null) return;
                    try {
                      await widget.repository.updateUserRole(
                        userId: jsonString(user['id']),
                        roleId: value,
                      );
                      _reload();
                    } on Exception catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gagal mengubah role: $error'),
                          ),
                        );
                      }
                    }
                  },
                ),
              );
            }),
          ],
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

  void _reload() => setState(() => _masterData = _loadMasterData());

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
          return Center(
            child: Text('Gagal memuat data master: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Kategori'),
              subtitle: Text(
                '${data.categories.length} kategori dari Supabase',
              ),
              trailing: IconButton(
                tooltip: 'Tambah kategori',
                onPressed: () => _showCategoryDialog(context),
                icon: const Icon(Icons.add),
              ),
            ),
            for (final category in data.categories)
              ListTile(
                dense: true,
                title: Text(jsonString(category['nama'])),
                subtitle: Text(jsonString(category['slug'])),
              ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.location_city_outlined),
              title: const Text('Kecamatan'),
              subtitle: Text(
                '${data.districts.length} kecamatan dari Supabase',
              ),
              trailing: IconButton(
                tooltip: 'Tambah kecamatan',
                onPressed: data.cities.isEmpty
                    ? null
                    : () => _showDistrictDialog(context, data.cities),
                icon: const Icon(Icons.add),
              ),
            ),
            for (final district in data.districts)
              ListTile(
                dense: true,
                title: Text(jsonString(district['nama'])),
                subtitle: Text(
                  jsonString(
                    asJsonMap(district['kabupaten_kota'])?['nama'],
                    'Kabupaten/kota tidak diketahui',
                  ),
                ),
              ),
            if (data.cities.isEmpty)
              const ListTile(
                title: Text('Data kabupaten/kota belum tersedia.'),
              ),
          ],
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _activity,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return snapshot.hasError
              ? Center(child: Text('Gagal memuat: ${snapshot.error}'))
              : const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('Belum ada aktivitas.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final row = rows[index];
            final user = asJsonMap(row['users']);
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(jsonString(row['aktivitas'])),
              subtitle: Text(jsonString(user?['nama'], 'Pengguna')),
              trailing: Text(jsonString(row['waktu']).substring(0, 10)),
            );
          },
        );
      },
    );
  }
}
