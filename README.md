Setting the dmenu width in dxmms2 requires the patch provided in this repo. The patch hasn't been tested; application may require manual effort.

* xc - a tool for manipulating xmms2 collections. requires `xce-serv` to be running
* xce - a server that manages a stack machine and interfaces with an `xmms2d` for `xc` clients
* dxmms2 - a dmenu shell for xmms2
  ![dxmms2 screenie](/dxmms2.png)
* xmms2-string.rb - a track-progression indicator for use in xmobar. Can be placed in `.config/xmms2/startup.d` to have it run when xmms2 starts up.
  You can configure xmobar with this line in `commands`: 
```
    , Run PipeReader "/tmp/YOUR_USER_NAME_HERE-xmms2-string-ipc-pipe" "xmms2_curr"
```
  replacing YOUR_USER_NAME_HERE with your user name.
