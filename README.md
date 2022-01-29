# UPDATE LOG

Just made a quick update, it now uses class names to find the required services.

You can use this to execute scripts in any/every game now.



# WORKING AS OF 1/21/22

After a long duration of side projects, I've come back to redo this completely.

In order to run scripts using nothing other than Cheat Engine's own Lua Engine,
you only have to run 1 script -- executor.lua

Go into Memory View and hit Ctrl+L or Tools --> Lua Engine
and paste the script there.

Make any modifications you want to the "rbx_main()" function in executor.lua
which is plainly visible, among the first couple lines.
If you know lua, this should be easy.

Everything in that function will get executed INSIDE ROBLOX.
Now, please note this is still a work in progress and it DOES NOT SUPPORT BIG SCRIPTS YET.



# UNDETECTED CHEAT ENGINE WHEN??

............
After looking into it, I'm probably not allowed to distribute my custom cheat engine here, so please try to look for an alternative such as NOPDE or Check Cashed. Any version of cheat engine should work, if it supports lua 5.3 in the lua engine. There are many cheat engine spoofs out there... if you're really desparate, you can DM me at jayzoinks#8941



# NOTICE

DONT use 'Open Cheat Table' for executing the lua script

That is all. :)
