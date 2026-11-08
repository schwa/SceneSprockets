default:
	just --list

preview-docs target="SceneSprockets":
	swift package --disable-sandbox preview-documentation --target {{target}}

check-docs:
	swift package --disable-sandbox --allow-writing-to-directory /tmp/SceneSprockets-docs generate-documentation --target SceneSprockets --target SceneSprocketsPhysics --target SceneSprocketsPBR --target SceneSprocketsBlinnPhong --target SceneSprocketsShaderMaterial --target SceneSprocketsAudio --target SceneSprocketsGizmos --target SceneSprocketsAddOns --enable-experimental-combined-documentation --warnings-as-errors --output-path /tmp/SceneSprockets-docs
