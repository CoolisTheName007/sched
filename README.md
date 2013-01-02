sched is a pure Lua multitasking manager, inspired in the Luasched and Lumen
projects. Base modules like init.lua and platform.lua were totally overhauled, while optional utilities like pipe.lua were left pratically untouched.
While the platform module is written so that the scheduler can be run from the ComputerCraft environment, the rest of the scheduler is platform independent.


###Install
In /packages/sched: put init.lua, platform.lua and timer.lua.

You may optionally include other modules from the scheduler repository.

####Dependencies:
the loadreq API must be loaded first, before using the scheduler. It attempts to make loadreq.require a global (require)

-To be put in /packages:

+ loadreq: https://github.com/CoolisTheName007/loadreq
+ log: https://github.com/CoolisTheName007/log
+ checker: https://github.com/CoolisTheName007/checker

-From the utils repository, to be put in /utils:

+ print
+ table
+ linked
