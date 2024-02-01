import 'dart:async';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ski_master/game/actors/player.dart';
import 'package:ski_master/game/actors/snowman.dart';
import 'package:ski_master/game/hud.dart';
import 'package:ski_master/game/input.dart';
import 'package:ski_master/game/ski_master_game.dart';

class GamePlay extends Component with HasGameReference<SkiMasterGame> {
  GamePlay(
    this.currentLevel, {
    super.key,
    required this.onPausePressed,
    required this.onLevelCompleted,
    required this.onGameOver,
  });

  static const id = 'GamePlay';

  static const _timeScaleRate = 1;
  static const _bgmFadeRate = 1;
  static const _bgmMinVolume = 0;
  static const _bgmMaxVolume = 0.6;

  final int currentLevel;
  final VoidCallback onPausePressed;
  final ValueChanged<int> onLevelCompleted;
  final VoidCallback onGameOver;

  late final input = Input(keyCallbacks: {
    LogicalKeyboardKey.keyP: onPausePressed,
    LogicalKeyboardKey.keyC: () => onLevelCompleted.call(3),
    LogicalKeyboardKey.keyO: onGameOver,
  });

  late final _resetTimer = Timer(
    1,
    autoStart: false,
    onTick: _resetPlayer,
  );
  late final _cameraShake = MoveEffect.by(
    Vector2(0, 3),
    InfiniteEffectController(ZigzagEffectController(period: 0.2)),
  );
  late final World _world;
  late final CameraComponent _camera;
  late final Player _player;
  late final Vector2 _lastSafePosition;
  late final RectangleComponent _fader;
  late final Hud _hud;
  late final SpriteSheet _spriteSheet;
  int _nSnowmanCollected = 0;
  int _nLives = 3;
  late int _start1;
  late int _start2;
  late int _start3;
  int _nTrailTriggers = 0;
  bool get _isOffTrail => _nTrailTriggers == 0;
  bool _levelCompleted = false;
  bool _gameOver = false;
  AudioPlayer? _bgmPlayer;

  @override
  Future<void> onLoad() async {
    if (game.musicValueNotifier.value) {
      _bgmPlayer = await FlameAudio.loopLongAudio(
        SkiMasterGame.bgmTrack,
        volume: 0,
      );
    }
    final map = await TiledComponent.load(
      'Level$currentLevel.tmx',
      Vector2.all(16),
    );
    final tiles = game.images.fromCache('../images/tilemap_packed.png');
    _spriteSheet = SpriteSheet(image: tiles, srcSize: Vector2.all(16));
    _start1 = map.tileMap.map.properties.getValue<int>('Star1')!;
    _start2 = map.tileMap.map.properties.getValue<int>('Star2')!;
    _start3 = map.tileMap.map.properties.getValue<int>('Star3')!;
    await _setupWorldAndCamera(map);
    await _handleSpawnPoints(map);
    await _handleTriggers(map);
    _fader = RectangleComponent(
      size: _camera.viewport.virtualSize,
      paint: Paint()..color = game.backgroundColor(),
      children: [
        OpacityEffect.fadeOut(LinearEffectController(1.5)),
      ],
      priority: 1,
    );
    _hud = Hud(
      playerSprite: _spriteSheet.getSprite(5, 10),
      snowmanSprite: _spriteSheet.getSprite(5, 9),
    );
    await _camera.viewport.addAll([_fader, _hud]);
    await _camera.viewfinder.add(_cameraShake);
    _cameraShake.pause();
  }

  @override
  void update(double dt) {
    if (_levelCompleted || _gameOver) {
      _player.timeScale = lerpDouble(
        _player.timeScale,
        0,
        _timeScaleRate * dt,
      )!;
    } else {
      if (_isOffTrail && input.active) {
        _resetTimer.update(dt);

        if (!_resetTimer.isRunning()) {
          _resetTimer.start();
        }

        if (_cameraShake.isPaused) {
          _cameraShake.resume();
        }
      } else {
        if (_resetTimer.isRunning()) {
          _resetTimer.stop();
        }

        if (!_cameraShake.isPaused) {
          _cameraShake.pause();
        }
      }
    }
    if (_bgmPlayer != null) {
      if (_levelCompleted) {
        if (_bgmPlayer!.volume > _bgmMinVolume) {
          _bgmPlayer!.setVolume(
            lerpDouble(_bgmPlayer!.volume, _bgmMinVolume, _bgmFadeRate * dt)!,
          );
        }
      } else {
        if (_bgmPlayer!.volume < _bgmMaxVolume) {
          _bgmPlayer!.setVolume(
            lerpDouble(_bgmPlayer!.volume, _bgmMaxVolume, _bgmFadeRate * dt)!,
          );
        }
      }
    }
  }

  @override
  Future<void> onRemove() async {
    await _bgmPlayer?.dispose();
  }

  Future<void> _setupWorldAndCamera(
      TiledComponent<FlameGame<World>> map) async {
    _world = World(children: [map, input]);
    await add(_world);
    _camera = CameraComponent.withFixedResolution(
      width: 320,
      height: 180,
      world: _world,
    );
    await add(_camera);
  }

