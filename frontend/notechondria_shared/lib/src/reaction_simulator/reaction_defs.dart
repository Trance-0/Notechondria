import 'dart:ui';

/// Data tables for the reaction-simulator splash animation.
///
/// Ported from the owner's `index` repo
/// (`D:/Documents/Github/index/lib/reaction_simulator`, also live at
/// https://index.trance-0.com/utils/reaction_simulator) at 0.1.128.
/// Only the TCA (citric-acid cycle) preset and the CPK palette are
/// ported — the splash is a fixed ambient animation, so the upstream
/// preset/theme/colormap configuration surface is intentionally
/// dropped and the tuning values live in [ReactionSimOptions].

/// One atom inside a molecule definition: element symbol plus its
/// fixed offset from the molecule center (simulation px).
class AtomSpec {
  const AtomSpec(this.element, this.dx, this.dy);

  final String element;
  final double dx;
  final double dy;
}

/// One bond: indexes into the molecule's atom list plus bond order
/// (1 = single, 2 = double).
class BondSpec {
  const BondSpec(this.a, this.b, this.order);

  final int a;
  final int b;
  final int order;
}

/// A molecule kind: its drawn structure and collision radius.
class MoleculeDef {
  const MoleculeDef(
      {required this.atoms, required this.bonds, required this.r});

  final List<AtomSpec> atoms;
  final List<BondSpec> bonds;
  final double r;
}

/// A bimolecular reaction rule: `a + b -> products`.
class BimolRule {
  const BimolRule({
    required this.a,
    required this.b,
    required this.products,
    required this.pictogram,
  });

  final String a;
  final String b;
  final List<String> products;
  final String pictogram;
}

/// A unimolecular (ripening) rule: after `minAge..maxAge` seconds the
/// particle decays into `products`.
class UnimolRule {
  const UnimolRule({
    required this.kind,
    required this.minAge,
    required this.maxAge,
    required this.products,
    required this.pictogram,
  });

  final String kind;
  final double minAge;
  final double maxAge;
  final List<String> products;
  final String pictogram;
}

/// Hardcoded simulation tuning (owner spec, 0.1.128): spawn kinetic
/// energy ~ N(250000, 60000). The upstream library exposes these as
/// runtime config; the splash does not.
///
/// 0.1.139: the particle target now scales with the viewport AREA so
/// the field is neither dense on phones nor sparse on large monitors.
/// [referenceParticles] is calibrated for a [referenceArea]
/// (1920×1080) screen; [ReactionSimulator.targetParticles] interpolates
/// by area and clamps to [minParticles] / [maxParticlesCap].
class ReactionSimOptions {
  static const int referenceParticles = 128;
  static const double referenceArea = 1920.0 * 1080.0;
  static const int minParticles = 24;
  static const int maxParticlesCap = 320;
  static const double energyMean = 250000;
  static const double energyStd = 60000;
  static const double spawnFadeIn = 0.8;
  static const double staleFadeStart = 20;
  static const double staleFadeEnd = 30;
  static const double speedMin = 20;
  static const double speedMax = 320;
}

const Map<String, double> kAtomicMass = {
  'H': 1,
  'B': 11,
  'C': 12,
  'N': 14,
  'O': 16,
  'F': 19,
  'Na': 23,
  'Mg': 24,
  'Al': 27,
  'Si': 28,
  'P': 31,
  'S': 32,
  'Cl': 35.5,
  'K': 39,
  'Ca': 40,
  'Mn': 55,
  'Fe': 56,
  'Cu': 63,
  'Zn': 65,
  'Br': 80,
  'I': 127,
};

double molecularMass(MoleculeDef def) {
  var sum = 0.0;
  for (final atom in def.atoms) {
    sum += kAtomicMass[atom.element] ?? 12;
  }
  return sum < 1 ? 1 : sum;
}

/// CPK fill/stroke/radius per element (upstream `ATOM_PALETTES.cpk`).
class AtomStyle {
  const AtomStyle(this.fill, this.stroke, this.r);

  final Color fill;
  final Color stroke;
  final double r;
}

