import 'package:flutter/material.dart';

import 'beam_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final BeamController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NovaBeam'),
        centerTitle: true,
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final busy = c.status == BeamStatus.beaming ||
              c.status == BeamStatus.connecting ||
              c.status == BeamStatus.transferring;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(controller: c),
                const SizedBox(height: 12),
                if (c.file != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(c.file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${c.file!.size} bytes'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: busy ? null : c.clearFile,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : c.pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(c.file == null ? 'Pick a file to beam' : 'Change file'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: c.toggleBeaming,
                  icon: Icon(busy ? Icons.stop_circle : Icons.nfc),
                  label: Text(busy ? 'Stop beaming' : 'Start beaming — tap phones together'),
                ),
                const SizedBox(height: 16),
                if (c.status == BeamStatus.transferring) ...[
                  LinearProgressIndicator(value: c.progress),
                  const SizedBox(height: 4),
                  Text(
                    '${(c.progress * 100).toStringAsFixed(0)}%  ·  ${c.transferred} / ${c.total} bytes',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                if (c.status == BeamStatus.done)
                  Text(
                    c.receivedPath != null
                        ? 'Received: ${c.receivedPath}'
                        : 'Sent to ${c.peerName ?? 'peer'}',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    textAlign: TextAlign.center,
                  ),
                if (c.errorMessage != null)
                  Text(
                    c.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: Card(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: c.logLines.length,
                      itemBuilder: (context, i) => Text(
                        c.logLines[c.logLines.length - 1 - i],
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final BeamController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (label, icon) = switch (c.status) {
      BeamStatus.idle => ('Idle', Icons.radio_button_unchecked),
      BeamStatus.beaming => ('Beaming…', Icons.nfc),
      BeamStatus.connecting => ('Connecting…', Icons.sync),
      BeamStatus.transferring => ('Transferring…', Icons.swap_vert),
      BeamStatus.done => ('Done', Icons.check_circle),
      BeamStatus.error => ('Error', Icons.error),
    };
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          c.role == BeamRole.sender
              ? 'Role: sender'
              : c.role == BeamRole.receiver
                  ? 'Role: receiver'
                  : 'NFC ${c.nfcAvailable ? 'ready' : 'unavailable'} · endpoint ${c.endpoint}',
        ),
      ),
    );
  }
}
