# Écran de réinscription (passage à l’année suivante)

## Décisions prises
- Réinscrire = **modifier l’élève existant** (mise à jour `academicYear` + `className` sur la même ligne).
- Mode = **par classe** (flux principal) + option **toute l’école** (mode batch).
- `Sous conditions` = **redouble par défaut**.

---

## Objectif
Permettre de faire passer les élèves vers l’année cible en mettant à jour leur `academicYear/className`, selon la décision (auto/manuel) et avec possibilité de corrections, puis appliquer en une seule opération.

## Principes UX
- Flux guidé + tableau éditable.
- Actions en masse + override individuel.
- Validation avant exécution.
- Journalisation (audit) de l’opération.

---

## Structure de l’écran

### 1) En-tête (contexte)
- **Année source** (auto = année courante)
- **Année cible** (sélection)
- **Mode**: `Par classe` / `Toute l’école`
- Indicateurs: `Élèves`, `À traiter`, `Prêts`, `Erreurs`
- Actions rapides:
  - `Archiver l’année source` (si nécessaire)
  - `Rafraîchir les décisions`

---

### 2) Sélection (mode "Par classe")
- Dropdown: **Classe source** (filtrée par année source)
- Aperçu: effectif, titulaire, niveau (si dispo)

### 2 bis) Sélection (mode "Toute l’école")
- Multi-sélection de classes source (ou “Toutes”)
- Résumé effectifs par classe

---

## 3) Règles de passage

### 3.1 Classe cible
- Dropdown: **Classe cible**
- Option: **Mapping automatique** (ex: `CP→CE1`, `CE1→CE2`…) + override

### 3.2 Source de décision
- `Mixte` (recommandé):
  - si décision bulletin saisie → utiliser
  - sinon → décision automatique (seuils/moyenne) si fin d’année (T3/S2)
- Options alternatives: `Manuelle seulement`, `Automatique seulement`

### 3.3 Interprétation (par défaut)
- `Admis` → destination = **classe cible**
- `Sous conditions` → destination = **classe de redoublement** (par défaut: même classe que source)
- `Redouble` → destination = **classe de redoublement** (même classe source)
- `Non décidé` → état = **à traiter** (bloquant si on veut appliquer)

---

## 4) Tableau de contrôle élèves
Colonnes proposées:
- Élève (Nom + ID)
- Moyenne annuelle (si dispo)
- Décision (auto + champ éditable)
- Destination (dropdown)
- Statut (Prêt / À traiter / Erreur)

Fonctions:
- Recherche (nom/id)
- Filtres: `Admis`, `Sous conditions`, `Redouble`, `Non décidé`, `Erreurs`
- Actions en masse:
  - `Appliquer règles`
  - `Forcer passage` / `Forcer redoublement`
  - `Destination = …` pour la sélection

Validations:
- Destination obligatoire
- Empêcher “destination identique” si année cible identique
- Alerter si décision non fin d’année et “automatique seulement” choisi

---

## 5) Prévisualisation & exécution
- Résumé:
  - `X` élèves → `Classe cible`
  - `Y` élèves → `Redoublement`
  - `Z` non traités / erreurs
- Boutons:
  - `Simuler` (aucune écriture)
  - `Appliquer la réinscription`

### Confirmation
- “Vous allez **modifier N élèves** (année/classe). Continuer ?”

---

## 6) Écriture des données (rappel)
- Réinscription = `UPDATE students SET academicYear=?, className=? WHERE id=?`
- Mettre à jour tout autre champ dépendant de l’année si existant (ex: filtres/état), selon ton modèle.

---

## 7) Audit / historique
- Log par lot: année source→cible, classe source→cible, nombre d’élèves, utilisateur, timestamp.
- Option: “Annuler le lot” (si on stocke l’ancien `academicYear/className` par élève).

---

## Reste à faire (selon le programme)
- Rafraîchir l’UI après application (recharger classe/élèves + compteurs dans l’écran “Élèves & Classes”).
- Implémenter le mode **“Toute l’école”** (batch multi-classes) avec prévisualisation.
- Ajouter un **mapping automatique** configurable (CP→CE1, …) + actions en masse avancées.
- Renforcer sécurité/cohérence:
  - audit “réinscription” (lot/batchId)
  - règles sur l’archivage/consultation des anciennes notes et bulletins après changement d’année
  - option d’annulation du dernier lot (si souhaité).

