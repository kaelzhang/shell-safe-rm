PREFIX=/bin

install:
	@cp bin/rm.sh $(PREFIX)/safe-rm
	@chmod 755 $(PREFIX)/safe-rm
	@echo "Installation Succeeded!"
	@echo "Please add \"alias rm='$(PREFIX)/safe-rm'\" to your ~/.bashrc script"
	@echo "Enjoy!"

uninstall:
	@rm $(PREFIX)/safe-rm
	@echo "Please remove \"alias rm='$(PREFIX)/safe-rm'\" from your ~/.bashrc script"
	@echo "and do 'unalias rm' from all your terminal sessions"
	@echo "Successfully removed $(PREFIX)/safe-rm"
