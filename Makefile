.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open FlipDoc.app

clean:
	swift package clean
	rm -rf .build FlipDoc.app
