import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/particles.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:ski_master/game/actors/player.dart';
import 'package:ski_master/game/ski_master_game.dart';

class Snowman extends PositionComponent
    with CollisionCallbacks, HasGameReference<SkiMasterGame> {
  Snowman({
    super.position,
    required Sprite sprite,
    this.onCollected,
  }) : _body = SpriteComponent(
          sprite: sprite,
          anchor: Anchor.center,
        );

  final VoidCallback? onCollected;

  final SpriteComponent _body;
  late final _particlePaint = Paint()..color = game.backgroundColor();

  static final _random = Random();
  static Vector2 _randomVector(double scale) {
    return Vector2(2 * _random.nextDouble() - 1, 2 * _random.nextDouble() - 1)
      ..normalize()
      ..scale(scale);
  }

  @override
  Future<void> onLoad() async {
    await add(_body);
    await add(CircleHitbox.relative(
      1,
      parentSize: _body.size,
      anchor: Anchor.center,
      collisionType: CollisionType.passive,
    ));
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      _collect();
    }
  }

  Future<void> _collect() async {
    if (game.sfxValueNotifier.value) {
      await FlameAudio.play(SkiMasterGame.collectSfx);
    }
    await addAll([
      OpacityEffect.fadeOut(
        LinearEffectController(0.4),
        target: _body,
        onComplete: removeFromParent,
      ),
      ScaleEffect.by(
        Vector2.all(1.2),
        LinearEffectController(0.4),
      ),
    ]);
    await parent?.add(
      ParticleSystemComponent(
        position: position,
        particle: Particle.generate(
          count: 30,
          lifespan: 1,
          generator: (index) {
            return MovingParticle(
              child: ScalingParticle(
                child: CircleParticle(
                  radius: 2 + _random.nextDouble() * 3,
                  paint: _particlePaint,
                ),
              ),
              to: _randomVector(16),
            );
          },
        ),
      ),
    );
    onCollected?.call();
  }
}
