SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# proxy
export https_proxy=http://127.0.0.1:62559 http_proxy=http://127.0.0.1:62559 all_proxy=socks5://127.0.0.1:62559

cd $SCRIPT_DIR

# generate appcast.xml
./Sparkle-2.6.4/bin/generate_appcast ../archives-new

# copy all files to public
rm ../firebase-new/public/downloads/ExcalidrawZ*
rm ../firebase-new/public/downloads/appcast.xml
cp ../archives-new/* ../firebase-new/public/downloads

# cd ../firebase-new/public/downloads
latest_url=$(swift ./find_latest_url.swift)
node adjust_config.js $latest_url
# [ -L "./ExcalidrawZ-latest" ] && rm "./ExcalidrawZ-latest"
# ln -s ./$latest_url ./ExcalidrawZ-latest

# deploy firebase
cd ../firebase-new

firebase deploy
