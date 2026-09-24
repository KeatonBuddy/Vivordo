import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class VivordoRobot extends StatelessWidget {
  const VivordoRobot({super.key, this.size = 40, this.faceOnly = false});
  final double size;
  final bool faceOnly;
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    faceOnly ? _kRobotFaceSvg : _kRobotSvg,
    width: size,
    height: size,
  );
}

// Reuse the same head artwork, excluding the body and hover platform.
final String _kRobotFaceSvg =
    _kRobotSvg
        .split('<path d="M420 502')
        .first
        .replaceFirst('viewBox="288 35 648 900"', 'viewBox="300 35 624 440"')
        .replaceFirst(
          RegExp(r'<ellipse cx="610"[\s\S]*?<g opacity=".95">'),
          '<g opacity=".95">',
        ) +
    '</svg>';

const String _kRobotSvg =
    r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="288 35 648 900" fill="none">
<defs>
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
</defs>
<ellipse cx="610" cy="842" rx="300" ry="82" fill="url(#hoverGlow)"/>
<ellipse cx="610" cy="812" rx="155" ry="29" stroke="#EEEAFE" stroke-width="8" opacity=".75"/>
<ellipse cx="610" cy="812" rx="108" ry="18" stroke="#A79EFF" stroke-width="4" opacity=".55"/>
<g opacity=".95">
<path d="M618 158V78" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<path d="M430 270l-23-80" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<path d="M812 275l28-76" stroke="#8F82FF" stroke-width="8" stroke-linecap="round"/>
<circle cx="618" cy="66" r="21" fill="url(#purpleLight)"/><circle cx="401" cy="176" r="18" fill="url(#purpleLight)"/><circle cx="845" cy="185" r="18" fill="url(#purpleLight)"/>
</g>
<ellipse cx="374" cy="318" rx="57" ry="92" fill="url(#earGrad)"/>
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
<circle cx="558" cy="316" r="38" fill="#2B1457"/>
<circle cx="558" cy="316" r="27" stroke="url(#purpleLight)" stroke-width="13"/>
<circle cx="720" cy="318" r="38" fill="#2B1457"/>
<circle cx="720" cy="318" r="27" stroke="url(#purpleLight)" stroke-width="13"/>
<rect x="615" y="363" width="57" height="17" rx="9" fill="url(#purpleLight)"/>
<path d="M420 502C454 450 514 434 624 444c111 10 180 41 196 92 18 59-5 156-45 199-31 34-81 49-169 47-94-2-150-20-181-61-38-52-38-167-5-219Z" fill="url(#shellBody)"/>
<path d="M425 498c58-40 230-48 329 11-61-25-246-27-329-11Z" fill="#FFFFFF" opacity=".28"/>
<path d="M435 714c66 45 250 51 340 14-34 36-84 54-169 52-90-2-143-20-171-66Z" fill="#312286" opacity=".25"/>
<path d="M424 504c22-36 66-54 139-59" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round" opacity=".27"/>
<path d="M381 505c44 0 62 41 42 91-19 47-61 83-101 75-39-8-48-54-19-102 20-34 48-64 78-64Z" fill="url(#armGrad)"/>
<path d="M351 530c27-10 46-4 52 16-26 9-55 49-74 88-18-17-5-79 22-104Z" fill="#FFFFFF" opacity=".34"/>
<path d="M826 505c39 4 77 41 93 90 14 43-7 75-45 70-38-5-73-38-91-80-20-45 3-83 43-80Z" fill="url(#armGrad)" opacity=".95"/>
<path d="M856 525c30 15 48 47 52 79-24-32-58-50-91-55 5-19 19-31 39-24Z" fill="#FFFFFF" opacity=".31"/>
<ellipse cx="444" cy="525" rx="26" ry="43" fill="#151337" opacity=".54"/>
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
<path d="M490 760c74 26 166 27 241 2" stroke="#DCD6FF" stroke-width="5" opacity=".66"/>
<path d="M735 151c65 12 99 32 115 67" stroke="#FFFFFF" stroke-width="13" stroke-linecap="round" opacity=".48"/>
<path d="M805 520c33 16 56 43 68 80" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round" opacity=".42"/>
<path d="M448 562c-17 50-11 113 17 147" stroke="#FFFFFF" stroke-width="10" stroke-linecap="round" opacity=".23"/>
</svg>''';
