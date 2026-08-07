/// The app's source of "now".
///
/// Everything that renders a wall clock — the live lesson's running timer, a
/// notification's "12 daq oldin", the demo fixtures' relative timestamps —
/// reads this instead of calling `DateTime.now()` directly.
///
/// The reason is the golden tests. They rasterise whole screens and compare
/// them pixel for pixel; with a real clock the live lesson's elapsed time
/// ticks between the run that generated the golden and the run that checks
/// it, and every comparison fails on a handful of changed digits. Pinning
/// this in a test makes the rendered output a function of the fixtures alone.
///
/// Production never assigns it.
DateTime Function() hkNow = DateTime.now;
