test:
	python3 test/run.py

synth:
	python3 scripts/synth.py --liberty "$(LIBERTY)"

.PHONY: test synth
