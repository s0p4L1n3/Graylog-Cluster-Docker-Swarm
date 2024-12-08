#!/bin/bash

# Fichier temporaire pour stocker les résultats
temp_file=$(mktemp)

# Couleurs ANSI
BLUE="\033[34m"       # Couleur pour les nœuds
PINK="\033[35m"       # Couleur pour les services
GREEN="\033[32m"      # Couleur pour Running
RESET="\033[0m"       # Réinitialisation des couleurs

# Récupérer les services et leurs nœuds
for service in $(docker service ls --format '{{.Name}}'); do
    docker service ps $service --format "{{.Node}} {{.Name}} {{.CurrentState}}" \
        | grep -E "Running|Starting" >> "$temp_file"
done

# Afficher les résultats regroupés par nœud
echo -e "\n=== Nodes and Services Tables ===\n"

# Lire les nœuds uniques
nodes=$(awk '{print $1}' "$temp_file" | sort | uniq)

for node in $nodes; do
    echo -e "${BLUE}Node : $node${RESET}"
    echo "-------------------------"
    awk -v node="$node" -v pink="$PINK" -v green="$GREEN" -v reset="$RESET" '
    $1 == node {
        status = ($3 == "Running") ? green $3 reset : $3
        printf "%s%s %s%s\n", pink, $2, status, reset
    }' "$temp_file"
    echo ""
done

# Nettoyer le fichier temporaire
rm -f "$temp_file"
