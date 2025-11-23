import 'package:flutter/widgets.dart';

class FapNavigatorObserver extends NavigatorObserver {
  String? _currentRoute;

  String? get currentRoute => _currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = route.settings.name;
    print('FapNavigatorObserver: Pushed ${_currentRoute}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = previousRoute?.settings.name;
    print('FapNavigatorObserver: Popped to ${_currentRoute}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _currentRoute = newRoute?.settings.name;
    print('FapNavigatorObserver: Replaced with ${_currentRoute}');
  }
}
