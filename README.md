     _______  _______  _______  _______         ______    __   __ 
    |       ||   _   ||       ||       |       |    _ |  |  |_|  |
    |  _____||  |_|  ||    ___||    ___| ____  |   | ||  |       |
    | |_____ |       ||   |___ |   |___ |____| |   |_||_ |       |
    |_____  ||       ||    ___||    ___|       |    __  ||       |
     _____| ||   _   ||   |    |   |___        |   |  | || ||_|| |
    |_______||__| |__||___|    |_______|       |___|  |_||_|   |_|

A much safer replacement for bash rm

Mac OS X **ONLY** so far.

Using safe-rm will replace the original `/bin/rm` of Mac OS X which will be backed up before replacing.

Install
----
	make && sudo make install
	# and enjoy
	
After installation, when you execute `rm` command in the Terminal, lines of below will be printed:

	> rm
	safe-rm
	usage: rm [-f | -i] [-dPRrvW] file ...
       unlink file

which helps to tell safe-rm from the original rm.
	
Uninstall
----
	make && sudo make uninstall