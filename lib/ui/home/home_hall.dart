import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/app_preferences.dart';
import '../../core/models/history_entry.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../recent_files.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../widgets/mobile_promo_banner.dart';
import '../widgets/omnia_button.dart';
import 'hall_artwork.dart';
import 'hall_model.dart';

/// L'accueil d'OMNIA : le hall du cinéma.
///
/// Dans un cinéma, le hall affiche ce qui passe. Ici, les affiches sont les
/// médias ouverts dernièrement : une bande qu'on parcourt à la souris ou au
/// clavier (← →, Entrée), dont l'affiche sélectionnée est éclairée par le
/// projecteur et donne au hall son fond. Au-dessus, le titre de la séance et
/// de quoi la reprendre ; en haut, les rayons et l'heure.
///
/// La référence, demandée explicitement : l'accueil d'une console et les
/// façades d'émulateurs — une page qu'on laisse ouverte parce qu'elle est
/// belle à l'arrêt.
class HomeHall extends ConsumerStatefulWidget {
  const HomeHall({super.key});

  /// Hauteur sous laquelle la bannière mobile et la date se retirent.
  static const double roomyHeight = 560;

  @override
  ConsumerState<HomeHall> createState() => _HomeHallState();
}

class _HomeHallState extends ConsumerState<HomeHall> {
  final ScrollController _ribbon = ScrollController();
  Timer? _clock;
  DateTime _now = DateTime.now();

  /// Largeur des affiches à la dernière mise en page : le défilement vers la
  /// sélection en dépend.
  double _posterWidth = 200;

  @override
  void initState() {
    super.initState();
    _scheduleClock();
  }

  /// L'heure change à la minute pile, pas une minute après l'ouverture.
  void _scheduleClock() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _clock = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleClock();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _ribbon.dispose();
    super.dispose();
  }

  /// Garde l'affiche sélectionnée dans la bande visible : le clavier la fait
  /// avancer au-delà du bord.
  void _revealSelection(int index, double posterWidth) {
    if (!_ribbon.hasClients) return;
    final position = _ribbon.position;
    final itemStart = index * (posterWidth + _HallRibbon.gap);
    final itemEnd = itemStart + posterWidth;
    final viewStart = position.pixels;
    final viewEnd = viewStart + position.viewportDimension;
    double? target;
    if (itemStart < viewStart) {
      target = itemStart - _HallRibbon.gap;
    } else if (itemEnd > viewEnd) {
      target = itemEnd - position.viewportDimension + _HallRibbon.gap;
    }
    if (target == null) return;
    unawaited(
      _ribbon.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: OmniaMotion.panel,
        curve: OmniaMotion.panelCurve,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recents = ref.watch(recentFilesProvider);
    final hall = ref.watch(hallProvider);
    final items = hallItems(recents, hall.category);
    final selected = hallSelection(items, hall);
    final prefs = ref.watch(
      preferencesProvider.select((p) => (background: p.hallBackground, wallpaper: p.hallWallpaper)),
    );
    // Hors plein écran, la barre de titre flotte sur le haut du hall :
    // l'image passe dessous, le texte commence en dessous.
    final fullscreen = ref.watch(playbackStateProvider.select((s) => s.fullscreen));
    final topInset = fullscreen ? 0.0 : OmniaMetrics.titleBarHeight;

    // Écoute posée pendant la construction, comme le veut Riverpod — et non
    // dans la mise en page, où elle ne serait pas permise.
    ref.listen<HallState>(hallProvider, (previous, next) {
      if (previous?.index == next.index) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealSelection(next.index, _posterWidth),
      );
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;
        final height = constraints.hasBoundedHeight ? constraints.maxHeight : 720.0;
        final posterWidth = (width * 0.19).clamp(132.0, 248.0);
        _posterWidth = posterWidth;
        final gutter = width < 560 ? OmniaMetrics.space4 : OmniaMetrics.space6;

        final content = Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, topInset + OmniaMetrics.space4, gutter, 0),
              child: _HallHeader(
                category: hall.category,
                now: _now,
                showDate: height >= HomeHall.roomyHeight && width >= 640,
              ),
            ),
            // La séance et sa bande forment un seul bloc : sur une grande
            // fenêtre il se tient au milieu, entre l'en-tête et le pied ; sur
            // une petite, ses marges gardent l'écart avec les deux.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OmniaMetrics.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: _HallFeature(
                      selected: selected,
                      anyRecent: recents.isNotEmpty,
                      category: hall.category,
                    ),
                  ),
                  const SizedBox(height: OmniaMetrics.space5),
                  _HallRibbon(
                    controller: _ribbon,
                    items: items,
                    selectedIndex: selected == null ? -1 : items.indexOf(selected),
                    posterWidth: posterWidth,
                    gutter: gutter,
                    ghostCount: recents.isEmpty ? 3 : 0,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, OmniaMetrics.space5),
              child: _HallFooter(
                anyRecent: recents.isNotEmpty,
                showPromo: height >= HomeHall.roomyHeight && width >= 900,
              ),
            ),
          ],
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _HallBackdrop(
                background: prefs.background,
                wallpaper: prefs.wallpaper,
                selected: selected,
              ),
            ),
            // Sur une scène courte, le hall défile plutôt que de déborder ;
            // sur une grande, il occupe toute la hauteur.
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- Fond ----------------------------------------------------------------------

