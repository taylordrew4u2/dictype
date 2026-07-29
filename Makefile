all:
	python3 build.py

check:
	python3 -m pytest -q tests/test_build.py

clean:
	rm -rf build
