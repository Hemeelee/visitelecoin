# VisiteLeCoin

![Logo](./logo.jpeg)

# Ecrans:
- Page de connexion : connexion possible après création d'utilisateur.
- Page de création de comptes : La création de compte fonctionne -> ajout en bd.
- Page avec la carte. 

# BackEnd
- Open Street Map
- Firebase Auth + Firestore Database


# Fonctionnalités :


1. Ecran de Connexion:
Possibilité de se connecter avec une adresse mail et un mot de passe (utilisation de l'authentification de FireBase, ne fonctionne que avec un téléphone simulé)

2. Ecran de Création de Compte:
Création de compte: Nom, Prénom, Date de Naissance, Adresse Mail, Mot de Passe


3. Ecran Page d'accueil:
- Affichage de la carte
- Nom de la ville en haut de l'écran avec un bouton pour rechercher une ville
- Possibilité de se déconnecter du profil (données en fonction de chaque utilisateurs) (Bouton déconnexion en haut à gauche)
- 3 boutons de sélections (en bas) : un pour les villes, un pour la catégorie et un pour la liste des lieux de la catégorie sélectionnée.
- Bouton "Villes" : affichage des villes en fonctions des données en base, permet de recentrer sur la ville à la sélection.
- Bouton "Catégories" : permet de choisir une catégorie entre bars, musées, parcs, restaurants), cela affiche les points en fonction de la catégorie choisie.
- Bouton "Liste" : affichage de l'ensemble des lieux de la catégorie, il est possible de cocher directement un lieu visité via cette liste, ou alors de rechercher un lieu avec la barre de recherche.

4. Ecran de Statistiques: (bouton en haut à droite)

- Récapitulatif de l'ensemble des lieux visités en fonction de la ville (Globale ou par ville)
- Barres de progression des différentes catégories


# Ce qu'on aimerait ajouter :

- Fusionner les marqueurs qui sont trop proches entre eux et en afficher un seul avec une liste des lieux
- Un système de récompense, par exemple : un badge pour les 10% de complétion d'une ville, un pour 100% etc...
- Une dimension sociale pour comparer ses stats avec ses amis
- un mode nuit