/// Le fond du hall : l'affiche sélectionnée, très floutée — la lumière de
/// l'écran qui baigne la salle —, une image choisie, ou le velours seul.
///
/// Les deux voiles qui la recouvrent ne décorent pas : ils gardent le texte
/// lisible, quel que soit le fond.
class _HallBackdrop extends StatelessWidget {
  const _HallBackdrop({
    required this.background,
    required this.wallpaper,
    required this.selected,
  });

  final HallBackground background;
  final String wallpaper;
  final RecentFile? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Widget? image;
    switch (background) {
      case HallBackground.plain:
        image = null;
      case HallBackground.wallpaper:
        image = wallpaper.isEmpty
            ? null
            : Image.file(
                File(wallpaper),
                key: ValueKey('fond:$wallpaper'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              );
      case HallBackground.artwork:
        final recent = selected;
        image = recent == null || !recent.exists
            ? null
            : Opacity(
                key: ValueKey('affiche:${recent.path}'),
                opacity: 0.6,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                  child: Transform.scale(
                    scale: 1.15,
                    child: HallArtwork(path: recent.path, exists: true),
                  ),
                ),
              );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.velvet),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: OmniaMotion.stageCurve,
          switchOutCurve: OmniaMotion.concealCurve,
          child: image ?? const SizedBox.shrink(key: ValueKey('velours')),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                colors.velvet,
                colors.velvet.withValues(alpha: 0.72),
                colors.velvet.withValues(alpha: 0.25),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.velvet.withValues(alpha: 0.7), colors.velvet.withValues(alpha: 0)],
              stops: const [0, 0.65],
            ),
          ),
        ),
        // Sous la barre de titre posée sur l'image : ses boutons restent
        // lisibles même sur une photo claire choisie comme fond.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: 140,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.velvet.withValues(alpha: 0.6), colors.velvet.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- En-tête : rayons et heure --------------------------------------------------

class _HallHeader extends ConsumerWidget {
  const _HallHeader({required this.category, required this.now, required this.showDate});

  final HallCategory category;
  final DateTime now;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final controller = ref.read(hallProvider.notifier);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in HallCategory.values)
                  _CategoryTab(
                    label: c.label,
                    selected: c == category,
                    onTap: () => controller.showCategory(c),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OmniaMetrics.space4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hallClock(now),
              style: type.timecodeLarge.copyWith(color: colors.screen, fontSize: 20),
            ),
            if (showDate)
              Text(hallDate(now), style: type.caption.copyWith(color: colors.dust)),
          ],
        ),
      ],
    );
  }
}

