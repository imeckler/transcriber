.PHONY: app
app:
	./scripts/engines.sh
	./scripts/ffmpeg.sh
	./scripts/package.sh

.PHONY: test
test:
	mkdir -p build/swift-cache
	swiftc -module-cache-path build/swift-cache src/Models.swift src/Recording.swift src/TranscriptEditing.swift src/Export.swift Tests/main.swift -o build/transcript-tests
	build/transcript-tests
