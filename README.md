     _______  _______  _______  _______         ______    __   __ 
    |       ||   _   ||       ||       |       |    _ |  |  |_|  |
    |  _____||  |_|  ||    ___||    ___| ____  |   | ||  |       |
    | |_____ |       ||   |___ |   |___ |____| |   |_||_ |       |
    |_____  ||       ||    ___||    ___|       |    __  ||       |
     _____| ||   _   ||   |    |   |___        |   |  | || ||_|| |
    |_______||__| |__||___|    |_______|       |___|  |_||_|   |_|

A much safer replacement of bash rm

Mac OS X **ONLY** so far.

Using safe-rm, the files or directories you choose to remove will move to Trash(OS X) instead of simply deleting them. You could put them back whenever you want manually.

If a file or directory with the same name already exists in the Trash, the name of newly-deleted items will be ended with the current date and time.

Install
----
Normally:

	make && sudo make install
	# and enjoy
	
For those who have no `make` command:

	sudo sh install.sh
	
Installing safe-rm will replace the original `/bin/rm` of Mac OS X which will be backed up before replacing.
	
After installation, when you execute `rm` command in the Terminal, lines of below will be printed:

	> rm
	safe-rm
	usage: rm [-f | -i] [-dPRrvW] file ...
       unlink file

which helps to tell safe-rm from the original rm.
	
Uninstall
----
	make && sudo make uninstall
Or

	sudo sh uninstall.sh