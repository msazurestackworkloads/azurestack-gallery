.PHONY: build-encoder
build-encoder: 
	go build -o _out/encoder scripts/encode/main.go

.PHONY: clean
clean: 
	rm -rf _out

.PHONY: generate
generate: clean build-encoder
	scripts/generate.sh

# Windows only
.PHONY: release
release: clean
	powershell scripts/release.ps1
