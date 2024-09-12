SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# proxy
export https_proxy=http://127.0.0.1:62559 http_proxy=http://127.0.0.1:62559 all_proxy=socks5://127.0.0.1:62559

cd $SCRIPT_DIR

# generate appcast.xml
./Sparkle-2.3.1/bin/generate_appcast ../archives

# copy all files to public
rm ../firebase/public/ExcalidrawZ*
rm ../firebase/public/ExcaliDrawZ*
rm ../firebase/public/appcast.xml
cp ../archives/* ../firebase/public
cp -r ../assets ../firebase/public

# deploy firebase
cd ../firebase && firebase deploy
