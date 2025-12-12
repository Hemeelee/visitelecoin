import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StatsScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final Map<String, Map<String, int>> totalPlacesByCityAndCategory;
  final String currentCity;

  const StatsScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.totalPlacesByCityAndCategory,
    required this.currentCity,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _selectedCity = "Toutes les villes";
  List<String> _availableCities = ["Toutes les villes"];

  @override
  void initState() {
    super.initState();
    _selectedCity = widget.currentCity;

    // Récupérer toutes les villes disponibles
    _availableCities = ["Toutes les villes", ...widget.totalPlacesByCityAndCategory.keys.toList()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green, // Couleur de fond du Dropdown
                  borderRadius: BorderRadius.circular(8),
                ),
              child: DropdownButton<String>(
                value: _selectedCity,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                dropdownColor: Colors.green,
                style: const TextStyle(color: Colors.white),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCity = newValue!;
                  });
                },
                items: _availableCities.map<DropdownMenuItem<String>>((String city) {
                  return DropdownMenuItem<String>(
                    value: city,
                    child: Text(
                      city,
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          )],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('visitedPlaces')
            .where('userId', isEqualTo: widget.userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Aucune donnée disponible'));
          }

          final allVisitedPlaces = snapshot.data!.docs;

          // Calculer les statistiques pour toutes les villes
          final globalStats = _calculateGlobalStats(allVisitedPlaces);

          // Filtrer par ville si nécessaire
          final filteredPlaces = _selectedCity == "Toutes les villes"
              ? allVisitedPlaces
              : allVisitedPlaces.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data.containsKey('city') && data['city'] != null) {
              final city = data['city'].toString();
              return city == _selectedCity;
            }
            return false; // Exclure les lieux sans ville
          }).toList();

          // Calculer les statistiques pour la ville sélectionnée
          final cityStats = _calculateCityStats(filteredPlaces);

          return _buildStatsContent(
            visitedPlaces: filteredPlaces,
            globalStats: globalStats,
            cityStats: cityStats,
            allVisitedPlacesCount: allVisitedPlaces.length,
            selectedCityVisitedCount: filteredPlaces.length,
          );
        },
      ),
    );
  }

  Map<String, dynamic> _calculateGlobalStats(List<QueryDocumentSnapshot> places) {
    final stats = <String, int>{};
    final cities = <String, int>{};
    int totalVisited = places.length;

    for (var place in places) {
      final data = place.data() as Map<String, dynamic>;
      final category = data['category']?.toString() ?? 'Non catégorisé';
      stats[category] = (stats[category] ?? 0) + 1;

      final city = data['city']?.toString() ?? 'Inconnue';
      cities[city] = (cities[city] ?? 0) + 1;
    }

    return {
      'categories': stats,
      'cities': cities,
      'total': totalVisited,
      'cityCount': cities.length,
    };
  }

  Map<String, dynamic> _calculateCityStats(List<QueryDocumentSnapshot> places) {
    final stats = <String, int>{};
    int totalVisited = places.length;

    for (var place in places) {
      final data = place.data() as Map<String, dynamic>;
      final category = data['category']?.toString() ?? 'Non catégorisé';
      stats[category] = (stats[category] ?? 0) + 1;
    }

    return {
      'categories': stats,
      'total': totalVisited,
    };
  }

  Widget _buildStatsContent({
    required List<QueryDocumentSnapshot> visitedPlaces,
    required Map<String, dynamic> globalStats,
    required Map<String, dynamic> cityStats,
    required int allVisitedPlacesCount,
    required int selectedCityVisitedCount,
  }) {
    // Calculer les statistiques par catégorie
    final completionStats = <String, Map<String, dynamic>>{};
    final categories = ['Bars', 'Restaurants', 'Musées', 'Parcs'];

    for (var category in categories) {
      final visitedCount = _selectedCity == "Toutes les villes"
          ? (globalStats['categories'] as Map<String, int>)[category] ?? 0
          : (cityStats['categories'] as Map<String, int>)[category] ?? 0;

      int totalInArea = 0;
      bool hasRealData = false;

      if (_selectedCity == "Toutes les villes") {
        // Pour "Toutes les villes", on montre la progression globale
        totalInArea = _calculateTotalForAllCities(category);
        hasRealData = totalInArea > 0;
      } else {
        // Pour une ville spécifique
        totalInArea = widget.totalPlacesByCityAndCategory[_selectedCity]?[category] ?? 0;
        hasRealData = totalInArea > 0 && widget.totalPlacesByCityAndCategory.containsKey(_selectedCity);

        // Si pas de données réelles, utiliser une estimation
        if (!hasRealData) {
          totalInArea = _getEstimatedTotalForCategory(category, _selectedCity);
        }
      }

      final percentage = totalInArea > 0
          ? (visitedCount / totalInArea * 100).round()
          : 0;

      completionStats[category] = {
        'visited': visitedCount,
        'total': totalInArea,
        'percentage': percentage,
        'hasRealData': hasRealData,
      };
    }

    // Trier par pourcentage décroissant
    final sortedEntries = completionStats.entries.toList()
      ..sort((a, b) => b.value['percentage'].compareTo(a.value['percentage']));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // En-tête
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.green.shade100,
                      child: Icon(
                        _selectedCity == "Toutes les villes"
                            ? Icons.public
                            : Icons.location_city,
                        size: 30,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _selectedCity == "Toutes les villes"
                                    ? Icons.public
                                    : Icons.place,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _selectedCity == "Toutes les villes"
                                      ? 'Toutes les villes explorées'
                                      : 'Statistiques pour $_selectedCity',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Statistiques clés
                if (_selectedCity == "Toutes les villes") ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard(
                        value: globalStats['total'].toString(),
                        label: 'Lieux visités',
                        color: Colors.green,
                        icon: Icons.place,
                      ),
                      _buildStatCard(
                        value: (globalStats['categories'] as Map<String, int>).length.toString(),
                        label: 'Catégories',
                        color: Colors.blue,
                        icon: Icons.category,
                      ),
                      _buildStatCard(
                        value: globalStats['cityCount'].toString(),
                        label: 'Villes',
                        color: Colors.orange,
                        icon: Icons.location_city,
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCard(
                        value: selectedCityVisitedCount.toString(),
                        label: 'Lieux visités',
                        color: Colors.green,
                        icon: Icons.place,
                      ),
                      _buildStatCard(
                        value: (cityStats['categories'] as Map<String, int>).length.toString(),
                        label: 'Catégories',
                        color: Colors.blue,
                        icon: Icons.category,
                      ),
                      _buildStatCard(
                        value: _getCityCompletionPercentage(_selectedCity).toString(),
                        label: 'Progression',
                        color: Colors.purple,
                        icon: Icons.trending_up,
                        isPercentage: true,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_getExploredCategoriesCount(_selectedCity)} catégories explorées sur 4',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Vue par ville (uniquement pour "Toutes les villes")
        if (_selectedCity == "Toutes les villes" && widget.totalPlacesByCityAndCategory.isNotEmpty) ...[
          const Text(
            'Progression par ville :',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          Column(
            children: widget.totalPlacesByCityAndCategory.entries.map((entry) {
              final city = entry.key;
              final cityData = entry.value;

              // Compter les lieux visités pour cette ville
              final cityPlaces = visitedPlaces.where((place) {
                final data = place.data() as Map<String, dynamic>;
                final placeCity = data['city'] as String?;
                return placeCity == city;
              }).toList();

              final cityVisitedCount = cityPlaces.length;

              // Calculer le total pour cette ville
              int cityTotalPlaces = 0;
              for (var category in ['Bars', 'Restaurants', 'Musées', 'Parcs']) {
                cityTotalPlaces += cityData[category] ?? 0;
              }

              final cityPercentage = cityTotalPlaces > 0
                  ? (cityVisitedCount / cityTotalPlaces * 100).round()
                  : 0;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCity = city;
                  });
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: _selectedCity == city ? Colors.green.shade50 : null,
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.location_city, color: Colors.blue),
                    ),
                    title: Text(city),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: cityTotalPlaces > 0 ? cityVisitedCount / cityTotalPlaces : 0,
                          backgroundColor: Colors.grey[200],
                          color: _getProgressColor(cityPercentage),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$cityVisitedCount/$cityTotalPlaces lieux ($cityPercentage%)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Progression par catégorie
        const Text(
          'Progression par catégorie :',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        if (sortedEntries.isEmpty || (selectedCityVisitedCount == 0 && _selectedCity != "Toutes les villes"))
          _buildEmptyState()
        else
          ...sortedEntries.map((entry) {
            final category = entry.key;
            final visited = entry.value['visited'] as int;
            final total = entry.value['total'] as int;
            final percentage = entry.value['percentage'] as int;
            final hasRealData = entry.value['hasRealData'] as bool;

            return _buildCategoryCard(
              category: category,
              visited: visited,
              total: total,
              percentage: percentage,
              hasRealData: hasRealData,
            );
          }).toList(),

        // Derniers lieux visités
        if (visitedPlaces.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Derniers lieux visités :',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          ...visitedPlaces.take(5).map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = doc['visitedAt']?.toDate();
            final city = data['city'] as String? ?? 'Ville inconnue';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: _getCategoryIcon(data['category']),
                title: Text(data['name']),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedCity == "Toutes les villes")
                      Text(
                        city,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    if (date != null)
                      Text(
                        'Visité le ${_formatDate(date)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
                trailing: _selectedCity == "Toutes les villes"
                    ? null
                    : const Icon(Icons.check, color: Colors.green, size: 16),
              ),
            );
          }).toList(),

          if (visitedPlaces.length > 5)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '... et ${visitedPlaces.length - 5} autres lieux',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
        ],
      ],
    );
  }

  // Fonctions utilitaires
  int _calculateTotalForAllCities(String category) {
    int total = 0;
    for (var cityData in widget.totalPlacesByCityAndCategory.values) {
      total += cityData[category] ?? 0;
    }
    return total;
  }

  int _getEstimatedTotalForCategory(String category, String city) {
    // Estimation basée sur la taille de la ville
    switch (category) {
      case 'Bars':
        return city.contains('Paris') ? 500 :
        city.contains('Lyon') ? 200 :
        city.contains('Marseille') ? 150 : 50;
      case 'Restaurants':
        return city.contains('Paris') ? 1000 :
        city.contains('Lyon') ? 400 :
        city.contains('Marseille') ? 300 : 100;
      case 'Musées':
        return city.contains('Paris') ? 100 :
        city.contains('Lyon') ? 30 :
        city.contains('Marseille') ? 20 : 10;
      case 'Parcs':
        return city.contains('Paris') ? 50 :
        city.contains('Lyon') ? 20 :
        city.contains('Marseille') ? 15 : 10;
      default:
        return 0;
    }
  }

  int _getCityCompletionPercentage(String city) {
    if (!widget.totalPlacesByCityAndCategory.containsKey(city)) {
      return 0;
    }

    final cityData = widget.totalPlacesByCityAndCategory[city]!;
    int totalPlaces = 0;

    for (var category in ['Bars', 'Restaurants', 'Musées', 'Parcs']) {
      totalPlaces += cityData[category] ?? 0;
    }

    if (totalPlaces == 0) return 0;

    // Dans la vraie version, on compterait les lieux visités
    // Pour l'instant, on retourne un placeholder
    return 25;
  }

  int _getExploredCategoriesCount(String city) {
    int count = 0;
    for (var category in ['Bars', 'Restaurants', 'Musées', 'Parcs']) {
      if (widget.totalPlacesByCityAndCategory[city]?[category] != null) {
        count++;
      }
    }
    return count;
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Icon(
            _selectedCity == "Toutes les villes"
                ? Icons.explore
                : Icons.location_city,
            size: 60,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _selectedCity == "Toutes les villes"
                ? 'Explorez des lieux dans différentes villes pour voir vos statistiques !'
                : 'Aucun lieu visité à $_selectedCity\n\nVisitez des lieux dans cette ville pour commencer vos statistiques.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (_selectedCity != "Toutes les villes")
            ElevatedButton.icon(
              icon: const Icon(Icons.explore),
              label: const Text('Explorer cette ville'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String category,
    required int visited,
    required int total,
    required int percentage,
    required bool hasRealData,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _getCategoryIcon(category),
                    const SizedBox(width: 8),
                    Text(
                      category,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (!hasRealData && _selectedCity != "Toutes les villes")
                      Tooltip(
                        message: 'Données estimées',
                        child: const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('$percentage%'),
                      backgroundColor: _getProgressColor(percentage),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total > 0 ? visited / total : 0,
              backgroundColor: Colors.grey[200],
              color: _getCategoryColor(category),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedCity == "Toutes les villes"
                      ? '$visited lieux visités'
                      : '$visited sur $total lieux',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  _selectedCity == "Toutes les villes"
                      ? '$visited'
                      : '$visited/$total',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (!hasRealData && _selectedCity != "Toutes les villes")
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Explorez cette catégorie pour des données précises',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
    bool isPercentage = false,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(
                  isPercentage ? '$value%' : value,
                  style: TextStyle(
                    fontSize: isPercentage ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Color _getProgressColor(int percentage) {
    if (percentage >= 75) return Colors.green;
    if (percentage >= 50) return Colors.orange;
    if (percentage >= 25) return Colors.blue;
    return Colors.grey;
  }

  Icon _getCategoryIcon(String category) {
    switch (category) {
      case 'Bars':
        return const Icon(Icons.local_bar, color: Colors.blue, size: 20);
      case 'Restaurants':
        return const Icon(Icons.restaurant, color: Colors.red, size: 20);
      case 'Musées':
        return const Icon(Icons.museum, color: Colors.purple, size: 20);
      case 'Parcs':
        return const Icon(Icons.park, color: Colors.green, size: 20);
      default:
        return const Icon(Icons.place, color: Colors.grey, size: 20);
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Bars':
        return Colors.blue;
      case 'Restaurants':
        return Colors.red;
      case 'Musées':
        return Colors.purple;
      case 'Parcs':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}