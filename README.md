# UPDATED!!!!! WORKING AS OF 1/21/22

After a long duration of side projects, I've come back to redo this completely.

In order to run scripts using nothing other than Cheat Engine's own Lua Engine,
you only have to run 1 script -- executor.lua

Go into Memory View and hit Ctrl+L or Tools --> Lua Engine
and paste the script there.

Make any modifications you want to the "rbx_main()" function in executor.lua
which is plainly visible, among the first couple lines.
If you know lua, this should be easy.

Everything in that function will get executed INSIDE ROBLOX.
Now, please note this is still a work in progress and it DOES NOT SUPPORT BIG SCRIPTS YET

It should run most small scripts for now.
As always, enjoy :))



# UNDETECTED CHEAT ENGINE WHEN??

Right now! That's when.
Simply install Cheat Engine from the official website - https://www.cheatengine.org/downloads.php
Download the latest version, or at least 7.0 and up.
Once you installed Cheat Engine, download CeleryEngine.exe from this repo, and drop this into the installed cheat engine folder -- the same place that the real cheatengine exe is located.
Now, run CeleryEngine.exe INSTEAD and make your settings look exactly like the images linked in this repo.
You should be able to use cheat engine fully undetected now.

# NOTICE

DONT use 'Open Cheat Table' for executing the lua script

That is all. :)
