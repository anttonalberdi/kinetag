/// Which long sideline holds both teams' benches in the court view.
enum BenchSideline {
  top('Top sideline'),
  bottom('Bottom sideline');

  const BenchSideline(this.displayName);

  final String displayName;
}

/// When a due substitution may begin.
enum SubstitutionTiming {
  anyTime('Any time'),
  whileAttacking('While attacking');

  const SubstitutionTiming(this.displayName);

  final String displayName;
}
