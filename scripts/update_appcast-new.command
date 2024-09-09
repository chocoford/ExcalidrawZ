SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# proxy
export https_proxy=http://127.0.0.1:62559 http_proxy=http://127.0.0.1:62559 all_proxy=socks5://127.0.0.1:62559

cd $SCRIPT_DIR

# generate appcast.xml
./Sparkle-2.6.4/bin/generate_appcast ../archives

# copy all files to public
rm ../firebase-new/public/ExcalidrawZ*
rm ../firebase-new/public/ExcaliDrawZ*
rm ../firebase-new/public/appcast.xml
cp ../archives-new/* ../firebase-new/public
cp -r ../assets ../firebase-new/public

# deploy firebase
cd ../firebase-new && firebase deploy
