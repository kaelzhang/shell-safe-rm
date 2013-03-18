PREFIX=/bin

install:
	@if [ ! -e $(PREFIX)/rm.bak ]; then \
		echo "... backup $(PREFIX)/rm to $(PREFIX)/rm.bak"; \
		cp $(PREFIX)/rm $(PREFIX)/rm.bak; \
	fi

	@cp bin/rm.sh $(PREFIX)/rm
	@chmod 755 $(PREFIX)/rm
	@echo "Installation Succeeded! Enjoy!"

uninstall:
	@cp $(PREFIX)/rm.bak $(PREFIX)/rm
	@chmod 755 $(PREFIX)/rm
	@echo "Successfully recovered to the original rm"