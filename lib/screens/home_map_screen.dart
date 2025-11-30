import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late MapController _mapController;
  LatLng _currentPosition = LatLng(48.117266, -1.6777926); // Rennes par défaut
  String _selectedCategory = "Bars";

  final Map<String, LatLng> _cities = {
    "Rennes": LatLng(48.117266, -1.6777926),
    "Paris": LatLng(48.8566, 2.3522),
    "Lyon": LatLng(45.764043, 4.835659),
    "Marseille": LatLng(43.296482, 5.36978),
  };

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  void _selectCity() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Choisir une ville",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: _cities.entries
                  .map((entry) => ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentPosition = entry.value;
                    _mapController.move(_currentPosition, 13);
                  });
                  Navigator.pop(context);
                },
                child: Text(entry.key),
              ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _selectCategory() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Choisir une catégorie",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: ["Bars", "Restaurants", "Musées", "Parcs"]
                  .map((category) => ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedCategory = category;
                  });
                  Navigator.pop(context);
                },
                child: Text(category),
              ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showList() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 300,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Liste de $_selectedCategory à ${_cities.entries.firstWhere((e) => e.value == _currentPosition).key}",
              style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: 10,
                itemBuilder: (context, index) => ListTile(
                  title: Text("$_selectedCategory #${index + 1}"),
                  leading: const Icon(Icons.place),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStats() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: const [
            Text(
              "Statistiques",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text("Statistiques des visites, des lieux sélectionnés etc."),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.example.visitelecoin',
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: "city",
                  onPressed: _selectCity,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.location_city),
                  tooltip: "Choisir une ville",
                ),
                FloatingActionButton(
                  heroTag: "category",
                  onPressed: _selectCategory,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.category),
                  tooltip: "Sélectionner catégorie",
                ),
                FloatingActionButton(
                  heroTag: "list",
                  onPressed: _showList,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.list),
                  tooltip: "Voir la liste",
                ),
                FloatingActionButton(
                  heroTag: "stats",
                  onPressed: _showStats,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.bar_chart),
                  tooltip: "Statistiques",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