  Future<void> _handleSpawnPoints(TiledComponent<FlameGame<World>> map) async {
    final spawnPointLayer = map.tileMap.getLayer<ObjectGroup>('SpawnPoint');
    final objects = spawnPointLayer?.objects;
    if (objects != null) {
      for (final object in objects) {
        switch (object.class_) {
          case 'Player':
            _player = Player(
              position: Vector2(object.x, object.y),
              sprite: _spriteSheet.getSprite(5, 10),
              priority: 1,
            );
            await _world.add(_player);
            _camera.follow(_player);
            _lastSafePosition = Vector2(object.x, object.y);
            break;
          case 'Snowman':
            final snowman = Snowman(
              position: Vector2(object.x, object.y),
              sprite: _spriteSheet.getSprite(5, 9),
              onCollected: _onSnowmanCollected,
            );
            await _world.add(snowman);
            break;
          default:
            break;
        }
      }
    }
  }

  Future<void> _handleTriggers(TiledComponent<FlameGame<World>> map) async {
    final triggerLayer = map.tileMap.getLayer<ObjectGroup>('Trigger');
    final objects = triggerLayer?.objects;
    if (objects != null) {
      for (final object in objects) {
        switch (object.class_) {
          case 'Trail':
            final vertices = <Vector2>[];
            for (final point in object.polygon) {
              vertices.add(Vector2(point.x + object.x, point.y + object.y));
            }
            final hitBox = PolygonHitbox(
              vertices,
              collisionType: CollisionType.passive,
              isSolid: true,
            );
            hitBox.onCollisionStartCallback = (_, __) => _onTrailEnter();
            hitBox.onCollisionEndCallback = (_) => _onTrailExist();
            await map.add(hitBox);
            break;
          case 'Checkpoint':
            final checkpoint = RectangleHitbox(
              position: Vector2(object.x, object.y),
              size: Vector2(object.width, object.height),
              collisionType: CollisionType.passive,
            );
            checkpoint.onCollisionStartCallback =
                (_, __) => _onCheckpoint(checkpoint);
            await map.add(checkpoint);
            break;
          case 'Ramp':
            final ramp = RectangleHitbox(
              position: Vector2(object.x, object.y),
              size: Vector2(object.width, object.height),
              collisionType: CollisionType.passive,
            );
            ramp.onCollisionStartCallback = (_, __) => _onRamp();
            await map.add(ramp);
            break;
          case 'Start':
            final trailStart = RectangleHitbox(
              position: Vector2(object.x, object.y),
              size: Vector2(object.width, object.height),
              collisionType: CollisionType.passive,
            );
            trailStart.onCollisionStartCallback = (_, __) => _onTrailStart();
            await map.add(trailStart);
            break;
          case 'End':
            final trailEnd = RectangleHitbox(
              position: Vector2(object.x, object.y),
              size: Vector2(object.width, object.height),
              collisionType: CollisionType.passive,
            );
            trailEnd.onCollisionStartCallback = (_, __) => _onTrailEnd();
            await map.add(trailEnd);
            break;
          default:
            break;
        }
      }
    }
  }

  void _onTrailEnter() {
    ++_nTrailTriggers;
  }

  void _onTrailExist() {
    --_nTrailTriggers;
  }

  void _onCheckpoint(RectangleHitbox checkpoint) {
    _lastSafePosition.setFrom(checkpoint.absoluteCenter);
    checkpoint.removeFromParent();
  }

  Future<void> _onRamp() async {
    final jumpFactor = await _player.jump();
    final jumpScale = lerpDouble(1, 1.08, jumpFactor)!;
    final jumpDuration = lerpDouble(0, 0.8, jumpFactor)!;
    await _camera.viewfinder.add(ScaleEffect.by(
      Vector2.all(jumpScale),
      EffectController(
        duration: jumpDuration,
        alternate: true,
        curve: Curves.easeInOut,
      ),
    ));
  }

  void _onTrailStart() {
    input.active = true;
    _lastSafePosition.setFrom(_player.position);
  }

  Future<void> _onTrailEnd() async {
    await _fader.add(OpacityEffect.fadeIn(LinearEffectController(1.5)));
    input.active = false;
    _levelCompleted = true;
    if (_nSnowmanCollected >= _start3) {
      onLevelCompleted.call(3);
      return;
    }
    if (_nSnowmanCollected >= _start2) {
      onLevelCompleted.call(2);
      return;
    }
    if (_nSnowmanCollected >= _start1) {
      onLevelCompleted.call(1);
      return;
    }
    onLevelCompleted.call(0);
  }

  Future<void> _onSnowmanCollected() async {
    ++_nSnowmanCollected;
    await _hud.updateSnowmanCount(_nSnowmanCollected);
  }

  Future<void> _resetPlayer() async {
    --_nLives;
    await _hud.updateLifeCount(_nLives);
    if (_nLives > 0) {
      await _player.resetTo(_lastSafePosition);
      return;
    }
    _gameOver = true;
    await _fader.add(OpacityEffect.fadeIn(LinearEffectController(1.5)));
    onGameOver.call();
  }
}
