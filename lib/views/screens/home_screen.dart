import 'package:flutter/material.dart';
import 'package:group_money_management_app/views/screens/details_screen.dart';
import 'package:group_money_management_app/views/screens/pay_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [const PayScreen(), const DetailsScreen()];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: "Pay"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Details"),
        ],
      ),
    );
  }
}
