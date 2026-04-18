# Roadmap - Logiciel de Gestion d'École

Ce document suit l'évolution du projet et planifie les prochaines étapes de développement.

## ✅ Réalisé (Phase Initial & Authentification)
- [x] Structure de base du projet (Flutter/Dart).
- [x] Gestion de la base de données SQLite avec migrations.
- [x] Système d'authentification robuste (SHA-256 + Sel).
- [x] Authentification à deux facteurs (2FA/TOTP).
- [x] Module de gestion des élèves (Inscription, Profils).
- [x] Module de gestion des notes et bulletins (Brouillon, Verrouillage).
- [x] Gestion des types de notes (Devoir, Composition).
- [x] Import/Export Excel pour les notes.
- [x] Audit Trail (Journal d'audit pour les transactions).
- [x] Paramètres généraux de l'établissement.

## 🚀 En cours : Module Examens Blancs
- [ ] **Écran Dédié** : Créer `mock_exams_page.dart` pour la gestion isolée des sessions d'examens.
- [ ] **Navigation** : Ajouter une entrée "Examens Blancs" dans la Sidebar.
- [ ] **Saisie Groupée** : Interface optimisée pour la saisie massive des notes par session (Examen Blanc 1, 2, etc.).
- [ ] **Logique de Calcul** : Moyenne spécifique à l'examen blanc, calculée séparément du trimestre.
- [ ] **Exportation** : Génération de palmarès PDF/Excel dédiés, sans impact sur le bulletin standard.
- [ ] **Persistance** : Amélioration de la persistance des appréciations automatiques.

## 📅 Prochaines Étapes (Priorité Haute)
- [x] **Suivi de la Discipline** : Absences, retards, sanctions et avertissements.
- [x] **Gestion du Personnel** : Présences, absences, attribution des classes.
- [x] **Statistiques Avancées** : Tableaux de bord visuels, taux de réussite par matière.
- [x] **Paiements & Finances** : Suivi des frais de scolarité, alertes impayés, rapports financiers.

## 🛠️ Futur (Priorité Basse / Optionnel)
- [x] **Gestion de la Bibliothèque** : Emprunts, retours, inventaire.
- [x] **Gestion du Matériel** : Stock de fournitures scolaires.
- [x] **Réinscriptions** : Processus automatisé pour les années suivantes.

---
*Dernière mise à jour : 18 Avril 2026*
