#!/usr/bin/env python3
"""
Script pour nettoyer tous les marqueurs de conflit Git dans les fichiers Dart.
Conserve seulement la version qui vient APRÈS le marqueur ======= (la version depuis origin).
"""
import os
import sys

def clean_git_conflicts(file_path):
    """Nettoie les marqueurs de conflit Git d'un fichier."""
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    cleaned_lines = []
    in_conflict = False
    in_ours = False  # True si on est dans la section HEAD, False si dans la section origin
    
    for line in lines:
        if line.startswith('<<<<<<< HEAD'):
            in_conflict = True
            in_ours = True
            continue
        elif line.startswith('=======') and in_conflict:
            in_ours = False
            continue
        elif line.startswith('>>>>>>> ') and in_conflict:
            in_conflict = False
            in_ours = False
            continue
        
        # Si on n'est pas en conflit, ou si on est dans la section origin (après =======)
        if not in_conflict or not in_ours:
            cleaned_lines.append(line)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(cleaned_lines)
    
    return True

def main():
    """Parcourt tous les fichiers .dart et nettoie les conflits."""
    lib_dir = 'lib'
    count = 0
    
    for root, dirs, files in os.walk(lib_dir):
        for file in files:
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                try:
                    clean_git_conflicts(file_path)
                    count += 1
                    print(f"Nettoyé: {file_path}")
                except Exception as e:
                    print(f"Erreur avec {file_path}: {e}", file=sys.stderr)
    
    print(f"\nTotal: {count} fichiers nettoyés")

if __name__ == '__main__':
    main()
