import 'package:material_ui/material_ui.dart';

import '../data/explorer_repository.dart';
import '../data/models.dart';

class _AdminRefreshState extends StatelessWidget {
  const _AdminRefreshState({required this.onRefresh, required this.child});

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

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({required this.repository, super.key});

  final ExplorerRepository repository;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  late Future<JsonMap> _stats;

  @override
  void initState() {
    super.initState();
    _stats = widget.repository.getAdminStats();
  }

  Future<void> _reload() async {
    final request = widget.repository.getAdminStats();
    setState(() => _stats = request);
    await request;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JsonMap>(
    future: _stats,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: Text('Gagal memuat statistik: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: const CircularProgressIndicator(),
        );
      }
      final stats = snapshot.data!;
      final metrics = [
        (
          label: 'Pengguna',
          value: stats['total_pengguna'],
          icon: Icons.people_alt_outlined,
          color: const Color(0xFF1B5E20),
          tint: const Color(0xFFE8F3E8),
        ),
        (
          label: 'Kurator',
          value: stats['total_kurator'],
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF5B4AA5),
          tint: const Color(0xFFF0EDFA),
        ),
        (
          label: 'Spot menunggu',
          value: stats['spot_menunggu'],
          icon: Icons.pending_actions_outlined,
          color: const Color(0xFFB26A12),
          tint: const Color(0xFFFFF3DF),
        ),
        (
          label: 'Spot terverifikasi',
          value: stats['spot_terverifikasi'],
          icon: Icons.place_outlined,
          color: const Color(0xFF287A62),
          tint: const Color(0xFFE6F4EF),
        ),
        (
          label: 'Spot ditolak',
          value: stats['spot_ditolak'],
          icon: Icons.block_outlined,
          color: const Color(0xFFB1443C),
          tint: const Color(0xFFFCEBE9),
        ),
        (
          label: 'Laporan baru',
          value: stats['laporan_baru'],
          icon: Icons.flag_outlined,
          color: const Color(0xFFB1443C),
          tint: const Color(0xFFFCEBE9),
        ),
        (
          label: 'Pengajuan kurator',
          value: stats['pengajuan_kurator_menunggu'],
          icon: Icons.person_add_alt_1_outlined,
          color: const Color(0xFF3568A8),
          tint: const Color(0xFFEAF1FA),
        ),
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 600
              ? 3
              : 2;
          final gap = 12.0;
          final horizontalPadding = 18.0;
          final cardWidth =
              (constraints.maxWidth -
                  horizontalPadding * 2 -
                  gap * (columns - 1)) /
              columns;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(horizontalPadding),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ringkasan Admin',
                            style: TextStyle(
                              color: Color(0xFF243042),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Pantau kondisi komunitas dan konten.',
                            style: TextStyle(
                              color: Color(0xFF718096),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Muat ulang statistik',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: cardWidth,
                        child: _StatCard(
                          label: metric.label,
                          value: metric.value,
                          icon: metric.icon,
                          color: metric.color,
                          tint: metric.tint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Tarik layar ke bawah untuk memperbarui data',
                    style: const TextStyle(
                      color: Color(0xFF8A948C),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class CuratorApplicationCard extends StatefulWidget {
  const CuratorApplicationCard({required this.repository, super.key});

  final ExplorerRepository repository;

  @override
  State<CuratorApplicationCard> createState() => _CuratorApplicationCardState();
}

class _CuratorApplicationCardState extends State<CuratorApplicationCard> {
  late Future<Map<String, dynamic>?> _application;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _application = widget.repository.getMyCuratorApplication();
  }

  void _reload() {
    setState(() => _application = widget.repository.getMyCuratorApplication());
  }

  Future<void> _apply() async {
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajukan sebagai Kurator'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: reason,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Alasan pengajuan',
              hintText: 'Ceritakan pengalaman dan kontribusi yang direncanakan',
            ),
            validator: (value) => (value?.trim().length ?? 0) < 10
                ? 'Alasan minimal 10 karakter'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (submit == true) {
      setState(() => _sending = true);
      try {
        await widget.repository.submitCuratorApplication(reason.text.trim());
        _reload();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengajuan Kurator terkirim.')),
          );
        }
      } on Exception catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pengajuan gagal dikirim: $error')),
          );
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _application,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          child: ListTile(
            title: const Text('Pengajuan Kurator'),
            subtitle: Text('Gagal memuat status: ${snapshot.error}'),
          ),
        );
      }
      if (!snapshot.hasData &&
          snapshot.connectionState != ConnectionState.done) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        );
      }
      final application = snapshot.data;
      final status = jsonString(application?['status']);
      final title = switch (status) {
        'menunggu' => 'Pengajuan sedang ditinjau',
        'disetujui' => 'Pengajuan disetujui',
        'ditolak' => 'Pengajuan ditolak',
        _ => 'Ingin menjadi Kurator?',
      };
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (jsonString(application?['catatan_admin']).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Catatan Admin: ${application!['catatan_admin']}'),
              ],
              if (status != 'menunggu' && status != 'disetujui') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: _sending ? null : _apply,
                    child: Text(_sending ? 'Mengirim...' : 'Ajukan Kurator'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.tint,
  });

  final String label;
  final Object? value;
  final IconData icon;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 132),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE8EDE6)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x080F2414),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(height: 10),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 24,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF66736A),
            fontSize: 11,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRefresh,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3EC),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: const Color(0xFF1B5E20), size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF243042),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF718096),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (onRefresh != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Muat ulang'),
              ),
            ],
          ],
        ),
      ),
    );
    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: content,
          ),
        ],
      ),
    );
  }
}

