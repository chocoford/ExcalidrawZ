# generate appcast.xml
./Sparkle-2.3.1/bin/generate_appcast ../archives

# deploy firebase
cd ../firebase && firebase deploy
