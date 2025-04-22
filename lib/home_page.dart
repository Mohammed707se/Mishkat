import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:movie_ai_validator/Screen/HomeScreen/home_screen.dart';

class HomePage extends StatefulWidget {
  final List<CameraDescription>? cameras;
  const HomePage({Key? key, this.cameras}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 2;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      HomeScreen(cameras: widget.cameras!),
      HomeScreen(cameras: widget.cameras!),
      HomeScreen(cameras: widget.cameras!),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [_pages[_selectedIndex], _buildCustomNavigationBar()],
      ),
    );
  }

  Widget _buildCustomNavigationBar() {
    return Positioned(
      bottom: 25,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        height: 70,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,

              right: _getIndicatorPosition(context),
              bottom: 5,
              child: Container(
                width: 60,
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFFAA2A2A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFAA2A2A).withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(_getSelectedIcon(), color: Colors.white, size: 30),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(2, Icons.home),

                _buildNavItem(1, Icons.play_arrow),

                _buildNavItem(0, Icons.person_outline),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _getIndicatorPosition(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double containerWidth = screenWidth - 80;
    double itemWidth = containerWidth / 3;

    switch (_selectedIndex) {
      case 2:
        return itemWidth / 2 - 30;
      case 1:
        return containerWidth / 2 - 30;
      case 0:
        return containerWidth - itemWidth / 2 - 30;
      default:
        return 0;
    }
  }

  IconData _getSelectedIcon() {
    switch (_selectedIndex) {
      case 0:
        return Icons.person_outline;
      case 1:
        return Icons.play_arrow;
      case 2:
        return Icons.home;
      default:
        return Icons.home;
    }
  }

  Widget _buildNavItem(int index, IconData icon) {
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: Container(
        width: 60,
        height: 60,
        padding: const EdgeInsets.all(10),

        color: Colors.transparent,
        child: Icon(
          icon,

          color: _selectedIndex == index ? Colors.transparent : Colors.grey,
          size: 30,
        ),
      ),
    );
  }
}