const Map<String, AtomStyle> kCpkPalette = {
  'H': AtomStyle(Color(0xFFDCDCDC), Color(0xFF888888), 3),
  'C': AtomStyle(Color(0xFF5E5E5E), Color(0xFF3A3A3A), 6),
  'N': AtomStyle(Color(0xFF4A6DB4), Color(0xFF243A6C), 6),
  'O': AtomStyle(Color(0xFFC1574C), Color(0xFF7A2F27), 6),
  'P': AtomStyle(Color(0xFFD68A36), Color(0xFF7A4B14), 6),
  'S': AtomStyle(Color(0xFFCDAA1F), Color(0xFF7D6510), 7),
  'F': AtomStyle(Color(0xFF7EC47B), Color(0xFF365A35), 5),
  'Cl': AtomStyle(Color(0xFF7AC14A), Color(0xFF3D6C25), 6),
  'Br': AtomStyle(Color(0xFFA35A35), Color(0xFF5B3220), 6),
  'I': AtomStyle(Color(0xFF9B4DCA), Color(0xFF4A1A64), 7),
};

AtomStyle atomStyle(String element) =>
    kCpkPalette[element] ?? kCpkPalette['C']!;

/// TCA preset molecule structures (upstream `TCA_DEFS`).
const Map<String, MoleculeDef> kTcaDefs = {
  'h2o': MoleculeDef(
    atoms: [AtomSpec('O', 0, 0), AtomSpec('H', -6, 4), AtomSpec('H', 6, 4)],
    bonds: [BondSpec(0, 1, 1), BondSpec(0, 2, 1)],
    r: 8,
  ),
  'co2': MoleculeDef(
    atoms: [AtomSpec('O', -8, 0), AtomSpec('C', 0, 0), AtomSpec('O', 8, 0)],
    bonds: [BondSpec(0, 1, 2), BondSpec(1, 2, 2)],
    r: 10,
  ),
  'acetyl_coa': MoleculeDef(
    atoms: [
      AtomSpec('C', -18, 0),
      AtomSpec('C', -10, 0),
      AtomSpec('O', -10, -8),
      AtomSpec('S', -2, 0),
      AtomSpec('C', 6, 0),
      AtomSpec('N', 12, 6),
      AtomSpec('P', 12, -6),
    ],
    bonds: [
      BondSpec(0, 1, 1),
      BondSpec(1, 2, 2),
      BondSpec(1, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(4, 5, 1),
      BondSpec(4, 6, 1),
    ],
    r: 18,
  ),
  'oxaloacetate': MoleculeDef(
    atoms: [
      AtomSpec('O', -18, -5),
      AtomSpec('O', -18, 5),
      AtomSpec('C', -12, 0),
      AtomSpec('C', -4, 0),
      AtomSpec('O', -4, -8),
      AtomSpec('C', 4, 0),
      AtomSpec('C', 12, 0),
      AtomSpec('O', 18, -5),
      AtomSpec('O', 18, 5),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 2),
      BondSpec(3, 5, 1),
      BondSpec(5, 6, 1),
      BondSpec(6, 7, 2),
      BondSpec(6, 8, 1),
    ],
    r: 18,
  ),
  'citrate': MoleculeDef(
    atoms: [
      AtomSpec('C', 0, -10),
      AtomSpec('O', -6, -16),
      AtomSpec('O', 6, -16),
      AtomSpec('C', 0, -2),
      AtomSpec('O', 7, -2),
      AtomSpec('C', -8, 4),
      AtomSpec('C', 8, 4),
      AtomSpec('C', -14, 12),
      AtomSpec('O', -20, 8),
      AtomSpec('O', -20, 16),
      AtomSpec('C', 14, 12),
      AtomSpec('O', 20, 8),
      AtomSpec('O', 20, 16),
    ],
    bonds: [
      BondSpec(0, 1, 2),
      BondSpec(0, 2, 1),
      BondSpec(0, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(3, 5, 1),
      BondSpec(3, 6, 1),
      BondSpec(5, 7, 1),
      BondSpec(7, 8, 2),
      BondSpec(7, 9, 1),
      BondSpec(6, 10, 1),
      BondSpec(10, 11, 2),
      BondSpec(10, 12, 1),
    ],
    r: 22,
  ),
  'isocitrate': MoleculeDef(
    atoms: [
      AtomSpec('C', -2, -10),
      AtomSpec('O', -8, -16),
      AtomSpec('O', 4, -16),
      AtomSpec('C', -2, -2),
      AtomSpec('C', -10, 4),
      AtomSpec('O', -2, 6),
      AtomSpec('C', 6, 4),
      AtomSpec('C', -16, 12),
      AtomSpec('O', -22, 8),
      AtomSpec('O', -22, 16),
      AtomSpec('C', 14, 12),
      AtomSpec('O', 20, 8),
      AtomSpec('O', 20, 16),
    ],
    bonds: [
      BondSpec(0, 1, 2),
      BondSpec(0, 2, 1),
      BondSpec(0, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(4, 5, 1),
      BondSpec(3, 6, 1),
      BondSpec(4, 7, 1),
      BondSpec(7, 8, 2),
      BondSpec(7, 9, 1),
      BondSpec(6, 10, 1),
      BondSpec(10, 11, 2),
      BondSpec(10, 12, 1),
    ],
    r: 22,
  ),
  'alpha_kg': MoleculeDef(
    atoms: [
      AtomSpec('O', -18, -5),
      AtomSpec('O', -18, 5),
      AtomSpec('C', -12, 0),
      AtomSpec('C', -4, 0),
      AtomSpec('O', -4, -8),
      AtomSpec('C', 4, 4),
      AtomSpec('C', 12, 0),
      AtomSpec('O', 18, -5),
      AtomSpec('O', 18, 5),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 2),
      BondSpec(3, 5, 1),
      BondSpec(5, 6, 1),
      BondSpec(6, 7, 2),
      BondSpec(6, 8, 1),
    ],
    r: 18,
  ),
  'succinyl_coa': MoleculeDef(
    atoms: [
      AtomSpec('O', -22, -5),
      AtomSpec('O', -22, 5),
      AtomSpec('C', -16, 0),
      AtomSpec('C', -8, 0),
      AtomSpec('C', 0, 0),
      AtomSpec('S', 8, 0),
      AtomSpec('C', 14, 0),
      AtomSpec('N', 18, 6),
      AtomSpec('P', 18, -6),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(4, 5, 1),
      BondSpec(5, 6, 1),
      BondSpec(6, 7, 1),
      BondSpec(6, 8, 1),
    ],
    r: 20,
  ),
  'succinate': MoleculeDef(
    atoms: [
      AtomSpec('O', -18, -5),
      AtomSpec('O', -18, 5),
      AtomSpec('C', -12, 0),
      AtomSpec('C', -4, 0),
      AtomSpec('C', 4, 0),
      AtomSpec('C', 12, 0),
      AtomSpec('O', 18, -5),
      AtomSpec('O', 18, 5),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(4, 5, 1),
      BondSpec(5, 6, 2),
      BondSpec(5, 7, 1),
    ],
    r: 18,
  ),
  'fumarate': MoleculeDef(
    atoms: [
      AtomSpec('O', -18, -5),
      AtomSpec('O', -18, 5),
      AtomSpec('C', -12, 0),
      AtomSpec('C', -4, 0),
      AtomSpec('C', 4, 0),
      AtomSpec('C', 12, 0),
      AtomSpec('O', 18, -5),
      AtomSpec('O', 18, 5),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 2),
      BondSpec(4, 5, 1),
      BondSpec(5, 6, 2),
      BondSpec(5, 7, 1),
    ],
    r: 18,
  ),
  'malate': MoleculeDef(
    atoms: [
      AtomSpec('O', -18, -5),
      AtomSpec('O', -18, 5),
      AtomSpec('C', -12, 0),
      AtomSpec('C', -4, 0),
      AtomSpec('O', -4, -7),
      AtomSpec('C', 4, 0),
      AtomSpec('C', 12, 0),
      AtomSpec('O', 18, -5),
      AtomSpec('O', 18, 5),
    ],
    bonds: [
      BondSpec(0, 2, 2),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(3, 5, 1),
      BondSpec(5, 6, 1),
      BondSpec(6, 7, 2),
      BondSpec(6, 8, 1),
    ],
    r: 18,
  ),
  'coa_sh': MoleculeDef(
    atoms: [
      AtomSpec('S', -8, 0),
      AtomSpec('C', 0, 0),
      AtomSpec('N', 6, -5),
      AtomSpec('P', 6, 5),
      AtomSpec('H', -14, 0),
    ],
    bonds: [
      BondSpec(0, 1, 1),
      BondSpec(1, 2, 1),
      BondSpec(1, 3, 1),
      BondSpec(0, 4, 1),
    ],
    r: 12,
  ),
  'nad_plus': MoleculeDef(
    atoms: [
      AtomSpec('N', -6, 0),
      AtomSpec('C', 0, 0),
      AtomSpec('P', 6, -4),
      AtomSpec('O', 6, 4),
      AtomSpec('C', 12, 0),
    ],
    bonds: [
      BondSpec(0, 1, 1),
      BondSpec(1, 2, 1),
      BondSpec(1, 3, 1),
      BondSpec(1, 4, 1),
    ],
    r: 12,
  ),
  'fad': MoleculeDef(
    atoms: [
      AtomSpec('N', -10, -4),
      AtomSpec('N', -10, 4),
      AtomSpec('C', -4, 0),
      AtomSpec('C', 4, 0),
      AtomSpec('P', 10, -4),
      AtomSpec('O', 10, 4),
    ],
    bonds: [
      BondSpec(0, 2, 1),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 1),
      BondSpec(3, 4, 1),
      BondSpec(3, 5, 1),
    ],
    r: 12,
  ),
  'gdp': MoleculeDef(
    atoms: [
      AtomSpec('C', -8, 0),
      AtomSpec('O', -2, -4),
      AtomSpec('P', 4, 0),
      AtomSpec('O', 4, -7),
      AtomSpec('P', 12, 0),
      AtomSpec('O', 12, -7),
    ],
    bonds: [
      BondSpec(0, 1, 1),
      BondSpec(1, 2, 1),
      BondSpec(2, 3, 2),
      BondSpec(2, 4, 1),
      BondSpec(4, 5, 2),
    ],
    r: 14,
  ),
  'pi': MoleculeDef(
    atoms: [
      AtomSpec('P', 0, 0),
      AtomSpec('O', -7, 0),
      AtomSpec('O', 7, 0),
      AtomSpec('O', 0, -7),
      AtomSpec('O', 0, 7),
    ],
    bonds: [
      BondSpec(0, 1, 1),
      BondSpec(0, 2, 1),
      BondSpec(0, 3, 2),
      BondSpec(0, 4, 1),
    ],
    r: 10,
  ),
};

