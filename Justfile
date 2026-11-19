default:
	just --list

preview-docs target="SceneSprockets":
	swift package --disable-sandbox preview-documentation --target {{target}}

# Clone or update the Khronos glTF-Sample-Assets that the glTF tests and benchmarks read.
download-sample-assets:
	#!/usr/bin/env bash
	set -euo pipefail
	if [ ! -d .sample-assets ]; then
		git clone --depth 1 https://github.com/KhronosGroup/glTF-Sample-Assets.git .sample-assets
	else
		git -C .sample-assets pull --ff-only
	fi

# Benchmark glTF sample scenes (Release) against this machine's baseline in Benchmarks/glTF. Extra arguments go to `ms-gltf-render bench` (e.g. scene names, --record).
bench-gltf *args:
	xcb build -S SceneSprockets/ms-gltf-render -c release
	.build/out/Products/Release/ms-gltf-render bench {{args}}

# Record this machine's glTF benchmark baseline.
bench-gltf-record *args:
	just bench-gltf --record {{args}}

# Regenerate GLTFViewer's built-in shapes: write them from BasicShape, then pack them with gltfpack (quantized, meshopt).
gltfviewer-basic-shapes:
	#!/usr/bin/env bash
	set -euo pipefail
	raw=$(mktemp -d)
	cd Examples/GLTFViewer/Packages/GLTFViewerSupport
	WRITE_BASIC_SHAPES="$raw" xcb test -S --raw -- --filter writeBasicShapes > /dev/null
	out=Sources/GLTFViewerSupport/Resources/BasicShapes
	mkdir -p "$out"
	for file in "$raw"/*.glb; do
		# -kv keeps TEXCOORD_0, which gltfpack otherwise drops because no texture uses it (the UV debug views do).
		# -vt 16: with the default 12 bits gltfpack undoes the UV scaling through KHR_texture_transform on textures;
		# these shapes have none, so their UVs would come out 16 times too small.
		npx --yes gltfpack -cc -kv -vt 16 -i "$file" -o "$out/$(basename "$file")"
	done
	ls -l "$out"

check-docs:
	swift package --disable-sandbox --allow-writing-to-directory /tmp/SceneSprockets-docs generate-documentation --target SceneSprockets --target SceneSprocketsPhysics --target SceneSprocketsPBR --target SceneSprocketsBlinnPhong --target SceneSprocketsShaderMaterial --target SceneSprocketsAudio --target SceneSprocketsGizmos --enable-experimental-combined-documentation --warnings-as-errors --output-path /tmp/SceneSprockets-docs
