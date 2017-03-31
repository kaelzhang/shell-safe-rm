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

# the test target will not work properly if a file named test is ever created
# in this directory. Since it has no prerequisites, test would always be considered
# up to date and its recipe would not be executed. To avoid this problem you
# can explicitly declare the target to be phony by making it a prerequisite of
# the special target
# TODO: is test directory really needed?
.PHONY: test

test:
	@echo "Testing safe-rm by creating a directory and a symbolic link to it"
	@mkdir /tmp/test_dir
	@ln -s /tmp/test_dir /tmp/test_link
	@echo yes | bin/rm.sh /tmp/test_link
	@bin/rm.sh -r /tmp/test_dir
	@cd $(OLDPWD)
