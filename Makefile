.PHONY: build test app dmg run clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

dmg:
	./Scripts/build-dmg.sh

run: app
	open MELD.app --args --studio

clean:
	swift package clean
	rm -rf .build FlipDoc.app MELD.app dist
