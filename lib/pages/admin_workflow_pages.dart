import 'package:material_ui/material_ui.dart';

import '../data/explorer_repository.dart';
import '../data/models.dart';

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

  void _reload() => setState(() => _stats = widget.repository.getAdminStats());

  @override
  Widget build(BuildContext context) => FutureBuilder<JsonMap>(
    future: _stats,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Gagal memuat statistik: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final stats = snapshot.data!;
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Ringkasan dari Supabase',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(label: 'Pengguna', value: stats['total_pengguna']),
                _StatCard(label: 'Kurator', value: stats['total_kurator']),
                _StatCard(
                  label: 'Spot menunggu',
                  value: stats['spot_menunggu'],
                ),
                _StatCard(
                  label: 'Spot terverifikasi',
                  value: stats['spot_terverifikasi'],
                ),
                _StatCard(label: 'Spot ditolak', value: stats['spot_ditolak']),
                _StatCard(label: 'Laporan baru', value: stats['laporan_baru']),
                _StatCard(
                  label: 'Pengajuan Kurator',
                  value: stats['pengajuan_kurator_menunggu'],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang'),
              ),
            ),
          ],
        ),
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
  const _StatCard({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 185,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            Text(label),
          ],
        ),
      ),
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

  void _reload() => setState(() => _reports = widget.repository.getReports());

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
        _reload();
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
        return Center(child: Text('Gagal memuat laporan: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final reports = snapshot.data!;
      if (reports.isEmpty) {
        return const Center(child: Text('Belum ada laporan.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final report = reports[index];
          return ListTile(
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

  void _reload() {
    setState(() => _applications = widget.repository.getCuratorApplications());
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
        _reload();
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
        return Center(child: Text('Gagal memuat pengajuan: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final applications = snapshot.data!;
      if (applications.isEmpty) {
        return const Center(child: Text('Tidak ada pengajuan Kurator.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: applications.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final application = applications[index];
          final user = asJsonMap(application['users']);
          return ListTile(
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

  void _reload() {
    setState(() => _notifications = widget.repository.getNotifications());
  }

  Future<void> _markAllRead() async {
    try {
      await widget.repository.markAllNotificationsRead();
      _reload();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menandai notifikasi: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifikasi'),
      actions: [
        TextButton(onPressed: _markAllRead, child: const Text('Baca semua')),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _notifications,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat notifikasi: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notifications = snapshot.data!;
        if (notifications.isEmpty) {
          return const Center(child: Text('Belum ada notifikasi.'));
        }
        return ListView.separated(
          itemCount: notifications.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final notification = notifications[index];
            final read = notification['sudah_dibaca'] == true;
            return ListTile(
              leading: Icon(
                read ? Icons.notifications_none : Icons.notifications_active,
              ),
              title: Text(
                jsonString(notification['judul']),
                style: TextStyle(
                  fontWeight: read ? FontWeight.normal : FontWeight.bold,
                ),
              ),
              subtitle: Text(jsonString(notification['isi'])),
            );
          },
        );
      },
    ),
  );
}
