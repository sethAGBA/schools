# Ajouts proposés — écran par écran

## Tableau de bord (`DashboardHome`)
- Tuiles “alertes” (impayés, retards, sanctions du jour, conflits EDT)
- Mini-calendrier (événements/échéances) + “à faire” (tâches administratives)
- KPIs par année/classe (filtres rapides) + export snapshot (PDF)

## Élèves & Classes (`StudentsPage`)
- Import/Export élèves (CSV/Excel) + détection doublons (nom/date naissance/téléphone)
- Champs “responsables” (parents/tuteurs), contacts, adresse, infos médicales, documents (scan)
- Actions en masse (changer classe/année, réinscrire, imprimer cartes, supprimer/restaurer)

## Profil élève (`StudentProfilePage`)
- Déjà présent : onglets Infos / Paiements / Bulletins (archives) + export PDF (reçus, bulletins)
- À ajouter : onglet “Documents” (liste/ouvrir/ajouter/supprimer) basé sur `Student.documents` (pièces jointes ajoutées au formulaire)
- À ajouter : onglet “Assiduité/Discipline” (retards/absences/sanctions) + filtres par période + export
- À ajouter : génération “carte d’élève” (QR/Code-barres, photo, drapeau/logo) + impression
- À ajouter : timeline “journal de l’élève” (modifs, paiements, exports, sanctions) via l’audit + pièces jointes

## Détails classe (`ClassDetailsPage`)
- Déjà présent : infos classe + seuils (félicitations/encouragement/admission/avertissement/sous conditions), gestion matières + coefficients, exports (listes élèves PDF/Excel/Word, cartes scolaires PDF, fiches élèves), modèles notes (global + par matière), réinscription
- Déjà présent : actions en masse sur la liste élèves (mode sélection, tout sélectionner, transfert/changer classe, supprimer corbeille, restaurer, imprimer cartes pour sélection)
- Déjà présent : filtre d’affichage élèves (Actifs / Corbeille / Tous) dans la classe, pour pouvoir restaurer sans passer par `StudentsPage`
- Déjà présent : section “Bulletins archivés” (par période) + simulation de décision (via seuils) + export ZIP (duplicata) depuis la classe

## Personnel (`StaffPage`)
- Déjà présent : fiche personnel (contrat, contacts, diplômes) + dialogue “Détails” avec onglets Infos/Documents/Historique
- Déjà présent : gestion des absences/congés (CRUD) par personnel
- Déjà présent : vue “charge horaire” depuis l’EDT (heures hebdo + détail)

## Notes & Bulletins (`GradesPage`)
- Modèles d’évaluations (types, barèmes, coefficients) par niveau/classe
- Déjà présent : workflow de validation + verrouillage par période (Brouillon → Soumis → Validé)
- Analytique (moyennes/écarts, top/flop, compétences) + exports améliorés

## Paiements (`PaymentsPage`)
- Échéancier (mensuel/trimestriel), paiements partiels, ristournes/remises
- Relances automatiques (PDF/email/SMS) + statut “en retard”
- Numérotation reçus + rapprochement (caisse/journal) + justificatifs (scan)

## Finance & Matériel (`FinanceAndInventoryPage`)
- Budgets (prévision/réalisé) + catégories comptables + graphiques
- Pièces justificatives (factures) sur dépenses + fournisseurs normalisés
- Inventaire multi-quantités/état/localisation + alertes stock/maintenance + import

## Utilisateurs (`UsersManagementPage`)
- Réinitialisation mot de passe / désactivation compte / verrouillage après échecs
- Groupes de permissions (prof, compta, direction) + modèle par rôle
- Journal d’activité par utilisateur + “sessions” (qui est connecté)

## Emplois du Temps (`TimetablePage`)
- Gestion des salles (capacités/équipements) + contraintes plus “éditables” (UI dédiée)
- Exports calendrier (ICS) + impression “planning prof/classe”
- Gestion jours fériés/vacances + modèles d’EDT réutilisables

## Matières (`SubjectsPage`)
- Coefficients/volumes horaires par niveau/classe (pas seulement global)
- Prérequis / regroupements (UE) + affectation prof par matière
- Import/Export (Excel) + validation doublons

## Signatures & Cachets (`SignaturesPage`)
- Aperçu rendu dans les documents (bulletin/reçu) avant validation
- Dates de validité + versioning (ancienne signature archivée)
- Règles d’assignation (par classe + rôle + “par défaut” clair)

## Bibliothèque (`LibraryPage`)
- Gestion des exemplaires (plusieurs copies), cotes/localisation, état
- Réservations + pénalités/retards + notifications de retour
- Scan ISBN/QR + impression étiquettes code-barres

## Discipline (`DisciplinePage`)
- Workflow (proposition → validation) + notifications aux responsables
- Barème/points + rapports mensuels (récap par classe/élève)
- Modèles de documents + pièces jointes (preuves/convocations)

## Audits (`AuditPage`)
- Filtre par “entité” (élève X, paiement Y, classe Z) + liens cliquables
- Export PDF + politique de rétention (purge/archivage)
- Vue “diff” des modifications (avant/après) pour actions sensibles

## Mode coffre-fort (`SafeModePage`)
- Politique par action (annulation paiement, suppression, restore DB…) + temporisation
- Exiger 2FA pour actions critiques + expiration de session coffre-fort
- Procédure de récupération (supadmin) mieux guidée + logs dédiés

## Licence (`LicensePage`)
- Assistant d’activation (étapes + diagnostic) + période de grâce
- Historique des clés utilisées + infos machine (si pertinent)
- Bouton support (copier diagnostic, exporter logs)

## Paramètres (`SettingsPage`)
- Sauvegarde planifiée + option chiffrage + restauration guidée (prévisualisation)
- Import global (élèves/classes/matières) + vérification avant écriture
- Centre de notifications (relances, retards bibliothèque, absences, sanctions)

## Connexion / 2FA (`LoginPage`, `TwoFactorPage`)
- “Mot de passe oublié” (au moins admin) + verrouillage après X tentatives
- Appareils de confiance (ne pas redemander OTP sur un poste)
- Politique mot de passe (force, rotation) + audit sécurité
