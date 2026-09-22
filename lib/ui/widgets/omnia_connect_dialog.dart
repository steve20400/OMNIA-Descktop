import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';
import 'omnia_button.dart';
import 'omnia_qr_code.dart';

/// Boîte de dialogue OMNIA Connect sur Desktop : Appairage & Projection Zero-Internet.
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
  String? _pairingData;
  bool _isLoading = true;
  StreamSubscription<PlayerCommand>? _cmdSubscription;

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

  @override
  void dispose() {
    _cmdSubscription?.cancel();
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
              const SizedBox(height: 20),

              // Contenu principal
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
                    size: 220,
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
                            connected
                                ? Icons.check_circle_rounded
                                : Icons.sensors_rounded,
                            color: connected ? Colors.green : colors.dust,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            connected
                                ? 'Périphérique Mobile Appairé et Synchronisé'
                                : 'Scannez ce QR Code avec l\'application OMNIA Mobile',
                            style: type.secondary.copyWith(
                              color: connected ? Colors.green : colors.dust,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Information de sécurité / Zero Internet
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: colors.dust, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Chiffrement de session local point-à-point • 100% Hors-ligne',
                      style: type.secondary.copyWith(
                        color: colors.dust,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
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
}
