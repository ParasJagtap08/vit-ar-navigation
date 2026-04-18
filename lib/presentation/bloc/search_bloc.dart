/// SearchBloc — handles destination search with debouncing.

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/navigation/models.dart';
import '../../domain/usecases/navigation_usecases.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EVENTS
// ─────────────────────────────────────────────────────────────────────────────

sealed class SearchEvent {}

class SearchQueryChanged extends SearchEvent {
  final String query;
  SearchQueryChanged(this.query);
}

class SearchCleared extends SearchEvent {}

class SearchResultSelected extends SearchEvent {
  final NavNode node;
  SearchResultSelected(this.node);
}

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

sealed class SearchState {}

class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {
  final String query;
  SearchLoading(this.query);
}

class SearchResults extends SearchState {
  final String query;
  final List<NavNode> results;
  final int resultCount;

  SearchResults({
    required this.query,
    required this.results,
  }) : resultCount = results.length;

  bool get hasResults => results.isNotEmpty;
}

class SearchError extends SearchState {
  final String message;
  SearchError(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOC
// ─────────────────────────────────────────────────────────────────────────────

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchDestinationsUseCase _searchUseCase;
  Timer? _debounceTimer;

  SearchBloc({required SearchDestinationsUseCase searchUseCase})
      : _searchUseCase = searchUseCase,
        super(SearchInitial()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchCleared>(_onCleared);
  }

  void _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim();

    if (query.isEmpty) {
      emit(SearchInitial());
      return;
    }

    if (query.length < 2) return; // Min 2 chars

    emit(SearchLoading(query));

    // Debounce: wait 300ms after last keystroke
    _debounceTimer?.cancel();
    final completer = Completer<void>();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      completer.complete();
    });
    await completer.future;

    try {
      final results = await _searchUseCase.execute(query);

      // Sort: rooms first, then labs, then offices, then others
      results.sort((a, b) {
        const priority = {
          NodeType.room: 0,
          NodeType.lab: 1,
          NodeType.office: 2,
          NodeType.washroom: 3,
          NodeType.entrance: 4,
        };
        final pa = priority[a.type] ?? 5;
        final pb = priority[b.type] ?? 5;
        if (pa != pb) return pa.compareTo(pb);
        return a.displayName.compareTo(b.displayName);
      });

      emit(SearchResults(query: query, results: results));
    } catch (e) {
      emit(SearchError('Search failed: $e'));
    }
  }

  void _onCleared(SearchCleared event, Emitter<SearchState> emit) {
    _debounceTimer?.cancel();
    emit(SearchInitial());
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