class _AdminListHeader extends StatelessWidget {
  const _AdminListHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final int count;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF243042),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF718096), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onRefresh != null)
          IconButton.filledTonal(
            tooltip: 'Muat ulang',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        if (onRefresh != null) const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3E8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF1B5E20),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({required this.repository, super.key});

  final ExplorerRepository repository;

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  late Future<List<Map<String, dynamic>>> _reports;

  @override
  void initState() {
    super.initState();
    _reports = widget.repository.getReports();
  }

  Future<void> _reload() async {
    final request = widget.repository.getReports();
    setState(() => _reports = request);
    await request;
  }

  Future<void> _updateReport(Map<String, dynamic> report, String status) async {
    final note = TextEditingController(
      text: jsonString(report['catatan_admin']),
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tindak lanjuti laporan'),
        content: TextField(
          controller: note,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Catatan Admin'),
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
    if (save == true) {
      try {
        await widget.repository.updateReport(
          reportId: jsonString(report['id']),
          status: status,
          adminNote: note.text.trim(),
        );
        await _reload();
      } on Exception catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memperbarui laporan: $error')),
          );
        }
      }
    }
    note.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _reports,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: Text('Gagal memuat laporan: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: const CircularProgressIndicator(),
        );
      }
      final reports = snapshot.data!;
      if (reports.isEmpty) {
        return _AdminEmptyState(
          icon: Icons.flag_outlined,
          title: 'Belum ada laporan',
          message: 'Laporan dari pengguna akan muncul di halaman ini.',
          onRefresh: _reload,
        );
      }
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: reports.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _AdminListHeader(
                title: 'Laporan masuk',
                subtitle: 'Tinjau laporan dan perbarui statusnya.',
                count: reports.length,
                onRefresh: _reload,
              );
            }
            final report = reports[index - 1];
            return ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE8EDE6)),
              ),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBE9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.flag_outlined,
                  color: Color(0xFFB1443C),
                  size: 20,
                ),
              ),
              titleTextStyle: const TextStyle(
                color: Color(0xFF243042),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              subtitleTextStyle: const TextStyle(
                color: Color(0xFF718096),
                fontSize: 12,
                height: 1.45,
              ),
              title: Text(
                '${jsonString(report['jenis_target'])} • ${jsonString(report['status'])}',
              ),
              subtitle: Text(
                '${jsonString(report['alasan'])}\nID: ${jsonString(report['id_target'])}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (status) => _updateReport(report, status),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'diproses',
                    child: Text('Tandai diproses'),
                  ),
                  PopupMenuItem(value: 'selesai', child: Text('Selesaikan')),
                  PopupMenuItem(value: 'ditolak', child: Text('Tolak laporan')),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class CuratorApplicationsPage extends StatefulWidget {
  const CuratorApplicationsPage({required this.repository, super.key});

  final ExplorerRepository repository;

  @override
  State<CuratorApplicationsPage> createState() =>
      _CuratorApplicationsPageState();
}

class _CuratorApplicationsPageState extends State<CuratorApplicationsPage> {
  late Future<List<Map<String, dynamic>>> _applications;

  @override
  void initState() {
    super.initState();
    _applications = widget.repository.getCuratorApplications();
  }

  Future<void> _reload() async {
    final request = widget.repository.getCuratorApplications();
    setState(() => _applications = request);
    await request;
  }

  Future<void> _review(Map<String, dynamic> application, bool approve) async {
    final note = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Setujui pengajuan' : 'Tolak pengajuan'),
        content: TextField(
          controller: note,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Catatan untuk pengguna (opsional)',
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
    if (save == true) {
      try {
        await widget.repository.reviewCuratorApplication(
          applicationId: jsonString(application['id']),
          approve: approve,
          note: note.text.trim(),
        );
        await _reload();
      } on Exception catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memproses pengajuan: $error')),
          );
        }
      }
    }
    note.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _applications,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: Text('Gagal memuat pengajuan: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return _AdminRefreshState(
          onRefresh: _reload,
          child: const CircularProgressIndicator(),
        );
      }
      final applications = snapshot.data!;
      if (applications.isEmpty) {
        return _AdminEmptyState(
          icon: Icons.person_add_alt_1_outlined,
          title: 'Belum ada pengajuan',
          message: 'Pengajuan menjadi kurator akan muncul di halaman ini.',
          onRefresh: _reload,
        );
      }
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: applications.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _AdminListHeader(
                title: 'Pengajuan kurator',
                subtitle: 'Tinjau pengajuan akses kurator.',
                count: applications.length,
                onRefresh: _reload,
              );
            }
            final application = applications[index - 1];
            final user = asJsonMap(application['users']);
            return ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE8EDE6)),
              ),
              leading: CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFEAF1FA),
                child: Text(
                  jsonString(user?['nama'], 'P').trim().isEmpty
                      ? 'P'
                      : jsonString(
                          user?['nama'],
                          'P',
                        ).trim().substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF3568A8),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              titleTextStyle: const TextStyle(
                color: Color(0xFF243042),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              subtitleTextStyle: const TextStyle(
                color: Color(0xFF718096),
                fontSize: 12,
                height: 1.45,
              ),
              title: Text(jsonString(user?['nama'], 'Pengguna')),
              subtitle: Text(
                '@${jsonString(user?['username'])}\n${jsonString(application['alasan'])}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<bool>(
                onSelected: (approve) => _review(application, approve),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: true,
                    child: Text('Setujui sebagai Kurator'),
                  ),
                  PopupMenuItem(value: false, child: Text('Tolak')),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.repository, super.key});

  final ExplorerRepository repository;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<Map<String, dynamic>>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = widget.repository.getNotifications();
  }

  Future<void> _reload() async {
    final request = widget.repository.getNotifications();
    setState(() => _notifications = request);
    await request;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifikasi'),
      actions: [
        IconButton(
          tooltip: 'Muat ulang notifikasi',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _notifications,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AdminRefreshState(
            onRefresh: _reload,
            child: Text('Gagal memuat notifikasi: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return _AdminRefreshState(
            onRefresh: _reload,
            child: const CircularProgressIndicator(),
          );
        }
        final notifications = snapshot.data!;
        if (notifications.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.68,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3EC),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            color: Color(0xFF1B5E20),
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Belum ada notifikasi',
                          style: TextStyle(
                            color: Color(0xFF243042),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Informasi penting tentang aktivitasmu akan muncul di sini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF718096),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final unreadCount = notifications
            .where((notification) => notification['sudah_dibaca'] != true)
            .length;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Aktivitas terbaru',
                        style: TextStyle(
                          color: Color(0xFF243042),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3E8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$unreadCount belum dibaca',
                          style: const TextStyle(
                            color: Color(0xFF1B5E20),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final notification in notifications) ...[
                _NotificationCard(notification: notification),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final Map<String, dynamic> notification;

  @override
  Widget build(BuildContext context) {
    final read = notification['sudah_dibaca'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: read ? Colors.white : const Color(0xFFF3F8F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: read ? const Color(0xFFE8EDE6) : const Color(0xFFD9E9D7),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F2414),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: read ? const Color(0xFFF0F3ED) : const Color(0xFFE1F0E1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              read
                  ? Icons.notifications_none_rounded
                  : Icons.notifications_active_rounded,
              color: const Color(0xFF1B5E20),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jsonString(notification['judul'], 'Notifikasi'),
                  style: TextStyle(
                    color: const Color(0xFF243042),
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  jsonString(notification['isi']),
                  style: const TextStyle(
                    color: Color(0xFF66736A),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (!read) ...[
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
