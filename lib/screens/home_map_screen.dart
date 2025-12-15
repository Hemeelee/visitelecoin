import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:visitelecoin/screens/stats_screen.dart';
import 'package:visitelecoin/screens/login_screen.dart';

class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late MapController _mapController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;

  LatLng _currentPosition = LatLng(48.117266, -1.6777926); // Rennes
  String _selectedCategory = "Bars";
  String _currentCityName = "Rennes";
  double _currentCityLat = 0;
  double _currentCityLon = 0;

  Map<String, LatLng> _cities = {};
  bool _loadingCities = true;

  List<Map<String, dynamic>> _results = [];
  List<Marker> _markers = [];
  bool _loading = false;

  //stats
  Map<String, int> _visitedStats = {};
  Set<String> _visitedPlaces = {};
  bool _loadingVisited = false;

  // Stocks les totaux par ville et par catégorie
  Map<String, Map<String, int>> _totalPlacesByCityAndCategory = {};
  bool _initialLoadingComplete = false;

  // Mappage des catégories avec leurs tags OSM
  final Map<String, Map<String, dynamic>> _categories = {
    "Bars": {
      "tag": "\"amenity\"=\"bar\"",
      "icon": Icons.local_bar,
      "color": Colors.blue,
    },
    "Restaurants": {
      "tag": "\"amenity\"=\"restaurant\"",
      "icon": Icons.restaurant,
      "color": Colors.red,
    },
    "Musées": {
      "tag": "\"tourism\"=\"museum\"",
      "icon": Icons.museum,
      "color": Colors.purple,
    },
    "Parcs": {
      "tag": "\"leisure\"=\"park\"",
      "icon": Icons.park,
      "color": Colors.deepOrangeAccent,
    },
  };

  final Map<String, String> osmHeaders = {
    "User-Agent": "VisiteLeCoin/1.0 (contact: emilie.huard747@gmail.com)"
  };

  final String mapTilerKey = "323qSV9Uj2AXSUjRLRuR";

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _checkCurrentUser();
  }

  Future<void> _checkCurrentUser() async {
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      await _loadCities();
      await _loadVisitedPlaces();
      await _loadStats();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadAllCategoriesForCity();
        _searchAmenities();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logout();
      });
    }
  }

  Future<void> _loadAllCategoriesForCity() async {
    if (_currentUser == null) return;

    final String defaultCity = "Rennes";

    // Initialise la map pour cette ville
    if (!_totalPlacesByCityAndCategory.containsKey(defaultCity)) {
      _totalPlacesByCityAndCategory[defaultCity] = {
        'Bars': 0,
        'Restaurants': 0,
        'Musées': 0,
        'Parcs': 0,
      };
    }

    for (var category in _categories.keys) {
      await _loadCategoryTotalForCity(defaultCity, category);
    }

    setState(() {
      _initialLoadingComplete = true;
    });
  }

  Future<void> _loadCategoryTotalForCity(String city, String category) async {
    try {
      final categoryConfig = _categories[category] ?? _categories["Bars"]!;
      String tag = categoryConfig["tag"] as String;

      final nominatimUrl = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=$city&format=json&limit=1",
      );

      final nominatimRes = await http.get(
        nominatimUrl,
        headers: osmHeaders,
      );

      if (nominatimRes.statusCode != 200) return;

      final cityData = jsonDecode(nominatimRes.body)[0];
      _currentCityLat = double.parse(cityData["lat"]);
      _currentCityLon = double.parse(cityData["lon"]);

      final overpassQuery = """
    [out:json];
    (
      node[$tag](around:5000, $_currentCityLat, $_currentCityLon);
      way[$tag](around:5000, $_currentCityLat, $_currentCityLon);
      relation[$tag](around:5000, $_currentCityLat, $_currentCityLon);
    );
    out center;
    """;

      final overpassRes = await http.post(
        Uri.parse("https://overpass-api.de/api/interpreter"),
        headers: osmHeaders,
        body: {"data": overpassQuery},
      );

      if (overpassRes.statusCode != 200) return;

      final data = jsonDecode(overpassRes.body);
      List<Map<String, dynamic>> elements =
      List<Map<String, dynamic>>.from(data["elements"]);

      final filteredElements = elements.where((item) {
        return item["tags"]?["name"] != null &&
            item["tags"]["name"].toString().trim().isNotEmpty;
      }).toList();

      if (mounted) {
        setState(() {
          _totalPlacesByCityAndCategory[city]![category] = filteredElements.length;
        });
      }
    } catch (e) {
      print("Erreur lors du chargement de $category pour $city: $e");
    }
  }

  Future<void> _loadCities() async {
    final snapshot = await FirebaseFirestore.instance.collection('cities').get();

    final Map<String, LatLng> cities = {};
    for (var doc in snapshot.docs) {
      cities[doc['name']] = LatLng(doc['latitude'], doc['longitude']);
    }

    setState(() {
      _cities = cities;
      _loadingCities = false;
    });
  }

  // Charge les lieux visités par l'utilisateur courant
  Future<void> _loadVisitedPlaces() async {
    if (_currentUser == null) return;

    setState(() => _loadingVisited = true);

    final snapshot = await FirebaseFirestore.instance
        .collection('visitedPlaces')
        .where('userId', isEqualTo: _currentUser!.uid)
        .get();

    final visitedIds = <String>{};
    for (var doc in snapshot.docs) {
      visitedIds.add(doc['placeId']);
    }

    setState(() {
      _visitedPlaces = visitedIds;
      _loadingVisited = false;
    });

    if (_results.isNotEmpty) {
      _createMarkers();
    }
  }

  // Charge les statistiques par catégorie
  Future<void> _loadStats() async {
    if (_currentUser == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('visitedPlaces')
        .where('userId', isEqualTo: _currentUser!.uid)
        .get();

    final stats = <String, int>{};
    for (var doc in snapshot.docs) {
      final category = doc['category'] ?? 'Non catégorisé';
      stats[category] = (stats[category] ?? 0) + 1;
    }

    setState(() {
      _visitedStats = stats;
    });
  }

  // Marque un lieu comme visité
  Future<void> _markAsVisited(Map<String, dynamic> place) async {
    if (_currentUser == null) return;

    final placeId = place['id'].toString();
    final placeName = place['tags']['name'] ?? 'Lieu sans nom';
    final placeCategory = _selectedCategory;

    bool isCurrentlyVisited = _visitedPlaces.contains(placeId);

    setState(() {
      if (isCurrentlyVisited) {
        _visitedPlaces.remove(placeId);
        if (_visitedStats.containsKey(placeCategory)) {
          _visitedStats[placeCategory] = _visitedStats[placeCategory]! - 1;
          if (_visitedStats[placeCategory]! <= 0) {
            _visitedStats.remove(placeCategory);
          }
        }
      } else {
        _visitedPlaces.add(placeId);
        _visitedStats[placeCategory] = (_visitedStats[placeCategory] ?? 0) + 1;
      }
    });

    // Met à jour Firebase
    if (isCurrentlyVisited) {
      await FirebaseFirestore.instance
          .collection('visitedPlaces')
          .where('placeId', isEqualTo: placeId)
          .where('userId', isEqualTo: _currentUser!.uid)
          .get()
          .then((querySnapshot) {
        for (var doc in querySnapshot.docs) {
          doc.reference.delete();
        }
      });
    } else {
      await FirebaseFirestore.instance.collection('visitedPlaces').add({
        'placeId': placeId,
        'name': placeName,
        'category': placeCategory,
        'latitude': place['lat'],
        'longitude': place['lon'],
        'userId': _currentUser!.uid,
        'userEmail': _currentUser!.email,
        'city': _currentCityName, // Stocker la ville
        'visitedAt': FieldValue.serverTimestamp(),
      });
      FirebaseFirestore.instance.collection('cities').add({
        'name' : _currentCityName,
        'latitude' : _currentCityLat,
        'longitude' : _currentCityLon,
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _createMarkers();
      }
    });
  }

  Future<void> _searchAmenities() async {
    if (_currentUser == null) return;

    setState(() {
      _loading = true;
      _results = [];
      _markers = [];
    });

    final String city = _currentCityName;

    if (!_totalPlacesByCityAndCategory.containsKey(city)) {
      _totalPlacesByCityAndCategory[city] = {
        'Bars': 0,
        'Restaurants': 0,
        'Musées': 0,
        'Parcs': 0,
      };
    }

    final categoryConfig = _categories[_selectedCategory] ?? _categories["Bars"]!;
    String tag = categoryConfig["tag"] as String;

    final nominatimUrl = Uri.parse(
      "https://nominatim.openstreetmap.org/search?q=$city&format=json&limit=1",
    );

    final nominatimRes = await http.get(
      nominatimUrl,
      headers: osmHeaders,
    );

    if (nominatimRes.statusCode != 200) {
      setState(() => _loading = false);
      return;
    }

    final cityData = jsonDecode(nominatimRes.body)[0];
    final double lat = double.parse(cityData["lat"]);
    final double lon = double.parse(cityData["lon"]);

    // Définir la position actuelle à la nouvelle ville
    _currentPosition = LatLng(lat, lon);
    _mapController.move(_currentPosition, 13);

    final overpassQuery = """
  [out:json];
  (
    node[$tag](around:5000, $lat, $lon);
    way[$tag](around:5000, $lat, $lon);
    relation[$tag](around:5000, $lat, $lon);
  );
  out center;
  """;

    final overpassRes = await http.post(
      Uri.parse("https://overpass-api.de/api/interpreter"),
      headers: osmHeaders,
      body: {"data": overpassQuery},
    );

    if (overpassRes.statusCode != 200) {
      setState(() => _loading = false);
      return;
    }

    final data = jsonDecode(overpassRes.body);
    List<Map<String, dynamic>> elements =
    List<Map<String, dynamic>>.from(data["elements"]);

    final filteredElements = elements.where((item) {
      return item["tags"]?["name"] != null &&
          item["tags"]["name"].toString().trim().isNotEmpty;
    }).toList();

    final processedElements = filteredElements.map((item) {
      if (item["type"] == "node") {
        return {
          ...item,
          "lat": item["lat"]?.toDouble(),
          "lon": item["lon"]?.toDouble(),
        };
      } else if (item["center"] != null) {
        return {
          ...item,
          "lat": item["center"]["lat"]?.toDouble(),
          "lon": item["center"]["lon"]?.toDouble(),
        };
      }
      return item;
    }).where((item) {
      return item["lat"] != null && item["lon"] != null;
    }).toList();

    // Stocke le total pour cette ville et catégorie
    setState(() {
      _results = List<Map<String, dynamic>>.from(processedElements);
      _totalPlacesByCityAndCategory[_currentCityName]![_selectedCategory] = _results.length;
      _loading = false;
    });

    _createMarkers();

    if (_markers.isNotEmpty) {
      _mapController.move(_markers[0].point, 14);
    }
  }

  List<Map<String, dynamic>> filterResults(String query) {
    if (query.isEmpty) return List.from(_results);

    final filtered = _results.where((item) {
      final name = item['tags']['name']?.toString().toLowerCase() ?? '';
      return name.contains(query.toLowerCase());
    }).toList();

    return filtered;
  }

  void _createMarkers() {
    final categoryConfig = _categories[_selectedCategory] ?? _categories["Bars"]!;
    final Color categoryColor = categoryConfig["color"] as Color;

    final markers = _results.where((item) {
      final hasLat = item["lat"] != null;
      final hasLon = item["lon"] != null;
      return hasLat && hasLon;
    }).map((item) {
      final lat = item["lat"]?.toDouble();
      final lon = item["lon"]?.toDouble();

      final placeId = item['id'].toString();
      final isVisited = _visitedPlaces.contains(placeId);

      return Marker(
        width: 40,
        height: 40,
        point: LatLng(lat!, lon!),
        child: GestureDetector(
          onTap: () => _showPlaceDetails(item),
          child: Stack(
            children: [
              Icon(
                Icons.location_pin,
                color: isVisited ? Colors.green : categoryColor,
                size: 40,
              ),
              if (isVisited)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }).whereType<Marker>().toList();

    setState(() {
      _markers = markers;
    });
  }

  void _showPlaceDetails(Map<String, dynamic> place) {
    final placeId = place['id'].toString();
    final isVisited = _visitedPlaces.contains(placeId);
    final categoryConfig = _categories[_selectedCategory] ?? _categories["Bars"]!;
    final Color categoryColor = categoryConfig["color"] as Color;
    final IconData categoryIcon = categoryConfig["icon"] as IconData;

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  categoryIcon,
                  color: categoryColor,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    place["tags"]["name"] ?? "Lieu sans nom",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isVisited)
                  const Icon(Icons.check_circle, color: Colors.green, size: 24),
              ],
            ),
            const SizedBox(height: 16),

            if (place["tags"]["addr:street"] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${place["tags"]["addr:street"]}${place["tags"]["addr:city"] != null ? ", ${place["tags"]["addr:city"]}" : ""}",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

            if (place["tags"]["opening_hours"] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.schedule, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(place["tags"]["opening_hours"]),
                    ),
                  ],
                ),
              ),

            if (place["tags"]["phone"] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.phone, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(place["tags"]["phone"]),
                    ),
                  ],
                ),
              ),

            if (place["tags"]["website"] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        place["tags"]["website"],
                        style: TextStyle(color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(isVisited ? Icons.check_circle : Icons.place),
              label: Text(isVisited ? 'Déjà visité' : 'Marquer comme visité'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isVisited ? Colors.green : categoryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.pop(context);
                _markAsVisited(place);
              },
            ),

            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Fermer'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _selectCity() {
    if (_loadingCities || _currentUser == null) return;

    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: _cities.entries.map((entry) {
          return ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(entry.key),
            trailing: _currentCityName == entry.key
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              setState(() {
                _currentPosition = entry.value;
                _currentCityName = entry.key;
              });
              Navigator.pop(context);
              _searchAmenities();
            },
          );
        }).toList(),
      ),
    );
  }

  void _selectCategory() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: _categories.keys.map((key) {
          final category = _categories[key]!;
          final visitedCount = _visitedStats[key] ?? 0;

          return ListTile(
            leading: Icon(category["icon"] as IconData, color: category["color"] as Color),
            title: Text(key),
            trailing: _selectedCategory == key
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              setState(() {
                _selectedCategory = key;
              });
              Navigator.pop(context);
              _searchAmenities();
            },
          );
        }).toList(),
      ),
    );
  }

  void _showList() {
    final categoryConfig = _categories[_selectedCategory] ?? _categories["Bars"]!;
    final Color categoryColor = categoryConfig["color"] as Color;


    TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredResults = List.from(_results);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateLocal) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.1),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                categoryConfig["icon"] as IconData,
                                color: categoryColor,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedCategory,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: categoryColor,
                                ),
                              ),
                            ],
                          ),
                          Chip(
                            label: Text('${filteredResults.length} résultats'),
                            backgroundColor: categoryColor,
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Rechercher un lieu...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (value) {
                          setStateLocal(() {
                            filteredResults = filterResults(value);
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredResults.length,
                        itemBuilder: (_, i) {
                          final item = filteredResults[i];
                          final placeId = item['id'].toString();
                          final isVisited = _visitedPlaces.contains(placeId);

                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isVisited ? Colors.green : categoryColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                categoryConfig["icon"] as IconData,
                                color: isVisited ? Colors.white : categoryColor,
                              ),
                            ),
                            title: Text(
                              item["tags"]["name"],
                              style: TextStyle(
                                fontWeight: isVisited ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item["tags"]["addr:street"] != null)
                                  Text(
                                    "${item["tags"]["addr:street"]}",
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Checkbox(
                              value: isVisited,
                              onChanged: (bool? value) async {
                                setStateLocal(() {});
                                await _markAsVisited(item);
                                setStateLocal(() {});
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              activeColor: Colors.green,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _mapController.move(
                                LatLng(
                                  item["lat"]?.toDouble() ?? 0,
                                  item["lon"]?.toDouble() ?? 0,
                                ),
                                16,
                              );
                              _showPlaceDetails(item);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _navigateToStats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsScreen(
          userId: _currentUser!.uid,
          userName: _currentUser!.email?.split('@').first ?? 'Utilisateur',
          totalPlacesByCityAndCategory: _totalPlacesByCityAndCategory,
          currentCity: _currentCityName,
        ),
      ),
    );
  }

  final TextEditingController _citySearchController = TextEditingController();


  void _openCitySearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _citySearchController,
              decoration: const InputDecoration(
                hintText: 'Rechercher une ville...',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (value) async {
                if (value.isEmpty) return;
                await _searchCityByName(value);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _searchCityByName(String city) async {
    final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=$city&format=json&limit=1");
    final response = await http.get(url, headers: osmHeaders);
    if (response.statusCode != 200) return;


    final List data = jsonDecode(response.body);
    if (data.isEmpty) return;


    final double lat = double.parse(data[0]["lat"]);
    final double lon = double.parse(data[0]["lon"]);


    setState(() {
      _currentCityName = city;
      _currentPosition = LatLng(lat, lon);
      //_loadCategoryTotalForCity(_currentCityName,_selectedCategory);
    });


    _mapController.move(_currentPosition, 13);
    await _searchAmenities();
  }

  Future<void> _logout() async {
    await _auth.signOut();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13,
              onTap: (_, __) {
                if (ModalRoute.of(context)?.isCurrent != true) {
                  Navigator.pop(context);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                "https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerKey",
                userAgentPackageName: 'com.visitelecoin.app',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),

          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: "logout",
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _logout,
                  child: const Icon(Icons.logout, color: Colors.black),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xCCFFFFFF),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nom de la ville
                      Flexible(
                        child: Text(
                          _currentCityName.isEmpty ? 'Aucune ville' : _currentCityName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Bouton de recherche
                      InkWell(
                        onTap: _openCitySearch,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.search, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                FloatingActionButton(
                  heroTag: "stats",
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: _navigateToStats,
                  child: const Icon(Icons.bar_chart, color: Colors.white),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xCCFFFFFF),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.location_city,
                    label: _currentCityName,
                    onPressed: _selectCity,
                  ),
                  _buildActionButton(
                    icon: Icons.category,
                    label: _selectedCategory,
                    onPressed: _selectCategory,
                  ),
                  _buildActionButton(
                    icon: Icons.list,
                    label: 'Liste',
                    onPressed: _showList,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: Colors.green,
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}