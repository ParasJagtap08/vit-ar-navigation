/// App entry point — dependency injection and BLoC provider setup.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'data/datasources/firebase_datasource.dart';
import 'data/datasources/local_datasource.dart';
import 'data/repositories/navigation_repository_impl.dart';
import 'domain/usecases/navigation_usecases.dart';
import 'presentation/bloc/navigation_bloc.dart';
import 'presentation/bloc/search_bloc.dart';
import 'presentation/bloc/localization_bloc.dart';
import 'presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System UI overlay
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0E21),
  ));

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Hive (local cache)
  await Hive.initFlutter();

  // ── Dependency Injection (manual, no get_it needed for this scope) ──

  // Data layer
  final remoteDatasource = FirebaseNavigationDatasource();
  final localDatasource = LocalNavigationDatasource();

  // Repository
  final repository = NavigationRepositoryImpl(
    remote: remoteDatasource,
    local: localDatasource,
  );

  // Use cases
  final navigateUseCase = NavigateToDestinationUseCase(repository);
  final searchUseCase = SearchDestinationsUseCase(repository);
  final amenityUseCase = FindNearestAmenityUseCase(repository);
  final watchEdgesUseCase = WatchBlockedEdgesUseCase(repository);

  runApp(VITNavigationApp(
    navigateUseCase: navigateUseCase,
    searchUseCase: searchUseCase,
    amenityUseCase: amenityUseCase,
    watchEdgesUseCase: watchEdgesUseCase,
  ));
}

class VITNavigationApp extends StatelessWidget {
  final NavigateToDestinationUseCase navigateUseCase;
  final SearchDestinationsUseCase searchUseCase;
  final FindNearestAmenityUseCase amenityUseCase;
  final WatchBlockedEdgesUseCase watchEdgesUseCase;

  const VITNavigationApp({
    super.key,
    required this.navigateUseCase,
    required this.searchUseCase,
    required this.amenityUseCase,
    required this.watchEdgesUseCase,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => NavigationBloc(
            navigateUseCase: navigateUseCase,
            amenityUseCase: amenityUseCase,
            watchEdgesUseCase: watchEdgesUseCase,
          ),
        ),
        BlocProvider(
          create: (_) => SearchBloc(searchUseCase: searchUseCase),
        ),
        BlocProvider(
          create: (_) => LocalizationBloc(),
        ),
      ],
      child: MaterialApp(
        title: 'VIT Campus Navigator',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF00BCD4),
          scaffoldBackgroundColor: const Color(0xFF0A0E21),
          fontFamily: 'Inter',
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00BCD4),
            secondary: Color(0xFF00BCD4),
            surface: Color(0xFF1A1A2E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A0E21),
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
