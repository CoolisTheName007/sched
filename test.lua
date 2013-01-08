ta=os.clock()
if not main then os.loadAPI('APIS/main') end
-- ex=require'utils.extendbit'.extend
-- pprint(ex(1))
-- loadreq.vars.required['packages/utils/extendbit.lua']=nil

-- sha1=require'packages.osi.sha1'
-- print(sha1(1))

-- require'utils.linked'.test()
-- function benchmark(f,...)
	-- local ta=os.clock()
	-- f(...)
	-- return os.clock()-ta
-- end
-- Hsm=require'packages.miros'.new()

sched=require'packages.sched'
sched.reset()

input=require'packages.sched.tasks.input'

-- -- -- catalog=require 'packages.sched.catalog'
-- -- -- catalog.reset()

log=require 'packages.log'
-- print('time to load (precision is 0.05 for everything in CC):'..(os.clock()-ta))
-- log.setlevel('ALL')--,'sched')--,'catalog')

sched.sighook(function() sched.stop() end ,'platform','terminate')
sched.sighook(
	function(...)
		print(...)
	end,
	{[input]={'ctrl_key'}}
)
sched.loop()