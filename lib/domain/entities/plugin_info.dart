import 'package:equatable/equatable.dart';

class FilterChoice extends Equatable {
  final String label;
  final String value;

  const FilterChoice({required this.label, required this.value});

  @override
  List<Object?> get props => [label, value];
}

class FilterOption extends Equatable {
  final String name;
  final String label;
  final String defaultValue;
  final List<FilterChoice> choices;

  const FilterOption({
    required this.name,
    required this.label,
    required this.defaultValue,
    required this.choices,
  });

  @override
  List<Object?> get props => [name, label, defaultValue, choices];
}

class PluginInfo extends Equatable {
  final String id;
  final String name;
  final String shortName;
  final String? description;
  final double score;
  final String? href;
  final bool disabled;
  final bool needsProxy;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.shortName,
    this.description,
    this.score = 5.0,
    this.href,
    this.disabled = false,
    this.needsProxy = false,
  });

  @override
  List<Object?> get props => [id, name, shortName, description, score, href, disabled, needsProxy];
}
