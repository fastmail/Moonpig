
.SUFFIXES: .pod .html
PERL=perl5.14.1

.pod.html:
	pod2html $*.pod > $*.html

default:
	@echo 'Use "make test" to run tests'

test:
	$(PERL) `which prove` -j2 -Ilib -r t

doc:	doc/design.html

print-%: ; @echo $*=$($*)
