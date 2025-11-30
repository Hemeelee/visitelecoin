import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late MapController _mapController;
  LatLng _currentPosition = LatLng(48.117266, -1.6777926); // Rennes par défaut
  String _selectedCategory = "Bars";

  Map<String, LatLng> _cities = {};
  bool _isLoadingCities = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadCities();
  }

  // Charger les villes depuis Firestore
  Future<void> _loadCities() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('cities').get();
      final Map<String, LatLng> citiesMap = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String;
        final lat = data['latitude'] as double;
        final lng = data['longitude'] as double;
        citiesMap[name] = LatLng(lat, lng);
      }
      setState(() {
        _cities = citiesMap;
        _isLoadingCities = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCities = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du chargement des villes : $e')),
      );
    }
  }

  void _selectCity() {
    if (_isLoadingCities) return;
    if (_cities.isEmpty) return;

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
    if (_cities.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        height: 300,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Liste de $_selectedCategory à ${_cities.entries.firstWhere((e) => e.value == _currentPosition).key}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: 10, // Pour l'instant fixe
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
