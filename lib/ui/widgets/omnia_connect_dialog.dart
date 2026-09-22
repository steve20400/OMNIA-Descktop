import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_icon_button.dart';
import 'omnia_qr_code.dart';

enum _ConnectTab { share, remote }

/// Boîte de dialogue OMNIA Connect sur Desktop : Appairage, Télécommande & Projection Zero-Internet.
class OmniaConnectDialog extends ConsumerStatefulWidget {
  const OmniaConnectDialog({super.key, this.initialPairingData});

  final String? initialPairingData;

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => const OmniaConnectDialog(),
    );
  }

  @override
  ConsumerState<OmniaConnectDialog> createState() => _OmniaConnectDialogState();
}

class _OmniaConnectDialogState extends ConsumerState<OmniaConnectDialog> {
  _ConnectTab _activeTab = _ConnectTab.share;
  String? _pairingData;
  bool _isLoading = true;
  StreamSubscription<PlayerCommand>? _cmdSubscription;

  final TextEditingController _ipController = TextEditingController();
  bool _isConnectingClient = false;
  String? _clientError;

  @override
  void initState() {
    super.initState();
    if (widget.initialPairingData != null) {
      _pairingData = widget.initialPairingData;
      _isLoading = false;
    } else {
      _initConnect();
    }
  }

