
.SUFFIXES: .pod .html

.pod.html:
	pod2html $*.pod > $*.html

default:
	@echo 'Use "make test" to run tests'

test:
	prove -Ilib -r t

doc:	doc/design.html
