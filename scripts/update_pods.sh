SCRIPT_PATH=`grealpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`
LICENSE_FILE="$SCRIPT_DIR/../pdf-keys/pspdfkit_pod.txt"

if [ ! -f $LICENSE_FILE ]; then
	echo "License pod file missing"
	exit 1
fi

POD_FILE="$SCRIPT_DIR/../Podfile"

if [ ! -f $POD_FILE ] || [ ! -w $POD_FILE ]; then
	echo "Podfile missing"
	exit 1
fi

echo "Updating Podfile"
PLACEHOLDER="#pspdfkit"
POD=`cat $LICENSE_FILE`
sed -i "" "s%$PLACEHOLDER%$POD%g" "$POD_FILE"

echo "Updating pods"
pod install

echo "Restoring original Podfile"
sed -i "" "s%$POD%$PLACEHOLDER%g" "$POD_FILE"