// example/lib/offline_face_page.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:face_verification/face_verification.dart';

class OfflineFacePage extends StatefulWidget {
  const OfflineFacePage({super.key});

  @override
  State<OfflineFacePage> createState() => _OfflineFacePageState();
}

class _OfflineFacePageState extends State<OfflineFacePage> {
  bool ready = false;
  String? statusMessage;
  List<dynamic> _users = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      setState(() => statusMessage = 'Loading model...');
      await FaceVerification.instance.init();
      final users = await FaceVerification.instance.listRegisteredAsync();
      setState(() {
        ready = true;
        _users = users;
        statusMessage = 'Model loaded successfully';
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => statusMessage = null);
    } catch (e) {
      setState(() {
        ready = false;
        statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _register() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      setState(() => statusMessage = 'Registering...');
      final id = await FaceVerification.instance.registerFromImagePath(imagePath: picked.path, displayName: 'User ${DateTime.now().millisecondsSinceEpoch}');
      if (!mounted) return;
      final users = await FaceVerification.instance.listRegisteredAsync();
      setState(() {
        statusMessage = null;
        _users = users;
      });
      _show('Success', 'Registered with id: $id');
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = null);
      _show('Error', 'Registration failed: $e');
    }
  }

  Future<void> _verify() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      setState(() => statusMessage = 'Verifying...');
      final match = await FaceVerification.instance.verifyFromImagePath(imagePath: picked.path);
      if (!mounted) return;
      setState(() => statusMessage = null);
      if (match != null) {
        _show('MATCH', 'Matched: ${match.name}');
      } else {
        _show('NO MATCH', 'No user matched.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => statusMessage = null);
      _show('Error', 'Verification failed: $e');
    }
  }

  void _show(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Face Recognition')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ready ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ready ? Colors.green.shade200 : Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(ready ? Icons.check_circle : Icons.hourglass_empty, color: ready ? Colors.green : Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        ready ? 'Model Ready' : 'Loading Model...',
                        style: TextStyle(fontWeight: FontWeight.bold, color: ready ? Colors.green.shade700 : Colors.orange.shade700),
                      ),
                    ],
                  ),
                  if (statusMessage != null) ...[const SizedBox(height: 8), Text(statusMessage!)],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(onPressed: ready ? _register : null, icon: const Icon(Icons.person_add), label: const Text('Register Face')),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(onPressed: ready && _users.isNotEmpty ? _verify : null, icon: const Icon(Icons.face_6), label: const Text('Verify')),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                Text('Registered Users (${users.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: users.isEmpty
                  ? const Center(child: Text('No registered users'))
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(u.name),
                            subtitle: Text('ID: ${u.id}  |  Emb: ${u.embedding.length}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                await FaceVerification.instance.deleteRecord(u.id);
                                final refreshed = await FaceVerification.instance.listRegisteredAsync();
                                if (!mounted) return;
                                setState(() {
                                  _users = refreshed;
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
