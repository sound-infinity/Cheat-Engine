# PLEASE READ

To avoid conflict, you need to make sure you opened the correct roblox process (high memory usage)
and not the secondary one only used for roblox's AC (only uses 0-10mb of RAM).

Once you've opened the correct process in cheat engine, go to Memory View --> Tools --> Lua Engine --> Paste the script in the text box and hit Execute.

# UPDATE LOG

3/21/22 - Fixed a bug

# WORKING AS OF 2/19/22

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



# P.S.

DONT use 'Open Cheat Table' for executing the lua script

That is all. :)