const List<BimolRule> kTcaBimol = [
  BimolRule(
    a: 'acetyl_coa',
    b: 'oxaloacetate',
    products: ['citrate', 'coa_sh'],
    pictogram: 'plus',
  ),
  BimolRule(
    a: 'alpha_kg',
    b: 'coa_sh',
    products: ['succinyl_coa', 'co2'],
    pictogram: 'co2_up',
  ),
  BimolRule(
    a: 'fumarate',
    b: 'h2o',
    products: ['malate'],
    pictogram: 'h2o_in',
  ),
];

const List<UnimolRule> kTcaUnimol = [
  UnimolRule(
      kind: 'citrate',
      minAge: 4,
      maxAge: 8,
      products: ['isocitrate'],
      pictogram: 'rotate'),
  UnimolRule(
      kind: 'isocitrate',
      minAge: 3,
      maxAge: 6,
      products: ['alpha_kg', 'co2'],
      pictogram: 'co2_up'),
  UnimolRule(
      kind: 'succinyl_coa',
      minAge: 3,
      maxAge: 6,
      products: ['succinate', 'coa_sh'],
      pictogram: 'arrow'),
  UnimolRule(
      kind: 'succinate',
      minAge: 3,
      maxAge: 6,
      products: ['fumarate'],
      pictogram: 'h2_up'),
  UnimolRule(
      kind: 'malate',
      minAge: 3,
      maxAge: 6,
      products: ['oxaloacetate'],
      pictogram: 'h2_up'),
];

const List<String> kTcaSpawnable = [
  'acetyl_coa',
  'oxaloacetate',
  'h2o',
  'coa_sh',
  'nad_plus',
  'fad',
  'gdp',
  'pi',
];
