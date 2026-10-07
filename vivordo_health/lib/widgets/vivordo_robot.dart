import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Vivordo robot, whole or head only. Static; see [VivordoRobotRig] for
/// the animated character.
class VivordoRobot extends StatelessWidget {
  const VivordoRobot({super.key, this.size = 40, this.faceOnly = false});
  final double size;
  final bool faceOnly;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    faceOnly ? _faceSvg : _robotSvg,
    width: size,
    height: size,
  );
}

enum RobotPose { idle, wave, pointLeft, pointRight, celebrate }

/// The robot as a character: it hovers and blinks, and turns its head and
/// arms to match [pose]. While [talking] its eyes pulse instead of blinking.
/// [size] is the height; the width follows the artwork.
class VivordoRobotRig extends StatefulWidget {
  const VivordoRobotRig({
    super.key,
    this.size = 160,
    this.pose = RobotPose.idle,
    this.talking = false,
  });
  final double size;
  final RobotPose pose;
  final bool talking;

  static const aspect = 648 / 900;

  @override
  State<VivordoRobotRig> createState() => _VivordoRobotRigState();
}

class _VivordoRobotRigState extends State<VivordoRobotRig>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  static const _poseDuration = Duration(milliseconds: 450);
  static const _poseCurve = Curves.easeOutBack;

  // Joints in the artwork's viewBox (288 35 648 900), as alignments.
  static const _neck = Alignment(0, -.1);
  static const _leftShoulder = Alignment(-.519, .089);
  static const _rightShoulder = Alignment(.583, .096);
  static const _eyes = Alignment(.08, -.37);
  static const _platform = Alignment(0, .76);

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  Widget _layer(String svg) => SvgPicture.string(
    svg,
    width: widget.size * VivordoRobotRig.aspect,
    height: widget.size,
  );

  Widget _joint(double turns, Alignment pivot, Widget child) =>
      AnimatedRotation(
        turns: turns,
        alignment: pivot,
        duration: _poseDuration,
        curve: _poseCurve,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final pose = widget.pose;
    final headTurns = switch (pose) {
      RobotPose.pointLeft => -.03,
      RobotPose.pointRight => .03,
      RobotPose.wave => .015,
      _ => 0.0,
    };
    final leftTurns = switch (pose) {
      RobotPose.wave => .26,
      RobotPose.pointLeft => .15,
      RobotPose.celebrate => .22,
      _ => 0.0,
    };
    final rightTurns = switch (pose) {
      RobotPose.pointRight => -.135,
      RobotPose.celebrate => -.22,
      _ => 0.0,
    };
    return SizedBox(
      width: widget.size * VivordoRobotRig.aspect,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final v = _loop.value;
          final bob = math.sin(2 * math.pi * v);
          final wave = pose == RobotPose.wave
              ? math.sin(2 * math.pi * v * 4) * .04
              : 0.0;
          final bounce = pose == RobotPose.celebrate
              ? math.sin(2 * math.pi * v * 3).abs() * .04
              : 0.0;
          // One blink per loop, or a quick pulse while talking.
          final blink = ((v - .93) / .04).clamp(0.0, 1.0);
          final eyeScaleY = widget.talking
              ? 1 + .08 * math.max(0, math.sin(2 * math.pi * v * 6))
              : 1 - .85 * math.sin(math.pi * blink);
          final eyeScaleX = widget.talking ? eyeScaleY : 1.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scaleX: 1 - bob * .05,
                alignment: _platform,
                child: _layer(_platformSvg),
              ),
              Transform.translate(
                offset: Offset(0, bob * widget.size * .02),
                child: Transform.scale(
                  scale: 1 + bounce,
                  alignment: Alignment.bottomCenter,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _joint(
                        headTurns,
                        _neck,
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            _layer(_antennaSvg),
                            _layer(_headSvg),
                            Transform.scale(
                              scaleX: eyeScaleX,
                              scaleY: eyeScaleY,
                              alignment: _eyes,
                              child: _layer(_eyesSvg),
                            ),
                          ],
                        ),
                      ),
                      _layer(_bodyShellSvg),
                      _joint(
                        leftTurns,
                        _leftShoulder,
                        // The wave is a per-frame wobble on top of the pose,
                        // so it must not retarget the implicit animation.
                        Transform.rotate(
                          angle: wave * 2 * math.pi,
                          alignment: _leftShoulder,
                          child: _layer(_leftArmSvg),
                        ),
                      ),
                      _joint(rightTurns, _rightShoulder, _layer(_rightArmSvg)),
                      _layer(_bodyDetailSvg),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// The artwork, split into the parts the rig moves. Every part carries the
// shared defs so it renders alone.
const _viewBox = 'viewBox="288 35 648 900"';
const _faceViewBox = 'viewBox="300 35 624 440"';
const _open = '<svg xmlns="http://www.w3.org/2000/svg" ';
const _close = '</svg>';

const _platformSvg =
    '$_open$_viewBox fill="none">\n$_defs\n$_platform\n$_close';
const _antennaSvg = '$_open$_viewBox fill="none">\n$_defs\n$_antenna\n$_close';
const _headSvg = '$_open$_viewBox fill="none">\n$_defs\n$_head\n$_close';
const _eyesSvg = '$_open$_viewBox fill="none">\n$_defs\n$_eyes\n$_close';
const _bodyShellSvg =
    '$_open$_viewBox fill="none">\n$_defs\n$_bodyShell\n$_close';
const _leftArmSvg = '$_open$_viewBox fill="none">\n$_defs\n$_leftArm\n$_close';
const _rightArmSvg =
    '$_open$_viewBox fill="none">\n$_defs\n$_rightArm\n$_close';
const _bodyDetailSvg =
    '$_open$_viewBox fill="none">\n$_defs\n$_bodyDetail\n$_close';

const _robotSvg =
    '$_open$_viewBox fill="none">\n$_defs\n$_platform\n$_antenna\n$_head\n'
    '$_eyes\n$_bodyShell\n$_leftArm\n$_rightArm\n$_bodyDetail\n$_close';
const _faceSvg =
    '$_open$_faceViewBox fill="none">\n$_defs\n$_antenna\n$_head\n$_eyes\n'
    '$_close';

const _defs = r'''<defs>
<radialGradient id="shellHead" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(580 182) rotate(70) scale(410 300)">
<stop offset="0" stop-color="#FBFAFF"/><stop offset=".20" stop-color="#DCD8FF"/><stop offset=".52" stop-color="#7B6EF6"/><stop offset="1" stop-color="#4636BE"/>
</radialGradient>
<radialGradient id="shellBody" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(545 505) rotate(67) scale(310 280)">
<stop offset="0" stop-color="#F6F3FF"/><stop offset=".22" stop-color="#BCB3FF"/><stop offset=".58" stop-color="#7B6EF6"/><stop offset="1" stop-color="#4B3BC9"/>
</radialGradient>
<linearGradient id="edgeShade" x1="363" y1="178" x2="850" y2="462" gradientUnits="userSpaceOnUse">
<stop stop-color="#FFFFFF" stop-opacity=".70"/><stop offset=".45" stop-color="#FFFFFF" stop-opacity=".12"/><stop offset="1" stop-color="#2A216F" stop-opacity=".36"/>
</linearGradient>
<linearGradient id="glass" x1="455" y1="214" x2="810" y2="426" gradientUnits="userSpaceOnUse">
<stop stop-color="#151A32"/><stop offset=".55" stop-color="#030611"/><stop offset="1" stop-color="#121423"/>
</linearGradient>
<linearGradient id="glassShine" x1="655" y1="214" x2="815" y2="370" gradientUnits="userSpaceOnUse">
<stop stop-color="#FFFFFF" stop-opacity=".35"/><stop offset=".42" stop-color="#FFFFFF" stop-opacity=".10"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
</linearGradient>
<linearGradient id="purpleLight" x1="0" y1="0" x2="1" y2="1">
<stop stop-color="#FFFFFF"/><stop offset=".28" stop-color="#D9CFFF"/><stop offset=".63" stop-color="#A178FF"/><stop offset="1" stop-color="#7B6EF6"/>
</linearGradient>
<radialGradient id="hoverGlow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(612 817) scale(280 82)">
<stop stop-color="#B8ADFF" stop-opacity=".62"/><stop offset=".48" stop-color="#7B6EF6" stop-opacity=".22"/><stop offset="1" stop-color="#7B6EF6" stop-opacity="0"/>
</radialGradient>
<radialGradient id="armGrad" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(360 540) rotate(55) scale(120 88)">
<stop stop-color="#FFFFFF"/><stop offset=".25" stop-color="#CBC5FF"/><stop offset=".68" stop-color="#7B6EF6"/><stop offset="1" stop-color="#4D3DCC"/>
</radialGradient>
<radialGradient id="earGrad" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(370 260) rotate(82) scale(112 82)">
<stop stop-color="#FFFFFF"/><stop offset=".30" stop-color="#C9C1FF"/><stop offset=".72" stop-color="#7B6EF6"/><stop offset="1" stop-color="#4535BB"/>
</radialGradient>
</defs>''';

const _platform =
    r'''<ellipse cx="610" cy="842" rx="300" ry="82" fill="url(#hoverGlow)"/>
<ellipse cx="610" cy="812" rx="155" ry="29" stroke="#EEEAFE" stroke-width="8" opacity=".75"/>
<ellipse cx="610" cy="812" rx="108" ry="18" stroke="#A79EFF" stroke-width="4" opacity=".55"/>''';

const _antenna = r'''<g opacity=".95">
<path d="M618 158V78" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<path d="M430 270l-23-80" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<path d="M812 275l28-76" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<circle cx="618" cy="66" r="21" fill="url(#purpleLight)"/><circle cx="401" cy="176" r="18" fill="url(#purpleLight)"/><circle cx="845" cy="185" r="18" fill="url(#purpleLight)"/>
</g>''';

const _head =
    r'''<ellipse cx="374" cy="318" rx="57" ry="92" fill="url(#earGrad)"/>
<ellipse cx="371" cy="318" rx="34" ry="59" fill="#111326"/>
<ellipse cx="371" cy="318" rx="25" ry="47" stroke="url(#purpleLight)" stroke-width="9"/>
<ellipse cx="351" cy="258" rx="15" ry="20" fill="#FFFFFF" opacity=".44"/>
<ellipse cx="866" cy="322" rx="45" ry="86" fill="url(#earGrad)" opacity=".88"/>
<ellipse cx="870" cy="322" rx="25" ry="53" fill="#111326" opacity=".72"/>
<ellipse cx="870" cy="322" rx="17" ry="43" stroke="url(#purpleLight)" stroke-width="7" opacity=".84"/>
<path d="M410 188C437 145 486 124 612 124c143 0 234 25 261 80 17 35 17 153-3 192-25 49-82 62-250 59-164-3-220-21-240-74-23-60-13-146 30-193Z" fill="url(#shellHead)"/>
<path d="M412 190C464 139 604 123 744 142c68 10 109 32 128 65-65-43-170-51-293-43-86 6-144 15-167 26Z" fill="#FFFFFF" opacity=".32"/>
<path d="M386 362c38 90 237 102 420 77-31 22-88 29-186 27-164-3-220-21-240-74-5-13-8-23-9-34 5 2 10 3 15 4Z" fill="#33258F" opacity=".20"/>
<path d="M414 185c67-54 260-70 380-27" stroke="url(#edgeShade)" stroke-width="18" stroke-linecap="round" opacity=".5"/>
<path d="M455 238C474 207 516 198 617 200c112 2 178 13 200 46 15 23 16 104 1 132-22 41-71 47-201 45-126-3-169-15-185-52-16-39-8-104 23-133Z" fill="url(#glass)"/>
<path d="M455 238C474 207 516 198 617 200c112 2 178 13 200 46 15 23 16 104 1 132-22 41-71 47-201 45-126-3-169-15-185-52-16-39-8-104 23-133Z" stroke="#FFFFFF" stroke-opacity=".58" stroke-width="8"/>
<path d="M692 218c58 5 102 18 124 48 15 21 17 64 6 98-14-43-50-72-110-92 22-17 21-37-20-54Z" fill="url(#glassShine)"/>
<rect x="615" y="363" width="57" height="17" rx="9" fill="url(#purpleLight)"/>
<path d="M735 151c65 12 99 32 115 67" stroke="#FFFFFF" stroke-width="13" stroke-linecap="round" opacity=".48"/>''';

const _eyes = r'''<circle cx="558" cy="316" r="38" fill="#2B1457"/>
<circle cx="558" cy="316" r="27" stroke="url(#purpleLight)" stroke-width="13"/>
<circle cx="720" cy="318" r="38" fill="#2B1457"/>
<circle cx="720" cy="318" r="27" stroke="url(#purpleLight)" stroke-width="13"/>''';

const _bodyShell =
    r'''<path d="M420 502C454 450 514 434 624 444c111 10 180 41 196 92 18 59-5 156-45 199-31 34-81 49-169 47-94-2-150-20-181-61-38-52-38-167-5-219Z" fill="url(#shellBody)"/>
<path d="M425 498c58-40 230-48 329 11-61-25-246-27-329-11Z" fill="#FFFFFF" opacity=".28"/>
<path d="M435 714c66 45 250 51 340 14-34 36-84 54-169 52-90-2-143-20-171-66Z" fill="#312286" opacity=".25"/>
<path d="M424 504c22-36 66-54 139-59" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round" opacity=".27"/>''';

const _leftArm =
    r'''<path d="M381 505c44 0 62 41 42 91-19 47-61 83-101 75-39-8-48-54-19-102 20-34 48-64 78-64Z" fill="url(#armGrad)"/>
<path d="M351 530c27-10 46-4 52 16-26 9-55 49-74 88-18-17-5-79 22-104Z" fill="#FFFFFF" opacity=".34"/>
<path d="M448 562c-17 50-11 113 17 147" stroke="#FFFFFF" stroke-width="10" stroke-linecap="round" opacity=".23"/>''';

const _rightArm =
    r'''<path d="M826 505c39 4 77 41 93 90 14 43-7 75-45 70-38-5-73-38-91-80-20-45 3-83 43-80Z" fill="url(#armGrad)" opacity=".95"/>
<path d="M856 525c30 15 48 47 52 79-24-32-58-50-91-55 5-19 19-31 39-24Z" fill="#FFFFFF" opacity=".31"/>
<path d="M805 520c33 16 56 43 68 80" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round" opacity=".42"/>''';

const _bodyDetail =
    r'''<ellipse cx="444" cy="525" rx="26" ry="43" fill="#151337" opacity=".54"/>
<ellipse cx="801" cy="528" rx="24" ry="43" fill="#151337" opacity=".50"/>
<rect x="497" y="530" width="251" height="155" rx="42" fill="url(#glass)"/>
<rect x="497" y="530" width="251" height="155" rx="42" stroke="#FFFFFF" stroke-width="8" stroke-opacity=".62"/>
<rect x="515" y="548" width="215" height="119" rx="30" stroke="#A79EFF" stroke-width="4" opacity=".50"/>
<path d="M650 540c42 3 70 13 83 32-19-9-56-15-101-15 9-5 15-10 18-17Z" fill="#FFFFFF" opacity=".18"/>
<g stroke="url(#purpleLight)" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">
<path d="M575 601c-18-24 5-50 31-35 11-25 48-21 54 4 27-5 47 17 35 42 20 16 6 50-22 48-12 23-47 24-61 3-23 14-54-7-44-33-18-4-24-19-18-29 5-9 14-12 25 0Z"/>
<path d="M604 566c-12 24 10 31 31 29M653 572c-12 17-4 34 17 37M587 621c27-15 56-9 87 22M618 604c-7 22 2 40 26 56"/>
</g>
<g fill="#EDE8FF">
<circle cx="545" cy="604" r="4"/><circle cx="699" cy="589" r="4"/><circle cx="562" cy="642" r="4"/><circle cx="682" cy="650" r="4"/>
<circle cx="573" cy="707" r="8"/><circle cx="621" cy="707" r="8"/><circle cx="672" cy="707" r="8"/>
</g>
<path d="M500 766c56 24 159 25 216 2-11 29-49 46-105 47-57 0-97-17-111-49Z" fill="#33278D" opacity=".62"/>
<path d="M490 760c74 26 166 27 241 2" stroke="#DCD6FF" stroke-width="5" opacity=".66"/>''';
