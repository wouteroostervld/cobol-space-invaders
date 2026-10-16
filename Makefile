COBC   ?= cobc
CFLAGS ?= -x -O2
TARGET  = invaders

.PHONY: all run clean

all: $(TARGET) sounds/.stamp

$(TARGET): invaders.cob
	$(COBC) $(CFLAGS) -o $@ $<

# Sound effects are synthesized, not stored in the repository.
sounds/.stamp: tools/gen_sounds.py
	python3 tools/gen_sounds.py sounds
	touch $@

run: all
	./$(TARGET)

clean:
	rm -rf $(TARGET) sounds
