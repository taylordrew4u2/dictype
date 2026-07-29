.PHONY: all dmg app test icon clean

# The DMG is the thing people install, so it is the default target.
all: dmg

# Build DicType.app and wrap it in a drag-to-Applications disk image.
dmg:
	bash DicType/build-dmg.sh

# Build DicType.app on its own.
app:
	bash DicType/build.sh

# Repository checks. These run on any OS; the macOS-only build verification
# lives in .github/workflows/ci.yml.
test:
	python3 -m unittest discover -s tests -v

# Regenerate AppIcon.icns from AppIcon.svg. Needs `pip install cairosvg`.
# The .icns is committed, so this is only needed when the artwork changes.
icon:
	python3 tools/make-icon.py

clean:
	rm -rf DicType/.build DicType/DicType.app DicType/DicType.dmg DicType/DicType.zip
	rm -f assets/DicType.dmg assets/DicType.zip
	find . -name __pycache__ -type d -prune -exec rm -rf {} +
