import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_back_ground_service_usecase/bg_service.dart';
import 'package:flutter_back_ground_service_usecase/repositories/tick_preferences_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBackgroundService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  final _tickPreferencesRepository = const TickPreferencesRepository();

  bool? _serviceStatus;
  int _tickCount = 0;
  int _tickBackgroundCount = 0;
  String? _lastBackgroundFetchAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSavedTicks());
      AppBackgroundService.isRunning().then((value) {
        if (!mounted) return;
        setState(() {
          _serviceStatus = value;
        });
      });
      AppBackgroundService.on('tick-background').listen((event) {
        print(
          'Tick Background Count: ${event?['count'] ?? 0} ${event?['platform'] ?? ''}',
        );
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppBackgroundService.notifyAppLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      print('didChangeAppLifecycleState: $state');
      _loadSavedTicks();
    }
  }

  Future<void> _loadSavedTicks() async {
    final saved = await _tickPreferencesRepository.loadTickCounts();
    if (!mounted) return;

    setState(() {
      _tickCount = saved.tickCount;
      _tickBackgroundCount = saved.tickBackgroundCount;
      _lastBackgroundFetchAt = saved.lastFetchAt;
    });

    print(' prefs tickCount: ${saved.tickCount}');
    print(' prefs tickBackgroundCount: ${saved.tickBackgroundCount}');
    print(' lastBackgroundFetchAt: ${saved.lastFetchAt}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: 15,
          children: [
            Text('Saved Tick Count: $_tickCount'),
            Text('Saved Tick Background Count: $_tickBackgroundCount'),
            Text('Last BG Fetch: ${_lastBackgroundFetchAt ?? 'never'}'),
            Text('Service Status: $_serviceStatus'),

            StreamBuilder(
              stream: AppBackgroundService.on('pong'),
              builder: (context, snapshot) {
                return Text(
                  'Pong Message: ${snapshot.data?['message'] ?? 'No message received'}',
                );
              },
            ),

            StreamBuilder(
              stream: AppBackgroundService.on('tick'),
              builder: (context, snapshot) {
                return Text('Tick Count: ${snapshot.data?['count'] ?? 0}');
              },
            ),
            StreamBuilder(
              stream: AppBackgroundService.on('tick-background'),
              builder: (context, snapshot) {
                return Text(
                  'Tick Background Count: ${snapshot.data?['count'] ?? 0}',
                );
              },
            ),
            ElevatedButton(
              onPressed: _serviceStatus == true
                  ? null
                  : () async {
                      await AppBackgroundService.start();
                      _serviceStatus = true;
                      setState(() {});
                    },
              child: Text('Start Service'),
            ),
            ElevatedButton(
              onPressed: _serviceStatus == false || _serviceStatus == null
                  ? null
                  : () {
                      AppBackgroundService.stop();
                      _serviceStatus = false;
                      setState(() {});
                    },
              child: Text('Stop Service'),
            ),
            ElevatedButton(
              onPressed: () {
                AppBackgroundService.invoke('ping');
              },
              child: Text('Ping Service'),
            ),
            ElevatedButton(
              onPressed: () {
                AppBackgroundService.invoke('ping', {'userId': '123'});
              },
              child: Text('Ping Service with arguments'),
            ),
          ],
        ),
      ),
    );
  }
}