/// « 14:05 ».
String hallClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// « mardi 17 novembre ».
String hallDate(DateTime t) {
  const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  const months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}';
}

/// Un rayon : un mot, souligné par le faisceau quand il est choisi.
class _CategoryTab extends StatefulWidget {
  const _CategoryTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<_CategoryTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final lit = widget.selected || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: OmniaMetrics.space5, top: OmniaMetrics.space1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: type.sectionTitle.copyWith(
                  color: lit ? colors.screen : colors.dust,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: OmniaMetrics.space1),
              AnimatedContainer(
                duration: OmniaMotion.hover,
                curve: OmniaMotion.hoverCurve,
                height: 2,
                width: widget.selected ? 22 : 0,
                decoration: BoxDecoration(
                  color: colors.projector,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(color: colors.projector.withValues(alpha: 0.55), blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- La séance sélectionnée -----------------------------------------------------

/// Le titre du média sélectionné, où l'on en est, et de quoi le reprendre.
class _HallFeature extends ConsumerWidget {
  const _HallFeature({required this.selected, required this.anyRecent, required this.category});

  final RecentFile? selected;
  final bool anyRecent;
  final HallCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final recent = selected;

    if (recent == null) {
      // Rien à l'affiche : la bienvenue, ou un rayon encore vide.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            anyRecent ? 'Rien dans ce rayon' : l10n.emptyStageHint,
            style: type.heroTitle.copyWith(color: colors.screen),
          ),
          const SizedBox(height: OmniaMetrics.space2),
          Text(
            anyRecent
                ? 'Les ${category.label.toLowerCase()} que vous ouvrirez s’afficheront ici.'
                : l10n.emptyStageSubtitle,
            style: type.body.copyWith(color: colors.dust),
          ),
        ],
      );
    }

    final mediaType = MediaRouter.typeForPath(recent.path);
    final progress = hallProgressLabel(recent.entry, mediaType);
    final resumable = recent.entry.resumePosition != null ||
        recent.entry.resumePage != null ||
        recent.entry.resumeScroll != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hallTitleFor(recent.path),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.heroTitle.copyWith(color: colors.screen, height: 1.15),
        ),
        const SizedBox(height: OmniaMetrics.space2),
        Wrap(
          spacing: OmniaMetrics.space3,
          runSpacing: OmniaMetrics.space1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              hallTypeLabel(mediaType),
              style: type.secondary.copyWith(color: colors.projector, fontWeight: FontWeight.w600),
            ),
            if (progress != null)
              Text(
                progress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.timecode.copyWith(color: colors.screen),
              ),
            // Un nom de dossier peut être très long : une ligne, coupée net.
            Text(
              recent.exists ? p.basename(p.dirname(recent.path)) : 'Fichier introuvable',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.secondary.copyWith(color: recent.exists ? colors.dust : colors.alert),
            ),
          ],
        ),
        const SizedBox(height: OmniaMetrics.space4),
        Wrap(
          spacing: OmniaMetrics.space3,
          runSpacing: OmniaMetrics.space2,
          children: [
            OmniaButton(
              label: resumable ? 'Reprendre' : 'Ouvrir',
              icon: Icons.play_arrow_rounded,
              shortcut: 'Entrée',
              primary: true,
              onPressed: recent.exists ? () => openFromHall(ref, recent) : null,
            ),
            OmniaButton(
              label: 'Afficher dans le dossier',
              icon: Icons.folder_open_outlined,
              onPressed:
                  recent.exists ? () => ref.dispatch(RevealInFolder(recent.path)) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Le nom à afficher : sans extension, et sans les points ou soulignés qui
/// tiennent lieu d'espaces dans les noms de fichiers de films.
String hallTitleFor(String path) {
  final name = p.basenameWithoutExtension(path);
  if (name.contains(' ')) return name;
  return name.replaceAll(RegExp(r'[._]+'), ' ').trim();
}

String hallTypeLabel(MediaType type) => switch (type) {
      MediaType.video => 'Vidéo',
      MediaType.audio => 'Musique',
      MediaType.pdf => 'PDF',
      MediaType.text => 'Texte',
      MediaType.doc => 'Document',
      MediaType.image => 'Image',
      MediaType.unknown => 'Fichier',
    };

/// Où l'on en est, dit en clair : « Reprise à 12:05 sur 40:00 », « Page 12
/// sur 140 », « Lu à 40 % », « Terminé ».
String? hallProgressLabel(HistoryEntry entry, MediaType type) {
  if (entry.completed) return 'Terminé';
  if (type.isAv) {
    final resume = entry.resumePosition;
    if (resume == null) {
      return entry.duration > Duration.zero ? _clock(entry.duration) : null;
    }
    return entry.duration > Duration.zero
        ? 'Reprise à ${_clock(resume)} sur ${_clock(entry.duration)}'
        : 'Reprise à ${_clock(resume)}';
  }
  if (entry.page > 0 && entry.pageCount > 0) {
    return 'Page ${entry.page} sur ${entry.pageCount}';
  }
  if (entry.scrollFraction > 0.02) {
    return 'Lu à ${(entry.scrollFraction * 100).round()} %';
  }
  return null;
}

/// Part déjà vue, de 0 à 1 : le faisceau au pied de l'affiche.
double hallProgressFraction(HistoryEntry entry, MediaType type) {
  if (entry.completed) return 1;
  if (type.isAv && entry.duration > Duration.zero) {
    return (entry.position.inMilliseconds / entry.duration.inMilliseconds).clamp(0.0, 1.0);
  }
  if (entry.pageCount > 0 && entry.page > 0) {
    return (entry.page / entry.pageCount).clamp(0.0, 1.0);
  }
  return entry.scrollFraction.clamp(0.0, 1.0);
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// --- La bande d'affiches ----------------------------------------------------------

class _HallRibbon extends ConsumerWidget {
  const _HallRibbon({
    required this.controller,
    required this.items,
    required this.selectedIndex,
    required this.posterWidth,
    required this.gutter,
    required this.ghostCount,
  });

  static const double gap = 18;

  /// Proportions d'une affiche : celles d'un écran large.
  static const double aspect = 16 / 10;

  final ScrollController controller;
  final List<RecentFile> items;
  final int selectedIndex;
  final double posterWidth;
  final double gutter;

  /// Affiches fantômes quand rien n'a encore été ouvert : l'emplacement des
  /// premières séances.
  final int ghostCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterHeight = posterWidth / aspect;
    final count = items.isEmpty ? ghostCount : items.length;
    if (count == 0) return SizedBox(height: posterHeight);
    final controllerRef = ref.read(hallProvider.notifier);

    return SizedBox(
      // Place pour l'affiche agrandie, son halo et son nom.
      height: posterHeight + 56,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter, vertical: OmniaMetrics.space2),
        clipBehavior: Clip.none,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (context, index) {
          if (items.isEmpty) {
            return SizedBox(
              width: posterWidth,
              child: _GhostPoster(height: posterHeight, index: index),
            );
          }
          return SizedBox(
            width: posterWidth,
            child: HallPoster(
              key: ValueKey('affiche:${items[index].path}'),
              recent: items[index],
              selected: index == selectedIndex,
              height: posterHeight,
              onHover: () => controllerRef.select(index),
              onTap: () {
                controllerRef.select(index);
                openFromHall(ref, items[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Une affiche : l'image du média, le faisceau de ce qui en a été vu, et
/// son nom. Sélectionnée, elle grandit et le projecteur l'éclaire.
class HallPoster extends StatefulWidget {
  const HallPoster({
    super.key,
    required this.recent,
    required this.selected,
    required this.height,
    required this.onHover,
    required this.onTap,
  });

  final RecentFile recent;
  final bool selected;
  final double height;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<HallPoster> createState() => _HallPosterState();
}

class _HallPosterState extends State<HallPoster> {
  /// Le survol sélectionne après un court instant : balayer la bande d'un
  /// geste ne fait pas défiler tous les fonds.
  Timer? _hoverDelay;

  @override
  void dispose() {
    _hoverDelay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final recent = widget.recent;
    final mediaType = MediaRouter.typeForPath(recent.path);
    final fraction = hallProgressFraction(recent.entry, mediaType);
    final selected = widget.selected;

    return MouseRegion(
      cursor: recent.exists ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        _hoverDelay?.cancel();
        _hoverDelay = Timer(const Duration(milliseconds: 120), widget.onHover);
      },
      onExit: (_) => _hoverDelay?.cancel(),
      child: GestureDetector(
        onTap: recent.exists ? widget.onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              scale: selected ? 1 : 0.9,
              alignment: Alignment.bottomCenter,
              duration: OmniaMotion.reveal,
              curve: OmniaMotion.revealCurve,
              child: AnimatedContainer(
                duration: OmniaMotion.reveal,
                curve: OmniaMotion.revealCurve,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: OmniaMetrics.overlayRadius,
                  border: Border.all(
                    color: selected ? colors.projector : colors.seam,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: colors.projector.withValues(alpha: 0.38),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusLarge - 1)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: recent.exists ? 1 : 0.35,
                        child: HallArtwork(path: recent.path, exists: recent.exists),
                      ),
                      if (fraction > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _PosterBeam(fraction: fraction),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: OmniaMetrics.space2),
            Text(
              hallTitleFor(recent.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.secondary.copyWith(
                color: selected ? colors.screen : colors.dust,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le faisceau au pied de l'affiche : la part déjà vue, en lumière ambre.
class _PosterBeam extends StatelessWidget {
  const _PosterBeam({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.projector,
                boxShadow: [
                  BoxShadow(color: colors.projector.withValues(alpha: 0.55), blurRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Emplacement d'une affiche à venir, sur un hall encore vide.
class _GhostPoster extends StatelessWidget {
  const _GhostPoster({required this.height, required this.index});

  final double height;
  final int index;

  static const _types = [MediaType.video, MediaType.audio, MediaType.pdf];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: OmniaMetrics.overlayRadius,
        border: Border.all(color: colors.seam),
        color: colors.curtain.withValues(alpha: 0.5),
      ),
      child: Center(
        child: Icon(
          HallBlankPoster.iconFor(_types[index % _types.length]),
          size: height * 0.32,
          color: colors.dust.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// --- Pied : ouvrir, et la version mobile --------------------------------------------

class _HallFooter extends ConsumerWidget {
  const _HallFooter({required this.anyRecent, required this.showPromo});

  final bool anyRecent;
  final bool showPromo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final buttons = Wrap(
      spacing: OmniaMetrics.space3,
      runSpacing: OmniaMetrics.space2,
      children: [
        OmniaButton(
          label: l10n.openFile,
          icon: Icons.insert_drive_file_outlined,
          shortcut: ref.shortcutOf(ShortcutAction.openFile, l10n),
          // Sur un hall vide, c'est le seul geste à faire : il prend la
          // lumière. Sinon, c'est la reprise qui l'a.
          primary: !anyRecent,
          onPressed: () => pickAndOpenFile(ref),
        ),
        OmniaButton(
          label: l10n.openFolder,
          icon: Icons.folder_outlined,
          shortcut: ref.shortcutOf(ShortcutAction.openFolder, l10n),
          onPressed: () => pickAndOpenFolder(ref),
        ),
      ],
    );
    if (!showPromo) return buttons;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: buttons),
        const SizedBox(width: OmniaMetrics.space5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const MobilePromoBanner(),
        ),
      ],
    );
  }
}
