import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/controllers/image_controller.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/models/document_layout.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';

class _CapturingSink implements PlaybackStateSink {
  @override
  PlaybackState state = const PlaybackState();

  @override
  void update(PlaybackState Function(PlaybackState current) edit) {
    state = edit(state);
  }
}


void main() {
  group('ImageController', () {
    late ImageController controller;
    late _CapturingSink sink;

    setUp(() {
      controller = ImageController();
      sink = _CapturingSink();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('gère MediaType.image', () {
      expect(controller.supportedTypes, contains(MediaType.image));
    });

    test('open initialise l’état avec succès', () async {
      final file = const MediaFile(path: '/photos/vacances.jpg', type: MediaType.image);
      await controller.open(file, sink);

      expect(sink.state.status, PlaybackStatus.ready);
      expect(sink.state.mediaType, MediaType.image);
      expect(sink.state.file, file);
      expect(sink.state.zoom, 1.0);
      expect(sink.state.rotation, 0);
    });


    test('ZoomRelative et SetZoom modifient le niveau de zoom dans les bornes', () async {
      final file = const MediaFile(path: '/photos/vacances.jpg', type: MediaType.image);
      await controller.open(file, sink);

      await controller.handle(const ZoomRelative(1.5));
      expect(sink.state.zoom, closeTo(1.5, 0.01));

      await controller.handle(const SetZoom(3.0));
      expect(sink.state.zoom, closeTo(3.0, 0.01));

      // Test des bornes (max 10.0, min 0.1)
      await controller.handle(const SetZoom(25.0));
      expect(sink.state.zoom, closeTo(10.0, 0.01));

      await controller.handle(const SetZoom(0.01));
      expect(sink.state.zoom, closeTo(0.1, 0.01));
    });

    test('RotateDocument pivote l’image par quart de tour modulo 4', () async {
      final file = const MediaFile(path: '/photos/vacances.jpg', type: MediaType.image);
      await controller.open(file, sink);

      await controller.handle(const RotateDocument(1));
      expect(sink.state.rotation, 1);

      await controller.handle(const RotateDocument(3));
      expect(sink.state.rotation, 0); // (1 + 3) % 4 == 0
    });


    test('FitZoom réinitialise le zoom à 1.0', () async {
      final file = const MediaFile(path: '/photos/vacances.jpg', type: MediaType.image);
      await controller.open(file, sink);

      await controller.handle(const SetZoom(2.5));
      expect(sink.state.zoom, 2.5);

      await controller.handle(const FitZoom(FitMode.width));
      expect(sink.state.zoom, 1.0);
    });
  });
}
