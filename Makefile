
default:
	@echo 'Use "make test" to run tests'

test:
	prove -Ilib -r t
