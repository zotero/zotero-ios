echo "Fetching types"
curl -s 'https://api.zotero.org/itemTypes' | jq '.[] | .itemType' | tr -d '"' | paste -sd "," - > "Zotero/Assets/items/item_types.txt"