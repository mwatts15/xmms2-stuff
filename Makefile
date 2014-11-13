install: install-xc install-dxmms2 install-xmms2-string

install-xc:
	cp xc $(HOME)/bin/.
	cp xce-serv $(HOME)/bin/.

install-dxmms2:
	cp dxmms2 $(HOME)/bin/.

install-xmms2-string:
	cp xmms2-string.rb $(HOME)/bin/.
