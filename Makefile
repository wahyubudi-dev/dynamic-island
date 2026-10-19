APP = build/Dynamic Island.app

.PHONY: build run stop clean install

build:
	./build.sh

run: build
	open "$(APP)"

# Runs the executable in the foreground so NSLog output stays on the terminal.
debug: build
	"./$(APP)/Contents/MacOS/DynamicIsland"

stop:
	-pkill -x DynamicIsland

install: build
	rm -rf "/Applications/Dynamic Island.app"
	cp -R "$(APP)" "/Applications/Dynamic Island.app"
	open "/Applications/Dynamic Island.app"

clean:
	rm -rf build .build
