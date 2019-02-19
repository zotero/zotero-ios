#!/bin/bash

function fetchFields {
	echo "Fetching fields for $1"
	curl -s "https://api.zotero.org/itemTypeFields?itemType=$1" | jq '.[] | .field' | tr -d '"' | paste -sd "," - > "Zotero/Assets/items/item_fields_$1.txt"
}

types=$(cat "Zotero/Assets/items/item_types.txt")
IFS=',' read -ra ADDR <<< "$types"
for i in "${ADDR[@]}"; do
    fetchFields "$i"
done