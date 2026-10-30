/// Plain-language reading of a freeze frame: the conditions the engine
/// computer saved when it stored a fault.
library;

/// [values] maps PID names (e.g. "coolant_temp") to their numbers, in the
/// PIDs' own units. Returns short sentences, most useful first.
List<String> describeConditions(Map<String, num> values) {
  final out = <String>[];
  final rpm = values['rpm'];
  final speed = values['speed'];
  final load = values['engine_load'];
  final coolant = values['coolant_temp'];

  if (rpm != null && rpm < 300) {
    out.add('The engine was not running.');
  } else if (speed != null) {
    if (speed < 3) {
      out.add(rpm != null && rpm < 1100 ? 'The car was standing still at idle.' : 'The car was standing still.');
    } else if (speed < 60) {
      out.add('The car was driving at low speed (${speed.round()} km/h).');
    } else if (speed < 100) {
      out.add('The car was driving at ${speed.round()} km/h.');
    } else {
      out.add('The car was driving fast (${speed.round()} km/h).');
    }
  }
  if (load != null) {
    if (load >= 75) {
      out.add('The engine was working hard (${load.round()}% load), e.g. accelerating or climbing.');
    } else if (load <= 25 && (rpm ?? 1000) >= 300) {
      out.add('The engine was lightly loaded (${load.round()}%).');
    }
  }
  if (coolant != null) {
    if (coolant < 60) {
      out.add(
        'The engine was still cold (${coolant.round()} °C). Faults that only appear cold often point to '
        'sensors, injectors or vacuum leaks that seal once warm.',
      );
    } else if (coolant > 110) {
      out.add('The engine was hot (${coolant.round()} °C).');
    } else {
      out.add('The engine was at normal temperature (${coolant.round()} °C).');
    }
  }
  final stft = values['stft_b1'];
  final ltft = values['ltft_b1'];
  if (stft != null && ltft != null) {
    final total = stft + ltft;
    if (total > 15) {
      out.add(
        'Fuel trims were high (+${total.round()}%): the engine was adding fuel, which suggests it was '
        'running lean (unmetered air or low fuel delivery).',
      );
    } else if (total < -15) {
      out.add(
        'Fuel trims were low (${total.round()}%): the engine was removing fuel, which suggests it was '
        'running rich.',
      );
    }
  }
  final volts = values['module_voltage'];
  if (volts != null && volts < 11.5) {
    out.add('System voltage was low (${volts.toStringAsFixed(1)} V), which can cause false faults.');
  }
  return out;
}