  Future<void> _initConnect() async {
    final connectService = ref.read(omniaConnectServiceProvider);
    await connectService.start();

    // Abonnement aux commandes distantes arrivant du mobile
    _cmdSubscription = connectService.remoteCommands.listen((cmd) {
      ref.read(commandBusProvider).dispatch(cmd, source: CommandSource.remote);
    });

    final payload = await connectService.getPairingPayload('OMNIA Desktop');
    if (mounted) {
      setState(() {
        _pairingData = payload;
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToRemote() async {
    final raw = _ipController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isConnectingClient = true;
      _clientError = null;
    });

    final service = ref.read(omniaConnectServiceProvider);
    String host = raw;
    int port = 41530;
    String token = '';

    try {
      if (raw.startsWith('{')) {
        final map = jsonDecode(raw) as Map<String, Object?>;
        host = map['host'] as String? ?? '127.0.0.1';
        port = (map['port'] as num?)?.toInt() ?? 41530;
        token = map['token'] as String? ?? '';
      } else if (raw.contains(':')) {
        final parts = raw.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? 41530;
      }
    } catch (_) {}

    final success = await service.client.connect(
      host: host,
      port: port,
      token: token,
      name: 'OMNIA Desktop Client',
    );

    if (mounted) {
      setState(() {
        _isConnectingClient = false;
        if (!success) {
          _clientError = 'Impossible de joindre l\'appareil distant.';
        }
      });
    }
  }

  @override
  void dispose() {
    _cmdSubscription?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final connectService = ref.watch(omniaConnectServiceProvider);
    final playbackState = ref.watch(playbackStateProvider);

    // Synchronisation d'état continue vers le mobile connecté
    if (connectService.hasConnectedClients) {
      connectService.broadcastState(playbackState);
    }

    return Dialog(
      backgroundColor: colors.curtain,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.seam, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // En-tête
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.velvet.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.wifi_tethering_rounded,
                      color: colors.projector,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OMNIA Connect',
                          style: type.bodyStrong.copyWith(
                            color: colors.screen,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Synchronisation locale sans Internet (PC ↔ Mobile)',
                          style: type.secondary.copyWith(
                            color: colors.dust,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.dust),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Sélecteur d'onglets (Partager / Télécommande)
              Container(
                decoration: BoxDecoration(
                  color: colors.velvet,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.seam),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _activeTab = _ConnectTab.share),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.share
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Partager (QR Code)',
                              style: TextStyle(
                                fontFamily: OmniaFonts.ui,
                                fontSize: 13,
                                fontWeight: _activeTab == _ConnectTab.share
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _activeTab == _ConnectTab.share
                                    ? colors.projector
                                    : colors.dust,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _activeTab = _ConnectTab.remote),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeTab == _ConnectTab.remote
                                ? colors.projector.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Télécommande / Connexion',
                              style: TextStyle(
                                fontFamily: OmniaFonts.ui,
                                fontSize: 13,
                                fontWeight: _activeTab == _ConnectTab.remote
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _activeTab == _ConnectTab.remote
                                    ? colors.projector
                                    : colors.dust,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_activeTab == _ConnectTab.share) ...[
                // Contenu principal de partage
                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: colors.projector),
                  )
                else if (_pairingData != null) ...[
                  // Zone QR Code
                  Center(
                    child: OmniaQrCode(
                      data: _pairingData!,
                      size: 210,
                      color: colors.screen,
                      backgroundColor: colors.velvet,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Statut de connexion
                  StreamBuilder<bool>(
                    stream: connectService.isConnectedStream,
                    initialData: connectService.hasConnectedClients,
                    builder: (context, snapshot) {
                      final connected = snapshot.data ?? false;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: connected
                              ? Colors.green.withValues(alpha: 0.15)
                              : colors.seam.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: connected ? Colors.green : colors.seam,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              connected ? Icons.check_circle_rounded : Icons.sensors_rounded,
                              color: connected ? Colors.green : colors.dust,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                connected
                                    ? 'Périphérique Mobile Appairé et Synchronisé'
                                    : 'Scannez ce QR Code avec l\'application OMNIA Mobile',
                                style: type.secondary.copyWith(
                                  color: connected ? Colors.green : colors.dust,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Information de sécurité / Zero Internet
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, color: colors.dust, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Chiffrement de session local point-à-point • 100% Hors-ligne',
                          style: type.secondary.copyWith(
                            color: colors.dust,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                // Mode Télécommande / Rejoindre
                _buildRemoteTab(colors, connectService, type),
              ],

              const SizedBox(height: 20),

              // Bouton Fermer
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OmniaButton(
                    label: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteTab(OmniaColors colors, OmniaConnectService service, OmniaTypography type) {
    if (!service.client.connected) {
      return Column(
        children: [
          Text(
            'Entrez l\'adresse IP locale du mobile (ex. 192.168.1.X) ou collez le code de couplage '
            'pour piloter l\'application distante ou recevoir son flux.',
            style: TextStyle(
              fontFamily: OmniaFonts.ui,
              fontSize: 13,
              color: colors.dust,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ipController,
            style: TextStyle(color: colors.screen, fontFamily: OmniaFonts.mono, fontSize: 14),
            decoration: InputDecoration(
              hintText: '192.168.1.X:41530',
              hintStyle: TextStyle(color: colors.dust.withValues(alpha: 0.5)),
              filled: true,
              fillColor: colors.velvet,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.seam),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          if (_clientError != null) ...[
            const SizedBox(height: 8),
            Text(_clientError!, style: TextStyle(color: colors.alert, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          OmniaButton(
            label: _isConnectingClient ? 'Connexion en cours...' : 'Se connecter au mobile',
            icon: Icons.link_rounded,
            primary: true,
            onPressed: _isConnectingClient ? null : _connectToRemote,
          ),
        ],
      );
    }

    // Connecté à l'hôte distant
    return StreamBuilder<PlaybackState>(
      stream: service.client.remoteState,
      builder: (context, snapshot) {
        final remote = snapshot.data;
        final title = remote?.file?.name ?? 'Lecture sur l\'appareil distant';
        final isPlaying = remote?.status == PlaybackStatus.playing;

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Connecté au mobile',
                  style: TextStyle(
                    fontFamily: OmniaFonts.ui,
                    fontWeight: FontWeight.bold,
                    color: colors.screen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: OmniaFonts.ui,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.projector,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OmniaIconButton(
                  icon: Icons.replay_10_rounded,
                  tooltip: 'Recul 10s',
                  onPressed: () => service.client.sendCommand(const SeekRelative(-10)),
                ),
                OmniaIconButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Précédent',
                  onPressed: () => service.client.sendCommand(const PreviousFile()),
                ),
                OmniaIconButton(
                  icon: isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                  size: 52,
                  iconSize: 42,
                  active: true,
                  onPressed: () => service.client.sendCommand(const TogglePlay()),
                ),
                OmniaIconButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Suivant',
                  onPressed: () => service.client.sendCommand(const NextFile()),
                ),
                OmniaIconButton(
                  icon: Icons.forward_10_rounded,
                  tooltip: 'Avance 10s',
                  onPressed: () => service.client.sendCommand(const SeekRelative(10)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OmniaIconButton(
                  icon: Icons.volume_down_rounded,
                  tooltip: 'Volume -',
                  onPressed: () => service.client.sendCommand(const VolumeRelative(-5)),
                ),
                const SizedBox(width: 24),
                OmniaIconButton(
                  icon: Icons.volume_up_rounded,
                  tooltip: 'Volume +',
                  onPressed: () => service.client.sendCommand(const VolumeRelative(5)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OmniaButton(
              label: 'Déconnecter',
              onPressed: () async {
                await service.client.disconnect();
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }
}
