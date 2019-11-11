.PHONY: build-encoder
build-encoder: 
	go build -o _out/encoder hack/encode/main.go

.PHONY: clean
clean: 
	rm -rf _out

.PHONY: generate
generate: clean build-encoder
	hack/generate.sh

# Windows only
.PHONY: release
release: clean
	powershell hack/release.ps1