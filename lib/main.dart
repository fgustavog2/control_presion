
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('users');
  await Hive.openBox('mediciones');
  runApp(MaterialApp(debugShowCheckedModeBanner:false, theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0F172A)), home: HomeScreen()));
}
