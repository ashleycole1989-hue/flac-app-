SCHEME = FlacPlayer
PROJECT = FlacPlayer.xcodeproj
DERIVED = build

.PHONY: device ipa clean

device:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -sdk iphoneos -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO

ipa: device
	rm -rf Payload FlacPlayer-unsigned.ipa
	mkdir -p Payload
	cp -R $(DERIVED)/Build/Products/Release-iphoneos/FlacPlayer.app Payload/
	zip -qry FlacPlayer-unsigned.ipa Payload
	rm -rf Payload
	@echo "Wrote FlacPlayer-unsigned.ipa"

clean:
	rm -rf $(DERIVED) Payload FlacPlayer-unsigned.ipa
